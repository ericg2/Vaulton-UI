enum TKind { upload, download }

enum TState { queued, running, done, failed, canceled }

class TransferTask {
  TransferTask({
    required this.id,
    required this.kind,
    required this.pointId,
    required this.remotePath,
    required this.name,
    this.localPath,
    this.total = 0,
    this.done = 0,
    this.state = TState.queued,
    this.error,
    this.origin = 'manual',
    this.snapshotId,
    this.overwrite = false,
    this.attempts = 0,
    DateTime? createdAt,
    this.completedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final TKind kind;
  /// For snapshot downloads [pointId] holds the backup vault id and [snapshotId] the snapshot.
  final String pointId, remotePath, name, origin;
  final String? snapshotId;
  final String? localPath;
  final DateTime createdAt;
  DateTime? completedAt;
  int total, done, attempts;
  TState state;
  String? error;
  bool overwrite;

  bool get active => state == TState.queued || state == TState.running;
  double? get fraction => total > 0 ? (done / total).clamp(0, 1).toDouble() : null;

  Map<String, dynamic> toJson() => {
        'id': id, 'kind': kind.name, 'pointId': pointId, 'remotePath': remotePath, 'name': name,
        'localPath': localPath, 'total': total, 'done': done, 'state': state.name, 'error': error,
        'origin': origin, 'snapshotId': snapshotId, 'overwrite': overwrite, 'attempts': attempts, 'createdAt': createdAt.toIso8601String(), 'completedAt': completedAt?.toIso8601String(),
      };

  factory TransferTask.fromJson(Map<String, dynamic> j) => TransferTask(
        id: j['id'],
        kind: TKind.values.byName(j['kind']),
        pointId: j['pointId'],
        remotePath: j['remotePath'],
        name: j['name'],
        localPath: j['localPath'],
        total: j['total'] ?? 0,
        done: j['done'] ?? 0,
        state: TState.values.byName(j['state']),
        error: j['error'],
        origin: j['origin'] ?? 'manual',
        snapshotId: j['snapshotId'],
        overwrite: j['overwrite'] ?? false,
        attempts: j['attempts'] ?? 0,
        createdAt: DateTime.tryParse(j['createdAt'] ?? ''),
        completedAt: DateTime.tryParse(j['completedAt'] ?? ''),
      );
}
