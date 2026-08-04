/// Generate all Stundenplan HTML fixture permutations (864) with resume support.
///
/// Axes:
/// - VonBisAusblenden: off/on
/// - KursnamenEinblenden: off/on
/// - kursnamenvergleich: 9 options
/// - CSV plan: entries from tool/timetable/csvs/index.json (24)
///
/// State file (default `tool/timetable/run/state.json`) tracks every job so
/// the run can be interrupted and resumed.
///
/// ```sh
/// dart run tool/timetable/generate_csvs.dart   # ensure CSVs exist
/// dart run tool/timetable/generate_permutations.dart
/// dart run tool/timetable/dedupe_fixtures.dart   # drop byte-identical HTML
/// dart run tool/timetable/generate_permutations.dart --dry-run
/// dart run tool/timetable/generate_permutations.dart --reset
/// dart run tool/timetable/generate_permutations.dart --limit=5
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' show parse;
import 'package:liblanis/easy_client.dart';
import 'package:path/path.dart' as p;

// ---------------------------------------------------------------------------
// Axes
// ---------------------------------------------------------------------------

class VergleichOption {
  const VergleichOption(this.value, this.label);
  final String value;
  final String label;
}

const vergleichOptions = <VergleichOption>[
  VergleichOption('-', 'keinen Vergleich vornehmen'),
  VergleichOption(
    'kuerzel',
    'nur anhand der Lehrkräftekürzel nicht mögliche Kurse aussortieren',
  ),
  VergleichOption(
    'kuerzel-lerngruppen',
    'nur anhand der Lehrkräftekürzel nicht mögliche Kurse aussortieren + erweitern um zugewiesene Lerngruppen',
  ),
  VergleichOption(
    'kuerzelfach1',
    'anhand der Lehrkräftekürzel … ersten Buchstaben des Faches',
  ),
  VergleichOption(
    'kuerzelfach2',
    'anhand der Lehrkräftekürzel … ersten beiden Buchstaben des Faches',
  ),
  VergleichOption(
    'kuerzelfach3',
    'anhand der Lehrkräftekürzel … ersten drei Buchstaben des Faches',
  ),
  VergleichOption(
    'kuerzelfach',
    'anhand der Lehrkräftekürzel … komplettes Fach',
  ),
  VergleichOption(
    'kuerzelkursname',
    'anhand der Lehrkräftekürzel … kompletten Lerngruppennamen',
  ),
  VergleichOption(
    'kuerzelkursnamelerngruppen',
    'anhand der Lehrkräftekürzel … Lerngruppennamen + zugewiesene Lerngruppen',
  ),
];

// ---------------------------------------------------------------------------
// Env / HTTP helpers
// ---------------------------------------------------------------------------

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

Future<EasyLanisClient> loginFromEnv(String envPath) async {
  final env = loadDotEnv(envPath);
  final client = EasyLanisClient.ephemeral(
    schoolId: int.parse(env['SCHOOLID']!),
    username: env['USERNAME']!,
    password: env['PASSWORD']!,
    userAgent: 'liblanis-timetable-permutations/0.1.0',
  );
  await client.login();
  return client;
}

String cachebreaker() =>
    '_cachebreaker=${DateTime.now().millisecondsSinceEpoch}';

String stundenplanUrl([String query = '']) {
  final parts = <String>[if (query.isNotEmpty) query, cachebreaker()];
  return 'https://start.schulportal.hessen.de/stundenplan.php?${parts.join('&')}';
}

Options get formOpts => Options(
      contentType: Headers.formUrlEncodedContentType,
      validateStatus: (s) => s != null && s < 500,
      headers: {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
    );

String todayDe() {
  final now = DateTime.now();
  return '${now.day.toString().padLeft(2, '0')}.'
      '${now.month.toString().padLeft(2, '0')}.'
      '${now.year}';
}

String todayIso() {
  final now = DateTime.now();
  return '${now.year}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class PermJob {
  PermJob({
    required this.id,
    required this.csvName,
    required this.csvFile,
    required this.vonBisAusblenden,
    required this.kursnamenEinblenden,
    required this.vergleich,
    required this.vergleichLabel,
    this.status = 'pending',
    this.fixture,
    this.error,
    this.bytes,
    this.stunde,
    this.vonBis,
    this.hasAll,
    this.hasOwn,
    this.completedAt,
  });

  final String id;
  final String csvName;
  final String csvFile;
  final bool vonBisAusblenden;
  final bool kursnamenEinblenden;
  final String vergleich;
  final String vergleichLabel;
  String status; // pending | running | done | failed | skipped
  String? fixture;
  String? error;
  int? bytes;
  int? stunde;
  int? vonBis;
  bool? hasAll;
  bool? hasOwn;
  String? completedAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'csvName': csvName,
        'csvFile': csvFile,
        'vonBisAusblenden': vonBisAusblenden,
        'kursnamenEinblenden': kursnamenEinblenden,
        'vergleich': vergleich,
        'vergleichLabel': vergleichLabel,
        'status': status,
        'fixture': fixture,
        'error': error,
        'bytes': bytes,
        'stunde': stunde,
        'vonBis': vonBis,
        'hasAll': hasAll,
        'hasOwn': hasOwn,
        'completedAt': completedAt,
      };

  factory PermJob.fromJson(Map<String, dynamic> json) => PermJob(
        id: json['id'] as String,
        csvName: json['csvName'] as String,
        csvFile: json['csvFile'] as String,
        vonBisAusblenden: json['vonBisAusblenden'] as bool,
        kursnamenEinblenden: json['kursnamenEinblenden'] as bool,
        vergleich: json['vergleich'] as String,
        vergleichLabel: json['vergleichLabel'] as String? ?? '',
        status: json['status'] as String? ?? 'pending',
        fixture: json['fixture'] as String?,
        error: json['error'] as String?,
        bytes: json['bytes'] as int?,
        stunde: json['stunde'] as int?,
        vonBis: json['vonBis'] as int?,
        hasAll: json['hasAll'] as bool?,
        hasOwn: json['hasOwn'] as bool?,
        completedAt: json['completedAt'] as String?,
      );
}

class RunState {
  RunState({
    required this.version,
    required this.total,
    required this.jobs,
    required this.startedAt,
    required this.updatedAt,
    this.initialSettings,
    this.lastUploadedCsv,
    this.fixtureDir,
  });

  final int version;
  final int total;
  final List<PermJob> jobs;
  final String startedAt;
  String updatedAt;
  Map<String, Object?>? initialSettings;
  String? lastUploadedCsv;
  String? fixtureDir;

  int get doneCount => jobs.where((j) => j.status == 'done').length;
  int get failedCount => jobs.where((j) => j.status == 'failed').length;
  int get pendingCount =>
      jobs.where((j) => j.status == 'pending' || j.status == 'running').length;

  Map<String, Object?> toJson() => {
        'version': version,
        'total': total,
        'done': doneCount,
        'failed': failedCount,
        'pending': pendingCount,
        'startedAt': startedAt,
        'updatedAt': updatedAt,
        'fixtureDir': fixtureDir,
        'lastUploadedCsv': lastUploadedCsv,
        'initialSettings': initialSettings,
        'axes': {
          'vonBisAusblenden': [false, true],
          'kursnamenEinblenden': [false, true],
          'vergleich': [
            for (final v in vergleichOptions) {'value': v.value, 'label': v.label},
          ],
          'csvCount': jobs.map((j) => j.csvName).toSet().length,
        },
        'jobs': [for (final j in jobs) j.toJson()],
      };

  factory RunState.fromJson(Map<String, dynamic> json) => RunState(
        version: json['version'] as int? ?? 1,
        total: json['total'] as int? ?? 0,
        jobs: [
          for (final j in (json['jobs'] as List? ?? const []))
            PermJob.fromJson(Map<String, dynamic>.from(j as Map)),
        ],
        startedAt: json['startedAt'] as String? ?? DateTime.now().toIso8601String(),
        updatedAt: json['updatedAt'] as String? ?? DateTime.now().toIso8601String(),
        initialSettings: json['initialSettings'] == null
            ? null
            : Map<String, Object?>.from(json['initialSettings'] as Map),
        lastUploadedCsv: json['lastUploadedCsv'] as String?,
        fixtureDir: json['fixtureDir'] as String?,
      );

  static RunState build({
    required List<Map<String, dynamic>> csvIndex,
    required String fixtureDir,
  }) {
    final jobs = <PermJob>[];
    for (final csv in csvIndex) {
      final csvName = csv['name'] as String;
      final csvFile = csv['file'] as String;
      for (final vonBis in [false, true]) {
        for (final kursnamen in [false, true]) {
          for (final vergleich in vergleichOptions) {
            final id =
                '${csvName}__vonbis-${vonBis ? 1 : 0}__kursnamen-${kursnamen ? 1 : 0}__vergleich-${_slug(vergleich.value)}';
            jobs.add(
              PermJob(
                id: id,
                csvName: csvName,
                csvFile: csvFile,
                vonBisAusblenden: vonBis,
                kursnamenEinblenden: kursnamen,
                vergleich: vergleich.value,
                vergleichLabel: vergleich.label,
              ),
            );
          }
        }
      }
    }
    final now = DateTime.now().toIso8601String();
    return RunState(
      version: 1,
      total: jobs.length,
      jobs: jobs,
      startedAt: now,
      updatedAt: now,
      fixtureDir: fixtureDir,
    );
  }
}

String _slug(String value) {
  if (value == '-' || value.isEmpty) return 'none';
  final s = value.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
  return s.isEmpty ? 'empty' : s;
}

// ---------------------------------------------------------------------------
// SPH admin / upload / capture
// ---------------------------------------------------------------------------

Future<Map<String, Object?>> readCurrentSettings(LanisSession session) async {
  final html = (await session.dio.get(stundenplanUrl('e=1&a=admin'))).data
      .toString();
  final doc = parse(html);
  final vonBis = doc.querySelector('#VonBisAusblenden');
  final kursnamen = doc.querySelector('#KursnamenEinblenden');
  final select = doc.querySelector('select[name="kursnamenvergleich"]');
  String vergleich = '-';
  if (select != null) {
    final selected = select.querySelector('option[selected]');
    vergleich = selected?.attributes['value'] ??
        select.querySelector('option')?.attributes['value'] ??
        '-';
  }
  return {
    'vonBisAusblenden': vonBis?.attributes.containsKey('checked') ?? false,
    'kursnamenEinblenden':
        kursnamen?.attributes.containsKey('checked') ?? false,
    'vergleich': vergleich,
  };
}

Future<void> applyDisplaySettings(
  LanisSession session, {
  required bool vonBisAusblenden,
  required bool kursnamenEinblenden,
}) async {
  final data = <String, dynamic>{
    'a': 'admin',
    'b': 'Anzeigeeinstellungen',
  };
  // Unchecked boxes are omitted; checked boxes are sent.
  if (vonBisAusblenden) data['VonBisAusblenden'] = 'on';
  if (kursnamenEinblenden) data['KursnamenEinblenden'] = 'on';
  final resp = await session.dio.post(
    stundenplanUrl('a=admin'),
    data: data,
    options: formOpts,
  );
  stdout.writeln(
    '  settings Anzeige vonBis=$vonBisAusblenden kursnamen=$kursnamenEinblenden '
    '-> HTTP ${resp.statusCode}',
  );
}

Future<void> applyVergleich(LanisSession session, String vergleich) async {
  final resp = await session.dio.post(
    stundenplanUrl('a=admin'),
    data: {
      'a': 'admin',
      'kursnamenvergleich': vergleich,
    },
    options: formOpts,
  );
  stdout.writeln(
    '  settings vergleich=$vergleich -> HTTP ${resp.statusCode}',
  );
}

Future<void> applyAllSettings(
  LanisSession session, {
  required bool vonBisAusblenden,
  required bool kursnamenEinblenden,
  required String vergleich,
}) async {
  await applyDisplaySettings(
    session,
    vonBisAusblenden: vonBisAusblenden,
    kursnamenEinblenden: kursnamenEinblenden,
  );
  await applyVergleich(session, vergleich);
}

Future<void> deleteAllPlans(LanisSession session) async {
  await session.dio.post(
    stundenplanUrl(),
    data: {'a': 'delete', 'b': 'all'},
    options: formOpts,
  );
  await session.dio.post(
    stundenplanUrl(),
    data: {'a': 'delete', 'b': 'time', 'date': todayIso()},
    options: formOpts,
  );
}

Future<void> uploadCsv(LanisSession session, File csv) async {
  final form = FormData.fromMap({
    'a': 'import',
    'type': 'csv',
    'ab': todayDe(),
    'file': await MultipartFile.fromFile(
      csv.path,
      filename: p.basename(csv.path),
    ),
  });
  final resp = await session.dio.post(
    stundenplanUrl(),
    data: form,
    options: Options(
      headers: {
        'Accept': '*/*',
        'Content-Type': 'multipart/form-data;',
        'Cache-Control': 'no-cache',
      },
      validateStatus: (s) => s != null && s < 500,
    ),
  );
  stdout.writeln(
    '  upload ${p.basename(csv.path)} -> HTTP ${resp.statusCode}',
  );
}

Future<String> fetchStudentHtml(LanisSession session) async {
  final response1 = await session.dio.get(
    stundenplanUrl(),
    options: Options(
      headers: {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
      validateStatus: (s) => s != null && s < 500,
    ),
  );
  var html = response1.data.toString();
  if (parse(html).getElementById('all') != null) return html;
  final location = response1.headers.value('location');
  if (location == null || location.isEmpty) return html;
  final target = location.startsWith('http')
      ? '$location${location.contains('?') ? '&' : '?'}${cachebreaker()}'
      : stundenplanUrl(location.contains('?')
          ? location.split('?').last
          : '');
  final response2 = await session.dio.get(
    target.startsWith('http')
        ? target
        : 'https://start.schulportal.hessen.de/$location'
            '${location.contains('?') ? '&' : '?'}${cachebreaker()}',
    options: Options(
      headers: {'Cache-Control': 'no-cache'},
      validateStatus: (s) => s != null && s < 500,
    ),
  );
  return response2.data.toString();
}

Set<String> csvMarkers(File csv) {
  final markers = <String>{};
  for (final line in csv.readAsLinesSync().skip(1)) {
    if (line.trim().isEmpty) continue;
    final parts = line.split(';');
    if (parts.length < 10) continue;
    final raum = parts[5].trim();
    if (raum.startsWith('RM')) markers.add(raum);
  }
  return markers;
}

Future<String> waitForStudentPlan({
  required LanisSession session,
  required Set<String> markers,
  required bool expectEmpty,
  required String settingsFingerprint,
  Duration timeout = const Duration(seconds: 60),
}) async {
  final deadline = DateTime.now().add(timeout);
  String last = '';
  var attempt = 0;
  while (DateTime.now().isBefore(deadline)) {
    attempt++;
    last = await fetchStudentHtml(session);
    final doc = parse(last);
    final stunde = doc.querySelectorAll('.stunde').length;
    final vonBis = doc.querySelectorAll('.VonBis').length;
    final hasMarker = markers.any(last.contains);
    // Settings that hide times: allow marker-only readiness when vonBis==0.
    final timesHiddenOk =
        settingsFingerprint.contains('vonbis-1') && hasMarker && stunde > 0;
    stdout.writeln(
      '  poll #$attempt: stunde=$stunde VonBis=$vonBis marker=$hasMarker',
    );
    if (expectEmpty && stunde == 0) return last;
    if (!expectEmpty && (hasMarker || timesHiddenOk) && stunde > 0) {
      return last;
    }
    if (!expectEmpty && markers.isEmpty && stunde >= 0) {
      // empty CSV under non-empty settings — accept after a couple polls
      if (attempt >= 3) return last;
    }
    await Future<void>.delayed(const Duration(milliseconds: 800));
  }
  stdout.writeln('  poll timeout — using last HTML');
  return last;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

Future<void> main(List<String> args) async {
  var adminEnv = '.adminaccount.env';
  var studentEnv = '.studentaccount.env';
  var statePath = 'tool/timetable/run/state.json';
  var fixtureDir = 'test/fixtures/timetable';
  var dryRun = false;
  var reset = false;
  var retryFailed = false;
  int? limit;
  var restoreSettings = true;

  for (final arg in args) {
    if (arg.startsWith('--admin-env=')) {
      adminEnv = arg.substring('--admin-env='.length);
    } else if (arg.startsWith('--student-env=')) {
      studentEnv = arg.substring('--student-env='.length);
    } else if (arg.startsWith('--state=')) {
      statePath = arg.substring('--state='.length);
    } else if (arg.startsWith('--fixture-dir=')) {
      fixtureDir = arg.substring('--fixture-dir='.length);
    } else if (arg == '--dry-run') {
      dryRun = true;
    } else if (arg == '--reset') {
      reset = true;
    } else if (arg == '--retry-failed') {
      retryFailed = true;
    } else if (arg == '--no-restore-settings') {
      restoreSettings = false;
    } else if (arg.startsWith('--limit=')) {
      limit = int.tryParse(arg.substring('--limit='.length));
    } else if (arg == '--help' || arg == '-h') {
      stdout.writeln('''
Usage: dart run tool/timetable/generate_permutations.dart [options]

  --dry-run              Build/update state.json only (no network writes)
  --reset                Rebuild job list from scratch (discards progress)
  --retry-failed         Re-queue failed jobs as pending
  --limit=N              Process at most N pending jobs this run
  --state=PATH           State file (default tool/timetable/run/state.json)
  --fixture-dir=PATH     HTML output dir
  --no-restore-settings  Do not restore admin settings at the end
''');
      return;
    }
  }

  final root = Directory.current.path;
  final stateFile = File(p.join(root, statePath));
  await stateFile.parent.create(recursive: true);
  final outDir = Directory(p.join(root, fixtureDir));
  await outDir.create(recursive: true);

  final indexFile = File(p.join(root, 'tool/timetable/csvs/index.json'));
  if (!indexFile.existsSync()) {
    stderr.writeln('Missing ${indexFile.path}. Run generate_csvs.dart first.');
    exitCode = 1;
    return;
  }
  final csvIndex = (jsonDecode(await indexFile.readAsString()) as List)
      .cast<Map<String, dynamic>>();

  RunState state;
  if (!reset && stateFile.existsSync()) {
    state = RunState.fromJson(
      jsonDecode(await stateFile.readAsString()) as Map<String, dynamic>,
    );
    stdout.writeln(
      'Resuming state: total=${state.total} done=${state.doneCount} '
      'failed=${state.failedCount} pending=${state.pendingCount}',
    );
    if (retryFailed) {
      for (final j in state.jobs.where((j) => j.status == 'failed')) {
        j.status = 'pending';
        j.error = null;
      }
    }
    // Mark interrupted "running" jobs as pending again.
    for (final j in state.jobs.where((j) => j.status == 'running')) {
      j.status = 'pending';
    }
  } else {
    state = RunState.build(csvIndex: csvIndex, fixtureDir: fixtureDir);
    stdout.writeln(
      'Created new state with ${state.total} jobs '
      '(2×2×${vergleichOptions.length}×${csvIndex.length}).',
    );
  }
  state.fixtureDir = fixtureDir;

  Future<void> persist() async {
    state.updatedAt = DateTime.now().toIso8601String();
    final tmp = File('${stateFile.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(state.toJson()),
    );
    await tmp.rename(stateFile.path);
  }

  await persist();

  if (dryRun) {
    stdout.writeln('Dry-run complete. State at ${stateFile.path}');
    stdout.writeln(
      'Pending=${state.pendingCount} done=${state.doneCount} failed=${state.failedCount}',
    );
    return;
  }

  EasyLanisClient? admin;
  EasyLanisClient? student;
  try {
    admin = await loginFromEnv(adminEnv);
    student = await loginFromEnv(studentEnv);
    stdout.writeln(
      'Logged in admin=${admin.session!.accountTypeOrNull} '
      'student=${student.session!.accountTypeOrNull}',
    );

    state.initialSettings ??=
        await readCurrentSettings(admin.session!);
    await persist();

    final pending = state.jobs.where((j) => j.status == 'pending').toList();
    final batch = limit == null ? pending : pending.take(limit).toList();
    stdout.writeln('Processing ${batch.length} of ${pending.length} pending jobs…');

    // Group by CSV so each plan is uploaded once per contiguous settings block.
    String? activeCsv;

    for (final job in batch) {
      job.status = 'running';
      state.updatedAt = DateTime.now().toIso8601String();
      await persist();

      stdout.writeln('=== ${job.id} ===');
      try {
        final csv = File(p.join(root, job.csvFile));
        if (!csv.existsSync()) {
          throw StateError('Missing CSV ${job.csvFile}');
        }

        if (activeCsv != job.csvName) {
          await deleteAllPlans(admin.session!);
          await uploadCsv(admin.session!, csv);
          activeCsv = job.csvName;
          state.lastUploadedCsv = job.csvName;
          await persist();
        }

        await applyAllSettings(
          admin.session!,
          vonBisAusblenden: job.vonBisAusblenden,
          kursnamenEinblenden: job.kursnamenEinblenden,
          vergleich: job.vergleich,
        );

        final markers = csvMarkers(csv);
        final expectEmpty = job.csvName.contains('empty') || markers.isEmpty;
        final html = await waitForStudentPlan(
          session: student.session!,
          markers: markers,
          expectEmpty: expectEmpty,
          settingsFingerprint: job.id,
        );

        final fixtureRel = p.join(fixtureDir, '${job.id}.html');
        final fixtureFile = File(p.join(root, fixtureRel));
        await fixtureFile.writeAsString(html);

        final doc = parse(html);
        job
          ..status = 'done'
          ..fixture = fixtureRel
          ..bytes = html.length
          ..stunde = doc.querySelectorAll('.stunde').length
          ..vonBis = doc.querySelectorAll('.VonBis').length
          ..hasAll = doc.getElementById('all') != null
          ..hasOwn = doc.getElementById('own') != null
          ..completedAt = DateTime.now().toIso8601String()
          ..error = null;

        stdout.writeln(
          '  saved $fixtureRel bytes=${job.bytes} '
          'stunde=${job.stunde} VonBis=${job.vonBis}',
        );
      } catch (e, st) {
        job
          ..status = 'failed'
          ..error = e.toString()
          ..completedAt = DateTime.now().toIso8601String();
        stderr.writeln('  FAILED ${job.id}: $e');
        stderr.writeln('$st');
        // Force re-upload next time in case plan/settings are inconsistent.
        activeCsv = null;
      }

      await persist();
    }

    if (restoreSettings && state.initialSettings != null) {
      final s = state.initialSettings!;
      stdout.writeln('Restoring initial admin settings…');
      await applyAllSettings(
        admin.session!,
        vonBisAusblenden: s['vonBisAusblenden'] as bool? ?? false,
        kursnamenEinblenden: s['kursnamenEinblenden'] as bool? ?? false,
        vergleich: s['vergleich'] as String? ?? 'kuerzel',
      );
    }
  } finally {
    await admin?.logout();
    await admin?.dispose();
    await student?.logout();
    await student?.dispose();
    await persist();
  }

  // Manifest of completed fixtures
  final manifest = [
    for (final j in state.jobs.where((j) => j.status == 'done')) j.toJson(),
  ];
  await File(p.join(root, fixtureDir, 'manifest.json')).writeAsString(
    const JsonEncoder.withIndent('  ').convert(manifest),
  );

  stdout.writeln(
    'Done. total=${state.total} done=${state.doneCount} '
    'failed=${state.failedCount} pending=${state.pendingCount}',
  );
  stdout.writeln('State: ${stateFile.path}');
  stdout.writeln('Fixtures: $fixtureDir');
}
