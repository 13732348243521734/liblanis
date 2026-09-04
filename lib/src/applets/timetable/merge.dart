import '../../models/merged_timetable.dart';

/// Re-merges consecutive, already-decomposed single-hour timetable cells
/// back into visual blocks (feature plan 7.1, step 3: "Wieder
/// zusammenführen — erst unmittelbar vor der Anzeige").
///
/// [hours] should already be the output of decomposition + substitution
/// matching for a single day/column (plan 7.1 steps 1–2, 7.2) — one
/// [DisplayLessonHour] per single hour, each with any matching overlay
/// already resolved. This function only decides which of those
/// already-resolved hours visually belong together; it performs no
/// decomposition and no substitution matching itself.
///
/// Merge rule (plan 7.1): two hours merge into one block only if
///   - their `stunde` numbers are directly consecutive, AND
///   - `fach`, `lehrer`, and `raum` are exactly identical, AND
///   - their overlay is exactly identical — both `null`, or equal
///     [LessonOverlay] values.
///
/// The third condition is "falls Vertretungseinträge existieren, diese
/// für beide Stunden konsistent sind": if only one of two otherwise
/// identical hours carries a substitution overlay (the plan's own
/// example: "nur Stunde 3 hat eine Vertretung"), they are **not** merged
/// and stay two separate rows.
///
/// [hours] does not need to be pre-sorted or duplicate-free; this
/// function sorts a copy by `stunde` before merging. A gap in the
/// `stunde` sequence (e.g. 1, 2, 4) ends a run even if every other field
/// still matches. Two entries that (incorrectly) share the same `stunde`
/// number are never merged into each other, since they can't be
/// "directly consecutive" with themselves — parallel lessons at the same
/// hour (e.g. Wahlpflichtkurse) are out of scope here and expected to be
/// handled as separate rows/columns upstream, not by this function.
List<MergedLessonBlock> mergeConsecutiveHours(List<DisplayLessonHour> hours) {
  if (hours.isEmpty) return const [];

  final sorted = [...hours]..sort((a, b) => a.stunde.compareTo(b.stunde));
  final blocks = <MergedLessonBlock>[];

  for (final hour in sorted) {
    final canExtend = blocks.isNotEmpty && _canMerge(blocks.last, hour);
    if (canExtend) {
      final previous = blocks.removeLast();
      blocks.add(
        MergedLessonBlock(
          stunden: [...previous.stunden, hour.stunde],
          fach: previous.fach,
          lehrer: previous.lehrer,
          raum: previous.raum,
          overlay: previous.overlay,
          id: previous.id,
        ),
      );
    } else {
      blocks.add(
        MergedLessonBlock(
          stunden: [hour.stunde],
          fach: hour.fach,
          lehrer: hour.lehrer,
          raum: hour.raum,
          overlay: hour.overlay,
          id: hour.id,
        ),
      );
    }
  }

  return blocks;
}

bool _canMerge(MergedLessonBlock block, DisplayLessonHour next) {
  if (next.stunde != block.endStunde + 1) return false;
  if (block.fach != next.fach) return false;
  if (block.lehrer != next.lehrer) return false;
  if (block.raum != next.raum) return false;
  return block.overlay == next.overlay;
}
