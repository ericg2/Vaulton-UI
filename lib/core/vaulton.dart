import 'package:dio/dio.dart';
import 'api_client.dart';
import 'models.dart';
import 'session.dart';

String _e(String s) => Uri.encodeComponent(s);

/// Typed wrapper around every endpoint of the Vaulton API.
class Vaulton {
  Vaulton(this.api);
  final ApiClient api;
  Dio get _d => api.dio;

  Future<dynamic> _req(String method, String path,
      {Map<String, dynamic>? q, Object? body, bool noAuth = false}) async {
    try {
      final query = <String, dynamic>{};
      q?.forEach((k, v) {
        if (v != null && !(v is String && v.isEmpty)) query[k] = v;
      });
      final r = await _d.request(path,
          data: body,
          queryParameters: query,
          options: Options(method: method, extra: {if (noAuth) 'noAuth': true}));
      return r.data;
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  /// The API expects `Asc` / `Desc`.
  static String? _ord(String? o) => (o == null || o.isEmpty) ? null : '${o[0].toUpperCase()}${o.substring(1).toLowerCase()}';

  Map<String, dynamic> _pg(String? cursor, int limit, String? order, [Map<String, dynamic>? more]) =>
      {'cursor': cursor, 'limit': limit.clamp(1, 200), 'order': _ord(order), ...?more};

  // ---------------------------------------------------------------- auth
  Future<AuthTokens> signIn(String user, String pass, {String? newPassword}) async {
    final d = await _req('POST', '/auth/token',
        body: {'username': user, 'password': pass, if (newPassword != null && newPassword.isNotEmpty) 'newPassword': newPassword},
        noAuth: true);
    return AuthTokens.fromJson(toJson(d));
  }

  Future<void> signOut() async {
    final rt = api.session.refreshToken;
    if (rt == null) return;
    try {
      await _req('POST', '/auth/logout', body: {'refreshToken': rt}, noAuth: true);
    } catch (_) {}
  }

  Future<void> logoutAll() => _req('POST', '/auth/logout-all');

  Future<AuthTokens> changePassword(String current, String next) async {
    final d = await _req('POST', '/auth/change-password', body: {'currentPassword': current, 'newPassword': next});
    return AuthTokens.fromJson(toJson(d));
  }

  // --------------------------------------------------------------- users
  Future<UserAccount> me() async => UserAccount.fromJson(toJson(await _req('GET', '/users/me')));
  Future<List<({String name, String description})>> scopes() async {
    final d = await _req('GET', '/users/scopes') as List;
    return d.map((e) => (name: '${e['name']}', description: '${e['description']}')).toList();
  }

  Future<Paged<UserAccount>> users({String? search, String? scope, bool? locked, bool? mustChange, String? cursor, int limit = 50}) async =>
      Paged.from(await _req('GET', '/users', q: _pg(cursor, limit, null, {'search': search, 'scope': scope, 'isLockedOut': locked, 'mustChangePassword': mustChange})), UserAccount.fromJson);
  Future<UserAccount> user(String n) async => UserAccount.fromJson(toJson(await _req('GET', '/users/${_e(n)}')));
  Future<Json> addUser(Json body) async => toJson(await _req('POST', '/users', body: body));
  Future<UserAccount> patchUser(String n, Json body) async => UserAccount.fromJson(toJson(await _req('PATCH', '/users/${_e(n)}', body: body)));
  Future<void> deleteUser(String n) => _req('DELETE', '/users/${_e(n)}');
  Future<UserAccount> setScopes(String n, List<String> s) async => UserAccount.fromJson(toJson(await _req('PUT', '/users/${_e(n)}/scopes', body: {'scopes': s})));
  Future<void> lockUser(String n) => _req('POST', '/users/${_e(n)}/lock');
  Future<void> unlockUser(String n) => _req('POST', '/users/${_e(n)}/unlock');
  Future<Json> resetPassword(String n, {bool sendEmail = false}) async => toJson(await _req('POST', '/users/${_e(n)}/reset-password', q: {'sendEmail': sendEmail}));
  Future<void> revokeSessions(String n) => _req('POST', '/users/${_e(n)}/revoke-sessions');

  // --------------------------------------------------------------- roots
  Future<Paged<Root>> roots({String? search, String? cursor, int limit = 50}) async =>
      Paged.from(await _req('GET', '/roots', q: _pg(cursor, limit, null, {'search': search})), Root.fromJson);
  Future<Root> root(String id) async => Root.fromJson(toJson(await _req('GET', '/roots/$id')));
  Future<Root> createRoot(Json body) async => Root.fromJson(toJson(await _req('POST', '/roots', body: body)));
  Future<Root> patchRoot(String id, Json body) async => Root.fromJson(toJson(await _req('PATCH', '/roots/$id', body: body)));
  Future<void> deleteRoot(String id) => _req('DELETE', '/roots/$id');
  Future<List<Json>> shares(String id) async => (await _req('GET', '/roots/$id/shares') as List).map(toJson).toList();
  Future<List<Json>> setShares(String id, List<Json> s) async => (await _req('PUT', '/roots/$id/shares', body: s) as List).map(toJson).toList();

  // -------------------------------------------------------- data / repos
  Future<Paged<Point>> datas({String? rootId, String? search, String? cursor, int limit = 100}) async =>
      Paged.from(await _req('GET', '/datas', q: _pg(cursor, limit, null, {'rootId': rootId, 'search': search})), Point.fromJson);
  Future<Point> createData(Json body) async => Point.fromJson(toJson(await _req('POST', '/datas', body: body)));
  Future<Point> patchData(String id, Json body) async => Point.fromJson(toJson(await _req('PATCH', '/datas/$id', body: body)));
  Future<void> deleteData(String id) => _req('DELETE', '/datas/$id');

  Future<Paged<Point>> repos({String? rootId, String? search, String? cursor, int limit = 100}) async =>
      Paged.from(await _req('GET', '/repos', q: _pg(cursor, limit, null, {'rootId': rootId, 'search': search})), Point.fromJson);
  Future<Point> repo(String id) async => Point.fromJson(toJson(await _req('GET', '/repos/$id')));
  Future<Point> createRepo(Json body) async => Point.fromJson(toJson(await _req('POST', '/repos', body: body)));
  Future<Point> patchRepo(String id, Json body) async => Point.fromJson(toJson(await _req('PATCH', '/repos/$id', body: body)));
  Future<void> deleteRepo(String id) => _req('DELETE', '/repos/$id');
  Future<Point> changeRepoPassword(String id, String cur, String next) async =>
      Point.fromJson(toJson(await _req('PUT', '/repos/$id/password', body: {'currentPassword': cur, 'newPassword': next})));
  Future<Paged<Snapshot>> snapshots(String id, {String? tag, String? path, bool? locked, String? idPrefix, String? cursor, int limit = 50}) async =>
      Paged.from(await _req('GET', '/repos/$id/snapshots', q: _pg(cursor, limit, 'Desc', {'tag': tag, 'path': path, 'locked': locked, 'idPrefix': idPrefix})), Snapshot.fromJson);

  Future<Paged<Node>> browseSnapshot(String id, String snap, {String? path, String? search, String? cursor, int limit = 100, String order = 'Asc'}) async =>
      Paged.from(
        await _req('GET', '/repos/$id/snapshots/${_e(snap)}/browse',
            q: _pg(cursor, limit, order, {'path': path, 'search': search})),
        Node.fromJson,
      );

  Future<Json> lockSnapshot(String id, String snap, bool lock) async =>
      toJson(await _req('POST', '/repos/$id/snapshots/${_e(snap)}/${lock ? 'lock' : 'unlock'}'));

  /// Finds the most recent job associated with a snapshot.
  /// Checks both the job's direct snapshot ID and its options for compatibility with older jobs.
  Future<RepoJob?> snapshotJob(String repoId, String snapshotId) async {
    String? cursor;
    do {
      final page = await jobs(repoId: repoId, cursor: cursor, limit: 100, order: 'Desc');
      for (final job in page.items) {
        if (job.snapshotId == snapshotId || job.options['snapshotId'] == snapshotId) return job;
      }
      cursor = page.hasMore ? page.nextCursor : null;
    } while (cursor != null);
    return null;
  }

  Future<RepoJob> backup(String repoId, Json body, {DateTime? runAt}) async =>
      RepoJob.fromJson(toJson(await _req('POST', '/repos/$repoId/backup', body: body, q: {'runAt': runAt?.toUtc().toIso8601String()})));
  Future<RepoJob> restore(String repoId, Json body, {DateTime? runAt}) async =>
      RepoJob.fromJson(toJson(await _req('POST', '/repos/$repoId/restore', body: body, q: {'runAt': runAt?.toUtc().toIso8601String()})));
  Future<RepoJob> check(String repoId, {DateTime? runAt}) async =>
      RepoJob.fromJson(toJson(await _req('POST', '/repos/$repoId/check', q: {'runAt': runAt?.toUtc().toIso8601String()})));
  Future<RepoJob> forget(String repoId, List<String> snaps) async =>
      RepoJob.fromJson(toJson(await _req('POST', '/repos/$repoId/forget', body: {'snapshots': snaps})));

  Future<RepoJob> retention(String repoId, Json policy, {bool dryRun = false}) async =>
      RepoJob.fromJson(toJson(await _req('POST', '/repos/$repoId/retention', body: {'policy': policy, 'dryRun': dryRun})));

  // ----------------------------------------------------------- schedules
  Future<Paged<Schedule>> schedules({String? repoId, bool? enabled, String? search, String? cursor, int limit = 50}) async =>
      Paged.from(await _req('GET', '/schedules', q: _pg(cursor, limit, null, {'repoId': repoId, 'enabled': enabled, 'search': search})), Schedule.fromJson);
  Future<Schedule> createSchedule(Json body) async => Schedule.fromJson(toJson(await _req('POST', '/schedules', body: body)));
  Future<Schedule> patchSchedule(String id, Json body) async => Schedule.fromJson(toJson(await _req('PATCH', '/schedules/$id', body: body)));
  Future<void> deleteSchedule(String id) => _req('DELETE', '/schedules/$id');
  Future<RepoJob> runSchedule(String id) async => RepoJob.fromJson(toJson(await _req('POST', '/schedules/$id/run')));
  Future<List<DateTime>> previewCron(String cron, {String? tz, int count = 5}) async {
    final d = toJson(await _req('GET', '/schedules/preview', q: {'cron': cron, 'timeZone': tz, 'count': count}));
    return (d['occurrences'] as List? ?? []).map((e) => toDate(e)).whereType<DateTime>().toList();
  }

  // ---------------------------------------------------------------- jobs
  /// [kind]: Backup|Restore|Check|Forget|Retention. [status]: Pending|Running|Succeeded|Failed|Cancelled.
  Future<Paged<RepoJob>> jobs({String? repoId, String? dataId, String? kind, String? status, String? cursor, int limit = 50,
      String order = 'Desc', bool admin = false, String? userName}) async {
    final path = admin ? '/admin/jobs' : (repoId != null ? '/repos/$repoId/jobs' : '/jobs');
    final q = _pg(cursor, limit, order, {
      if (repoId != null && admin) 'repoId': repoId,
      'dataId': dataId, 'kind': kind, 'status': status, if (admin) 'userName': userName,
    });
    return Paged.from(await _req('GET', path, q: q), RepoJob.fromJson);
  }

  Future<RepoJob> job(String id, {bool admin = false}) async => RepoJob.fromJson(toJson(await _req('GET', admin ? '/admin/jobs/$id' : '/jobs/$id')));
  Future<void> deleteJob(String id) => _req('DELETE', '/jobs/$id');
  Future<void> cancelJob(String id, {bool admin = false}) => _req('POST', admin ? '/admin/jobs/$id/cancel' : '/jobs/$id/cancel');
  Future<Paged<JobMessage>> jobMessages(String id, {String? search, String? cursor, int limit = 100, String order = 'Asc'}) async =>
      Paged.from(await _req('GET', '/jobs/$id/messages', q: _pg(cursor, limit, order, {'search': search})), JobMessage.fromJson);

  // --------------------------------------------------------------- files
  Future<Paged<Node>> list(String pointId, String path, {String? search, String type = 'All', String? cursor, int limit = 100, String order = 'Asc'}) async =>
      Paged.from(await _req('GET', '/files/$pointId/list', q: _pg(cursor, limit, order, {'path': path, 'search': search, 'type': type == 'All' ? null : type})), Node.fromJson);
  Future<Node> metadata(String pointId, String path) async => Node.fromJson(toJson(await _req('GET', '/files/$pointId/metadata', q: {'path': path})));
  Future<void> mkdir(String pointId, String path) => _req('POST', '/files/$pointId/directories', body: {'path': path});
  Future<void> deleteEntry(String pointId, String path) => _req('DELETE', '/files/$pointId/entry', q: {'path': path});
  Future<String> transfer(String src, String srcPath, String dst, String dstPath, {required bool copy}) async {
    final d = toJson(await _req('POST', '/files/transfer', body: {
      'sourcePointId': src, 'sourcePath': srcPath, 'destinationPointId': dst, 'destinationPath': dstPath, 'copy': copy}));
    return '${d['jobId']}';
  }

  Future<Json> transferStatus(String jobId) async => toJson(await _req('GET', '/files/transfers/${_e(jobId)}'));

  /// Polls a move/copy until finished. Returns an error string or null on success.
  /// Returns 'timeout' if it did not finish within [timeout] (the job continues server-side).
  Future<String?> awaitTransfer(String jobId, {Duration timeout = const Duration(minutes: 3), void Function(int done, int total)? onProgress}) async {
    final end = DateTime.now().add(timeout);
    final okRe = RegExp(r'(succe|complet|done|finish)', caseSensitive: false);
    final badRe = RegExp(r'(fail|error|cancel)', caseSensitive: false);
    while (DateTime.now().isBefore(end)) {
      try {
        final s = await transferStatus(jobId);
        final err = toStr(s['error']);
        if (err != null && err.isNotEmpty) return err;
        final st = '${s['state']}';
        final done = toInt(s['doneBytes']), total = toInt(s['totalBytes']);
        onProgress?.call(done, total);
        if (badRe.hasMatch(st)) return 'Transfer $st';
        if (okRe.hasMatch(st) || (total > 0 && done >= total)) return null;
      } on ApiException catch (e) {
        if (e.isNotFound) return null;
        rethrow;
      }
      await Future.delayed(const Duration(milliseconds: 800));
    }
    return 'timeout';
  }

  /// HEAD a file. Returns its size, or null if it does not exist.
  Future<int?> headSize(String pointId, String path) async {
    try {
      final r = await _d.head('/files/$pointId/content',
          queryParameters: {'path': path}, options: Options(validateStatus: (s) => s != null && s < 500));
      if (r.statusCode == 200) return int.tryParse(r.headers.value('content-length') ?? '');
      return null;
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------ messages
  Future<Paged<Msg>> inbox({bool? unread, String? from, String? search, String? cursor, int limit = 50}) async =>
      Paged.from(await _req('GET', '/messages/inbox', q: _pg(cursor, limit, 'Desc', {'unread': unread, 'from': from, 'search': search})), Msg.fromJson);
  Future<Paged<Msg>> sent({String? to, String? search, String? cursor, int limit = 50}) async =>
      Paged.from(await _req('GET', '/messages/sent', q: _pg(cursor, limit, 'Desc', {'to': to, 'search': search})), Msg.fromJson);
  Future<int> unreadCount() async => toInt(toJson(await _req('GET', '/messages/unread-count'))['count']);
  Future<Msg> message(String id) async => Msg.fromJson(toJson(await _req('GET', '/messages/$id')));
  Future<void> deleteMessage(String id) => _req('DELETE', '/messages/$id');
  Future<void> send(List<String> to, String subject, String body, {String? replyTo}) =>
      _req('POST', '/messages', body: {'recipients': to, 'subject': subject, 'body': body, 'replyToId': replyTo});
  Future<int> broadcast(String subject, String body) async =>
      toInt(toJson(await _req('POST', '/messages/broadcast', body: {'subject': subject, 'body': body}))['count']);
  Future<void> markRead(String id, bool read) => _req('POST', '/messages/$id/read', q: {'read': read});
  Future<int> readAll() async => toInt(toJson(await _req('POST', '/messages/read-all'))['count']);

  // --------------------------------------------------------------- admin
  Future<Json> status() async => toJson(await _req('GET', '/admin/status'));
  Future<Paged<Json>> vfs({String? user, String? search, String? cursor, int limit = 100}) async =>
      Paged.from(await _req('GET', '/admin/vfs', q: _pg(cursor, limit, null, {'user': user, 'search': search})), (j) => j);
  Future<void> reloadVfs(String user) => _req('POST', '/admin/vfs/users/${_e(user)}/reload');
  Future<void> resetQuota(String user, String pointId) =>
      _req('POST', '/admin/vfs/users/${_e(user)}/points/${_e(pointId)}/quota/reset');
  Future<void> syncVfs() => _req('POST', '/admin/vfs/sync');
  Future<Paged<Json>> logs({
    String? search,
    String? minPriority,
    DateTime? from,
    DateTime? to,
    String? cursor,
    int limit = 100,
    String order = 'Desc',
  }) async =>
      Paged.from(
        await _req(
          'GET',
          '/admin/logs',
          q: _pg(cursor, limit, order, {
            'search': search,
            'minPriority': minPriority,
            'from': from?.toUtc().toIso8601String(),
            'to': to?.toUtc().toIso8601String(),
          }),
        ),
        (j) => j,
      );
  Future<Paged<Json>> events({String? user, String? cursor, int limit = 100}) async =>
      Paged.from(await _req('GET', '/admin/events', q: _pg(cursor, limit, 'Desc', {'user': user})), (j) => j);
  Future<void> testEmail() => _req('POST', '/admin/email/test');
}
