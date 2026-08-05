/// Scrape vertretungsplan admin/settings pages (discovered routes).
///
/// ```sh
/// dart run tool/substitutions/scrape_settings.dart
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:liblanis/easy_client.dart';
import 'package:path/path.dart' as p;

Map<String, String> loadDotEnv(String path) {
  final map = <String, String>{};
  for (final raw in File(path).readAsLinesSync()) {
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
  var envPath = '.adminaccount.env';
  for (final arg in args) {
    if (arg.startsWith('--env=')) envPath = arg.substring('--env='.length);
  }
  final env = loadDotEnv(envPath);
  final client = EasyLanisClient.ephemeral(
    schoolId: int.parse(env['SCHOOLID']!),
    username: env['USERNAME']!,
    password: env['PASSWORD']!,
    userAgent: 'liblanis-substitutions-settings/0.1.0',
  );
  await client.login();
  final session = client.session!;
  final out = Directory('tool/substitutions/discovery/settings')
    ..createSync(recursive: true);

  // Routes discovered from admin nav + common guesses.
  final routes = <String, String>{
    'home': 'vertretungsplan.php',
    'my': 'vertretungsplan.php?a=my',
    'print': 'vertretungsplan.php?a=print',
    'admin': 'vertretungsplan.php?a=admin',
    'boards': 'vertretungsplan.php?a=boards',
    'infos': 'vertretungsplan.php?a=infos',
    'lauftext': 'vertretungsplan.php?a=lauftext&wx=0',
    'uploadManuell': 'vertretungsplan.php?a=uploadManuell&wx=0',
    'usesheets': 'vertretungsplan.php?a=usesheets',
  };

  final summary = <String, Object?>{};
  for (final entry in routes.entries) {
    final url =
        'https://start.schulportal.hessen.de/${entry.value}${entry.value.contains('?') ? '&' : '?'}${cb()}';
    final resp = await session.dio.get(
      url,
      options: Options(validateStatus: (_) => true),
    );
    final body = resp.data.toString();
    final loc = resp.headers.value('location');
    final file = '${entry.key}.html';
    await File(p.join(out.path, file)).writeAsString(body);
    summary[entry.key] = {
      'status': resp.statusCode,
      'bytes': body.length,
      'location': loc,
      'file': 'tool/substitutions/discovery/settings/$file',
      'hasFileInput': body.contains('type="file"'),
      'hasForm': body.contains('<form'),
      'dotDates': RegExp(
        r'data-tag="\d{2}\.\d{2}\.\d{4}"',
      ).allMatches(body).length,
    };
    stdout.writeln(
      '${entry.key}: status=${resp.statusCode} bytes=${body.length}',
    );
  }

  // Axes for individuelle consumer-affecting settings (from a=admin form).
  summary['consumerSettingAxes'] = {
    'strike': ['ja', 'nein'],
    'lehrerklar': ['nachname', 'vorname', 'nein'],
    'stundenanzeige': ['kurz', 'lang'],
    'farbigeZeilen': ['yes', 'no'],
    'vergleichBeiSuS': [
      'klasse-stufe',
      'klasse-stufe-lerngruppe',
      'klasse-stufe-lerngruppe-stundenplan',
    ],
    'skipDays': ['onlyInfos', 'no'],
    'zeigeStand': ['ja', 'nein'],
    'zeigeStandLuL': ['ja', 'nein'],
  };

  summary['shellAxes'] = {
    'student': ['', 'a=my', 'a=print'],
    'admin': [
      '',
      'a=my',
      'a=print',
      'a=admin',
      'a=boards',
      'a=infos',
      'a=lauftext&wx=0',
      'a=uploadManuell&wx=0',
      'a=usesheets',
    ],
  };

  summary['ajaxStyles'] = [
    'parser',
    'ganzer_false',
    'no_ganzer',
    'no_a',
    'empty_tag',
    'invalid_tag',
  ];

  await File(p.join(out.path, 'summary.json')).writeAsString(
    const JsonEncoder.withIndent('  ').convert(summary),
  );
  await File('tool/substitutions/discovery/axes.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'consumerSettingAxes': summary['consumerSettingAxes'],
      'shellAxes': summary['shellAxes'],
      'ajaxStyles': summary['ajaxStyles'],
      'writable': {
        'uploadManuell': true,
        'formats': [
          'csv-kuerzel',
          'csv-nachname',
          'untis-dif-browser',
          'asc-timetables',
        ],
        'note':
            'Dropzone CSV upload exists; live school currently has empty plan. '
            'Content coverage uses synthetic fixtures + live empty shells.',
      },
    }),
  );

  await client.logout();
  await client.dispose();
}
