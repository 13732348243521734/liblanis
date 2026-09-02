import 'dart:convert';

import '../../database/database.dart';
import '../../history/history_differ.dart';
import '../../models/substitution.dart';
import '../../models/substitution_change.dart';
import '../../util/tag_en.dart';

/// Account setting key controlling how long substitution-history entries
/// are kept (in days) before [pruneSubstitutionHistory] removes them.
/// Default is 30 days (feature plan 6, point 5).
const substitutionHistoryRetentionDaysKey =
    'substitution-history-retention-days';
const defaultSubstitutionHistoryRetentionDays = 30;

/// Compares [previous] against [current] for a single day (bucketed by
/// `tag_en`, feature plan 6.1) and returns the detected changes, or `null`
/// when there is nothing to report.
///
/// On the very first fetch for a given day (`previous == null`, e.g. right
/// after install/update), every entry in [current] is reported as
/// [SubstitutionChangeType.added] — there is no prior state to compare
/// against, so "newly seen by this device" and "newly added" are treated
/// the same.
///
/// Matching key: `lehrer|fach|stunde` (see [substitutionHistoryKey]). If
/// lehrer/fach/stunde stay the same but another field (e.g. `raum`)
/// changes, the entry is reported as [SubstitutionChangeType.modified].
List<SubstitutionChangeEvent>? diffSubstitutionDay(
  SubstitutionDay? previous,
  SubstitutionDay current,
) {
  final previousByKey = <String, Substitution>{
    for (final s in previous?.substitutions ?? []) substitutionHistoryKey(s): s,
  };
  final currentByKey = <String, Substitution>{
    for (final s in current.substitutions) substitutionHistoryKey(s): s,
  };

  final events = <SubstitutionChangeEvent>[];

  for (final entry in currentByKey.entries) {
    final key = entry.key;
    final currentSub = entry.value;
    final previousSub = previousByKey[key];

    if (previousSub == null) {
      events.add(
        SubstitutionChangeEvent(
          type: SubstitutionChangeType.added,
          entryKey: key,
          tagEn: currentSub.tag_en,
          current: currentSub,
        ),
      );
      continue;
    }

    final deltas = _fieldDeltas(previousSub, currentSub);
    if (deltas.isNotEmpty) {
      events.add(
        SubstitutionChangeEvent(
          type: SubstitutionChangeType.modified,
          entryKey: key,
          tagEn: currentSub.tag_en,
          previous: previousSub,
          current: currentSub,
          fieldDeltas: deltas,
        ),
      );
    }
  }

  for (final entry in previousByKey.entries) {
    if (!currentByKey.containsKey(entry.key)) {
      events.add(
        SubstitutionChangeEvent(
          type: SubstitutionChangeType.removed,
          entryKey: entry.key,
          tagEn: entry.value.tag_en,
          previous: entry.value,
        ),
      );
    }
  }

  return events.isEmpty ? null : events;
}

/// Fields compared for [SubstitutionChangeType.modified], beyond the
/// identity key (`lehrer`/`fach`/`stunde`). No `_alt` fields — unused at
/// the source school (feature plan 4.5).
final List<
  ({String name, String? Function(Substitution) get})
>
_comparedFields = [
  (name: 'raum', get: (s) => s.raum),
  (name: 'vertreter', get: (s) => s.vertreter),
  (name: 'hinweis', get: (s) => s.hinweis),
  (name: 'hinweis2', get: (s) => s.hinweis2),
  (name: 'art', get: (s) => s.art),
  (name: 'klasse', get: (s) => s.klasse),
];

List<SubstitutionFieldDelta> _fieldDeltas(
  Substitution previous,
  Substitution current,
) {
  final deltas = <SubstitutionFieldDelta>[];
  for (final field in _comparedFields) {
    final oldValue = field.get(previous);
    final newValue = field.get(current);
    if (oldValue != newValue) {
      deltas.add(
        SubstitutionFieldDelta(
          field: field.name,
          oldValue: oldValue,
          newValue: newValue,
        ),
      );
    }
  }
  return deltas;
}

/// [SnapshotStore] backed by the `substitution_history` table, scoped to a
/// single day (`tagEn`, `yyyy-MM-dd`). Diffing runs per day — one instance
/// per `tagEn` is created for each day in the fetched plan (feature plan
/// 6.1: "Datum ist impliziter Bucket").
class SubstitutionDayHistoryStore implements SnapshotStore<SubstitutionDay> {
  final LanisDatabase database;
  final String tagEn;

  SubstitutionDayHistoryStore(this.database, this.tagEn);

  @override
  SubstitutionDay? loadLast(int accountId) {
    final rows = database.getSubstitutionHistoryRows(
      accountId: accountId,
      tagEn: tagEn,
    );
    if (rows.isEmpty) return null;
    return SubstitutionDay(
      parsedDate: tagEnToParsedDate(tagEn),
      substitutions: [
        for (final row in rows)
          Substitution.fromJson(
            jsonDecode(row.snapshotJson) as Map<String, dynamic>,
          ),
      ],
    );
  }

  @override
  void save(int accountId, SubstitutionDay snapshot, DateTime capturedAt) {
    final existingRows = database.getSubstitutionHistoryRows(
      accountId: accountId,
      tagEn: tagEn,
    );
    final existingByKey = {
      for (final row in existingRows) row.entryKey: row,
    };
    final currentByKey = <String, Substitution>{
      for (final s in snapshot.substitutions) substitutionHistoryKey(s): s,
    };

    // Added / unchanged / modified — upsert with a status reflecting what
    // happened *this* round, preserving first_seen from the existing row.
    for (final entry in currentByKey.entries) {
      final key = entry.key;
      final currentSub = entry.value;
      final existing = existingByKey[key];

      final String status;
      DateTime? changeDetectedAt;
      String? fieldDeltasJson;
      if (existing == null) {
        status = SubstitutionChangeType.added.name;
        changeDetectedAt = capturedAt;
        fieldDeltasJson = null;
      } else {
        final previousSub = Substitution.fromJson(
          jsonDecode(existing.snapshotJson) as Map<String, dynamic>,
        );
        final deltas = _fieldDeltas(previousSub, currentSub);
        if (deltas.isNotEmpty) {
          status = SubstitutionChangeType.modified.name;
          changeDetectedAt = capturedAt;
          fieldDeltasJson = jsonEncode(
            deltas.map((d) => d.toJson()).toList(),
          );
        } else {
          // Unchanged this round -- keep whatever status/change timestamp/
          // deltas were last recorded, so a still-'modified' entry keeps
          // showing what changed until it's modified again.
          status = existing.status;
          changeDetectedAt = existing.changeDetectedAt;
          fieldDeltasJson = existing.fieldDeltasJson;
        }
      }

      database.upsertSubstitutionHistoryEntry(
        accountId: accountId,
        entryKey: key,
        tagEn: tagEn,
        stunde: currentSub.stunde,
        snapshotJson: jsonEncode(currentSub.toJson()),
        status: status,
        firstSeen: existing?.firstSeen ?? capturedAt,
        lastSeen: capturedAt,
        changeDetectedAt: changeDetectedAt,
        fieldDeltasJson: fieldDeltasJson,
      );
    }

    // Removed — entry existed before but is gone now. Keep the row (for
    // history display / retention window) with status 'removed', but do
    // *not* advance last_seen: it was last actually seen at its previous
    // last_seen timestamp.
    for (final entry in existingRows) {
      if (currentByKey.containsKey(entry.entryKey)) continue;
      database.upsertSubstitutionHistoryEntry(
        accountId: accountId,
        entryKey: entry.entryKey,
        tagEn: tagEn,
        stunde: entry.stunde,
        snapshotJson: entry.snapshotJson,
        status: SubstitutionChangeType.removed.name,
        firstSeen: entry.firstSeen,
        lastSeen: entry.lastSeen,
        changeDetectedAt: capturedAt,
        fieldDeltasJson: entry.fieldDeltasJson,
      );
    }
  }
}

/// Runs the history diff/save for every day in [days] and returns all
/// detected change events across days (feature plan 6.2, point 2).
///
/// [windowDates] should be the full set of days the school portal actually
/// returned for this fetch (`dd.MM.yyyy`, from
/// `SubstitutionsParser.getSubstitutionDates` — call it *before*
/// `parseDocumentHtml`, since that strips fully-empty days before
/// [days] is ever built). It closes a gap [days] alone can't: when a day
/// goes from having substitutions to having none (and no infos),
/// `removeEmptyDays()` inside `parseDocumentHtml` strips it before it ever
/// reaches this function, so its history rows would otherwise never be
/// marked removed and would only quietly disappear after
/// [pruneSubstitutionHistory]'s retention window.
///
/// Only days still present in [windowDates] but missing from [days] are
/// treated as "emptied" and diffed against an empty snapshot. A day that
/// simply scrolled out of the portal's returned window (e.g. it's now in
/// the past) is *not* in [windowDates] either, so it is correctly left
/// alone — that's normal passage of time, not a substitution-plan change,
/// and must not produce a false 'removed' event/notification.
///
/// [windowDates] defaults to empty, which preserves the previous behaviour
/// (only [days] are diffed) for callers that don't have it handy.
List<SubstitutionChangeEvent> runSubstitutionHistoryDiff({
  required LanisDatabase database,
  required int accountId,
  required List<SubstitutionDay> days,
  required DateTime capturedAt,
  List<String> windowDates = const [],
}) {
  final allEvents = <SubstitutionChangeEvent>[];
  final coveredTagEns = <String>{};

  for (final day in days) {
    final tagEn = day.substitutions.isNotEmpty
        ? day.substitutions.first.tag_en
        : parsedDateToTagEn(day.parsedDate);
    if (tagEn == null || tagEn.isEmpty) continue;
    coveredTagEns.add(tagEn);

    final events = _diffAndSaveDay(
      database: database,
      accountId: accountId,
      tagEn: tagEn,
      day: day,
      capturedAt: capturedAt,
    );
    if (events != null) allEvents.addAll(events);
  }

  for (final windowDate in windowDates) {
    final tagEn = parsedDateToTagEn(windowDate);
    if (tagEn == null || coveredTagEns.contains(tagEn)) continue;

    final emptyDay = SubstitutionDay(
      parsedDate: windowDate,
      substitutions: [],
    );
    final events = _diffAndSaveDay(
      database: database,
      accountId: accountId,
      tagEn: tagEn,
      day: emptyDay,
      capturedAt: capturedAt,
    );
    if (events != null) allEvents.addAll(events);
  }

  return allEvents;
}

List<SubstitutionChangeEvent>? _diffAndSaveDay({
  required LanisDatabase database,
  required int accountId,
  required String tagEn,
  required SubstitutionDay day,
  required DateTime capturedAt,
}) {
  final store = SubstitutionDayHistoryStore(database, tagEn);
  final differ = HistoryDiffer<SubstitutionDay>(store);
  return differ.process<List<SubstitutionChangeEvent>>(
    accountId,
    day,
    capturedAt,
    diffSubstitutionDay,
  );
}

/// Reconstructs display-ready [SubstitutionChangeEvent]s from persisted
/// `substitution_history` rows — one event per entry, reflecting its most
/// recently recorded status (feature plan 6, point 4: "Änderungsverlauf"
/// screen).
///
/// For a [SubstitutionChangeType.modified] entry,
/// [SubstitutionChangeEvent.fieldDeltas] reflects the *most recent*
/// change only — the table persists the current snapshot plus the last
/// detected transition, not a full delta history across every prior
/// update. An entry modified twice shows only what changed the second
/// time, not a combined view of both changes.
List<SubstitutionChangeEvent> loadSubstitutionHistoryEvents({
  required LanisDatabase database,
  required int accountId,
  int limit = 200,
}) {
  final rows = database.getAllSubstitutionHistoryRows(
    accountId: accountId,
    limit: limit,
  );
  return [
    for (final row in rows)
      _rowToChangeEvent(row),
  ];
}

SubstitutionChangeEvent _rowToChangeEvent(SubstitutionHistoryRow row) {
  final sub = Substitution.fromJson(
    jsonDecode(row.snapshotJson) as Map<String, dynamic>,
  );
  final type = SubstitutionChangeType.values.byName(row.status);
  final fieldDeltasJson = row.fieldDeltasJson;
  final fieldDeltas = fieldDeltasJson == null
      ? const <SubstitutionFieldDelta>[]
      : (jsonDecode(fieldDeltasJson) as List)
          .map((d) => SubstitutionFieldDelta.fromJson(d as Map<String, dynamic>))
          .toList();
  return SubstitutionChangeEvent(
    type: type,
    entryKey: row.entryKey,
    tagEn: row.tagEn,
    current: type == SubstitutionChangeType.removed ? null : sub,
    previous: type == SubstitutionChangeType.removed ? sub : null,
    fieldDeltas: fieldDeltas,
  );
}
