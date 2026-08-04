/// Capture calendar page + getEvents JSON across request/filter axes.
///
/// Also seeds a few admin events (f=add) so non-empty JSON can be tested.
/// Resume state: tool/calendar/run/state.json
///
/// ```sh
/// dart run tool/calendar/generate_permutations.dart
/// dart run tool/calendar/generate_permutations.dart --reset --limit=10
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:liblanis/easy_client.dart';
import 'package:path/path.dart' as p;

Map<String, String> loadDotEnv(String path) {
  final file = File(path);
  if (!file.existsSync()) throw StateError('Env file not found: $path');
  final map = <String, String>{};
  for (final raw in file.readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#') || !line.contains('=')) continue;
    final i = line.indexOf('=');
    var v = line.substring(i + 1).trim();
    if (v.length >= 2 &&
        ((v.startsWith('"') && v.endsWith('"')) ||
            (v.startsWith("'") && v.endsWith("'")))) {
      v = v.substring(1, v.length - 1);
    }
    map[line.substring(0, i).trim()] = v;
  }
  return map;
}

String cb() => '_cachebreaker=${DateTime.now().millisecondsSinceEpoch}';

class Job {
  Job({
    required this.id,
    required this.role,
    required this.requestStyle,
    required this.startKind,
    required this.search,
    required this.category,
    required this.zielgruppe,
  });

  final String id;
  final String role; // student | admin
  final String requestStyle; // parser_body_dt | parser_body_fmt | website_fc
  final String startKind; // default_window | year | empty_window | far_future
  final String search;
  final String category; // '' or id
  final String zielgruppe; // '' or filter
  String status = 'pending';
  String? error;
  String? pageFixture;
  String? eventsFixture;
  int? pageBytes;
  int? eventsBytes;
  String? eventsJsonType;

  Map<String, Object?> toJson() => {
        'id': id,
        'role': role,
        'requestStyle': requestStyle,
        'startKind': startKind,
        'search': search,
        'category': category,
        'zielgruppe': zielgruppe,
        'status': status,
        'error': error,
        'pageFixture': pageFixture,
        'eventsFixture': eventsFixture,
        'pageBytes': pageBytes,
        'eventsBytes': eventsBytes,
        'eventsJsonType': eventsJsonType,
      };

  static Job fromJson(Map<String, dynamic> j) => Job(
        id: j['id'] as String,
        role: j['role'] as String,
        requestStyle: j['requestStyle'] as String,
        startKind: j['startKind'] as String,
        search: j['search'] as String? ?? '',
        category: j['category'] as String? ?? '',
        zielgruppe: j['zielgruppe'] as String? ?? '',
      )
        ..status = j['status'] as String? ?? 'pending'
        ..error = j['error'] as String?
        ..pageFixture = j['pageFixture'] as String?
        ..eventsFixture = j['eventsFixture'] as String?
        ..pageBytes = j['pageBytes'] as int?
        ..eventsBytes = j['eventsBytes'] as int?
        ..eventsJsonType = j['eventsJsonType'] as String?;
}

List<Job> buildJobs() {
  const roles = ['student', 'admin'];
  const styles = ['parser_body_dt', 'parser_body_fmt', 'website_fc'];
  const starts = ['default_window', 'year', 'empty_window', 'far_future'];
  const searches = ['', 'RMFIX', '___nomatch___'];
  const categories = ['', '1', '4'];
  const ziel = ['', '-lul', '-sus'];

  final jobs = <Job>[];
  for (final role in roles) {
    for (final style in styles) {
      for (final start in starts) {
        for (final s in searches) {
          for (final k in categories) {
            for (final z in ziel) {
              final id = [
                role,
                'style-$style',
                'start-$start',
                's-${s.isEmpty ? 'none' : s}',
                'k-${k.isEmpty ? 'all' : k}',
                'z-${z.isEmpty ? 'all' : z}',
              ].join('__');
              jobs.add(
                Job(
                  id: id,
                  role: role,
                  requestStyle: style,
                  startKind: start,
                  search: s,
                  category: k,
                  zielgruppe: z,
                ),
              );
            }
          }
        }
      }
    }
  }
  return jobs;
}

({DateTime start, DateTime end}) windowFor(String kind) {
  final now = DateTime.now();
  switch (kind) {
    case 'year':
      return (start: DateTime(now.year, 1, 1), end: DateTime(now.year, 12, 31));
    case 'empty_window':
      return (start: DateTime(1999, 1, 1), end: DateTime(1999, 1, 2));
    case 'far_future':
      return (
        start: DateTime(now.year + 5, 1, 1),
        end: DateTime(now.year + 5, 12, 31),
      );
    case 'default_window':
    default:
      return (
        start: now.subtract(const Duration(days: 120)),
        end: now.add(const Duration(days: 356)),
      );
  }
}

Future<void> seedEvents(EasyLanisClient admin) async {
  final session = admin.session!;
  final fmt = DateFormat('dd.MM.yyyy');
  final day = DateTime.now().add(const Duration(days: 3));
  final von = fmt.format(day);
  final bis = fmt.format(day);

  // Discover a couple of recipient ids.
  final search = await session.dio.get(
    'https://start.schulportal.hessen.de/kalender.php?${cb()}',
    queryParameters: {'a': 'searchRecipt', 'q': '', 'page': 1},
    options: Options(validateStatus: (_) => true),
  );
  await File('tool/calendar/discovery/searchRecipt.json')
      .writeAsString(search.data.toString());

  final variants = <Map<String, dynamic>>[
    {
      'name': '01_basic_timed',
      'titel': 'LIBLANIS FIX 01 basic timed',
      'art': '1',
      'von': von,
      'vont': '10:00',
      'bis': bis,
      'bist': '11:00',
      'ganztag': '',
      'beschreibung': 'fingerprint RMFIX-01',
      'ort': 'RMFIX-01',
      'zielgruppe[]': '-lul',
    },
    {
      'name': '02_all_day',
      'titel': 'LIBLANIS FIX 02 all day',
      'art': '4',
      'von': von,
      'vont': '',
      'bis': bis,
      'bist': '',
      'ganztag': '1',
      'beschreibung': 'fingerprint RMFIX-02',
      'ort': 'RMFIX-02',
      'zielgruppe[]': '-sus',
    },
    {
      'name': '03_publicish',
      'titel': 'LIBLANIS FIX 03 public',
      'art': '5',
      'von': von,
      'vont': '14:30',
      'bis': bis,
      'bist': '15:45',
      'ganztag': '',
      'beschreibung': 'fingerprint RMFIX-03',
      'ort': 'RMFIX-03',
      'zielgruppe[]': '-public',
    },
  ];

  for (final v in variants) {
    final name = v.remove('name') as String;
    final data = Map<String, dynamic>.from(v)..['f'] = 'add';
    final resp = await session.dio.post(
      'https://start.schulportal.hessen.de/kalender.php?${cb()}',
      data: data,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        validateStatus: (_) => true,
      ),
    );
    await File('tool/calendar/discovery/seed_$name.json')
        .writeAsString(resp.data.toString());
    stdout.writeln('seed $name -> status=${resp.statusCode} body=${resp.data}');
  }
}

Future<Response> fetchEvents({
  required EasyLanisClient client,
  required Job job,
}) async {
  final session = client.session!;
  final win = windowFor(job.startKind);
  final fmt = DateFormat('yyyy-MM-dd');
  final startFmt = fmt.format(win.start);
  final endFmt = fmt.format(win.end);
  final url = 'https://start.schulportal.hessen.de/kalender.php?${cb()}';

  switch (job.requestStyle) {
    case 'parser_body_dt':
      // Exact CalendarParser body style (DateTime.toString in body).
      return session.dio.post(
        url,
        queryParameters: {
          'f': 'getEvents',
          's': job.search,
          'start': startFmt,
          'end': endFmt,
        },
        data:
            'f=getEvents&start=${win.start}&end=${win.end}&s=${job.search}',
        options: Options(
          headers: {
            'Content-Type':
                'application/x-www-form-urlencoded; charset=UTF-8',
          },
          validateStatus: (_) => true,
        ),
      );
    case 'parser_body_fmt':
      return session.dio.post(
        url,
        queryParameters: {
          'f': 'getEvents',
          's': job.search,
          'start': startFmt,
          'end': endFmt,
        },
        data: 'f=getEvents&start=$startFmt&end=$endFmt&s=${job.search}',
        options: Options(
          headers: {
            'Content-Type':
                'application/x-www-form-urlencoded; charset=UTF-8',
          },
          validateStatus: (_) => true,
        ),
      );
    case 'website_fc':
    default:
      // FullCalendar-style: start/end as ISO-ish query + filter fields.
      return session.dio.post(
        url,
        data: {
          'f': 'getEvents',
          'start': '${startFmt}T00:00:00',
          'end': '${endFmt}T00:00:00',
          'k': job.category,
          's': job.search,
          'z': job.zielgruppe,
          'u': '',
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          validateStatus: (_) => true,
        ),
      );
  }
}

Future<void> main(List<String> args) async {
  var adminEnv = '.adminaccount.env';
  var studentEnv = '.studentaccount.env';
  var statePath = 'tool/calendar/run/state.json';
  var fixtureDir = 'test/fixtures/calendar';
  var reset = false;
  var seed = true;
  int? limit;

  for (final arg in args) {
    if (arg.startsWith('--admin-env=')) {
      adminEnv = arg.substring('--admin-env='.length);
    } else if (arg.startsWith('--student-env=')) {
      studentEnv = arg.substring('--student-env='.length);
    } else if (arg == '--reset') {
      reset = true;
    } else if (arg == '--no-seed') {
      seed = false;
    } else if (arg.startsWith('--limit=')) {
      limit = int.tryParse(arg.substring('--limit='.length));
    } else if (arg == '--help' || arg == '-h') {
      stdout.writeln(
        'Usage: dart run tool/calendar/generate_permutations.dart '
        '[--reset] [--no-seed] [--limit=N]',
      );
      return;
    }
  }

  final root = Directory.current.path;
  final outDir = Directory(p.join(root, fixtureDir))..createSync(recursive: true);
  Directory(p.join(root, 'tool/calendar/discovery')).createSync(recursive: true);
  Directory(p.join(root, 'tool/calendar/run')).createSync(recursive: true);
  final stateFile = File(p.join(root, statePath));

  List<Job> jobs;
  if (!reset && stateFile.existsSync()) {
    final raw = jsonDecode(await stateFile.readAsString()) as Map<String, dynamic>;
    jobs = [
      for (final j in (raw['jobs'] as List).cast<Map<String, dynamic>>())
        Job.fromJson(j),
    ];
    stdout.writeln(
      'Resuming ${jobs.length} jobs '
      '(done=${jobs.where((j) => j.status == 'done').length})',
    );
  } else {
    jobs = buildJobs();
    stdout.writeln('Created ${jobs.length} jobs');
  }

  Future<void> persist() async {
    final tmp = File('${stateFile.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'updatedAt': DateTime.now().toIso8601String(),
        'fixtureDir': fixtureDir,
        'jobs': [for (final j in jobs) j.toJson()],
      }),
    );
    await tmp.rename(stateFile.path);
  }

  final adminEnvMap = loadDotEnv(adminEnv);
  final studentEnvMap = loadDotEnv(studentEnv);

  EasyLanisClient? admin;
  EasyLanisClient? student;
  try {
    admin = EasyLanisClient.ephemeral(
      schoolId: int.parse(adminEnvMap['SCHOOLID']!),
      username: adminEnvMap['USERNAME']!,
      password: adminEnvMap['PASSWORD']!,
      userAgent: 'liblanis-calendar-perms/0.1.0',
    );
    student = EasyLanisClient.ephemeral(
      schoolId: int.parse(studentEnvMap['SCHOOLID']!),
      username: studentEnvMap['USERNAME']!,
      password: studentEnvMap['PASSWORD']!,
      userAgent: 'liblanis-calendar-perms/0.1.0',
    );
    await admin.login();
    await student.login();
    stdout.writeln('Logged in admin+student');

    if (seed) {
      stdout.writeln('Seeding admin calendar events…');
      await seedEvents(admin);
    }

    var processed = 0;
    for (final job in jobs) {
      if (job.status == 'done') continue;
      if (limit != null && processed >= limit) break;
      job.status = 'running';
      await persist();

      try {
        final client = job.role == 'admin' ? admin : student;
        final page = await client.session!.dio.get(
          'https://start.schulportal.hessen.de/kalender.php?${cb()}',
        );
        final pageBody = page.data.toString();
        final pageRel = p.join(fixtureDir, '${job.id}__page.html');
        await File(p.join(root, pageRel)).writeAsString(pageBody);

        final eventsResp = await fetchEvents(client: client, job: job);
        final eventsBody = eventsResp.data.toString();
        final eventsRel = p.join(fixtureDir, '${job.id}__events.json');
        await File(p.join(root, eventsRel)).writeAsString(eventsBody);

        Object? decoded;
        try {
          decoded = jsonDecode(eventsBody);
        } catch (_) {}

        job
          ..status = 'done'
          ..pageFixture = pageRel
          ..eventsFixture = eventsRel
          ..pageBytes = pageBody.length
          ..eventsBytes = eventsBody.length
          ..eventsJsonType = decoded == null
              ? 'decode_fail'
              : decoded is List
              ? 'list:${decoded.length}'
              : decoded.runtimeType.toString()
          ..error = null;
        processed++;
        stdout.writeln(
          '[${processed}${limit == null ? '' : '/$limit'}] ${job.id} -> '
          '${job.eventsJsonType}',
        );
      } catch (e) {
        job
          ..status = 'failed'
          ..error = e.toString();
        stdout.writeln('FAIL ${job.id}: $e');
      }
      await persist();
    }
  } finally {
    await admin?.logout();
    await admin?.dispose();
    await student?.logout();
    await student?.dispose();
    await persist();
  }

  final manifest = [
    for (final j in jobs.where((j) => j.status == 'done')) j.toJson(),
  ];
  await File(p.join(root, fixtureDir, 'manifest.json')).writeAsString(
    const JsonEncoder.withIndent('  ').convert(manifest),
  );
  stdout.writeln(
    'Done. done=${jobs.where((j) => j.status == 'done').length} '
    'failed=${jobs.where((j) => j.status == 'failed').length} '
    'pending=${jobs.where((j) => j.status == 'pending').length}',
  );
}
