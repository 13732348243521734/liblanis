/// Discover kalender.php surface area (page markers, forms, getEvents shapes).
///
/// Loads credentials from dotenv itself (never prints secrets).
///
/// ```sh
/// dart run tool/calendar/discover.dart
/// dart run tool/calendar/discover.dart --env=.studentaccount.env
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' show parse;
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

Future<void> main(List<String> args) async {
  var envPath = '.studentaccount.env';
  for (final arg in args) {
    if (arg.startsWith('--env=')) envPath = arg.substring('--env='.length);
  }

  final env = loadDotEnv(envPath);
  final schoolId = int.tryParse(env['SCHOOLID'] ?? '');
  final username = env['USERNAME'];
  final password = env['PASSWORD'];
  if (schoolId == null ||
      username == null ||
      username.isEmpty ||
      password == null ||
      password.isEmpty) {
    stderr.writeln('Missing SCHOOLID/USERNAME/PASSWORD in $envPath');
    exitCode = 64;
    return;
  }

  final root = Directory.current.path;
  final out = Directory(p.join(root, 'tool/calendar/discovery'))
    ..createSync(recursive: true);

  final client = EasyLanisClient.ephemeral(
    schoolId: schoolId,
    username: username,
    password: password,
    userAgent: 'liblanis-calendar-discover/0.1.0',
  );
  await client.login();
  final session = client.session!;
  stdout.writeln(
    'Logged in. applets=${client.supportedApplets.join(',')}',
  );

  final pageUrl =
      'https://start.schulportal.hessen.de/kalender.php?${cb()}';
  final page = await session.dio.get(pageUrl);
  final html = page.data.toString();
  await File(p.join(out.path, 'kalender.html')).writeAsString(html);

  final hasCategoriesMarker = html.contains('var categories = new Array();');
  final hasGroupsMarker = html.contains('var groups = new Array();');
  final categoryLineCount = RegExp(
    r'categories\.push\s*\(',
  ).allMatches(html).length;

  final doc = parse(html);
  final forms = [
    for (final form in doc.querySelectorAll('form'))
      {
        'action': form.attributes['action'],
        'method': form.attributes['method'],
        'inputs': [
          for (final input in form.querySelectorAll('input,select,textarea'))
            {
              'tag': input.localName,
              'name': input.attributes['name'],
              'type': input.attributes['type'],
              'value': (input.attributes['value'] ?? '').length > 80
                  ? '${input.attributes['value']!.substring(0, 80)}…'
                  : input.attributes['value'],
            },
        ],
      },
  ];

  final links = doc
      .querySelectorAll('a[href*="kalender.php"]')
      .map((a) => a.attributes['href'] ?? '')
      .where((h) => h.isNotEmpty)
      .toSet()
      .take(40)
      .toList();

  final formatter = DateFormat('yyyy-MM-dd');
  final now = DateTime.now();
  final start = now.subtract(const Duration(days: 120));
  final end = now.add(const Duration(days: 356));
  final startFmt = formatter.format(start);
  final endFmt = formatter.format(end);

  // Mirror production request shapes (including the buggy body formatting).
  final probes = <String, Future<Response>>{
    'getEvents_query_fmt_body_fmt': session.dio.post(
      'https://start.schulportal.hessen.de/kalender.php?${cb()}',
      queryParameters: {
        'f': 'getEvents',
        's': '',
        'start': startFmt,
        'end': endFmt,
      },
      data: 'f=getEvents&start=$startFmt&end=$endFmt&s=',
      options: Options(
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        },
        validateStatus: (_) => true,
      ),
    ),
    'getEvents_query_fmt_body_datetime': session.dio.post(
      'https://start.schulportal.hessen.de/kalender.php?${cb()}',
      queryParameters: {
        'f': 'getEvents',
        's': '',
        'start': startFmt,
        'end': endFmt,
      },
      // Exact CalendarParser body style today.
      data: 'f=getEvents&start=$start&end=$end&s=',
      options: Options(
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        },
        validateStatus: (_) => true,
      ),
    ),
    'getEvents_body_only_fmt': session.dio.post(
      'https://start.schulportal.hessen.de/kalender.php?${cb()}',
      data: {
        'f': 'getEvents',
        'start': startFmt,
        'end': endFmt,
        's': '',
      },
      options: Options(
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        },
        validateStatus: (_) => true,
      ),
    ),
  };

  final probeSummary = <String, Object?>{};
  for (final entry in probes.entries) {
    final resp = await entry.value;
    final body = resp.data.toString();
    final path = p.join(out.path, '${entry.key}.txt');
    await File(path).writeAsString(body);
    Object? decoded;
    String decodeError = '';
    try {
      decoded = jsonDecode(body);
    } catch (e) {
      decodeError = e.toString();
    }
    probeSummary[entry.key] = {
      'status': resp.statusCode,
      'bytes': body.length,
      'contentType': resp.headers.value('content-type'),
      'startsWith': body.length > 80 ? body.substring(0, 80) : body,
      'jsonType': decoded == null
          ? null
          : decoded is List
          ? 'list(len=${decoded.length})'
          : decoded.runtimeType.toString(),
      'decodeError': decodeError.isEmpty ? null : decodeError,
      'file': p.relative(path, from: root),
    };
    stdout.writeln(
      '${entry.key}: status=${resp.statusCode} bytes=${body.length} '
      'json=${(probeSummary[entry.key] as Map)['jsonType'] ?? decodeError}',
    );
  }

  final summary = {
    'schoolId': schoolId,
    'pageBytes': html.length,
    'hasCategoriesMarker': hasCategoriesMarker,
    'hasGroupsMarker': hasGroupsMarker,
    'categoryPushCount': categoryLineCount,
    'forms': forms,
    'kalenderLinks': links,
    'probes': probeSummary,
    'dateWindow': {'start': startFmt, 'end': endFmt},
  };
  await File(p.join(out.path, 'summary.json')).writeAsString(
    const JsonEncoder.withIndent('  ').convert(summary),
  );
  stdout.writeln('Wrote ${out.path}/summary.json');

  await client.logout();
  await client.dispose();
}
