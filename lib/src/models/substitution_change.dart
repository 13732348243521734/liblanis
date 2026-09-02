import 'substitution.dart';

/// How a substitution history entry changed between two snapshots.
enum SubstitutionChangeType { added, removed, modified }

/// A single field-level difference between two [Substitution]s that share
/// the same identity key (`lehrer|fach|stunde`).
class SubstitutionFieldDelta {
  final String field;
  final String? oldValue;
  final String? newValue;

  const SubstitutionFieldDelta({
    required this.field,
    this.oldValue,
    this.newValue,
  });

  Map<String, dynamic> toJson() => {
    'field': field,
    'oldValue': oldValue,
    'newValue': newValue,
  };

  SubstitutionFieldDelta.fromJson(Map<String, dynamic> json)
    : field = json['field'] as String,
      oldValue = json['oldValue'] as String?,
      newValue = json['newValue'] as String?;
}

/// A change detected for a single substitution-history entry
/// (identity key `lehrer|fach|stunde`, bucketed by day/`tag_en`).
class SubstitutionChangeEvent {
  final SubstitutionChangeType type;

  /// `lehrer|fach|stunde` — see [substitutionHistoryKey].
  final String entryKey;

  /// `yyyy-MM-dd` day bucket this entry belongs to.
  final String tagEn;

  /// Present for [SubstitutionChangeType.added] and
  /// [SubstitutionChangeType.modified].
  final Substitution? current;

  /// Present for [SubstitutionChangeType.removed] and
  /// [SubstitutionChangeType.modified].
  final Substitution? previous;

  /// Only populated for [SubstitutionChangeType.modified].
  final List<SubstitutionFieldDelta> fieldDeltas;

  const SubstitutionChangeEvent({
    required this.type,
    required this.entryKey,
    required this.tagEn,
    this.current,
    this.previous,
    this.fieldDeltas = const [],
  });

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'entryKey': entryKey,
    'tagEn': tagEn,
    'current': current?.toJson(),
    'previous': previous?.toJson(),
    'fieldDeltas': fieldDeltas.map((d) => d.toJson()).toList(),
  };

  SubstitutionChangeEvent.fromJson(Map<String, dynamic> json)
    : type = SubstitutionChangeType.values.byName(json['type'] as String),
      entryKey = json['entryKey'] as String,
      tagEn = json['tagEn'] as String,
      current = json['current'] != null
          ? Substitution.fromJson(json['current'] as Map<String, dynamic>)
          : null,
      previous = json['previous'] != null
          ? Substitution.fromJson(json['previous'] as Map<String, dynamic>)
          : null,
      fieldDeltas = (json['fieldDeltas'] as List? ?? [])
          .map((d) => SubstitutionFieldDelta.fromJson(d as Map<String, dynamic>))
          .toList();
}

/// Identity key used to match a substitution entry across snapshots:
/// `lehrer + "|" + fach + "|" + stunde`. Null `lehrer`/`fach` become empty
/// strings so the key stays stable and comparable.
///
/// Found in review: with both `lehrer` and `fach` empty (e.g. two
/// "entfällt" rows for different classes at the same period, with no
/// teacher/subject info), the base key alone collides and one entry
/// silently overwrites the other in the matching maps. In that specific
/// case only, `klasse` is appended to disambiguate — the common case
/// (lehrer or fach present) is unaffected, so this doesn't invalidate
/// existing history for the vast majority of entries.
///
/// No `_alt`-field matching — confirmed unused at the source school
/// (feature plan 4.5 / 6).
String substitutionHistoryKey(Substitution s) {
  final lehrer = s.lehrer ?? '';
  final fach = s.fach ?? '';
  final base = '$lehrer|$fach|${s.stunde}';
  if (lehrer.isEmpty && fach.isEmpty) {
    return '$base|${s.klasse ?? ''}';
  }
  return base;
}
