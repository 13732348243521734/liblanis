import 'dart:convert';

import '../../database/database.dart';
import '../../history/history_differ.dart';
import '../../models/timetable.dart';

/// Monday (00:00, local wall-clock date) of the week [date] falls into.
/// The single place both storage ([TimeTableSnapshotStore]) and lookup
/// ([loadTimetableForWeek]) derive a week's identity from, so they can
/// never disagree on which Monday a given day belongs to.
DateTime mondayOf(DateTime date) {
  return DateTime(date.year, date.month, date.day - (date.weekday - 1));
}

/// Deep content equality for [TimeTable], beyond what the class itself
/// implements (it has no `==` override) -- used to decide whether a fresh
/// fetch actually changed anything before writing a new history row
/// (feature plan 7.5: "nur bei tatsächlicher Änderung wird ein neuer
/// Snapshot angelegt"). Compares via the same JSON shape that's persisted,
/// which already recursively covers every nested field.
bool timeTablesEqual(TimeTable a, TimeTable b) {
  return jsonEncode(a.toJson()) == jsonEncode(b.toJson());
}

/// [SnapshotStore] backed by the `timetable_history` table.
///
/// Unlike [SubstitutionDayHistoryStore] (which upserts one row per entry
/// key every single call), this store is deliberately conservative about
/// writing: [save] only inserts/updates a row when the content actually
/// differs from the most recently stored snapshot, so a week with no real
/// changes produces no new row -- [loadTimetableForWeek] falls back to the
/// closest earlier row instead.
class TimeTableSnapshotStore implements SnapshotStore<TimeTable> {
  final LanisDatabase database;

  TimeTableSnapshotStore(this.database);

  @override
  TimeTable? loadLast(int accountId) {
    final row = database.getLatestTimetableHistoryRow(accountId: accountId);
    if (row == null) return null;
    return TimeTable.fromJson(
      jsonDecode(row.timetableJson) as Map<String, dynamic>,
    );
  }

  @override
  void save(int accountId, TimeTable snapshot, DateTime capturedAt) {
    final last = database.getLatestTimetableHistoryRow(accountId: accountId);
    if (last != null) {
      final lastTimetable = TimeTable.fromJson(
        jsonDecode(last.timetableJson) as Map<String, dynamic>,
      );
      if (timeTablesEqual(lastTimetable, snapshot)) {
        // Unchanged since the last stored snapshot -- nothing to persist.
        // A lookup for this week will correctly fall back to `last`.
        return;
      }
    }
    database.upsertTimetableHistoryEntry(
      accountId: accountId,
      validFromDate: mondayOf(capturedAt),
      timetableJson: jsonEncode(snapshot.toJson()),
      capturedAt: capturedAt,
    );
  }
}

/// Runs the history diff/save for the freshly fetched [current] timetable
/// (feature plan 7.5, point 2). There's no per-entry event model here
/// (unlike substitutions) -- the return value is simply whether a new
/// snapshot was actually written, for callers/tests that want to know.
bool runTimetableHistoryDiff({
  required LanisDatabase database,
  required int accountId,
  required TimeTable current,
  required DateTime capturedAt,
}) {
  final store = TimeTableSnapshotStore(database);
  return HistoryDiffer<TimeTable>(store).process<bool>(
        accountId,
        current,
        capturedAt,
        (previous, current) =>
            previous == null || !timeTablesEqual(previous, current)
                ? true
                : null,
      ) ??
      false;
}

/// The stored timetable that was valid during the week starting on
/// [weekMonday] -- the most recent snapshot at-or-before that Monday
/// (feature plan 7.5: "zuletzt gültiger Snapshot vor/an diesem Datum").
/// `null` if no history covers that far back yet.
TimeTable? loadTimetableForWeek({
  required LanisDatabase database,
  required int accountId,
  required DateTime weekMonday,
}) {
  final row = database.getTimetableHistoryRowAtOrBefore(
    accountId: accountId,
    weekMonday: weekMonday,
  );
  if (row == null) return null;
  return TimeTable.fromJson(
    jsonDecode(row.timetableJson) as Map<String, dynamic>,
  );
}

/// Monday of the earliest week any timetable history is available for, or
/// `null` if there's no history yet. Used by the app to know when to stop
/// offering "previous week" navigation (feature plan 7.5: "rückwärts
/// unbegrenzt, soweit Historie vorhanden").
DateTime? earliestTimetableHistoryWeek({
  required LanisDatabase database,
  required int accountId,
}) {
  return database.getEarliestTimetableHistoryDate(accountId: accountId);
}
