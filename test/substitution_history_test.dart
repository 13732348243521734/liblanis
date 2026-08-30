import 'package:liblanis/liblanis.dart';
import 'package:test/test.dart';

Substitution _sub({
  String tag = '01.09.2026',
  String tagEn = '2026-09-01',
  String stunde = '3',
  String? lehrer = 'Müller',
  String? fach = 'Mathe',
  String? raum = '101',
  String? vertreter,
  String? hinweis,
}) => Substitution(
  tag: tag,
  tag_en: tagEn,
  stunde: stunde,
  lehrer: lehrer,
  fach: fach,
  raum: raum,
  vertreter: vertreter,
  hinweis: hinweis,
);

void main() {
  group('substitutionHistoryKey', () {
    test('built from lehrer|fach|stunde', () {
      final s = _sub(lehrer: 'Müller', fach: 'Mathe', stunde: '3');
      expect(substitutionHistoryKey(s), 'Müller|Mathe|3');
    });

    test('null lehrer/fach become empty segments', () {
      final s = _sub(lehrer: null, fach: null, stunde: '3');
      expect(substitutionHistoryKey(s), '||3');
    });
  });

  group('diffSubstitutionDay', () {
    test('previous == null -> every current entry reported as added', () {
      final day = SubstitutionDay(
        parsedDate: '01.09.2026',
        substitutions: [_sub(stunde: '3'), _sub(stunde: '5', fach: 'Physik')],
      );
      final events = diffSubstitutionDay(null, day);
      expect(events, hasLength(2));
      expect(
        events!.every((e) => e.type == SubstitutionChangeType.added),
        isTrue,
      );
      expect(events.map((e) => e.entryKey), [
        'Müller|Mathe|3',
        'Müller|Physik|5',
      ]);
    });

    test('previous == null and current has no entries -> null', () {
      final emptyDay = SubstitutionDay(
        parsedDate: '01.09.2026',
        substitutions: [],
      );
      expect(diffSubstitutionDay(null, emptyDay), isNull);
    });

    test('key collision, raum changes -> modified with a raum delta', () {
      final previous = SubstitutionDay(
        parsedDate: '01.09.2026',
        substitutions: [_sub(raum: '101')],
      );
      final current = SubstitutionDay(
        parsedDate: '01.09.2026',
        substitutions: [_sub(raum: '202')],
      );

      final events = diffSubstitutionDay(previous, current);
      expect(events, hasLength(1));
      expect(events!.single.type, SubstitutionChangeType.modified);
      expect(events.single.entryKey, 'Müller|Mathe|3');
      expect(events.single.fieldDeltas, hasLength(1));
      expect(events.single.fieldDeltas.single.field, 'raum');
      expect(events.single.fieldDeltas.single.oldValue, '101');
      expect(events.single.fieldDeltas.single.newValue, '202');
    });

    test('identical entries -> no events', () {
      final day = SubstitutionDay(
        parsedDate: '01.09.2026',
        substitutions: [_sub()],
      );
      final other = SubstitutionDay(
        parsedDate: '01.09.2026',
        substitutions: [_sub()],
      );
      expect(diffSubstitutionDay(day, other), isNull);
    });

    test('pure addition -> one added event', () {
      final previous = SubstitutionDay(
        parsedDate: '01.09.2026',
        substitutions: [_sub(stunde: '3')],
      );
      final current = SubstitutionDay(
        parsedDate: '01.09.2026',
        substitutions: [_sub(stunde: '3'), _sub(stunde: '5', fach: 'Physik')],
      );

      final events = diffSubstitutionDay(previous, current);
      expect(events, hasLength(1));
      expect(events!.single.type, SubstitutionChangeType.added);
      expect(events.single.entryKey, 'Müller|Physik|5');
      expect(events.single.current, isNotNull);
      expect(events.single.previous, isNull);
    });

    test('pure removal -> one removed event', () {
      final previous = SubstitutionDay(
        parsedDate: '01.09.2026',
        substitutions: [_sub(stunde: '3'), _sub(stunde: '5', fach: 'Physik')],
      );
      final current = SubstitutionDay(
        parsedDate: '01.09.2026',
        substitutions: [_sub(stunde: '3')],
      );

      final events = diffSubstitutionDay(previous, current);
      expect(events, hasLength(1));
      expect(events!.single.type, SubstitutionChangeType.removed);
      expect(events.single.entryKey, 'Müller|Physik|5');
      expect(events.single.previous, isNotNull);
      expect(events.single.current, isNull);
    });
  });

  group('SubstitutionDayHistoryStore + runSubstitutionHistoryDiff', () {
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

    test('day-bucket boundary: same key on different days stays separate', () {
      final day1 = SubstitutionDay(
        parsedDate: '01.09.2026',
        substitutions: [_sub(tag: '01.09.2026', tagEn: '2026-09-01', raum: '101')],
      );
      final day2 = SubstitutionDay(
        parsedDate: '02.09.2026',
        substitutions: [_sub(tag: '02.09.2026', tagEn: '2026-09-02', raum: '101')],
      );

      // First fetch: establishes baseline snapshots for both days.
      runSubstitutionHistoryDiff(
        database: db,
        accountId: accountId,
        days: [day1, day2],
        capturedAt: DateTime(2026, 9, 1, 8),
      );

      // Second fetch: only day1's room changes. day2 (same key!) must stay
      // untouched — the day bucket, not just the entry key, is the scope.
      final day1Changed = SubstitutionDay(
        parsedDate: '01.09.2026',
        substitutions: [_sub(tag: '01.09.2026', tagEn: '2026-09-01', raum: '202')],
      );
      final events = runSubstitutionHistoryDiff(
        database: db,
        accountId: accountId,
        days: [day1Changed, day2],
        capturedAt: DateTime(2026, 9, 1, 9),
      );

      expect(events, hasLength(1));
      expect(events.single.tagEn, '2026-09-01');
      expect(events.single.type, SubstitutionChangeType.modified);

      final day2Rows = db.getSubstitutionHistoryRows(
        accountId: accountId,
        tagEn: '2026-09-02',
      );
      expect(day2Rows, hasLength(1));
      expect(day2Rows.single.status, 'added');
    });

    test('status persists across fetches: added -> unchanged keeps status, then modified updates it', () {
      final tagEn = '2026-09-01';
      final v1 = SubstitutionDay(
        parsedDate: '01.09.2026',
        substitutions: [_sub(tagEn: tagEn, raum: '101')],
      );
      runSubstitutionHistoryDiff(
        database: db,
        accountId: accountId,
        days: [v1],
        capturedAt: DateTime(2026, 9, 1, 8),
      );
      var rows = db.getSubstitutionHistoryRows(accountId: accountId, tagEn: tagEn);
      expect(rows.single.status, 'added');

      // Unchanged second fetch: status should NOT revert, last_seen advances.
      runSubstitutionHistoryDiff(
        database: db,
        accountId: accountId,
        days: [v1],
        capturedAt: DateTime(2026, 9, 1, 9),
      );
      rows = db.getSubstitutionHistoryRows(accountId: accountId, tagEn: tagEn);
      expect(rows.single.status, 'added');
      expect(rows.single.lastSeen, DateTime(2026, 9, 1, 9));

      // Room changes: status flips to modified.
      final v2 = SubstitutionDay(
        parsedDate: '01.09.2026',
        substitutions: [_sub(tagEn: tagEn, raum: '202')],
      );
      runSubstitutionHistoryDiff(
        database: db,
        accountId: accountId,
        days: [v2],
        capturedAt: DateTime(2026, 9, 1, 10),
      );
      rows = db.getSubstitutionHistoryRows(accountId: accountId, tagEn: tagEn);
      expect(rows.single.status, 'modified');
    });

    test('removal keeps the row with status removed and does not bump last_seen', () {
      final tagEn = '2026-09-01';
      final v1 = SubstitutionDay(
        parsedDate: '01.09.2026',
        substitutions: [_sub(tagEn: tagEn)],
      );
      runSubstitutionHistoryDiff(
        database: db,
        accountId: accountId,
        days: [v1],
        capturedAt: DateTime(2026, 9, 1, 8),
      );

      final empty = SubstitutionDay(parsedDate: '01.09.2026', substitutions: []);
      // runSubstitutionHistoryDiff skips days with no substitutions when
      // determining the bucket, so drive the store directly for this case.
      final store = SubstitutionDayHistoryStore(db, tagEn);
      final differ = HistoryDiffer<SubstitutionDay>(store);
      final events = differ.process<List<dynamic>>(
        accountId,
        empty,
        DateTime(2026, 9, 1, 9),
        (previous, current) =>
            diffSubstitutionDay(previous, current) ?? const [],
      );

      expect(events, hasLength(1));
      final rows = db.getSubstitutionHistoryRows(accountId: accountId, tagEn: tagEn);
      expect(rows.single.status, 'removed');
      expect(rows.single.lastSeen, DateTime(2026, 9, 1, 8));
    });

    test('pruneSubstitutionHistory removes entries older than retention', () {
      final tagEn = '2026-01-01';
      db.upsertSubstitutionHistoryEntry(
        accountId: accountId,
        entryKey: 'A|B|1',
        tagEn: tagEn,
        stunde: '1',
        snapshotJson: '{}',
        status: 'removed',
        firstSeen: DateTime(2026, 1, 1),
        lastSeen: DateTime(2026, 1, 1),
      );

      db.pruneSubstitutionHistory(
        accountId: accountId,
        retention: const Duration(days: 30),
        now: DateTime(2026, 3, 1),
      );

      expect(
        db.getSubstitutionHistoryRows(accountId: accountId, tagEn: tagEn),
        isEmpty,
      );
    });

    test('loadSubstitutionHistoryEvents returns most recently changed entries first', () {
      final day1 = SubstitutionDay(
        parsedDate: '01.09.2026',
        substitutions: [_sub(tagEn: '2026-09-01', stunde: '1', fach: 'Deutsch')],
      );
      final day2 = SubstitutionDay(
        parsedDate: '02.09.2026',
        substitutions: [_sub(tagEn: '2026-09-02', stunde: '2', fach: 'Englisch')],
      );
      runSubstitutionHistoryDiff(
        database: db,
        accountId: accountId,
        days: [day1],
        capturedAt: DateTime(2026, 9, 1, 8),
      );
      runSubstitutionHistoryDiff(
        database: db,
        accountId: accountId,
        days: [day2],
        capturedAt: DateTime(2026, 9, 1, 9),
      );

      final events = loadSubstitutionHistoryEvents(
        database: db,
        accountId: accountId,
      );

      expect(events, hasLength(2));
      // Most recently detected change (day2, 09:00) comes first.
      expect(events.first.tagEn, '2026-09-02');
      expect(events.first.type, SubstitutionChangeType.added);
      expect(events.first.current?.fach, 'Englisch');
      expect(events.last.tagEn, '2026-09-01');
    });
  });
}
