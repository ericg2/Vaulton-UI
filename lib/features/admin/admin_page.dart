import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/scopes.dart';
import '../../core/util.dart';
import '../../core/vaulton.dart';
import '../../core/widgets.dart';
import '../backups/jobs_page.dart';

class AdminPage extends ConsumerWidget {
  const AdminPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = ref.watch(userProvider)!;
    final tabs = <(String, Widget)>[
      ('System', const _StatusTab()),
      ('Users', const _UsersTab()),
      if (u.has(Scopes.jobsManage)) ('All jobs', const JobsList(admin: true)),
      if (u.has(Scopes.adminVfs)) ('VFS', const _VfsTab()),
      if (u.has(Scopes.adminVfs)) ('Health events', const _EventsTab()),
      if (u.has(Scopes.adminLogs)) ('Logs', const _LogsTab()),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(title: const Text('Administration'), bottom: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [for (final t in tabs) Tab(text: t.$1)])),
        body: TabBarView(children: [for (final t in tabs) t.$2]),
      ),
    );
  }
}

// ----------------------------------------------------------------- status
class _StatusTab extends ConsumerWidget {
  const _StatusTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.read(vaultonProvider);
    final u = ref.watch(userProvider)!;
    return AsyncBody<Json>(
      load: v.status,
      builder: (ctx, s, reload) {
        Widget tile(String k, Object? val, [IconData? icon]) => ListTile(dense: true, leading: icon == null ? null : Icon(icon), title: Text(k), trailing: Text('$Val', style: Theme.of(ctx).textTheme.titleSmall));
        final ok = toBool(s['backendReachable']);
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(children: [
            Card(
              color: ok ? null : Theme.of(ctx).colorScheme.errorContainer,
              child: ListTile(
                leading: Icon(ok ? Icons.check_circle_outline : Icons.error_outline),
                title: Text(ok ? 'Storage backend reachable' : 'Storage backend unreachable'),
                subtitle: Text('Version ${S['version']} · ${s['environment']} · up ${fmtDuration(Duration(seconds: toInt(s['uptimeSeconds'])))}${s['backendError'] != null ? '\n${s['backendError']}' : ''}'),
              ),
            ),
            Section('Overview', children: [
              tile('Users', s['users'], Icons.people_outline),
              tile('Roots', s['roots'], Icons.dns_outlined),
              tile('Data points', s['dataPoints'], Icons.folder_outlined),
              tile('Repositories', s['repoPoints'], Icons.inventory_2_outlined),
              tile('Points healthy / failed / unknown', '${s['pointsHealthy']} / ${s['pointsFailed']} / ${s['pointsUnknown']}', Icons.monitor_heart_outlined),
              tile('Jobs pending / running', '${s['jobsPending']} / ${s['jobsRunning']}', Icons.work_outline),
              tile('Failed jobs (24h)', s['jobsFailedLast24h'], Icons.warning_amber_outlined),
              tile('Enabled schedules', s['schedulesEnabled'], Icons.schedule),
              tile('SMB', toBool(s['smbRunning']) ? 'running · ${s['smbShares']} shares' : 'stopped', Icons.folder_shared_outlined),
              tile('Email', toBool(s['emailEnabled']) ? 'enabled · ${s['emailPending']} queued' : 'disabled', Icons.email_outlined),
            ]),
            if (u.has(Scopes.adminVfs))
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(spacing: 8, children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.sync),
                    label: const Text('Push Config To Backend'),
                    onPressed: () async {
                      await guarded(ctx, v.syncVfs);
                      if (ctx.mounted) toast(ctx, 'Sync Requested');
                    },
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.mark_email_read_outlined),
                    label: const Text('Send Test Email'),
                    onPressed: () async {
                      await guarded(ctx, v.testEmail);
                      if (ctx.mounted) toast(ctx, 'Test Email Sent to Your Address');
                    },
                  ),
                ]),
              ),
          ]),
        );
      },
    );
  }
}

// ------------------------------------------------------------------ users
class _UsersTab extends ConsumerStatefulWidget {
  const _UsersTab();
  @override
  ConsumerState<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends ConsumerState<_UsersTab> {
  final _key = GlobalKey<CursorListState<UserAccount>>();
  String _search = '';
  Vaulton get _v => ref.read(vaultonProvider);
  bool get _manage => ref.read(userProvider)!.has(Scopes.usersManage);

  Future<void> _create() async {
    final f = await formDialog(context, 'New User', [
      const FieldSpec('u', 'User Name', required: true),
      const FieldSpec('first', 'First Name'),
      const FieldSpec('last', 'Last Name'),
      const FieldSpec('email', 'Email'),
      const FieldSpec('welcome', 'Send Welcome Email', kind: 'bool'),
    ], ok: 'Create');
    if (f == null) return;
    final r = await guarded(context, () => _v.addUser({
          'username': f['u'], if (f['first']!.isNotEmpty) 'firstName': f['first'], if (f['last']!.isNotEmpty) 'lastName': f['last'],
          if (f['email']!.isNotEmpty) 'email': f['email'], 'sendWelcomeEmail': f['welcome'] == 'true'}));
    if (r == null || !mounted) return;
    _key.currentState?.refresh();
    _showPassword('Temporary password for ${r['userName']}', '${r['temporaryPassword']}');
  }

  void _showPassword(String title, String pw) => showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Shown only once. The user must change password at first sign-in.'),
            const SizedBox(height: 12),
            SelectableText(pw, style: const TextStyle(fontFamily: 'monospace', fontSize: 18)),
          ]),
          actions: [
            TextButton(onPressed: () => copyText(ctx, pw), child: const Text('Copy')),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
          ],
        ),
      );

  Future<void> _scopes(UserAccount u) async {
    final all = await guarded(context, _v.scopes);
    if (all == null || !mounted) return;
    final chosen = {...u.scopes};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text('Scopes For ${U.Username}'),
          content: SizedBox(
            width: 460,
            child: ListView(shrinkWrap: true, children: [
              for (final s in all)
                CheckboxListTile(
                  title: Text(s.name),
                  subtitle: Text(s.description),
                  value: chosen.contains(s.name),
                  onChanged: (v) => set(() => v! ? chosen.add(s.name) : chosen.remove(s.name)),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await guarded(context, () => _v.setScopes(u.userName, chosen.toList()));
    _key.currentState?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(userProvider)!;
    return Scaffold(
      floatingActionButton: _manage ? FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.person_add_alt), label: const Text('New User')) : null,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search users'),
            onSubmitted: (v) => setState(() => _search = v.trim()),
          ),
        ),
        Expanded(
          child: CursorList<UserAccount>(
            key: ValueKey(_search),
            empty: 'No Users',
            emptyIcon: Icons.people_outline,
            fetch: (c) => _v.users(search: _search, cursor: c),
            itemBuilder: (ctx, u, i) => Card(
              child: ListTile(
                leading: CircleAvatar(child: Text(u.userName.isEmpty ? '?' : u.userName[0].toUpperCase())),
                title: Text(u.displayName),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${U.Username}${U.Email != Null ? ' · ${u.email}' : ''}\nLast sign-in ${fmtDate(u.lastLogin)}'),
                  Wrap(children: [
                    if (u.isLockedOut) chip(ctx, 'Locked', color: Theme.of(ctx).colorScheme.errorContainer),
                    if (u.mustChangePassword) chip(ctx, 'Temp password'),
                    for (final s in u.scopes) chip(ctx, s),
                  ]),
                ]),
                isThreeLine: true,
                trailing: _manage
                    ? PopupMenuButton<String>(
                        onSelected: (a) async {
                          switch (a) {
                            case 'scopes': _scopes(u);
                            case 'lock':
                              await guarded(context, () => u.isLockedOut ? _v.unlockUser(u.userName) : _v.lockUser(u.userName));
                              _key.currentState?.refresh();
                            case 'reset':
                              if (await confirm(context, 'Reset Password?', 'A new temporary password is created and all sessions of ${u.userName} end.', ok: 'Reset')) {
                                final r = await guarded(context, () => _v.resetPassword(u.userName));
                                if (r != null && context.mounted) _showPassword('New password for ${u.userName}', '${r['temporaryPassword']}');
                              }
                            case 'revoke':
                              await guarded(context, () => _v.revokeSessions(u.userName));
                              if (context.mounted) toast(context, 'Sessions Ended');
                            case 'del':
                              if (await confirm(context, 'Delete ${u.userName}?', 'Deletes the user and everything they own.', ok: 'Delete', danger: true)) {
                                await guarded(context, () => _v.deleteUser(u.userName));
                                _key.currentState?.refresh();
                              }
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'scopes', child: Text('Edit Scopes')),
                          PopupMenuItem(value: 'lock', child: Text(u.isLockedOut ? 'Unlock' : 'Lock')),
                          const PopupMenuItem(value: 'reset', child: Text('Reset Password')),
                          const PopupMenuItem(value: 'revoke', child: Text('Revoke Sessions')),
                          if (u.userName != me.userName) const PopupMenuItem(value: 'del', child: Text('Delete')),
                        ],
                      )
                    : null,
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// -------------------------------------------------------------------- vfs
class _VfsTab extends ConsumerWidget {
  const _VfsTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.read(vaultonProvider);
    return CursorList<Json>(
      empty: 'No Points',
      fetch: (c) => v.vfs(cursor: c),
      itemBuilder: (ctx, p, i) {
        final err = toStr(p['error']);
        return ListTile(
          leading: Icon(err != null ? Icons.error_outline : Icons.storage_outlined, color: err != null ? Theme.of(ctx).colorScheme.error : null),
          title: Text('${P['user']} / ${p['name']}'),
          subtitle: Text('${Fmtbytes(Toint(P['usedBytes']))} of ${fmtBytes(toInt(p['maxBytes']))} · health ${p['health']} · ${toBool(p['canWrite']) ? 'read/write' : 'read-only'}${err != null ? '\n$err' : ''}'),
          trailing: IconButton(
            tooltip: 'Reload User VFS',
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await guarded(ctx, () => v.reloadVfs('${p['user']}'));
              if (ctx.mounted) toast(ctx, 'Reloaded ${p['user']}');
            },
          ),
        );
      },
    );
  }
}

class _EventsTab extends ConsumerWidget {
  const _EventsTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.read(vaultonProvider);
    return CursorList<Json>(
      empty: 'No Health Events',
      fetch: (c) => v.events(cursor: c),
      itemBuilder: (ctx, e, i) => ListTile(
        dense: true,
        leading: const Icon(Icons.monitor_heart_outlined),
        title: Text('${E['user']} / ${e['pointName']} → ${e['health']}'),
        subtitle: Text('${Fmtdate(Todate(E['time']))}${e['error'] != null ? '\n${e['error']}' : ''}'),
      ),
    );
  }
}

class _LogsTab extends ConsumerStatefulWidget {
  const _LogsTab();
  @override
  ConsumerState<_LogsTab> createState() => _LogsTabState();
}

class _LogsTabState extends ConsumerState<_LogsTab> {
  String _search = '';
  @override
  Widget build(BuildContext context) {
    final v = ref.read(vaultonProvider);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Filter log'), onSubmitted: (s) => setState(() => _search = s.trim())),
      ),
      Expanded(
        child: CursorList<Json>(
          key: ValueKey(_search),
          empty: 'No Log Entries',
          fetch: (c) => v.logs(search: _search, cursor: c),
          itemBuilder: (ctx, e, i) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: SelectableText('${fmtDate(toDate(e['time']))}  [${e['priority']}] ${e['message']}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ),
        ),
      ),
    ]);
  }
}
