import 'package:flutter_test/flutter_test.dart';
import 'package:vaulton/core/api_client.dart';
import 'package:vaulton/core/models.dart';
import 'package:vaulton/core/util.dart';

void main() {
  test('fmtBytes', () {
    expect(fmtBytes(512), '512 B');
    expect(fmtBytes(1024), '1.00 KiB');
    expect(fmtBytes(5 * 1024 * 1024), '5.00 MiB');
  });

  test('storage quota errors are concise and use human-readable units', () {
    const raw = '''
Writing file failed in the backend.
Caused by:
RateLimited (permanent) at , context: { quota_id: point-id, quota_limit: 6979321856, quota_used: 7016140887 } => write quota exceeded for 'point-id': 7016140887 used, 7016140887 would be needed, 6979321856 limit
Backtrace:
disabled backtrace
''';
    expect(
      friendlyStorageError(raw),
      'Storage quota exceeded. Usage: 6.53 GiB of 6.50 GiB. Free up space or increase the configured quota, then retry.',
    );
  });

  test('physical storage exhaustion is actionable', () {
    expect(
      friendlyStorageError('No space left on device while writing file'),
      'The storage backend is out of space. Free up storage capacity, then retry.',
    );
  });

  test('remote path helpers', () {
    expect(joinPath('/', 'a'), '/a');
    expect(joinPath('/a/', '/b'), '/a/b');
    expect(parentPath('/a/b'), '/a');
    expect(parentPath('/a'), '/');
    expect(baseName('/a/b.txt'), 'b.txt');
  });

  test('paged parsing tolerates string numbers', () {
    final p = Paged.from({
      'items': [
        {'name': 'x', 'isDirectory': false, 'bytes': '42'}
      ],
      'nextCursor': 'abc',
      'hasMore': true,
    }, Node.fromJson);
    expect(p.items.single.bytes, 42);
    expect(p.hasMore, true);
  });

  test('job phase', () {
    final j = RepoJob.fromJson({
      'id': '1', 'repoId': '2', 'options': {'mode': 'backup'},
      'startDate': '2026-01-01T00:00:00Z', 'endDate': '2026-01-01T00:01:00Z', 'success': true,
    });
    expect(j.phase, JobPhase.succeeded);
    expect(j.kind, 'backup');
  });

  test('job status comes from the API when present', () {
    final j = RepoJob.fromJson({
      'id': '1', 'repoId': '2', 'options': {'mode': 'check'}, 'kind': 'Check', 'status': 'Failed',
      'startDate': '2026-01-01T00:00:00Z', 'endDate': '2026-01-01T00:01:00Z', 'success': false, 'error': 'boom',
    });
    expect(j.phase, JobPhase.failed);
    expect(j.kind, 'check');
    expect(j.duration, const Duration(minutes: 1));
  });

  test('browse entries use the server path, else fall back to parent/name', () {
    expect(Node.fromJson({'name': 'a', 'isDirectory': true, 'path': '/data/a'}).pathIn('/data'), '/data/a');
    final n = Node.fromJson({'name': 'b.txt', 'isDirectory': false});
    expect(n.pathIn(null), '/b.txt');
    expect(n.pathIn('/data'), '/data/b.txt');
    expect(n.pathIn('/'), '/b.txt');
  });

  test('stage fraction', () {
    expect(JobStage.fromJson({'barId': 'x', 'progress': 5, 'length': 10, 'isFinished': false}).fraction, 0.5);
    expect(JobStage.fromJson({'barId': 'x', 'progress': 0, 'isFinished': true}).fraction, 1);
  });
}
