import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart' show parse;
import 'package:liblanis/liblanis.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final synthDir = Directory('test/fixtures/substitutions/synthetic');
  final liveDir = Directory('test/fixtures/substitutions');

  group('parseHours', () {
    test('normalizes ranges', () {
      expect(SubstitutionsParser.parseHours('1'), '1');
      expect(SubstitutionsParser.parseHours('1-2'), '1 - 2');
      expect(SubstitutionsParser.parseHours('1 - 2'), '1 - 2');
      expect(SubstitutionsParser.parseHours('abc'), 'abc');
    });
  });

  group('synthetic fixtures', () {
    test('ajax_ok_rich parses rows and infos', () {
      final page = File(
        p.join(synthDir.path, 'ajax_ok_rich__page.html'),
      ).readAsStringSync();
      final day = File(
        p.join(synthDir.path, 'ajax_ok_rich__day.json'),
      ).readAsStringSync();
      final dates = SubstitutionsParser.getSubstitutionDates(page);
      expect(dates, isNotEmpty);
      final plan = SubstitutionsParser.parseDocumentHtml(
        page,
        ajaxByDate: {dates.first: day},
      );
      expect(plan.days, isNotEmpty);
      expect(plan.allSubstitutions.length, 5);
      expect(plan.days.first.infos, isNotEmpty);
      expect(plan.allSubstitutions.any((s) => s.klasse?.contains('Ea') == true), isTrue);
    });

    test('ajax_error_int becomes empty day not crash', () {
      final page = File(
        p.join(synthDir.path, 'ajax_error_int__page.html'),
      ).readAsStringSync();
      final day = File(
        p.join(synthDir.path, 'ajax_error_int__day.json'),
      ).readAsStringSync();
      final dates = SubstitutionsParser.getSubstitutionDates(page);
      final plan = SubstitutionsParser.parseDocumentHtml(
        page,
        ajaxByDate: {dates.first: day},
      );
      expect(plan.days, isEmpty); // empty day removed
    });

    test('ajax_html_body throws FormatException', () {
      final page = File(
        p.join(synthDir.path, 'ajax_html_body__page.html'),
      ).readAsStringSync();
      final day = File(
        p.join(synthDir.path, 'ajax_html_body__day.json'),
      ).readAsStringSync();
      final dates = SubstitutionsParser.getSubstitutionDates(page);
      expect(
        () => SubstitutionsParser.parseDocumentHtml(
          page,
          ajaxByDate: {dates.first: day},
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('ajax_missing_tag_element keeps rows without infos', () {
      final page = File(
        p.join(synthDir.path, 'ajax_missing_tag_element__page.html'),
      ).readAsStringSync();
      final day = File(
        p.join(synthDir.path, 'ajax_missing_tag_element__day.json'),
      ).readAsStringSync();
      final dates = SubstitutionsParser.getSubstitutionDates(page);
      final plan = SubstitutionsParser.parseDocumentHtml(
        page,
        ajaxByDate: {dates.first: day},
      );
      expect(plan.allSubstitutions, isNotEmpty);
      expect(plan.days.first.infos, isNull);
    });

    test('nonajax_full_columns matches DOM row count', () {
      final page = File(
        p.join(synthDir.path, 'nonajax_full_columns__page.html'),
      ).readAsStringSync();
      final plan = SubstitutionsParser.parseDocumentHtml(page);
      final doc = parse(page);
      final vtable = doc.querySelector(r'table[id^="vtable"]')!;
      final domRows = vtable
          .querySelectorAll('tbody tr')
          .where((e) => e.querySelectorAll('td[colspan]').isEmpty)
          .length;
      expect(plan.allSubstitutions.length, domRows);
      expect(plan.allSubstitutions.first.stunde, '1');
      expect(plan.allSubstitutions[1].stunde, '2 - 3');
    });

    test('nonajax_missing_stunde_header does not throw', () {
      final page = File(
        p.join(synthDir.path, 'nonajax_missing_stunde_header__page.html'),
      ).readAsStringSync();
      final plan = SubstitutionsParser.parseDocumentHtml(page);
      // Infos kept; unreadable rows skipped.
      expect(plan.days, isNotEmpty);
      expect(plan.allSubstitutions, isEmpty);
    });

    test('nonajax_missing_vtable keeps infos-only day', () {
      final page = File(
        p.join(synthDir.path, 'nonajax_missing_vtable__page.html'),
      ).readAsStringSync();
      final plan = SubstitutionsParser.parseDocumentHtml(page);
      expect(plan.days, hasLength(1));
      expect(plan.days.first.infos, isNotEmpty);
      expect(plan.allSubstitutions, isEmpty);
    });

    test('empty_shell parses empty', () {
      final page = File(
        p.join(synthDir.path, 'empty_shell__page.html'),
      ).readAsStringSync();
      final plan = SubstitutionsParser.parseDocumentHtml(page);
      expect(plan.days, isEmpty);
    });

    test('unauthorized_shell throws', () {
      final page = File(
        p.join(synthDir.path, 'unauthorized_shell__page.html'),
      ).readAsStringSync();
      expect(
        () => SubstitutionsParser.parseDocumentHtml(page),
        throwsA(isA<UnauthorizedException>()),
      );
    });
  });

  group('filter keys', () {
    Substitution sample({String? klasse, String? fach, String? art}) {
      return Substitution(
        tag: '05.08.2026',
        tag_en: '2026-08-05',
        stunde: '1',
        klasse: klasse ?? '10a',
        fach: fach ?? 'M',
        art: art ?? 'Entfall',
        raum: 'R1',
        lehrer: 'Mu',
        vertreter: 'Li',
        hinweis: 'note',
        hinweis2: 'n2',
        fach_alt: 'E',
        klasse_alt: '9a',
        raum_alt: 'R0',
        Lehrerkuerzel: 'Mu',
        Vertreterkuerzel: 'Li',
      );
    }

    final keys = <String, String Function(Substitution)>{
      'Klasse': (s) => s.klasse!,
      'Fach': (s) => s.fach!,
      'Fach_alt': (s) => s.fach_alt!,
      'Lehrer': (s) => s.lehrer!,
      'Raum': (s) => s.raum!,
      'Art': (s) => s.art!,
      'Hinweis': (s) => s.hinweis!,
      'Vertreter': (s) => s.vertreter!,
      'Stunde': (s) => s.stunde,
      'Lehrerkuerzel': (s) => s.Lehrerkuerzel!,
      'Vertreterkuerzel': (s) => s.Vertreterkuerzel!,
      'Klasse_alt': (s) => s.klasse_alt!,
      'Raum_alt': (s) => s.raum_alt!,
      'Hinweis2': (s) => s.hinweis2!,
    };

    for (final entry in keys.entries) {
      test('${entry.key} strict and loose', () {
        final s = sample();
        final value = entry.value(s);
        expect(
          s.passesFilter({
            entry.key: {
              'filter': [value],
              'strict': true,
            },
          }),
          isTrue,
        );
        expect(
          s.passesFilter({
            entry.key: {
              'filter': ['___nomatch___'],
              'strict': true,
            },
          }),
          isFalse,
        );
        expect(
          s.passesFilter({
            entry.key: {
              'filter': [value.substring(0, 1)],
              'strict': false,
            },
          }),
          isTrue,
        );
      });
    }
  });

  group('captured fixtures', () {
    test('every __page.html parses or is unauthorized', () {
      if (!liveDir.existsSync()) return;
      final pages = liveDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('__page.html'))
          .toList();
      for (final pageFile in pages) {
        final base = p.basename(pageFile.path).replaceAll('__page.html', '');
        final html = pageFile.readAsStringSync();
        final ajaxFile = File(p.join(liveDir.path, '${base}__ajax.txt'));
        try {
          final dates = SubstitutionsParser.getSubstitutionDates(html);
          final ajaxByDate = <String, String>{};
          if (ajaxFile.existsSync() && dates.isNotEmpty) {
            final body = ajaxFile.readAsStringSync();
            for (final d in dates) {
              ajaxByDate[d] = body;
            }
          }
          final plan = SubstitutionsParser.parseDocumentHtml(
            html,
            ajaxByDate: ajaxByDate,
          );
          expect(plan, isA<SubstitutionPlan>(), reason: base);
        } on UnauthorizedException {
          // expected for some shells
        } on FormatException {
          // AJAX HTML bodies for no_ganzer style are intentional garbage
          expect(base.contains('no_ganzer') || base.contains('html'), isTrue);
        }
      }
    });
  });

  group('manifest sanity', () {
    test('synthetic index exists', () {
      expect(File(p.join(synthDir.path, 'index.json')).existsSync(), isTrue);
      final idx =
          jsonDecode(File(p.join(synthDir.path, 'index.json')).readAsStringSync())
              as Map<String, dynamic>;
      expect((idx['synthetic'] as List), isNotEmpty);
    });
  });
}
