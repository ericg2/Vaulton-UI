import 'package:flutter_test/flutter_test.dart';
import 'package:vaulton/features/transfers/transfer_manager.dart';
import 'package:vaulton/features/transfers/transfer_models.dart';

// The transfer queue persists across restarts: only unfinished work (or work
// finished in the last week) is kept, and corrupt stores must not crash app
// startup. These pin the encode/decode contract the manager relies on.
void main() {
  TransferTask task(
    String id, {
    TKind kind = TKind.upload,
    TState state = TState.queued,
    DateTime? createdAt,
  }) => TransferTask(
    id: id,
    kind: kind,
    pointId: 'p1',
    remotePath: '/$id',
    name: id,
    total: 100,
    done: 40,
    state: state,
    createdAt: createdAt,
  );

  group('TransferTask', () {
    test('fraction and activity reflect progress and state', () {
      final running = task('a', state: TState.running);
      expect(running.active, isTrue);
      expect(running.fraction, 0.4);

      final done = task('b', state: TState.done);
      expect(done.active, isFalse);

      final unknown = TransferTask(
        id: 'c',
        kind: TKind.download,
        pointId: 'p1',
        remotePath: '/c',
        name: 'c',
      );
      expect(unknown.fraction, isNull);
      expect(unknown.active, isTrue);
    });

    test('round trips through JSON', () {
      final restored = TransferTask.fromJson(
        task('a', state: TState.failed).toJson(),
      );

      expect(restored.id, 'a');
      expect(restored.state, TState.failed);
      expect(restored.done, 40);
    });
  });

  group('queue persistence', () {
    test('keeps active work and drops week-old finished work', () {
      final old = DateTime.now().subtract(const Duration(days: 8));
      final encoded = encodeQueue([
        task('active', state: TState.running),
        task('recent', state: TState.done),
        task('stale', state: TState.done, createdAt: old),
      ]);

      final ids = decodeQueue(encoded).map((t) => t.id);
      expect(ids, containsAll(['active', 'recent']));
      expect(ids, isNot(contains('stale')));
    });

    test('decodes corrupt or missing stores as empty', () {
      expect(decodeQueue(null), isEmpty);
      expect(decodeQueue('not json'), isEmpty);
      expect(decodeQueue('{"not":"a list"}'), isEmpty);
      expect(decodeQueue('[{"id":1}]'), isEmpty);
    });
  });
}
