import 'dart:convert';
import 'dart:io';

import 'package:liblanis/liblanis.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final syntheticDir = Directory('test/fixtures/calendar/synthetic');
  final liveDir = Directory('test/fixtures/calendar');

  String readPair(String stem, {Directory? dir}) {
    final base = dir ?? syntheticDir;
    return File(p.join(base.path, '${stem}__page.html')).readAsStringSync();
  }

  String readEvents(String stem, {Directory? dir}) {
    final base = dir ?? syntheticDir;
    return File(p.join(base.path, '${stem}__events.json')).readAsStringSync();
  }

  group('parseCategoriesHtml', () {
    test('reads live categories including short and named colors', () {
      final cats = CalendarParser.parseCategoriesHtml(
        readPair('short_hex_color'),
      );
      expect(cats, isNotEmpty);
      final alle = cats.firstWhere((c) => c.id == 1);
      expect(alle.colorArgb, 0xFF000000);

      final named = CalendarParser.parseCategoriesHtml(readPair('named_color'));
      final dsh = named.firstWhere((c) => c.id == 4);
      // Named color is not hex — keep calendar readable with default blue.
      expect(dsh.colorArgb, 0xFF4242FC);
    });

    test('does not require categories/groups Array markers', () {
      final cats = CalendarParser.parseCategoriesHtml(
        readPair('missing_categories_marker'),
      );
      expect(cats.length, greaterThanOrEqualTo(1));
    });

    test('returns empty list when no push lines exist', () {
      expect(
        CalendarParser.parseCategoriesHtml('<html><body>no cats</body></html>'),
        isEmpty,
      );
    });
  });

  group('parseEventsJson', () {
    test('parses healthy live-shaped events', () {
      final cats = CalendarParser.parseCategoriesHtml(
        readPair('events_ok_live'),
      );
      final events = CalendarParser.parseEventsJson(
        readEvents('events_ok_live'),
        cats,
      );
      expect(events, isNotEmpty);
      expect(events.first.title, contains('LIBLANIS'));
      expect(events.first.category?.id, 1);
    });

    test('accepts DE Anfang format', () {
      final cats = CalendarParser.parseCategoriesHtml(
        readPair('events_bad_anfang'),
      );
      final events = CalendarParser.parseEventsJson(
        readEvents('events_bad_anfang'),
        cats,
      );
      expect(events, hasLength(1));
      expect(events.first.startTime.day, 7);
      expect(events.first.startTime.month, 8);
    });

    test('falls back to ISO start/end when Anfang is null', () {
      final cats = CalendarParser.parseCategoriesHtml(
        readPair('events_null_anfang'),
      );
      final events = CalendarParser.parseEventsJson(
        readEvents('events_null_anfang'),
        cats,
      );
      expect(events, hasLength(1));
      expect(events.first.title, contains('LIBLANIS'));
      expect(events.first.startTime.isBefore(events.first.endTime), isTrue);
    });

    test('skips one bad row without dropping the rest', () {
      final cats = <CalendarEventCategory>[
        CalendarEventCategory(id: 1, colorArgb: 0xFF000000, name: 'Alle'),
      ];
      final body = jsonEncode([
        {
          'Id': 'bad',
          'Anfang': null,
          'Ende': null,
          'title': 'gone',
          'category': '1',
        },
        {
          'Id': '2',
          'Anfang': '2026-08-08 10:00:00',
          'Ende': '2026-08-08 11:00:00',
          'title': 'kept',
          'category': '1',
          'Geheim': 'nein',
          'Neu': 'nein',
          'Oeffentlich': 'nein',
          'Privat': 'nein',
        },
      ]);
      final events = CalendarParser.parseEventsJson(body, cats);
      expect(events, hasLength(1));
      expect(events.single.title, 'kept');
    });

    test('throws on non-list / HTML bodies (global path)', () {
      final emptyCats = <CalendarEventCategory>[];
      expect(
        () => CalendarParser.parseEventsJson(
          readEvents('events_not_list_object'),
          emptyCats,
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => CalendarParser.parseEventsJson(
          readEvents('events_html_body'),
          emptyCats,
        ),
        throwsA(anything),
      );
    });
  });

  group('captured fixtures', () {
    test('every page+events pair parses without throw when events are a list', () {
      final pairs = liveDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('__page.html'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      for (final page in pairs) {
        final stem = p.basename(page.path).replaceAll('__page.html', '');
        final eventsFile = File(p.join(liveDir.path, '${stem}__events.json'));
        if (!eventsFile.existsSync()) continue;

        final cats = CalendarParser.parseCategoriesHtml(
          page.readAsStringSync(),
        );
        final body = eventsFile.readAsStringSync();
        final decoded = jsonDecode(body);
        if (decoded is! List) {
          expect(
            () => CalendarParser.parseEventsJson(body, cats),
            throwsA(isA<FormatException>()),
            reason: stem,
          );
          continue;
        }
        final events = CalendarParser.parseEventsJson(body, cats);
        expect(events, isA<List<CalendarEvent>>(), reason: stem);
      }
    });
  });
}
