import 'package:liblanis/liblanis.dart';
import 'package:test/test.dart';

TimetableSubject _subject({
  String id = 'a',
  String name = 'Mathe',
  int stunde = 1,
}) => TimetableSubject(
  id: id,
  name: name,
  raum: '101',
  lehrer: 'Müller',
  badge: null,
  duration: 1,
  startTime: const SphTimeOfDay(hour: 8, minute: 0),
  endTime: const SphTimeOfDay(hour: 8, minute: 45),
  stunde: stunde,
);

TimeTable _timetable() => TimeTable(
  planForAll: null,
  planForOwn: null,
  hours: [
    TimeTableRow(
      TimeTableRowType.lesson,
      const SphTimeOfDay(hour: 8, minute: 0),
      const SphTimeOfDay(hour: 8, minute: 45),
      '1',
      1,
    ),
  ],
);

void main() {
  group('TimeTableData.weekdayIndices', () {
    test('no empty days -> weekdayIndices is 0..n-1, matching timetableDays', () {
      final data = TimeTableData(
        [
          [_subject(id: 'mo')],
          [_subject(id: 'di')],
          [_subject(id: 'mi')],
        ],
        _timetable(),
        const {},
        null,
      );

      expect(data.timetableDays, hasLength(3));
      expect(data.weekdayIndices, [0, 1, 2]);
    });

    test('an empty day in the middle is filtered out, weekdayIndices skips it', () {
      final data = TimeTableData(
        [
          [_subject(id: 'mo')], // weekday 0
          [], // weekday 1 (Dienstag) -- empty, filtered
          [_subject(id: 'mi')], // weekday 2
        ],
        _timetable(),
        const {},
        null,
      );

      expect(data.timetableDays, hasLength(2));
      // Without this fix, the second surviving day would be
      // mistaken for weekday 1 (Tuesday) instead of its real weekday 2
      // (Wednesday).
      expect(data.weekdayIndices, [0, 2]);
      expect(data.timetableDays[1].single.id, 'mi');
    });

    test('multiple empty days -> weekdayIndices still lines up 1:1 with timetableDays', () {
      final data = TimeTableData(
        [
          [], // 0
          [_subject(id: 'di')], // 1
          [], // 2
          [], // 3
          [_subject(id: 'fr')], // 4
        ],
        _timetable(),
        const {},
        null,
      );

      expect(data.timetableDays, hasLength(2));
      expect(data.weekdayIndices, [1, 4]);
      expect(data.timetableDays[0].single.id, 'di');
      expect(data.timetableDays[1].single.id, 'fr');
    });

    test('all days empty -> both lists empty', () {
      final data = TimeTableData(
        [[], [], []],
        _timetable(),
        const {},
        null,
      );
      expect(data.timetableDays, isEmpty);
      expect(data.weekdayIndices, isEmpty);
    });
  });
}
