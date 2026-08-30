import 'dart:convert';

import '../../database/database.dart';
import '../../history/history_differ.dart';
import '../../models/substitution.dart';
import '../../models/substitution_change.dart';

/// Account setting key controlling how long substitution-history entries
/// are kept (in days) before [pruneSubstitutionHistory] removes them.
/// Default is 30 days (feature plan 6, point 5).
const substitutionHistoryRetentionDaysKey =
    'substitution-history-retention-days';
const defaultSubstitutionHistoryRetentionDays = 30;

/// Compares [previous] against [current] for a single day (bucketed by
/// `tag_en`, feature plan 6.1) and returns the detected changes, or `null`
/// when there is nothing to report — either because [previous] is `null`
/// (first fetch after install/update; see [HistoryDiffer.process]) or
/// because nothing changed.
///
/// Matching key: `lehrer|fach|stunde` (see [substitutionHistoryKey]). If
/// lehrer/fach/stunde stay the same but another field (e.g. `raum`)
/// changes, the entry is reported as [SubstitutionChangeType.modified].
List<SubstitutionChangeEvent>? diffSubstitutionDay(
  SubstitutionDay? previous,
  SubstitutionDay current,
) {
  if (previous == null) return null;

  final previousByKey = <String, Substitution>{
    for (final s in previous.substitutions) substitutionHistoryKey(s): s,
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
      parsedDate: _tagFromEn(tagEn),
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
      if (existing == null) {
        status = SubstitutionChangeType.added.name;
        changeDetectedAt = capturedAt;
      } else {
        final previousSub = Substitution.fromJson(
          jsonDecode(existing.snapshotJson) as Map<String, dynamic>,
        );
        final changed = _fieldDeltas(previousSub, currentSub).isNotEmpty;
        if (changed) {
          status = SubstitutionChangeType.modified.name;
          changeDetectedAt = capturedAt;
        } else {
          // Unchanged this round — keep whatever status/change timestamp
          // was last recorded.
          status = existing.status;
          changeDetectedAt = existing.changeDetectedAt;
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
      );
    }
  }

  static String _tagFromEn(String tagEn) {
    final parts = tagEn.split('-');
    if (parts.length != 3) return tagEn;
    return '${parts[2]}.${parts[1]}.${parts[0]}';
  }
}

/// Runs the history diff/save for every day in [current] and returns all
/// detected change events across days (feature plan 6.2, point 2).
///
/// [tagEnOf] extracts the `yyyy-MM-dd` bucket for a day; the substitutions
/// parser already carries this per-entry as `Substitution.tag_en`.
List<SubstitutionChangeEvent> runSubstitutionHistoryDiff({
  required LanisDatabase database,
  required int accountId,
  required List<SubstitutionDay> days,
  required DateTime capturedAt,
}) {
  final allEvents = <SubstitutionChangeEvent>[];
  for (final day in days) {
    final tagEn = day.substitutions.isNotEmpty
        ? day.substitutions.first.tag_en
        : _tagEnFromParsedDate(day.parsedDate);
    if (tagEn == null || tagEn.isEmpty) continue;

    final store = SubstitutionDayHistoryStore(database, tagEn);
    final differ = HistoryDiffer<SubstitutionDay>(store);
    final events = differ.process<List<SubstitutionChangeEvent>>(
      accountId,
      day,
      capturedAt,
      diffSubstitutionDay,
    );
    if (events != null) allEvents.addAll(events);
  }
  return allEvents;
}

String? _tagEnFromParsedDate(String parsedDate) {
  // parsedDate is dd.MM.yyyy; days with zero substitutions (info-only days)
  // fall back to converting it rather than requiring a substitution entry.
  final parts = parsedDate.split('.');
  if (parts.length != 3) return null;
  return '${parts[2]}-${parts[1]}-${parts[0]}';
}
