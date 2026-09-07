import 'timetable.dart';

/// The substitution-driven overlay resolved for a single decomposed
/// timetable hour (feature plan 7.2 matching + 7.3 display rules).
///
/// Produced by the substitution-matching step (7.2 — not yet
/// implemented); this model is [mergeConsecutiveHours]'s expected input
/// shape for an hour's already-resolved overlay, not a matcher itself.
class LessonOverlay {
  /// Substitute teacher, if any (7.3 row 1: original teacher struck
  /// through, substitute shown alongside).
  final String? vertreter;

  /// Substitution room, if it differs from the regular room (7.3 row 3:
  /// old room struck through, new room shown, orange background).
  final String? substituteRaum;

  /// `raum == "EVA"` or `hinweis == "EVA"` on the matched substitution
  /// entry (7.3 row 2). Takes priority when *rendering* a single hour
  /// (a UI-layer concern, not handled here), but still participates in
  /// the merge-equality check below like any other overlay field.
  final bool isEva;

  /// The lesson was cancelled outright ("Entfall"/"entfällt"), detected
  /// heuristically from the matched substitution's `art`/`hinweis` text
  /// -- see [matchOverlayForHour]. This is a best-effort keyword match,
  /// not a confirmed enum from the school portal; verify it actually
  /// fires against real data and adjust the keyword list if not.
  final bool isCancelled;

  /// Free-text note from the substitution entry, if any.
  final String? hinweis;

  const LessonOverlay({
    this.vertreter,
    this.substituteRaum,
    this.isEva = false,
    this.isCancelled = false,
    this.hinweis,
  });

  @override
  // ignore: hash_and_equals
  bool operator ==(Object other) {
    if (other is LessonOverlay) {
      return vertreter == other.vertreter &&
          substituteRaum == other.substituteRaum &&
          isEva == other.isEva &&
          isCancelled == other.isCancelled &&
          hinweis == other.hinweis;
    }
    return false;
  }

  @override
  String toString() =>
      'LessonOverlay(vertreter: $vertreter, substituteRaum: $substituteRaum, '
      'isEva: $isEva, isCancelled: $isCancelled, hinweis: $hinweis)';
}

/// One already-decomposed (single-period) timetable hour, with any
/// matching substitution overlay already resolved.
///
/// This is [mergeConsecutiveHours]'s input shape. Decomposition (splitting
/// double periods / substitution `stunde` ranges like `"3 - 4"` into
/// single hours, plan 7.1 step 1) and substitution matching (plan 7.2)
/// happen upstream and are out of scope for this file — merging only
/// decides which already-resolved single hours visually belong together.
class DisplayLessonHour {
  /// Single hour number after decomposition — never a range.
  final int stunde;
  final String fach;
  final String? lehrer;
  final String? raum;
  final LessonOverlay? overlay;

  /// The originating `TimetableSubject.id` this hour was decomposed from,
  /// if known. Not used by matching or merging (id differences never
  /// prevent a merge) — carried through purely so a consuming app can
  /// preserve id-keyed settings (hidden lessons, custom colors) after
  /// decomposing/re-merging.
  final String? id;

  const DisplayLessonHour({
    required this.stunde,
    required this.fach,
    this.lehrer,
    this.raum,
    this.overlay,
    this.id,
  });

  /// Returns a copy with [overlay] replaced. Used by the matching step
  /// (plan 7.2) to attach a resolved [LessonOverlay] onto an hour that was
  /// decomposed without one.
  DisplayLessonHour withOverlay(LessonOverlay? overlay) => DisplayLessonHour(
    stunde: stunde,
    fach: fach,
    lehrer: lehrer,
    raum: raum,
    overlay: overlay,
    id: id,
  );

  @override
  String toString() =>
      'DisplayLessonHour(stunde: $stunde, fach: $fach, lehrer: $lehrer, '
      'raum: $raum, overlay: $overlay)';
}

/// One or more consecutive [DisplayLessonHour]s re-merged into a single
/// visual block (feature plan 7.1 step 3: "Wieder zusammenführen"),
/// because they were exactly identical (fach/lehrer/raum) and, if a
/// substitution overlay was present, it was consistent across every
/// merged hour.
class MergedLessonBlock {
  /// Consecutive hour numbers making up this block, e.g. `[3, 4]`.
  /// Always non-empty and sorted ascending.
  final List<int> stunden;
  final String fach;
  final String? lehrer;
  final String? raum;
  final LessonOverlay? overlay;

  /// The originating `TimetableSubject.id` of the *first* merged hour, if
  /// known — see [DisplayLessonHour.id]. A real rowspan-based double
  /// period already only ever had one id to begin with, so using the
  /// first hour's id as the block's representative id matches that.
  final String? id;

  const MergedLessonBlock({
    required this.stunden,
    required this.fach,
    this.lehrer,
    this.raum,
    this.overlay,
    this.id,
  });

  int get startStunde => stunden.first;
  int get endStunde => stunden.last;

  /// Alias for [fach], so a [MergedLessonBlock] can be used anywhere a
  /// `TimetableSubject`-shaped `.name`/`.id` pair is expected via duck
  /// typing (e.g. `TimeTableHelper.getColorForLesson`).
  String get name => fach;

  /// Whether this block is the result of an actual merge (`true`) or is
  /// just a single, unmerged hour (`false`).
  bool get isMerged => stunden.length > 1;

  @override
  String toString() =>
      'MergedLessonBlock(stunden: $stunden, fach: $fach, lehrer: $lehrer, '
      'raum: $raum, overlay: $overlay)';
}
