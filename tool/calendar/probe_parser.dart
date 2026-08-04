/// Offline probe: run CalendarParser static parse helpers without network.
///
/// Uses fixtures under test/fixtures/calendar/ plus synthetic mutations.
///
/// ```sh
/// dart run tool/calendar/probe_parser.dart
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:liblanis/liblanis.dart';
import 'package:path/path.dart' as p;

class ProbeCase {
  ProbeCase({
    required this.id,
    required this.pageHtml,
    required this.eventsBody,
  });
  final String id;
  final String pageHtml;
  final String eventsBody;
}

void main() {
  final fixtureDir = Directory('test/fixtures/calendar');
  final cases = <ProbeCase>[];

  void collectFrom(Directory dir, {String prefix = ''}) {
    if (!dir.existsSync()) return;
    final pages = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('__page.html'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final page in pages) {
      final base = p.basename(page.path).replaceAll('__page.html', '');
      final events = File(p.join(dir.path, '${base}__events.json'));
      if (!events.existsSync()) continue;
      cases.add(
        ProbeCase(
          id: '$prefix$base',
          pageHtml: page.readAsStringSync(),
          eventsBody: events.readAsStringSync(),
        ),
      );
    }
  }

  collectFrom(fixtureDir);
  collectFrom(Directory(p.join(fixtureDir.path, 'synthetic')), prefix: 'disk_');

  final basePage = cases.isNotEmpty
      ? cases.first.pageHtml
      : '''
<script>
var categories = new Array();
  categories.push({ id: 1, name:'Alle', color:'#000000', logo:''} );
var groups = new Array();
</script>
''';
  final baseEvents = cases.isNotEmpty ? cases.first.eventsBody : '[]';

  Map<String, dynamic> sampleEvent([Map<String, dynamic>? overrides]) {
    final e = <String, dynamic>{
      'Anfang': '2026-08-07 10:00:00',
      'Ende': '2026-08-07 11:00:00',
      'FremdUID': null,
      'Lerngruppe': null,
      'Geheim': 'nein',
      'Id': '999001',
      'Institution': '5690',
      'LetzteAenderung': '2026-08-04 12:00:00',
      'Neu': 'nein',
      'Oeffentlich': 'nein',
      'Ort': 'RMFIX',
      'Privat': 'nein',
      'Verantwortlich': null,
      'allDay': false,
      'category': 1,
      'description': 'probe',
      'title': 'Probe Event',
    };
    if (overrides != null) e.addAll(overrides);
    return e;
  }

  void addSynthetic(String id, String page, Object events) {
    cases.add(
      ProbeCase(
        id: 'synthetic__$id',
        pageHtml: page,
        eventsBody: events is String ? events : jsonEncode(events),
      ),
    );
  }

  addSynthetic(
    'missing_categories_marker',
    basePage.replaceFirst(
      'var categories = new Array();',
      'var categoriesMissing = new Array();',
    ),
    baseEvents,
  );

  addSynthetic(
    'missing_groups_marker',
    basePage.replaceFirst(
      'var groups = new Array();',
      'var groupsMissing = new Array();',
    ),
    baseEvents,
  );

  addSynthetic(
    'short_hex_color',
    basePage.replaceFirst("color:'#000000'", "color:'#000'"),
    baseEvents,
  );

  addSynthetic(
    'named_color',
    basePage.replaceFirst("color:'#0080ff'", "color:'blue'"),
    baseEvents,
  );

  addSynthetic('events_not_list_object', basePage, {'error': 'nope'});
  addSynthetic('events_html_body', basePage, '<html><body>error</body></html>');
  addSynthetic('events_empty_list', basePage, []);
  addSynthetic('events_one_ok', basePage, [sampleEvent()]);
  addSynthetic(
    'events_bad_anfang',
    basePage,
    [sampleEvent({'Anfang': '07.08.2026 10:00'})],
  );
  addSynthetic(
    'events_null_anfang',
    basePage,
    [sampleEvent({'Anfang': null})],
  );
  addSynthetic(
    'events_missing_anfang',
    basePage,
    [sampleEvent()..remove('Anfang')],
  );
  addSynthetic(
    'events_all_day_true',
    basePage,
    [
      sampleEvent({
        'allDay': true,
        'Anfang': '2026-08-07 00:00:00',
        'Ende': '2026-08-08 00:00:00',
      }),
    ],
  );
  addSynthetic(
    'events_category_string',
    basePage,
    [sampleEvent({'category': '4'})],
  );

  for (final c in List<ProbeCase>.from(cases)) {
    if (c.id.startsWith('synthetic__')) continue;
    try {
      final decoded = jsonDecode(c.eventsBody);
      if (decoded is! List || decoded.isEmpty) continue;
      final first = Map<String, dynamic>.from(decoded.first as Map);
      addSynthetic(
        'live_${c.id}_null_ende',
        c.pageHtml,
        [
          {...first, 'Ende': null},
          ...decoded.skip(1),
        ],
      );
      break;
    } catch (_) {}
  }

  final byError = <String, List<String>>{};
  var ok = 0;
  for (final c in cases) {
    try {
      final categories = CalendarParser.parseCategoriesHtml(c.pageHtml);
      final events = CalendarParser.parseEventsJson(c.eventsBody, categories);
      ok++;
      stdout.writeln(
        'OK  ${c.id} categories=${categories.length} events=${events.length}',
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
  stdout.writeln('');
  stdout.writeln('=== remaining error classes (expected: non-list / HTML) ===');
  final entries = byError.entries.toList()
    ..sort((a, b) => b.value.length.compareTo(a.value.length));
  for (final e in entries) {
    stdout.writeln('${e.value.length} × ${e.key}');
    for (final id in e.value.take(12)) {
      stdout.writeln('  - $id');
    }
    if (e.value.length > 12) {
      stdout.writeln('  … +${e.value.length - 12} more');
    }
  }

  Directory('tool/calendar/discovery').createSync(recursive: true);
  File('tool/calendar/discovery/probe_report.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'cases': cases.length,
      'ok': ok,
      'fail': cases.length - ok,
      'errors': {for (final e in entries) e.key: e.value},
    }),
  );
}
