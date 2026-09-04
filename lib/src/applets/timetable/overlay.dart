import '../../models/merged_timetable.dart';
import '../../models/substitution.dart';
import '../../models/timetable.dart';
import 'merge.dart';

/// Splits every [TimetableSubject] in [subjects] into one
/// [DisplayLessonHour] per single hour it spans (feature plan 7.1, step 1
/// — "Zerlegen"). A subject with `duration == 2` and `stunde == 3` becomes
/// two [DisplayLessonHour]s for hours 3 and 4; a subject with
/// `duration == 1` becomes exactly one.
///
/// Subjects entered by the school as separate, already-single-hour rows
/// (rather than one row with `rowspan`) don't need splitting here — they
/// come out of this function unchanged in substance, just converted to
/// [DisplayLessonHour]. Either way, [mergeConsecutiveHours] is what
/// decides afterwards whether consecutive hours visually belong together.
///
/// Subjects with a `null` name or `null` stunde (row index) are skipped:
/// there's no hour to place them at or nothing to display, so they
/// wouldn't produce a meaningful [DisplayLessonHour] either way.
///
/// Returned hours are *not* sorted or deduplicated across subjects; that's
/// [mergeConsecutiveHours]'s job.
List<DisplayLessonHour> decomposeTimetableSubjects(
  List<TimetableSubject> subjects,
) {
  final result = <DisplayLessonHour>[];
  for (final subject in subjects) {
    final name = subject.name;
    final startStunde = subject.stunde;
    if (name == null || name.isEmpty || startStunde == null) continue;

    final duration = subject.duration < 1 ? 1 : subject.duration;
    for (var offset = 0; offset < duration; offset++) {
      result.add(
        DisplayLessonHour(
          stunde: startStunde + offset,
          fach: name,
          lehrer: subject.lehrer,
          raum: subject.raum,
          id: subject.id,
        ),
      );
    }
  }
  return result;
}

/// Splits every [Substitution] in [substitutions] whose `stunde` is a
/// range (e.g. `"3 - 4"`) into one entry per single hour (feature plan
/// 7.1, step 1), so matching (step 2) can do a plain 1:1 comparison
/// instead of range logic. A `stunde` that's already a single hour
/// (`"3"`) passes through as one entry.
///
/// A `stunde` that can't be parsed as either shape is kept as-is rather
/// than dropped — matching simply won't find it (its un-parseable
/// `stunde` string won't equal any decomposed hour's `stunde.toString()`),
/// which is the same effective outcome as skipping it, without silently
/// discarding data other callers might still want.
List<Substitution> decomposeSubstitutionRanges(
  List<Substitution> substitutions,
) {
  final result = <Substitution>[];
  for (final s in substitutions) {
    final hours = _parseStundeRange(s.stunde);
    if (hours.isEmpty) {
      result.add(s);
      continue;
    }
    for (final hour in hours) {
      result.add(
        Substitution(
          tag: s.tag,
          tag_en: s.tag_en,
          stunde: '$hour',
          vertreter: s.vertreter,
          lehrer: s.lehrer,
          klasse: s.klasse,
          klasse_alt: s.klasse_alt,
          fach: s.fach,
          fach_alt: s.fach_alt,
          raum: s.raum,
          raum_alt: s.raum_alt,
          hinweis: s.hinweis,
          hinweis2: s.hinweis2,
          art: s.art,
          Lehrerkuerzel: s.Lehrerkuerzel,
          Vertreterkuerzel: s.Vertreterkuerzel,
          lerngruppe: s.lerngruppe,
          hervorgehoben: s.hervorgehoben,
        ),
      );
    }
  }
  return result;
}

List<int> _parseStundeRange(String stunde) {
  final parts = stunde.split('-').map((p) => p.trim()).toList();
  if (parts.length == 1) {
    final n = int.tryParse(parts[0]);
    return n == null ? const [] : [n];
  }
  if (parts.length == 2) {
    final start = int.tryParse(parts[0]);
    final end = int.tryParse(parts[1]);
    if (start == null || end == null || end < start) return const [];
    return [for (var h = start; h <= end; h++) h];
  }
  return const [];
}

/// Resolves the [LessonOverlay] for a single decomposed hour by matching
/// it against already-decomposed [substitutions] (feature plan 7.1 step
/// 2 / 7.2). Returns `null` if no substitution entry matches this hour at
/// all.
///
/// Matching rule (7.2): a substitution entry affects this hour when its
/// (already-decomposed, single-hour) `stunde` equals [stunde] AND its
/// `fach` equals [fach]. Deliberately no teacher/room matching — the plan
/// only specifies stunde+fach identity.
///
/// If more than one substitution entry matches (shouldn't normally
/// happen after decomposition, but not structurally impossible), the
/// first match wins.
///
/// Display-rule resolution (7.3), all independent unless noted:
///   - `vertreter` set on the match (and non-empty) -> overlay.vertreter.
///   - `raum == "EVA"` or `hinweis == "EVA"` on the match -> overlay.isEva
///     — this is the priority signal; when it's true, rendering the
///     overlay as "fully red / struck through" is a UI concern (not
///     encoded in this model), but substituteRaum is deliberately left
///     unset in that case since an EVA entry's `raum` field isn't a real
///     replacement room.
///   - the match's `raum` differs from [originalRaum] (and isn't EVA) ->
///     overlay.substituteRaum. A substitution entry that just restates
///     the same room is *not* a room change.
LessonOverlay? matchOverlayForHour({
  required int stunde,
  required String fach,
  required String? originalRaum,
  required List<Substitution> substitutions,
}) {
  Substitution? match;
  for (final s in substitutions) {
    if (s.stunde == '$stunde' && s.fach == fach) {
      match = s;
      break;
    }
  }
  if (match == null) return null;

  final isEva = match.raum == 'EVA' || match.hinweis == 'EVA';
  final vertreter = (match.vertreter != null && match.vertreter!.isNotEmpty)
      ? match.vertreter
      : null;

  String? substituteRaum;
  if (!isEva &&
      match.raum != null &&
      match.raum!.isNotEmpty &&
      match.raum != originalRaum) {
    substituteRaum = match.raum;
  }

  final hinweis = (match.hinweis != null && match.hinweis!.isNotEmpty)
      ? match.hinweis
      : null;

  return LessonOverlay(
    vertreter: vertreter,
    substituteRaum: substituteRaum,
    isEva: isEva,
    hinweis: hinweis,
  );
}

/// End-to-end pipeline for a single day (feature plan 7.1 steps 1–3 /
/// 7.2): decompose both inputs, match substitutions onto decomposed
/// hours, then re-merge consecutive identical hours back into visual
/// blocks via [mergeConsecutiveHours].
///
/// [subjects] and [substitutions] should already be scoped to the same
/// single day — this function does no date filtering itself.
List<MergedLessonBlock> buildDisplayBlocksForDay({
  required List<TimetableSubject> subjects,
  required List<Substitution> substitutions,
}) {
  final decomposedSubjects = decomposeTimetableSubjects(subjects);
  final decomposedSubstitutions = decomposeSubstitutionRanges(substitutions);

  final withOverlay = [
    for (final hour in decomposedSubjects)
      hour.withOverlay(
        matchOverlayForHour(
          stunde: hour.stunde,
          fach: hour.fach,
          originalRaum: hour.raum,
          substitutions: decomposedSubstitutions,
        ),
      ),
  ];

  return mergeConsecutiveHours(withOverlay);
}
