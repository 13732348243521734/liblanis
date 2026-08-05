/// Discover vertretungsplan.php surface (shell, dates, AJAX shapes, forms).
///
/// ```sh
/// dart run tool/substitutions/discover.dart
/// dart run tool/substitutions/discover.dart --env=.adminaccount.env
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' show parse;
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

List<String> extractDotDates(String html) {
  final re = RegExp(r'data-tag="(\d{2}\.\d{2}\.\d{4})"');
  final out = <String>[];
  for (final m in re.allMatches(html)) {
    final d = m.group(1)!;
    if (!out.contains(d)) out.add(d);
  }
  return out;
}

List<String> extractUnderscoreDates(String html) {
  final re = RegExp(r'data-tag="(\d{2}_\d{2}_\d{4})"');
  final out = <String>[];
  for (final m in re.allMatches(html)) {
    final d = m.group(1)!;
    if (!out.contains(d)) out.add(d);
  }
  return out;
}

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
  final role = envPath.contains('admin') ? 'admin' : 'student';
  final out = Directory(p.join(root, 'tool/substitutions/discovery'))
    ..createSync(recursive: true);

  final client = EasyLanisClient.ephemeral(
    schoolId: schoolId,
    username: username,
    password: password,
    userAgent: 'liblanis-substitutions-discover/0.1.0',
  );
  await client.login();
  final session = client.session!;
  stdout.writeln(
    'Logged in as $role. applets=${client.supportedApplets.join(',')}',
  );

  final pageUrl =
      'https://start.schulportal.hessen.de/vertretungsplan.php?${cb()}';
  final page = await session.dio.get(pageUrl);
  final html = page.data.toString();
  await File(p.join(out.path, 'vertretungsplan_$role.html')).writeAsString(html);

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
              'options': input.localName == 'select'
                  ? [
                      for (final o in input.querySelectorAll('option'))
                        {
                          'value': o.attributes['value'],
                          'text': o.text.trim(),
                        },
                    ]
                  : null,
            },
        ],
      },
  ];

  final links = doc
      .querySelectorAll('a[href*="vertretungsplan.php"]')
      .map((a) => a.attributes['href'] ?? '')
      .where((h) => h.isNotEmpty)
      .toSet()
      .toList()
    ..sort();

  final aParams = <String>{};
  for (final href in links) {
    final m = RegExp(r'[?&]a=([^&#]+)').firstMatch(href);
    if (m != null) aParams.add(Uri.decodeComponent(m.group(1)!));
  }
  for (final form in forms) {
    for (final input in (form['inputs'] as List<dynamic>)) {
      final map = input as Map<String, dynamic>;
      if (map['name'] == 'a' && map['value'] != null) {
        aParams.add('${map['value']}');
      }
    }
  }

  final dotDates = extractDotDates(html);
  final usDates = extractUnderscoreDates(html);
  final mode = dotDates.isNotEmpty
      ? 'ajax'
      : usDates.isNotEmpty
      ? 'non_ajax'
      : 'empty_or_unknown';

  final hasFehler = html.contains('Fehler - Schulportal Hessen - ');
  final lastEdit = RegExp(
    r'Letzte\s+Aktualisierung:\s*(\d{2}\.\d{2}\.\d{4})\s+um\s+(\d{2}:\d{2}:\d{2})',
    caseSensitive: false,
  ).firstMatch(html);

  // Probe AJAX request styles for first date (or a synthetic tag).
  final probeTag = dotDates.isNotEmpty ? dotDates.first : '01.01.2099';
  final ajaxProbes = <String, Map<String, String>>{
    'parser': {'a': 'my', 'tag': probeTag, 'ganzerPlan': 'true'},
    'ganzer_false': {'a': 'my', 'tag': probeTag, 'ganzerPlan': 'false'},
    'no_ganzer': {'a': 'my', 'tag': probeTag},
    'no_a': {'tag': probeTag, 'ganzerPlan': 'true'},
    'empty_tag': {'a': 'my', 'tag': '', 'ganzerPlan': 'true'},
    'invalid_tag': {'a': 'my', 'tag': '99.99.9999', 'ganzerPlan': 'true'},
  };

  final probeSummary = <String, Object?>{};
  for (final entry in ajaxProbes.entries) {
    final qp = <String, dynamic>{};
    final body = <String, dynamic>{};
    entry.value.forEach((k, v) {
      if (k == 'a') {
        qp['a'] = v;
      } else {
        body[k] = v;
      }
    });
    final resp = await session.dio.post(
      'https://start.schulportal.hessen.de/vertretungsplan.php?${cb()}',
      queryParameters: qp.isEmpty ? null : qp,
      data: body,
      options: Options(
        headers: {
          'Accept': '*/*',
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        },
        validateStatus: (_) => true,
      ),
    );
    final bodyStr = resp.data.toString();
    final fileName = 'ajax_${role}_${entry.key}.txt';
    await File(p.join(out.path, fileName)).writeAsString(bodyStr);
    Object? decoded;
    String? decodeError;
    try {
      decoded = jsonDecode(bodyStr);
    } catch (e) {
      decodeError = e.toString();
    }
    probeSummary[entry.key] = {
      'status': resp.statusCode,
      'bytes': bodyStr.length,
      'contentType': resp.headers.value('content-type'),
      'startsWith': bodyStr.length > 100 ? bodyStr.substring(0, 100) : bodyStr,
      'jsonType': decoded == null
          ? null
          : decoded is List
          ? 'list(len=${decoded.length})'
          : decoded.runtimeType.toString(),
      'decodeError': decodeError,
      'file': 'tool/substitutions/discovery/$fileName',
    };
    stdout.writeln(
      'ajax ${entry.key}: status=${resp.statusCode} bytes=${bodyStr.length} '
      'json=${(probeSummary[entry.key] as Map)['jsonType'] ?? decodeError}',
    );
  }

  // Fetch AJAX for every live date with parser style.
  final dayFiles = <String, Object?>{};
  for (final date in dotDates) {
    final resp = await session.dio.post(
      'https://start.schulportal.hessen.de/vertretungsplan.php?${cb()}',
      queryParameters: {'a': 'my'},
      data: {'tag': date, 'ganzerPlan': 'true'},
      options: Options(
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        },
        validateStatus: (_) => true,
      ),
    );
    final bodyStr = resp.data.toString();
    final safe = date.replaceAll('.', '_');
    final fileName = 'day_${role}_$safe.json';
    await File(p.join(out.path, fileName)).writeAsString(bodyStr);
    Object? decoded;
    try {
      decoded = jsonDecode(bodyStr);
    } catch (_) {}
    dayFiles[date] = {
      'bytes': bodyStr.length,
      'rows': decoded is List ? decoded.length : null,
      'file': 'tool/substitutions/discovery/$fileName',
    };
  }

  // Shell query variants from discovered a= params + common guesses.
  final shellGuesses = <String>{
    '',
    'a=my',
    'e=1',
    'a=print',
    'a=einst',
    'a=upload',
    'a=import',
    'a=admin',
    ...aParams.map((a) => 'a=$a'),
  };
  final shellSummary = <String, Object?>{};
  for (final q in shellGuesses) {
    final url =
        'https://start.schulportal.hessen.de/vertretungsplan.php${q.isEmpty ? '?' : '?$q&'}${cb()}';
    final resp = await session.dio.get(
      url,
      options: Options(validateStatus: (_) => true),
    );
    final body = resp.data.toString();
    final key = q.isEmpty ? 'bare' : q.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
    final fileName = 'shell_${role}_$key.html';
    await File(p.join(out.path, fileName)).writeAsString(body);
    shellSummary[key] = {
      'query': q,
      'status': resp.statusCode,
      'bytes': body.length,
      'dotDates': extractDotDates(body).length,
      'usDates': extractUnderscoreDates(body).length,
      'shaPrefix': body.hashCode.toRadixString(16),
    };
  }

  final summary = {
    'role': role,
    'env': envPath,
    'schoolId': schoolId,
    'pageBytes': html.length,
    'mode': mode,
    'hasFehler': hasFehler,
    'dotDates': dotDates,
    'underscoreDates': usDates,
    'lastEdit': lastEdit == null
        ? null
        : '${lastEdit.group(1)} ${lastEdit.group(2)}',
    'forms': forms,
    'links': links,
    'aParams': aParams.toList()..sort(),
    'ajaxProbes': probeSummary,
    'days': dayFiles,
    'shellVariants': shellSummary,
    'writableHints': {
      'hasFileInput': html.contains('type="file"'),
      'hasImport': html.toLowerCase().contains('import'),
      'hasUpload': html.toLowerCase().contains('upload'),
      'hasCsv': html.toLowerCase().contains('csv'),
    },
  };

  final summaryPath = p.join(out.path, 'summary_$role.json');
  await File(summaryPath).writeAsString(
    const JsonEncoder.withIndent('  ').convert(summary),
  );
  // Keep a convenience pointer for the student run.
  if (role == 'student') {
    await File(p.join(out.path, 'summary.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert(summary),
    );
  }
  stdout.writeln('Wrote $summaryPath mode=$mode dates=${dotDates.length}');

  await client.logout();
  await client.dispose();
}
