import 'package:liblanis/liblanis.dart';
import 'package:test/test.dart';

void main() {
  group('tagEnToDateTime', () {
    test('parses a valid yyyy-MM-dd tag_en', () {
      expect(tagEnToDateTime('2026-09-01'), DateTime(2026, 9, 1));
    });

    test('returns null for malformed input', () {
      expect(tagEnToDateTime('not-a-date'), isNull);
      expect(tagEnToDateTime('2026-09'), isNull);
      expect(tagEnToDateTime(''), isNull);
    });
  });

  group('tagEnToParsedDate', () {
    test('converts to dd.MM.yyyy, zero-padded', () {
      expect(tagEnToParsedDate('2026-09-01'), '01.09.2026');
      expect(tagEnToParsedDate('2026-12-25'), '25.12.2026');
    });

    test('malformed input is returned unchanged, not thrown', () {
      expect(tagEnToParsedDate('not-a-date'), 'not-a-date');
    });
  });

  group('parsedDateToTagEn', () {
    test('converts dd.MM.yyyy to yyyy-MM-dd, zero-padded', () {
      expect(parsedDateToTagEn('01.09.2026'), '2026-09-01');
      expect(parsedDateToTagEn('1.9.2026'), '2026-09-01');
    });

    test('returns null for malformed input', () {
      expect(parsedDateToTagEn('not-a-date'), isNull);
      expect(parsedDateToTagEn('01.09'), isNull);
    });
  });

  test('round-trips through both directions', () {
    expect(tagEnToParsedDate(parsedDateToTagEn('01.09.2026')!), '01.09.2026');
    expect(parsedDateToTagEn(tagEnToParsedDate('2026-09-01')), '2026-09-01');
  });
}
