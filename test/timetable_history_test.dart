import 'package:liblanis/liblanis.dart';
import 'package:test/test.dart';

TimetableSubject _subject({
  String id = 'a',
  String name = 'Mathe',
  String? raum = '101',
  String? lehrer = 'Müller',
  int stunde = 1,
  int duration = 1,
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

TimeTable _timetable({String subjectName = 'Mathe', String? weekBadge}) =>
    TimeTable(
      planForAll: [
        [_subject(name: subjectName)],
        [],
        [],
        [],
        [],
      ],
      hours: const [],
      weekBadge: weekBadge,
    );

void main() {
  group('mondayOf', () {
    test('a Wednesday resolves to that week\'s Monday', () {
      expect(mondayOf(DateTime(2026, 9, 16)), DateTime(2026, 9, 14));
    });

    test('a Monday resolves to itself', () {
      expect(mondayOf(DateTime(2026, 9, 14)), DateTime(2026, 9, 14));
    });

    test('a Sunday resolves to the Monday that started its week', () {
      expect(mondayOf(DateTime(2026, 9, 20)), DateTime(2026, 9, 14));
    });
  });

  group('timeTablesEqual', () {
    test('identical content -> equal', () {
      expect(timeTablesEqual(_timetable(), _timetable()), isTrue);
    });

    test('different subject name -> not equal', () {
      expect(
        timeTablesEqual(_timetable(), _timetable(subjectName: 'Deutsch')),
        isFalse,
      );
    });
  });

  group('TimeTableSnapshotStore + runTimetableHistoryDiff', () {
    late LanisDatabase db;
    const accountId = 1;

    setUp(() async {
      db = LanisDatabase.open();
      await db.addAccount(
        schoolId: 1,
        schoolName: 'S',
        username: 'u',
        password: 'p',
      );
    });

    tearDown(() {
      db.dispose();
    });

    test('first fetch always writes a snapshot', () {
      final changed = runTimetableHistoryDiff(
        database: db,
        accountId: accountId,
        current: _timetable(),
        capturedAt: DateTime(2026, 9, 14, 7),
      );
      expect(changed, isTrue);

      final row = db.getLatestTimetableHistoryRow(accountId: accountId);
      expect(row, isNotNull);
      expect(row!.validFromDate, DateTime(2026, 9, 14));
    });

    test('unchanged content on a later day -> no new row written', () {
      runTimetableHistoryDiff(
        database: db,
        accountId: accountId,
        current: _timetable(),
        capturedAt: DateTime(2026, 9, 14, 7),
      );
      final changed = runTimetableHistoryDiff(
        database: db,
        accountId: accountId,
        current: _timetable(),
        capturedAt: DateTime(2026, 9, 21, 7),
      );
      expect(changed, isFalse);

      // Still only the original Monday's row -- next week's identical
      // content did not create a second one.
      final row = db.getLatestTimetableHistoryRow(accountId: accountId);
      expect(row!.validFromDate, DateTime(2026, 9, 14));
    });

    test('changed content on a later week -> new row written', () {
      runTimetableHistoryDiff(
        database: db,
        accountId: accountId,
        current: _timetable(subjectName: 'Mathe'),
        capturedAt: DateTime(2026, 9, 14, 7),
      );
      final changed = runTimetableHistoryDiff(
        database: db,
        accountId: accountId,
        current: _timetable(subjectName: 'Deutsch'),
        capturedAt: DateTime(2026, 9, 21, 7),
      );
      expect(changed, isTrue);

      final row = db.getLatestTimetableHistoryRow(accountId: accountId);
      expect(row!.validFromDate, DateTime(2026, 9, 21));
    });

    test('loadTimetableForWeek falls back to the closest earlier snapshot', () {
      runTimetableHistoryDiff(
        database: db,
        accountId: accountId,
        current: _timetable(subjectName: 'Mathe'),
        capturedAt: DateTime(2026, 9, 7, 7),
      );
      runTimetableHistoryDiff(
        database: db,
        accountId: accountId,
        current: _timetable(subjectName: 'Deutsch'),
        capturedAt: DateTime(2026, 9, 21, 7),
      );

      // A week in between the two snapshots (14.9.) has no row of its own
      // -- should fall back to the 7.9. snapshot ("Mathe"), not the later
      // 21.9. one ("Deutsch").
      final result = loadTimetableForWeek(
        database: db,
        accountId: accountId,
        weekMonday: DateTime(2026, 9, 14),
      );
      expect(result, isNotNull);
      expect(result!.planForAll![0][0].name, 'Mathe');

      final onOrAfterLater = loadTimetableForWeek(
        database: db,
        accountId: accountId,
        weekMonday: DateTime(2026, 9, 21),
      );
      expect(onOrAfterLater!.planForAll![0][0].name, 'Deutsch');
    });

    test('loadTimetableForWeek before any history -> null', () {
      runTimetableHistoryDiff(
        database: db,
        accountId: accountId,
        current: _timetable(),
        capturedAt: DateTime(2026, 9, 14, 7),
      );
      final result = loadTimetableForWeek(
        database: db,
        accountId: accountId,
        weekMonday: DateTime(2026, 9, 7),
      );
      expect(result, isNull);
    });

    test('earliestTimetableHistoryWeek reports the first stored Monday', () {
      expect(
        earliestTimetableHistoryWeek(database: db, accountId: accountId),
        isNull,
      );
      runTimetableHistoryDiff(
        database: db,
        accountId: accountId,
        current: _timetable(subjectName: 'Mathe'),
        capturedAt: DateTime(2026, 9, 7, 7),
      );
      runTimetableHistoryDiff(
        database: db,
        accountId: accountId,
        current: _timetable(subjectName: 'Deutsch'),
        capturedAt: DateTime(2026, 9, 21, 7),
      );
      expect(
        earliestTimetableHistoryWeek(database: db, accountId: accountId),
        DateTime(2026, 9, 7),
      );
    });

    test('different accounts stay isolated', () async {
      await db.addAccount(
        schoolId: 1,
        schoolName: 'S',
        username: 'u2',
        password: 'p',
      );
      runTimetableHistoryDiff(
        database: db,
        accountId: 1,
        current: _timetable(subjectName: 'Mathe'),
        capturedAt: DateTime(2026, 9, 14, 7),
      );
      runTimetableHistoryDiff(
        database: db,
        accountId: 2,
        current: _timetable(subjectName: 'Deutsch'),
        capturedAt: DateTime(2026, 9, 14, 7),
      );

      final row1 = loadTimetableForWeek(
        database: db,
        accountId: 1,
        weekMonday: DateTime(2026, 9, 14),
      );
      final row2 = loadTimetableForWeek(
        database: db,
        accountId: 2,
        weekMonday: DateTime(2026, 9, 14),
      );
      expect(row1!.planForAll![0][0].name, 'Mathe');
      expect(row2!.planForAll![0][0].name, 'Deutsch');
    });
  });
}
