typedef Json = Map<String, dynamic>;

int toInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
String? toStr(dynamic v) => v == null ? null : '$v';
DateTime? toDate(dynamic v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();
bool toBool(dynamic v) => v == true || v == 'true';
List<String> toStrList(dynamic v) => v is List ? v.map((e) => '$e').toList() : <String>[];
Json toJson(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

class Paged<T> {
  Paged(this.items, this.nextCursor, this.hasMore);
  final List<T> items;
  final String? nextCursor;
  final bool hasMore;
  factory Paged.from(dynamic data, T Function(Json) f) {
    final m = toJson(data);
    final items = (m['items'] as List? ?? []).map((e) => f(toJson(e))).toList();
    final next = toStr(m['nextCursor']);
    return Paged(items, next, toBool(m['hasMore']) && next != null);
  }
}

class Node {
  Node({required this.name, required this.isDir, required this.bytes, this.modified, this.created, this.path});
  final String name;
  final bool isDir;
  final int bytes;
  final DateTime? modified;
  final DateTime? created;

  /// Full path inside a snapshot, as returned by the browse endpoint (when the server supplies it).
  final String? path;

  /// The path to pass back to the server for this entry. Prefers the server-provided path.
  String pathIn(String? parent) {
    if (path != null && path!.isNotEmpty) return path!;
    final base = (parent == null || parent == '/') ? '' : (parent.endsWith('/') ? parent.substring(0, parent.length - 1) : parent);
    return '$base/$name';
  }

  factory Node.fromJson(Json j) => Node(
        name: '${j['name']}',
        isDir: toBool(j['isDirectory']),
        bytes: toInt(j['bytes']),
        modified: toDate(j['modifiedAt']),
        created: toDate(j['createdAt']),
        path: toStr(j['path']),
      );
}

class Point {
  Point({required this.id, required this.rootId, required this.name, required this.maxBytes, required this.usedBytes,
      required this.isReady, required this.isError, this.error, this.createdAt, this.health});
  final String id, rootId, name;
  final int maxBytes, usedBytes;
  final bool isReady, isError;
  final String? error, health;
  final DateTime? createdAt;
  String get healthLabel => isError ? 'Error' : (isReady ? 'Ready' : (health ?? 'Unknown'));
  factory Point.fromJson(Json j) => Point(
        id: '${j['id']}',
        rootId: '${j['rootId']}',
        name: '${j['name']}',
        maxBytes: toInt(j['maxBytes']),
        usedBytes: toInt(j['usedBytes']),
        isReady: toBool(j['isReady']),
        isError: toBool(j['isError']),
        error: toStr(j['error']),
        createdAt: toDate(j['createdAt']),
        health: j['health'] is String ? j['health'] : null,
      );
}

class Root {
  Root({required this.id, required this.name, required this.userName, this.source, required this.maxBytes,
      required this.allocatedBytes, required this.freeBytes, required this.isDataAllowed, required this.isRepoAllowed, required this.isOwner});
  final String id, name, userName;
  final Json? source;
  final int maxBytes, allocatedBytes, freeBytes;
  final bool isDataAllowed, isRepoAllowed, isOwner;
  factory Root.fromJson(Json j) => Root(
        id: '${j['id']}',
        name: '${j['name']}',
        userName: '${j['userName']}',
        source: j['source'] is Map ? toJson(j['source']) : null,
        maxBytes: toInt(j['maxBytes']),
        allocatedBytes: j['allocatedBytes'] == null
            ? (toInt(j['maxBytes']) - toInt(j['freeBytes'])).clamp(0, 1 << 62).toInt()
            : toInt(j['allocatedBytes']),
        freeBytes: toInt(j['freeBytes']),
        isDataAllowed: toBool(j['isDataAllowed']),
        isRepoAllowed: toBool(j['isRepoAllowed']),
        isOwner: toBool(j['isOwner']),
      );
}

enum JobPhase { waiting, running, succeeded, failed, cancelled }

class JobStage {
  JobStage(this.title, this.length, this.progress, this.finished, this.percent);
  final String title;
  final int? length;
  final int progress;
  final bool finished;
  final double? percent;
  double? get fraction {
    if (finished) return 1;
    if (percent != null) return percent!.clamp(0, 1).toDouble();
    return (length != null && length! > 0) ? (progress / length!).clamp(0, 1).toDouble() : null;
  }

  factory JobStage.fromJson(Json j) => JobStage(
        toStr(j['title']) ?? toStr(j['barId']) ?? 'Stage',
        j['length'] == null ? null : toInt(j['length']),
        toInt(j['progress']),
        toBool(j['isFinished']),
        j['percent'] == null ? null : (j['percent'] is num ? (j['percent'] as num).toDouble() : double.tryParse('${j['percent']}')),
      );
}

class JobMessage {
  JobMessage(this.id, this.time, this.priority, this.message);
  final String id;
  final DateTime? time;
  final String priority, message;
  factory JobMessage.fromJson(Json j) =>
      JobMessage('${j['id'] ?? '${j['time']}${j['message']}'}', toDate(j['time']), '${j['priority']}', '${j['message']}');
}

class RepoJob {
  RepoJob({required this.id, required this.repoId, this.dataId, this.scheduleId, required this.options,
      this.kindRaw, this.statusRaw, this.createdAt, this.scheduleDate, this.startDate, this.endDate, this.success,
      this.error, this.snapshotId, required this.stages, required this.messages, this.live});
  final String id, repoId;
  final String? dataId, scheduleId, error, snapshotId, kindRaw, statusRaw;
  final Json options;
  final DateTime? createdAt, scheduleDate, startDate, endDate;
  final bool? success;
  final List<JobStage> stages;
  final List<JobMessage> messages;
  final Json? live;

  /// Lower-case job kind: backup | restore | check | forget | retention.
  String get kind {
    final k = kindRaw;
    if (k != null && k.isNotEmpty && int.tryParse(k) == null) return k.toLowerCase();
    return (toStr(options['mode']) ?? 'job').toLowerCase();
  }

  bool get active => phase == JobPhase.waiting || phase == JobPhase.running;
  int get liveDone => live == null ? 0 : toInt(live!['doneBytes']);
  int get liveTotal => live == null ? 0 : toInt(live!['totalBytes']);
  double? get liveFraction => liveTotal > 0 ? (liveDone / liveTotal).clamp(0, 1).toDouble() : null;
  Duration? get duration => startDate == null ? null : (endDate ?? DateTime.now()).difference(startDate!);

  JobPhase get phase {
    switch ((statusRaw ?? '').toLowerCase()) {
      case 'pending':
        return JobPhase.waiting;
      case 'running':
        return JobPhase.running;
      case 'succeeded':
        return JobPhase.succeeded;
      case 'failed':
        return JobPhase.failed;
      case 'cancelled':
      case 'canceled':
        return JobPhase.cancelled;
    }
    if (endDate == null) return startDate == null ? JobPhase.waiting : JobPhase.running;
    if (success == true) return JobPhase.succeeded;
    if ((error ?? '').toLowerCase().contains('cancel')) return JobPhase.cancelled;
    return JobPhase.failed;
  }

  factory RepoJob.fromJson(Json j) => RepoJob(
        id: '${j['id']}',
        repoId: '${j['repoId']}',
        dataId: toStr(j['dataId']),
        scheduleId: toStr(j['scheduleId']),
        options: toJson(j['options']),
        kindRaw: toStr(j['kind']),
        statusRaw: toStr(j['status']),
        createdAt: toDate(j['createdAt']),
        scheduleDate: toDate(j['scheduleDate']),
        startDate: toDate(j['startDate']),
        endDate: toDate(j['endDate']),
        success: j['success'] as bool?,
        error: toStr(j['error']),
        snapshotId: toStr(j['snapshotId']),
        stages: (j['stages'] as List? ?? []).map((e) => JobStage.fromJson(toJson(e))).toList(),
        messages: (j['messages'] as List? ?? []).map((e) => JobMessage.fromJson(toJson(e))).toList(),
        live: j['live'] is Map ? toJson(j['live']) : null,
      );
}

class Schedule {
  Schedule({required this.id, required this.name, required this.repoId, this.dataId, required this.options,
      required this.cron, required this.timeZone, required this.enabled, required this.skipIfRunning,
      this.nextRunAt, this.lastRunAt, this.lastJobId, this.lastError, required this.runCount});
  final String id, name, repoId, cron, timeZone;
  final String? dataId, lastJobId, lastError;
  final Json options;
  final bool enabled, skipIfRunning;
  final DateTime? nextRunAt, lastRunAt;
  final int runCount;
  String get mode => toStr(options['mode']) ?? '';
  factory Schedule.fromJson(Json j) => Schedule(
        id: '${j['id']}',
        name: '${j['name']}',
        repoId: '${j['repoId']}',
        dataId: toStr(j['dataId']),
        options: toJson(j['options']),
        cron: '${j['cron']}',
        timeZone: '${j['timeZone'] ?? ''}',
        enabled: toBool(j['enabled']),
        skipIfRunning: toBool(j['skipIfRunning']),
        nextRunAt: toDate(j['nextRunAt']),
        lastRunAt: toDate(j['lastRunAt']),
        lastJobId: toStr(j['lastJobId']),
        lastError: toStr(j['lastError']),
        runCount: toInt(j['runCount']),
      );
}

class UserAccount {
  UserAccount({required this.id, required this.userName, this.firstName, this.lastName, this.email, this.lastLogin,
      required this.scopes, required this.mustChangePassword, required this.isLockedOut, required this.emailNotifications});
  final String id, userName;
  final String? firstName, lastName, email;
  final DateTime? lastLogin;
  final List<String> scopes;
  final bool mustChangePassword, isLockedOut, emailNotifications;
  String get displayName {
    final n = [firstName, lastName].whereType<String>().where((s) => s.isNotEmpty).join(' ');
    return n.isEmpty ? userName : n;
  }
  bool has(String scope) => scopes.contains(scope);
  bool hasAny(Iterable<String> s) => s.any(scopes.contains);
  factory UserAccount.fromJson(Json j) => UserAccount(
        id: '${j['id']}',
        userName: '${j['userName']}',
        firstName: toStr(j['firstName']),
        lastName: toStr(j['lastName']),
        email: toStr(j['emailAddress']),
        lastLogin: toDate(j['lastLogin']),
        scopes: toStrList(j['scopes']),
        mustChangePassword: toBool(j['mustChangePassword']),
        isLockedOut: toBool(j['isLockedOut']),
        emailNotifications: toBool(j['emailNotifications']),
      );
}

class Msg {
  Msg({required this.id, required this.sender, required this.recipient, required this.subject, required this.preview,
      this.body, required this.isSystem, this.replyToId, this.createdAt, required this.isRead});
  final String id, sender, recipient, subject, preview;
  final String? body, replyToId;
  final bool isSystem, isRead;
  final DateTime? createdAt;
  factory Msg.fromJson(Json j) => Msg(
        id: '${j['id']}',
        sender: '${j['sender']}',
        recipient: '${j['recipient']}',
        subject: '${j['subject']}',
        preview: '${j['preview'] ?? ''}',
        body: toStr(j['body']),
        isSystem: toBool(j['isSystem']),
        replyToId: toStr(j['replyToId']),
        createdAt: toDate(j['createdAt']),
        isRead: toBool(j['isRead']),
      );
}

class Snapshot {
  Snapshot({required this.id, this.time, required this.tags, required this.paths, required this.locked, this.summary});
  final String id;
  final DateTime? time;
  final List<String> tags, paths;
  final bool locked;
  final Json? summary;
  factory Snapshot.fromJson(Json j) => Snapshot(
        id: '${j['id']}',
        time: toDate(j['time']),
        tags: toStrList(j['tags']),
        paths: toStrList(j['paths']),
        locked: toBool(j['locked']),
        summary: j['summary'] is Map ? toJson(j['summary']) : null,
      );
}
