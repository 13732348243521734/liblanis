import 'dart:io';

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
  String? klasse,
}) => Substitution(
  tag: tag,
  tag_en: tagEn,
  stunde: stunde,
  lehrer: lehrer,
  fach: fach,
  raum: raum,
  vertreter: vertreter,
  hinweis: hinweis,
  klasse: klasse,
);

void main() {
  group('substitutionHistoryKey', () {
    test('built from lehrer|fach|stunde', () {
      final s = _sub(lehrer: 'Müller', fach: 'Mathe', stunde: '3');
      expect(substitutionHistoryKey(s), 'Müller|Mathe|3');
    });

    test('lehrer or fach present -> klasse not appended, even if set', () {
      final s = _sub(lehrer: 'Müller', fach: null, stunde: '3', klasse: '7a');
      expect(substitutionHistoryKey(s), 'Müller||3');
    });

    test('lehrer AND fach both null -> falls back to appending klasse', () {
      final s = _sub(lehrer: null, fach: null, stunde: '3', klasse: '7a');
      expect(substitutionHistoryKey(s), '||3|7a');
    });

    test('lehrer AND fach both null, klasse also null -> stable empty segment', () {
      final s = _sub(lehrer: null, fach: null, stunde: '3', klasse: null);
      expect(substitutionHistoryKey(s), '||3|');
    });

    test('regression: two empty-lehrer/fach entries for different classes no longer collide', () {
      final classA = _sub(lehrer: null, fach: null, stunde: '3', klasse: '7a');
      final classB = _sub(lehrer: null, fach: null, stunde: '3', klasse: '7b');
      expect(
        substitutionHistoryKey(classA),
        isNot(substitutionHistoryKey(classB)),
      );

      final previous = SubstitutionDay(
        parsedDate: '01.09.2026',
        substitutions: [classA, classB],
      );
      final current = SubstitutionDay(
        parsedDate: '01.09.2026',
        substitutions: [classA], // classB's substitution is gone
      );
      final events = diffSubstitutionDay(previous, current);
      // Both entries must have been tracked independently: classB missing
      // is a real 'removed' event, not silently absorbed by classA's key.
      expect(events, hasLength(1));
      expect(events!.single.type, SubstitutionChangeType.removed);
      expect(events.single.previous?.klasse, '7b');
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

    test('day emptied but still in fetch window -> marked removed', () {
      final day = SubstitutionDay(
        parsedDate: '01.09.2026',
        substitutions: [_sub(tagEn: '2026-09-01')],
      );
      runSubstitutionHistoryDiff(
        database: db,
        accountId: accountId,
        days: [day],
        capturedAt: DateTime(2026, 9, 1, 8),
        windowDates: ['01.09.2026'],
      );

      // Next fetch: the portal still returns 01.09.2026 in its date window,
      // but with zero substitutions and zero infos -- parseDocumentHtml's
      // removeEmptyDays() would have stripped it from `days` already, so
      // simulate that by NOT including it in `days`, only in `windowDates`.
      final events = runSubstitutionHistoryDiff(
        database: db,
        accountId: accountId,
        days: [],
        capturedAt: DateTime(2026, 9, 1, 9),
        windowDates: ['01.09.2026'],
      );

      expect(events, hasLength(1));
      expect(events.single.type, SubstitutionChangeType.removed);
      expect(events.single.tagEn, '2026-09-01');

      final rows = db.getSubstitutionHistoryRows(
        accountId: accountId,
        tagEn: '2026-09-01',
      );
      expect(rows.single.status, 'removed');
    });

    test('day scrolls out of the fetch window entirely -> left untouched, no false removal', () {
      final day = SubstitutionDay(
        parsedDate: '01.09.2026',
        substitutions: [_sub(tagEn: '2026-09-01')],
      );
      runSubstitutionHistoryDiff(
        database: db,
        accountId: accountId,
        days: [day],
        capturedAt: DateTime(2026, 9, 1, 8),
        windowDates: ['01.09.2026'],
      );

      // Next fetch: 01.09.2026 is now in the past, the portal's date window
      // moved on and no longer returns it at all -- neither in `days` nor
      // in `windowDates`. This must NOT be treated as a removal.
      final events = runSubstitutionHistoryDiff(
        database: db,
        accountId: accountId,
        days: [],
        capturedAt: DateTime(2026, 9, 2, 8),
        windowDates: ['02.09.2026', '03.09.2026'],
      );

      expect(events, isEmpty);

      final rows = db.getSubstitutionHistoryRows(
        accountId: accountId,
        tagEn: '2026-09-01',
      );
      expect(rows.single.status, 'added');
    });

    test('windowDates defaults to empty -> preserves old days-only behaviour', () {
      final day = SubstitutionDay(
        parsedDate: '01.09.2026',
        substitutions: [_sub(tagEn: '2026-09-01')],
      );
      runSubstitutionHistoryDiff(
        database: db,
        accountId: accountId,
        days: [day],
        capturedAt: DateTime(2026, 9, 1, 8),
      );

      final events = runSubstitutionHistoryDiff(
        database: db,
        accountId: accountId,
        days: [],
        capturedAt: DateTime(2026, 9, 1, 9),
      );

      expect(events, isEmpty);
      final rows = db.getSubstitutionHistoryRows(
        accountId: accountId,
        tagEn: '2026-09-01',
      );
      expect(rows.single.status, 'added');
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
      expect(rows.single.fieldDeltasJson, isNull);

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

      // Room changes: status flips to modified, delta is persisted.
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
      expect(rows.single.fieldDeltasJson, isNotNull);

      // Unchanged again: the persisted delta from the last real change
      // must survive, not get cleared just because nothing changed now.
      runSubstitutionHistoryDiff(
        database: db,
        accountId: accountId,
        days: [v2],
        capturedAt: DateTime(2026, 9, 1, 11),
      );
      rows = db.getSubstitutionHistoryRows(accountId: accountId, tagEn: tagEn);
      expect(rows.single.status, 'modified');
      expect(rows.single.fieldDeltasJson, isNotNull);
    });

    test('loadSubstitutionHistoryEvents surfaces the persisted field deltas for modified entries', () {
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
      final v2 = SubstitutionDay(
        parsedDate: '01.09.2026',
        substitutions: [_sub(tagEn: tagEn, raum: '202')],
      );
      runSubstitutionHistoryDiff(
        database: db,
        accountId: accountId,
        days: [v2],
        capturedAt: DateTime(2026, 9, 1, 9),
      );

      final events = loadSubstitutionHistoryEvents(
        database: db,
        accountId: accountId,
      );
      expect(events, hasLength(1));
      expect(events.single.type, SubstitutionChangeType.modified);
      expect(events.single.fieldDeltas, hasLength(1));
      expect(events.single.fieldDeltas.single.field, 'raum');
      expect(events.single.fieldDeltas.single.oldValue, '101');
      expect(events.single.fieldDeltas.single.newValue, '202');
    });

    test('loadSubstitutionHistoryEvents returns no field deltas for a purely added entry', () {
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

      final events = loadSubstitutionHistoryEvents(
        database: db,
        accountId: accountId,
      );
      expect(events.single.type, SubstitutionChangeType.added);
      expect(events.single.fieldDeltas, isEmpty);
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

  group('loadSubstitutionDayForDisplay', () {
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

    test('no history for that day -> null', () {
      final result = loadSubstitutionDayForDisplay(
        database: db,
        accountId: accountId,
        tagEn: '2026-09-01',
      );
      expect(result, isNull);
    });

    test('reconstructs still-active entries, drops removed ones', () {
      final day = SubstitutionDay(
        parsedDate: '01.09.2026',
        substitutions: [
          _sub(tagEn: '2026-09-01', stunde: '3', fach: 'Mathe'),
          _sub(tagEn: '2026-09-01', stunde: '5', fach: 'Physik'),
        ],
      );
      runSubstitutionHistoryDiff(
        database: db,
        accountId: accountId,
        days: [day],
        capturedAt: DateTime(2026, 9, 1, 7),
      );

      // Next fetch (still the same day, e.g. a later refresh): Physik/5
      // is gone from the live plan again -> gets marked 'removed', Mathe/3
      // stays.
      final dayAfter = SubstitutionDay(
        parsedDate: '01.09.2026',
        substitutions: [
          _sub(tagEn: '2026-09-01', stunde: '3', fach: 'Mathe'),
        ],
      );
      runSubstitutionHistoryDiff(
        database: db,
        accountId: accountId,
        days: [dayAfter],
        capturedAt: DateTime(2026, 9, 1, 9),
        windowDates: ['01.09.2026'],
      );

      final result = loadSubstitutionDayForDisplay(
        database: db,
        accountId: accountId,
        tagEn: '2026-09-01',
      );
      expect(result, isNotNull);
      expect(result!.substitutions, hasLength(1));
      expect(result.substitutions.single.fach, 'Mathe');
      expect(result.parsedDate, '01.09.2026');
    });

    test('Vertretung changed to Entfall on the same key -> latest state wins', () {
      final added = SubstitutionDay(
        parsedDate: '01.09.2026',
        substitutions: [
          _sub(
            tagEn: '2026-09-01',
            stunde: '3',
            fach: 'Mathe',
            vertreter: 'Schmidt',
          ),
        ],
      );
      runSubstitutionHistoryDiff(
        database: db,
        accountId: accountId,
        days: [added],
        capturedAt: DateTime(2026, 9, 1, 7),
      );

      final becameEntfall = SubstitutionDay(
        parsedDate: '01.09.2026',
        substitutions: [
          _sub(tagEn: '2026-09-01', stunde: '3', fach: 'Mathe', hinweis: 'Entfall'),
        ],
      );
      runSubstitutionHistoryDiff(
        database: db,
        accountId: accountId,
        days: [becameEntfall],
        capturedAt: DateTime(2026, 9, 1, 9),
      );

      final result = loadSubstitutionDayForDisplay(
        database: db,
        accountId: accountId,
        tagEn: '2026-09-01',
      );
      expect(result!.substitutions, hasLength(1));
      expect(result.substitutions.single.hinweis, 'Entfall');
      expect(result.substitutions.single.vertreter, isNull);
    });
  });

  group('tag_en bucketing (regression: dd_MM_yyyy vs yyyy-MM-dd)', () {
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

    test('a day with substitutions is bucketed as yyyy-MM-dd, not the '
        "substitution's own raw dd_MM_yyyy tag_en", () {
      // Substitution.tag_en deliberately set to the portal's internal
      // AJAX-key shape here, the way the real parser actually produces
      // it -- this is what runSubstitutionHistoryDiff must *not* use
      // directly as the storage bucket key anymore.
      final day = SubstitutionDay(
        parsedDate: '08.09.2026',
        substitutions: [
          _sub(tag: '08.09.2026', tagEn: '08_09_2026', stunde: '3'),
        ],
      );
      runSubstitutionHistoryDiff(
        database: db,
        accountId: accountId,
        days: [day],
        capturedAt: DateTime(2026, 9, 8, 8),
      );

      // Findable by the documented yyyy-MM-dd bucket key ...
      final byCorrectKey = db.getSubstitutionHistoryRows(
        accountId: accountId,
        tagEn: '2026-09-08',
      );
      expect(byCorrectKey, hasLength(1));

      // ... and *not* stored under the substitution's own raw tag_en.
      final byRawSubstitutionTagEn = db.getSubstitutionHistoryRows(
        accountId: accountId,
        tagEn: '08_09_2026',
      );
      expect(byRawSubstitutionTagEn, isEmpty);
    });

    test('loadSubstitutionDayForDisplay finds a day with substitutions '
        'by its yyyy-MM-dd date, matching how the timetable week view '
        'looks it up', () {
      final day = SubstitutionDay(
        parsedDate: '08.09.2026',
        substitutions: [
          _sub(tag: '08.09.2026', tagEn: '08_09_2026', stunde: '3'),
        ],
      );
      runSubstitutionHistoryDiff(
        database: db,
        accountId: accountId,
        days: [day],
        capturedAt: DateTime(2026, 9, 8, 8),
      );

      final result = loadSubstitutionDayForDisplay(
        database: db,
        accountId: accountId,
        tagEn: '2026-09-08',
      );
      expect(result, isNotNull);
      expect(result!.substitutions, hasLength(1));
    });
  });

  group('LanisDatabase._migrateLegacyTagEnFormat', () {
    test('normalizes a pre-existing dd_MM_yyyy row to yyyy-MM-dd on the '
        'next open, and leaves already-correct rows alone', () async {
      final path =
          '${Directory.systemTemp.path}/liblanis_tagen_migration_test_'
          '${DateTime.now().microsecondsSinceEpoch}.db';
      addTearDown(() {
        final f = File(path);
        if (f.existsSync()) f.deleteSync();
      });

      var db = LanisDatabase.open(
        path: path,
        secretStore: MemorySecretStore(),
      );
      final accountId = await db.addAccount(
        schoolId: 1,
        schoolName: 'S',
        username: 'u',
        password: 'p',
      );

      // A legacy row, written the way the pre-fix code actually wrote
      // one for a day with substitutions.
      db.upsertSubstitutionHistoryEntry(
        accountId: accountId,
        entryKey: 'Müller|Mathe|3',
        tagEn: '08_09_2026',
        stunde: '3',
        snapshotJson: '{}',
        status: 'added',
        firstSeen: DateTime(2026, 9, 8),
        lastSeen: DateTime(2026, 9, 8),
      );
      // An already-correct row (e.g. from an empty-day windowDates entry)
      // -- must be left exactly as-is, not touched or duplicated.
      db.upsertSubstitutionHistoryEntry(
        accountId: accountId,
        entryKey: 'Schmidt|Deutsch|1',
        tagEn: '2026-09-09',
        stunde: '1',
        snapshotJson: '{}',
        status: 'added',
        firstSeen: DateTime(2026, 9, 9),
        lastSeen: DateTime(2026, 9, 9),
      );
      db.dispose();

      // Reopening re-runs _migrate(), which should normalize the legacy
      // row in place.
      db = LanisDatabase.open(path: path, secretStore: MemorySecretStore());

      final migrated = db.getSubstitutionHistoryRows(
        accountId: accountId,
        tagEn: '2026-09-08',
      );
      expect(migrated, hasLength(1));
      expect(migrated.single.entryKey, 'Müller|Mathe|3');

      final oldKeyGone = db.getSubstitutionHistoryRows(
        accountId: accountId,
        tagEn: '08_09_2026',
      );
      expect(oldKeyGone, isEmpty);

      final untouched = db.getSubstitutionHistoryRows(
        accountId: accountId,
        tagEn: '2026-09-09',
      );
      expect(untouched, hasLength(1));
      expect(untouched.single.entryKey, 'Schmidt|Deutsch|1');

      // Idempotency: running the migration again (a third open) must not
      // error or change anything further.
      db.dispose();
      db = LanisDatabase.open(path: path, secretStore: MemorySecretStore());
      final stillMigrated = db.getSubstitutionHistoryRows(
        accountId: accountId,
        tagEn: '2026-09-08',
      );
      expect(stillMigrated, hasLength(1));
      db.dispose();
    });
  });
}
