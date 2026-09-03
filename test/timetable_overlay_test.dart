import 'package:liblanis/liblanis.dart';
import 'package:test/test.dart';

TimetableSubject _subject({
  String? id = 'a',
  String? name = 'Mathe',
  String? lehrer = 'Müller',
  String? raum = '101',
  int duration = 1,
  int? stunde = 3,
}) => TimetableSubject(
  id: id,
  name: name,
  raum: raum,
  lehrer: lehrer,
  badge: null,
  duration: duration,
  startTime: const SphTimeOfDay(hour: 8, minute: 0),
  endTime: const SphTimeOfDay(hour: 8, minute: 45),
  stunde: stunde,
);

Substitution _sub({
  String stunde = '3',
  String? vertreter,
  String? fach = 'Mathe',
  String? raum,
  String? hinweis,
}) => Substitution(
  tag: '01.09.2026',
  tag_en: '2026-09-01',
  stunde: stunde,
  vertreter: vertreter,
  fach: fach,
  raum: raum,
  hinweis: hinweis,
);

void main() {
  group('decomposeTimetableSubjects', () {
    test('duration 1 -> exactly one hour', () {
      final hours = decomposeTimetableSubjects([_subject(duration: 1, stunde: 3)]);
      expect(hours, hasLength(1));
      expect(hours.single.stunde, 3);
      expect(hours.single.fach, 'Mathe');
    });

    test('duration 2 -> two consecutive hours, same fach/lehrer/raum', () {
      final hours = decomposeTimetableSubjects([_subject(duration: 2, stunde: 3)]);
      expect(hours, hasLength(2));
      expect(hours[0].stunde, 3);
      expect(hours[1].stunde, 4);
      expect(hours.every((h) => h.fach == 'Mathe' && h.lehrer == 'Müller'), isTrue);
    });

    test('duration 3 -> three consecutive hours', () {
      final hours = decomposeTimetableSubjects([_subject(duration: 3, stunde: 1)]);
      expect(hours.map((h) => h.stunde), [1, 2, 3]);
    });

    test('null name -> skipped', () {
      final hours = decomposeTimetableSubjects([_subject(name: null)]);
      expect(hours, isEmpty);
    });

    test('null stunde -> skipped', () {
      final hours = decomposeTimetableSubjects([_subject(stunde: null)]);
      expect(hours, isEmpty);
    });

    test('multiple subjects handled independently', () {
      final hours = decomposeTimetableSubjects([
        _subject(name: 'Mathe', stunde: 1, duration: 1),
        _subject(name: 'Physik', stunde: 3, duration: 2),
      ]);
      expect(hours.map((h) => (h.stunde, h.fach)), [
        (1, 'Mathe'),
        (3, 'Physik'),
        (4, 'Physik'),
      ]);
    });
  });

  group('decomposeSubstitutionRanges', () {
    test('single-hour stunde stays one entry', () {
      final result = decomposeSubstitutionRanges([_sub(stunde: '3')]);
      expect(result, hasLength(1));
      expect(result.single.stunde, '3');
    });

    test('range "3 - 4" splits into two identical-except-stunde entries', () {
      final result = decomposeSubstitutionRanges([
        _sub(stunde: '3 - 4', vertreter: 'Frau Schmidt', raum: '202'),
      ]);
      expect(result, hasLength(2));
      expect(result[0].stunde, '3');
      expect(result[1].stunde, '4');
      expect(result.every((s) => s.vertreter == 'Frau Schmidt' && s.raum == '202'), isTrue);
    });

    test('range "1-2" without spaces also splits correctly', () {
      final result = decomposeSubstitutionRanges([_sub(stunde: '1-2')]);
      expect(result.map((s) => s.stunde), ['1', '2']);
    });

    test('malformed stunde is kept as-is, not dropped', () {
      final result = decomposeSubstitutionRanges([_sub(stunde: 'ganztags')]);
      expect(result, hasLength(1));
      expect(result.single.stunde, 'ganztags');
    });

    test('multiple substitutions handled independently', () {
      final result = decomposeSubstitutionRanges([
        _sub(stunde: '1', fach: 'Mathe'),
        _sub(stunde: '3 - 4', fach: 'Physik'),
      ]);
      expect(result.map((s) => (s.stunde, s.fach)), [
        ('1', 'Mathe'),
        ('3', 'Physik'),
        ('4', 'Physik'),
      ]);
    });
  });

  group('matchOverlayForHour', () {
    test('no matching substitution -> null', () {
      final overlay = matchOverlayForHour(
        stunde: 3,
        fach: 'Mathe',
        originalRaum: '101',
        substitutions: const [],
      );
      expect(overlay, isNull);
    });

    test('matches by stunde + fach', () {
      final overlay = matchOverlayForHour(
        stunde: 3,
        fach: 'Mathe',
        originalRaum: '101',
        substitutions: [_sub(stunde: '3', fach: 'Mathe', vertreter: 'Frau Schmidt')],
      );
      expect(overlay, isNotNull);
      expect(overlay!.vertreter, 'Frau Schmidt');
    });

    test('different fach at the same stunde does not match', () {
      final overlay = matchOverlayForHour(
        stunde: 3,
        fach: 'Mathe',
        originalRaum: '101',
        substitutions: [_sub(stunde: '3', fach: 'Physik')],
      );
      expect(overlay, isNull);
    });

    test('substitution raum differs from original -> substituteRaum set', () {
      final overlay = matchOverlayForHour(
        stunde: 3,
        fach: 'Mathe',
        originalRaum: '101',
        substitutions: [_sub(stunde: '3', raum: '202')],
      );
      expect(overlay!.substituteRaum, '202');
    });

    test('substitution raum same as original -> not treated as a change', () {
      final overlay = matchOverlayForHour(
        stunde: 3,
        fach: 'Mathe',
        originalRaum: '101',
        substitutions: [_sub(stunde: '3', raum: '101')],
      );
      expect(overlay!.substituteRaum, isNull);
    });

    test('raum == EVA -> isEva true, substituteRaum stays null', () {
      final overlay = matchOverlayForHour(
        stunde: 3,
        fach: 'Mathe',
        originalRaum: '101',
        substitutions: [_sub(stunde: '3', raum: 'EVA')],
      );
      expect(overlay!.isEva, isTrue);
      expect(overlay.substituteRaum, isNull);
    });

    test('hinweis == EVA also sets isEva', () {
      final overlay = matchOverlayForHour(
        stunde: 3,
        fach: 'Mathe',
        originalRaum: '101',
        substitutions: [_sub(stunde: '3', hinweis: 'EVA')],
      );
      expect(overlay!.isEva, isTrue);
    });

    test('empty-string vertreter is treated as absent', () {
      final overlay = matchOverlayForHour(
        stunde: 3,
        fach: 'Mathe',
        originalRaum: '101',
        substitutions: [_sub(stunde: '3', vertreter: '')],
      );
      expect(overlay!.vertreter, isNull);
    });
  });

  group('buildDisplayBlocksForDay (end-to-end)', () {
    test('double period, matching substitution consistent on both hours -> merges', () {
      final blocks = buildDisplayBlocksForDay(
        subjects: [_subject(name: 'Mathe', stunde: 3, duration: 2)],
        substitutions: [
          _sub(stunde: '3 - 4', fach: 'Mathe', vertreter: 'Frau Schmidt'),
        ],
      );
      expect(blocks, hasLength(1));
      expect(blocks.single.stunden, [3, 4]);
      expect(blocks.single.overlay?.vertreter, 'Frau Schmidt');
    });

    test(
      'plan example end-to-end: substitution only on the first of two hours -> NOT merged',
      () {
        final blocks = buildDisplayBlocksForDay(
          subjects: [_subject(name: 'Mathe', stunde: 3, duration: 2)],
          substitutions: [
            _sub(stunde: '3', fach: 'Mathe', vertreter: 'Frau Schmidt'),
          ],
        );
        expect(blocks, hasLength(2));
        expect(blocks[0].stunden, [3]);
        expect(blocks[0].overlay?.vertreter, 'Frau Schmidt');
        expect(blocks[1].stunden, [4]);
        expect(blocks[1].overlay, isNull);
      },
    );

    test('no substitutions at all -> plain merge by identity, no overlay', () {
      final blocks = buildDisplayBlocksForDay(
        subjects: [_subject(name: 'Mathe', stunde: 3, duration: 2)],
        substitutions: const [],
      );
      expect(blocks, hasLength(1));
      expect(blocks.single.overlay, isNull);
    });

    test('unrelated substitution (different fach) does not affect the block', () {
      final blocks = buildDisplayBlocksForDay(
        subjects: [_subject(name: 'Mathe', stunde: 3, duration: 2)],
        substitutions: [_sub(stunde: '3 - 4', fach: 'Physik')],
      );
      expect(blocks, hasLength(1));
      expect(blocks.single.overlay, isNull);
    });
  });
}
