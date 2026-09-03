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

  /// Free-text note from the substitution entry, if any.
  final String? hinweis;

  const LessonOverlay({
    this.vertreter,
    this.substituteRaum,
    this.isEva = false,
    this.hinweis,
  });

  @override
  // ignore: hash_and_equals
  bool operator ==(Object other) {
    if (other is LessonOverlay) {
      return vertreter == other.vertreter &&
          substituteRaum == other.substituteRaum &&
          isEva == other.isEva &&
          hinweis == other.hinweis;
    }
    return false;
  }

  @override
  String toString() =>
      'LessonOverlay(vertreter: $vertreter, substituteRaum: $substituteRaum, '
      'isEva: $isEva, hinweis: $hinweis)';
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

  const DisplayLessonHour({
    required this.stunde,
    required this.fach,
    this.lehrer,
    this.raum,
    this.overlay,
  });

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

  const MergedLessonBlock({
    required this.stunden,
    required this.fach,
    this.lehrer,
    this.raum,
    this.overlay,
  });

  int get startStunde => stunden.first;
  int get endStunde => stunden.last;

  /// Whether this block is the result of an actual merge (`true`) or is
  /// just a single, unmerged hour (`false`).
  bool get isMerged => stunden.length > 1;

  @override
  String toString() =>
      'MergedLessonBlock(stunden: $stunden, fach: $fach, lehrer: $lehrer, '
      'raum: $raum, overlay: $overlay)';
}
