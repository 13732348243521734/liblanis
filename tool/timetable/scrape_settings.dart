/// Scrape Stundenplan admin/settings pages that may affect student HTML.
library;

import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart' show parse;
import 'package:liblanis/easy_client.dart';
import 'package:path/path.dart' as p;

Map<String, String> _loadDotEnv(String path) {
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

String _cb() => '_cachebreaker=${DateTime.now().millisecondsSinceEpoch}';

Future<void> main() async {
  final env = _loadDotEnv('.adminaccount.env');
  final client = EasyLanisClient.ephemeral(
    schoolId: int.parse(env['SCHOOLID']!),
    username: env['USERNAME']!,
    password: env['PASSWORD']!,
    userAgent: 'liblanis-timetable-settings/0.1.0',
  );
  await client.login();
  final session = client.session!;
  final out = Directory('tool/timetable/discovery/settings')..createSync(recursive: true);

  final routes = <String, String>{
    'upload': 'stundenplan.php?e=1&a=upload',
    'admin': 'stundenplan.php?e=1&a=admin',
    'wochen': 'stundenplan.php?e=1&a=wochen',
    'delete': 'stundenplan.php?e=1&a=delete',
    'start': 'stundenplan.php?a=start&e=1',
    'detail_klasse': 'stundenplan.php?a=detail_klasse&e=1',
    'detail_klasse_1': 'stundenplan.php?e=1&a=detail_klasse&k=1',
    'detail_lehrer': 'stundenplan.php?a=detail&e=1&t=lernsys',
    'leistenplan': 'stundenplan.php?e=1&a=leistenplan',
    'uv_admin': 'stundenplan.php?e=1&a=unterrichtsverteilungAdmin',
    'raster_guess': 'stundenplan.php?a=raster',
    'einstellungen_guess': 'stundenplan.php?e=1&a=einstellungen',
    'settings_guess': 'stundenplan.php?e=1&a=settings',
    'config_guess': 'stundenplan.php?e=1&a=config',
  };

  final summary = <String, Object?>{};
  for (final entry in routes.entries) {
    final url =
        'https://start.schulportal.hessen.de/${entry.value}&${_cb()}';
    try {
      final resp = await session.dio.get(url);
      final html = resp.data.toString();
      final path = p.join(out.path, '${entry.key}.html');
      await File(path).writeAsString(html);
      final doc = parse(html);
      final title = doc.querySelector('h1')?.text.trim() ??
          doc.querySelector('title')?.text.trim();
      final links = doc
          .querySelectorAll('a[href*="stundenplan.php"]')
          .map((e) => e.attributes['href'] ?? '')
          .where((h) => h.contains('stundenplan'))
          .toSet()
          .toList()
        ..sort();
      final forms = doc.querySelectorAll('form').map((f) {
        return {
          'action': f.attributes['action'],
          'inputs': f
              .querySelectorAll('input, select, textarea')
              .map((el) {
                final name = el.attributes['name'] ?? el.attributes['id'] ?? '';
                final type = el.attributes['type'] ?? el.localName;
                final value = el.attributes['value'] ??
                    (el.localName == 'select'
                        ? el
                            .querySelectorAll('option')
                            .map((o) => o.attributes['value'] ?? o.text.trim())
                            .take(12)
                            .join('|')
                        : el.text.trim());
                return '$type:$name=${value.toString().replaceAll('\n', ' ').trim()}';
              })
              .where((s) => !s.endsWith('=') || s.contains('select'))
              .take(40)
              .toList(),
        };
      }).toList();
      summary[entry.key] = {
        'url': url.split('&_cachebreaker').first,
        'bytes': html.length,
        'status': resp.statusCode,
        'title': title,
        'navLinks': links.take(40).toList(),
        'forms': forms,
        'checkboxes': doc
            .querySelectorAll('input[type=checkbox]')
            .map((e) {
              final label = e.parent?.text.trim() ?? '';
              return {
                'name': e.attributes['name'],
                'value': e.attributes['value'],
                'checked': e.attributes.containsKey('checked'),
                'label': label.replaceAll(RegExp(r'\s+'), ' ').trim(),
              };
            })
            .take(50)
            .toList(),
        'headings': doc
            .querySelectorAll('h1,h2,h3,h4,.panel-heading,.card-header')
            .map((e) => e.text.replaceAll(RegExp(r'\s+'), ' ').trim())
            .where((t) => t.isNotEmpty)
            .take(40)
            .toList(),
      };
      stdout.writeln(
        '${entry.key}: ${html.length}b title=$title links=${links.length}',
      );
    } catch (e) {
      summary[entry.key] = {'error': e.toString(), 'url': entry.value};
      stderr.writeln('${entry.key}: $e');
    }
  }

  // Student view for comparison
  await client.logout();
  await client.dispose();

  final studentEnv = _loadDotEnv('.studentaccount.env');
  final student = EasyLanisClient.ephemeral(
    schoolId: int.parse(studentEnv['SCHOOLID']!),
    username: studentEnv['USERNAME']!,
    password: studentEnv['PASSWORD']!,
    userAgent: 'liblanis-timetable-settings/0.1.0',
  );
  await student.login();
  final sHtml = (await student.session!.dio.get(
    'https://start.schulportal.hessen.de/stundenplan.php?${_cb()}',
  ))
      .data
      .toString();
  await File(p.join(out.path, 'student_current.html')).writeAsString(sHtml);
  final sDoc = parse(sHtml);
  summary['student_current'] = {
    'bytes': sHtml.length,
    'hasAll': sDoc.getElementById('all') != null,
    'hasOwn': sDoc.getElementById('own') != null,
    'weekBadge': sDoc.querySelector('#aktuelleWoche')?.text.trim(),
    'userData': {
      'klasse': student.session!.userData['klasse'],
      'stufe': student.session!.userData['stufe'],
    },
    'headings': sDoc
        .querySelectorAll('h1,h2,h3')
        .map((e) => e.text.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((t) => t.isNotEmpty)
        .toList(),
    'scriptsHints': RegExp(r'var\s+\w+\s*=\s*[^;]+;')
        .allMatches(sHtml)
        .map((m) => m.group(0)!)
        .where((s) =>
            s.toLowerCase().contains('woche') ||
            s.toLowerCase().contains('plan') ||
            s.toLowerCase().contains('stunde') ||
            s.toLowerCase().contains('klasse'))
        .take(30)
        .toList(),
  };
  await student.logout();
  await student.dispose();

  await File(p.join(out.path, 'summary.json')).writeAsString(
    const JsonEncoder.withIndent('  ').convert(summary),
  );
  stdout.writeln('Wrote ${out.path}/summary.json');
}
