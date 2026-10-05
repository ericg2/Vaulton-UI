import 'package:flutter_test/flutter_test.dart';
import 'package:vaulton/core/models.dart';
import 'package:vaulton/core/util.dart';

void main() {
  test('fmtBytes', () {
    expect(fmtBytes(512), '512 B');
    expect(fmtBytes(1024), '1.00 KB');
    expect(fmtBytes(5 * 1024 * 1024), '5.00 MB');
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
