/// Scrape kalender admin/settings pages + module JS endpoints.
///
/// ```sh
/// dart run tool/calendar/scrape_settings.dart --env=.adminaccount.env
/// ```
library;

import 'dart:convert';
import 'dart:io';

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
    userAgent: 'liblanis-calendar-settings/0.1.0',
  );
  await client.login();
  final session = client.session!;
  final out = Directory('tool/calendar/discovery/settings')
    ..createSync(recursive: true);

  final routes = <String, String>{
    'home': 'kalender.php',
    'my': 'kalender.php?a=my',
    'arten': 'kalender.php?a=arten',
    'gruppen': 'kalender.php?a=gruppen',
    'einst': 'kalender.php?a=einst',
    'usesheets': 'kalender.php?a=usesheets',
    'js': 'module/kalender/js/kalender.js?i=20201123',
  };

  final summary = <String, Object?>{};
  for (final entry in routes.entries) {
    final url =
        'https://start.schulportal.hessen.de/${entry.value}${entry.value.contains('?') ? '&' : '?'}${cb()}';
    final resp = await session.dio.get(url);
    final body = resp.data.toString();
    final file = '${entry.key}.${entry.key == 'js' ? 'js' : 'html'}';
    await File(p.join(out.path, file)).writeAsString(body);
    summary[entry.key] = {
      'status': resp.statusCode,
      'bytes': body.length,
      'file': 'tool/calendar/discovery/settings/$file',
    };
    stdout.writeln('${entry.key}: ${body.length} bytes');
  }

  // Pull f= values from kalender.js
  final js = await File(p.join(out.path, 'js.js')).readAsString();
  final fValues = RegExp(r"""['"]f['"]\s*:\s*['"]([^'"]+)['"]""")
      .allMatches(js)
      .map((m) => m.group(1)!)
      .toSet()
      .toList()
    ..sort();
  final fEquals = RegExp(r'f=([a-zA-Z0-9_]+)')
      .allMatches(js)
      .map((m) => m.group(1)!)
      .toSet()
      .toList()
    ..sort();
  summary['jsEndpoints'] = {'fColon': fValues, 'fEquals': fEquals};
  stdout.writeln('f: endpoints: $fValues');
  stdout.writeln('f= endpoints: $fEquals');

  await File(p.join(out.path, 'summary.json')).writeAsString(
    const JsonEncoder.withIndent('  ').convert(summary),
  );
  await client.logout();
  await client.dispose();
}
