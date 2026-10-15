import 'package:flutter_test/flutter_test.dart';
import 'package:vaulton/features/sync/sync_service.dart';
import 'package:vaulton/features/sync/sync_source.dart';

// Pins the plan arithmetic the Review Sync dialog and progress bar rely on:
// which changes upload, which delete, and how the byte totals add up.
void main() {
  SyncPlan planOf(List<SyncChange> changes) => SyncPlan(
    changes,
    sourceFiles: 4,
    destinationFiles: 3,
    sourceEntries: const [],
  );

  group('SyncPlan', () {
    test('splits uploads, deletes and directory creates', () {
      final plan = planOf(const [
        SyncChange(kind: SyncChangeKind.add, path: 'new.txt', bytes: 10),
        SyncChange(kind: SyncChangeKind.update, path: 'edit.txt', bytes: 20),
        SyncChange(kind: SyncChangeKind.mkdir, path: 'sub', bytes: 0),
        SyncChange(kind: SyncChangeKind.delete, path: 'old.txt', bytes: 30),
      ]);

      expect(plan.uploads.map((x) => x.path), ['new.txt', 'edit.txt']);
      expect(plan.deletes.map((x) => x.path), ['old.txt']);
      expect(plan.directories.map((x) => x.path), ['sub']);
      expect(plan.newFiles, 1);
      expect(plan.updatedFiles, 1);
      expect(plan.deletedFiles, 1);
      expect(plan.uploadBytes, 30);
      expect(plan.deleteBytes, 30);
    });

    test('empty plan uploads and deletes nothing', () {
      final plan = planOf(const []);

      expect(plan.uploads, isEmpty);
      expect(plan.deletes, isEmpty);
      expect(plan.directories, isEmpty);
      expect(plan.uploadBytes, 0);
      expect(plan.deleteBytes, 0);
      expect(plan.newFiles, 0);
      expect(plan.updatedFiles, 0);
      expect(plan.deletedFiles, 0);
    });

    test('replace of a file counts as an upload, replace of a folder as a directory', () {
      final plan = planOf([
        SyncChange(
          kind: SyncChangeKind.replace,
          path: 'file.txt',
          bytes: 5,
          source: SyncSourceEntry(
            relative: 'file.txt',
            size: 5,
            modified: DateTime(2026),
            isDir: false,
            location: '/src/file.txt',
          ),
        ),
        SyncChange(
          kind: SyncChangeKind.replace,
          path: 'new-dir',
          bytes: 0,
          source: SyncSourceEntry(
            relative: 'new-dir',
            size: 0,
            modified: DateTime(2026),
            isDir: true,
            location: '/src/new-dir',
          ),
        ),
      ]);

      expect(plan.uploads.map((x) => x.path), contains('file.txt'));
      expect(plan.directories.map((x) => x.path), contains('new-dir'));
      expect(plan.deletes, isEmpty);
    });
  });
}
