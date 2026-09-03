import 'package:liblanis/liblanis.dart';
import 'package:test/test.dart';

DisplayLessonHour _hour({
  required int stunde,
  String fach = 'Mathe',
  String? lehrer = 'Müller',
  String? raum = '101',
  LessonOverlay? overlay,
}) => DisplayLessonHour(
  stunde: stunde,
  fach: fach,
  lehrer: lehrer,
  raum: raum,
  overlay: overlay,
);

void main() {
  group('mergeConsecutiveHours', () {
    test('empty input -> empty output', () {
      expect(mergeConsecutiveHours(const []), isEmpty);
    });

    test('single hour -> one unmerged block', () {
      final blocks = mergeConsecutiveHours([_hour(stunde: 3)]);
      expect(blocks, hasLength(1));
      expect(blocks.single.stunden, [3]);
      expect(blocks.single.isMerged, isFalse);
    });

    test('two consecutive identical hours, no overlay -> merge', () {
      final blocks = mergeConsecutiveHours([
        _hour(stunde: 3),
        _hour(stunde: 4),
      ]);
      expect(blocks, hasLength(1));
      expect(blocks.single.stunden, [3, 4]);
      expect(blocks.single.isMerged, isTrue);
      expect(blocks.single.startStunde, 3);
      expect(blocks.single.endStunde, 4);
    });

    test('three consecutive identical hours -> merge into one block', () {
      final blocks = mergeConsecutiveHours([
        _hour(stunde: 1),
        _hour(stunde: 2),
        _hour(stunde: 3),
      ]);
      expect(blocks, hasLength(1));
      expect(blocks.single.stunden, [1, 2, 3]);
    });

    test('gap in stunde sequence -> stays two separate blocks', () {
      final blocks = mergeConsecutiveHours([
        _hour(stunde: 1),
        _hour(stunde: 3),
      ]);
      expect(blocks, hasLength(2));
      expect(blocks[0].stunden, [1]);
      expect(blocks[1].stunden, [3]);
    });

    test('input not pre-sorted -> still merges correctly', () {
      final blocks = mergeConsecutiveHours([
        _hour(stunde: 4),
        _hour(stunde: 3),
      ]);
      expect(blocks, hasLength(1));
      expect(blocks.single.stunden, [3, 4]);
    });

    test('different fach -> no merge', () {
      final blocks = mergeConsecutiveHours([
        _hour(stunde: 3, fach: 'Mathe'),
        _hour(stunde: 4, fach: 'Physik'),
      ]);
      expect(blocks, hasLength(2));
    });

    test('different lehrer -> no merge', () {
      final blocks = mergeConsecutiveHours([
        _hour(stunde: 3, lehrer: 'Müller'),
        _hour(stunde: 4, lehrer: 'Schmidt'),
      ]);
      expect(blocks, hasLength(2));
    });

    test('different raum -> no merge', () {
      final blocks = mergeConsecutiveHours([
        _hour(stunde: 3, raum: '101'),
        _hour(stunde: 4, raum: '202'),
      ]);
      expect(blocks, hasLength(2));
    });

    test('identical overlay on both hours -> merge, overlay carried through', () {
      const overlay = LessonOverlay(vertreter: 'Frau Schmidt');
      final blocks = mergeConsecutiveHours([
        _hour(stunde: 3, overlay: overlay),
        _hour(stunde: 4, overlay: overlay),
      ]);
      expect(blocks, hasLength(1));
      expect(blocks.single.overlay, overlay);
    });

    test(
      'plan example: only stunde 3 has a substitution -> NOT merged, two rows',
      () {
        final blocks = mergeConsecutiveHours([
          _hour(stunde: 3, overlay: const LessonOverlay(vertreter: 'Frau Schmidt')),
          _hour(stunde: 4, overlay: null),
        ]);
        expect(blocks, hasLength(2));
        expect(blocks[0].stunden, [3]);
        expect(blocks[1].stunden, [4]);
      },
    );

    test('different vertreter on each hour -> no merge', () {
      final blocks = mergeConsecutiveHours([
        _hour(stunde: 3, overlay: const LessonOverlay(vertreter: 'Frau Schmidt')),
        _hour(stunde: 4, overlay: const LessonOverlay(vertreter: 'Herr Meyer')),
      ]);
      expect(blocks, hasLength(2));
    });

    test('different substituteRaum on each hour -> no merge', () {
      final blocks = mergeConsecutiveHours([
        _hour(stunde: 3, overlay: const LessonOverlay(substituteRaum: '303')),
        _hour(stunde: 4, overlay: const LessonOverlay(substituteRaum: '404')),
      ]);
      expect(blocks, hasLength(2));
    });

    test('both hours EVA -> merge', () {
      final blocks = mergeConsecutiveHours([
        _hour(stunde: 3, overlay: const LessonOverlay(isEva: true)),
        _hour(stunde: 4, overlay: const LessonOverlay(isEva: true)),
      ]);
      expect(blocks, hasLength(1));
    });

    test('only one hour EVA -> no merge', () {
      final blocks = mergeConsecutiveHours([
        _hour(stunde: 3, overlay: const LessonOverlay(isEva: true)),
        _hour(stunde: 4, overlay: const LessonOverlay(isEva: false)),
      ]);
      expect(blocks, hasLength(2));
    });

    test('two hours sharing the same stunde number -> never merged into each other', () {
      final blocks = mergeConsecutiveHours([
        _hour(stunde: 3),
        _hour(stunde: 3),
      ]);
      expect(blocks, hasLength(2));
      expect(blocks[0].stunden, [3]);
      expect(blocks[1].stunden, [3]);
    });

    test('mixed run: identical pair merges, mismatched third stays separate', () {
      final blocks = mergeConsecutiveHours([
        _hour(stunde: 1, fach: 'Mathe'),
        _hour(stunde: 2, fach: 'Mathe'),
        _hour(stunde: 3, fach: 'Deutsch'),
      ]);
      expect(blocks, hasLength(2));
      expect(blocks[0].stunden, [1, 2]);
      expect(blocks[0].fach, 'Mathe');
      expect(blocks[1].stunden, [3]);
      expect(blocks[1].fach, 'Deutsch');
    });
  });

  group('LessonOverlay equality', () {
    test('two overlays with identical fields are equal', () {
      const a = LessonOverlay(vertreter: 'X', substituteRaum: 'Y', isEva: true, hinweis: 'Z');
      const b = LessonOverlay(vertreter: 'X', substituteRaum: 'Y', isEva: true, hinweis: 'Z');
      expect(a, b);
    });

    test('differing hinweis makes overlays unequal', () {
      const a = LessonOverlay(hinweis: 'A');
      const b = LessonOverlay(hinweis: 'B');
      expect(a == b, isFalse);
    });
  });
}
