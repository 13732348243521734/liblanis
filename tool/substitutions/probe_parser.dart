/// Offline probe of substitution fixtures without swallowing exceptions.
///
/// ```sh
/// dart run tool/substitutions/probe_parser.dart
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:liblanis/liblanis.dart';
import 'package:path/path.dart' as p;

void main() {
  final roots = [
    Directory('test/fixtures/substitutions'),
    Directory('test/fixtures/substitutions/synthetic'),
  ];
  final cases = <({String id, String page, String? ajax})>[];

  for (final dir in roots) {
    if (!dir.existsSync()) continue;
    final pages = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('__page.html'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final page in pages) {
      final base = p.basename(page.path).replaceAll('__page.html', '');
      final ajaxFile = File(p.join(dir.path, '${base}__ajax.txt'));
      final dayFile = File(p.join(dir.path, '${base}__day.json'));
      String? ajax;
      if (ajaxFile.existsSync()) {
        ajax = ajaxFile.readAsStringSync();
      } else if (dayFile.existsSync()) {
        ajax = dayFile.readAsStringSync();
      }
      cases.add((id: base, page: page.readAsStringSync(), ajax: ajax));
    }
  }

  final byError = <String, List<String>>{};
  var ok = 0;
  for (final c in cases) {
    try {
      final dates = SubstitutionsParser.getSubstitutionDates(c.page);
      final ajaxByDate = <String, String>{};
      if (dates.isNotEmpty && c.ajax != null) {
        // Live ajax jobs store one body; synthetics share one day file.
        for (final d in dates) {
          ajaxByDate[d] = c.ajax!;
        }
      } else if (dates.isNotEmpty) {
        // No ajax body: parse with empty map (days skipped).
      }
      final plan = SubstitutionsParser.parseDocumentHtml(
        c.page,
        ajaxByDate: ajaxByDate,
      );
      ok++;
      stdout.writeln(
        'OK  ${c.id} dates=${dates.length} days=${plan.days.length} '
        'rows=${plan.allSubstitutions.length}',
      );
    } catch (e) {
      final key = '${e.runtimeType}: $e';
      (byError[key] ??= []).add(c.id);
      stdout.writeln('ERR ${c.id} -> $key');
    }
  }

  stdout.writeln('');
  stdout.writeln('=== summary ===');
  stdout.writeln('cases=${cases.length} ok=$ok fail=${cases.length - ok}');
  final entries = byError.entries.toList()
    ..sort((a, b) => b.value.length.compareTo(a.value.length));
  for (final e in entries) {
    stdout.writeln('${e.value.length} × ${e.key}');
    for (final id in e.value.take(12)) {
      stdout.writeln('  - $id');
    }
  }

  Directory('tool/substitutions/discovery').createSync(recursive: true);
  File('tool/substitutions/discovery/probe_report.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'cases': cases.length,
      'ok': ok,
      'fail': cases.length - ok,
      'errors': {for (final e in entries) e.key: e.value},
    }),
  );
}
