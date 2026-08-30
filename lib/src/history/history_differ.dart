/// Persistence hook used by [HistoryDiffer] to load/save the last snapshot
/// of type [T] for a given account. Deliberately synchronous: the whole DB
/// layer (`LanisDatabase`, `sqlite3` FFI) is synchronous throughout the
/// codebase, so a `Future`-based store here would be an inconsistency
/// rather than future-proofing.
abstract class SnapshotStore<T> {
  T? loadLast(int accountId);
  void save(int accountId, T snapshot, DateTime capturedAt);
}

/// Shared "load last snapshot, diff, save new snapshot" plumbing for
/// history features (substitution history, timetable history). The
/// domain-specific diff logic (matching keys, field comparison, event
/// model) stays with each applet and is passed in as [diff] — this class
/// intentionally does not grow into an over-abstracted callback pile.
class HistoryDiffer<T> {
  final SnapshotStore<T> store;
  HistoryDiffer(this.store);

  /// Lädt den letzten Snapshot, ruft [diff] auf, speichert [current] danach
  /// immer als neuen letzten Stand — unabhängig davon, ob [diff] ein Ergebnis
  /// oder `null` liefert. So vergleicht der nächste Aufruf wieder gegen den
  /// tatsächlich zuletzt gesehenen Snapshot.
  ///
  /// [diff] liefert `null`, wenn es nichts zu berichten gibt: entweder weil
  /// `previous == null` (erster Fetch nach Update/Neuinstallation — bewusst
  /// KEIN Diff-Event beim allerersten Snapshot, sonst entsteht beim Rollout
  /// ein riesiges künstliches "alles ist neu"-Ereignis) oder weil sich
  /// inhaltlich nichts geändert hat.
  R? process<R>(
    int accountId,
    T current,
    DateTime capturedAt,
    R? Function(T? previous, T current) diff,
  ) {
    final previous = store.loadLast(accountId);
    final result = diff(previous, current);
    store.save(accountId, current, capturedAt);
    return result;
  }
}
