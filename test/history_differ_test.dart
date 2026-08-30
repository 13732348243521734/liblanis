import 'package:liblanis/liblanis.dart';
import 'package:test/test.dart';

class _InMemorySnapshotStore implements SnapshotStore<String> {
  final Map<int, String> _byAccount = {};
  final List<String> savedInOrder = [];

  @override
  String? loadLast(int accountId) => _byAccount[accountId];

  @override
  void save(int accountId, String snapshot, DateTime capturedAt) {
    _byAccount[accountId] = snapshot;
    savedInOrder.add(snapshot);
  }
}

void main() {
  group('HistoryDiffer', () {
    late _InMemorySnapshotStore store;
    late HistoryDiffer<String> differ;

    setUp(() {
      store = _InMemorySnapshotStore();
      differ = HistoryDiffer<String>(store);
    });

    test('previous == null -> diff returns null, snapshot is still saved', () {
      String? seenPrevious = 'not called';
      final result = differ.process<String>(1, 'A', DateTime(2026, 1, 1), (
        previous,
        current,
      ) {
        seenPrevious = previous;
        return null;
      });

      expect(result, isNull);
      expect(seenPrevious, isNull);
      expect(store.loadLast(1), 'A');
      expect(store.savedInOrder, ['A']);
    });

    test('previous == A, current == A -> diff returns null, A saved again', () {
      differ.process<String>(1, 'A', DateTime(2026, 1, 1), (p, c) => null);

      final result = differ.process<String>(1, 'A', DateTime(2026, 1, 2), (
        previous,
        current,
      ) {
        expect(previous, 'A');
        expect(current, 'A');
        return null;
      });

      expect(result, isNull);
      expect(store.loadLast(1), 'A');
      expect(store.savedInOrder, ['A', 'A']);
    });

    test('previous == A, current == B -> diff returns a result, B is saved', () {
      differ.process<String>(1, 'A', DateTime(2026, 1, 1), (p, c) => null);

      final result = differ.process<String>(1, 'B', DateTime(2026, 1, 2), (
        previous,
        current,
      ) {
        expect(previous, 'A');
        expect(current, 'B');
        return 'changed: $previous -> $current';
      });

      expect(result, 'changed: A -> B');
      expect(store.loadLast(1), 'B');
      expect(store.savedInOrder, ['A', 'B']);
    });

    test('snapshot is always saved even when diff throws nothing but returns null repeatedly', () {
      for (final value in ['A', 'A', 'A']) {
        differ.process<void>(1, value, DateTime(2026, 1, 1), (p, c) => null);
      }
      expect(store.savedInOrder, ['A', 'A', 'A']);
    });

    test('different accounts are diffed independently', () {
      differ.process<String>(1, 'A', DateTime(2026, 1, 1), (p, c) => null);
      differ.process<String>(2, 'X', DateTime(2026, 1, 1), (p, c) => null);

      final resultAccount2 = differ.process<String>(
        2,
        'Y',
        DateTime(2026, 1, 2),
        (previous, current) {
          expect(previous, 'X');
          return 'account2 changed';
        },
      );

      expect(resultAccount2, 'account2 changed');
      expect(store.loadLast(1), 'A');
      expect(store.loadLast(2), 'Y');
    });
  });
}
