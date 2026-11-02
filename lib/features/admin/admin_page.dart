import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/scopes.dart';
import '../../core/util.dart';
import '../../core/vaulton.dart';
import '../../core/widgets.dart';
import '../backups/jobs_page.dart';
import '../backups/log_widgets.dart';
import 'configuration_page.dart';

class AdminPage extends ConsumerWidget {
  const AdminPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = ref.watch(userProvider)!;
    final tabs = <(String, Widget)>[
      ('System', const _StatusTab()),
      ('Users', const _UsersTab()),
      if (u.has(Scopes.jobsManage)) ('All Jobs', const JobsList(admin: true)),
      if (u.has(Scopes.adminVfs)) ('VFS', const _VfsTab()),
      if (u.has(Scopes.adminLogs)) ('Logs', const _LogsTab()),
      if (u.has(Scopes.adminLogs)) ('Audit', const _AuditTab()),
      if (u.has(Scopes.adminSettings)) ('Maintenance', const _MaintenanceTab()),
      if (u.userName.toLowerCase() == 'admin')
        ('Configuration', const ConfigurationTab()),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Administration'),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [for (final t in tabs) Tab(text: t.$1)],
          ),
        ),
        body: TabBarView(children: [for (final t in tabs) t.$2]),
      ),
    );
  }
}

// ----------------------------------------------------------------- status
class _StatusCount {
  const _StatusCount(this.icon, this.label, this.value, this.color);
  final IconData icon;
  final String label;
  final int value;
  final Color color;
}

Widget _statusCountsTile(
  BuildContext context,
  String title,
  List<_StatusCount> counts,
  IconData icon,
) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final narrow = constraints.maxWidth < 520;
      final badges = Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final c in counts)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: c.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(c.icon, size: 14, color: c.color),
                  const SizedBox(width: 4),
                  Text(
                    '${c.value} ${c.label}',
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: c.color, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
        ],
      );
      if (narrow) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [Icon(icon), const SizedBox(width: 16), Text(title)],
              ),
              const SizedBox(height: 8),
              badges,
            ],
          ),
        );
      }
      return ListTile(
        dense: true,
        leading: Icon(icon),
        title: Text(title),
        trailing: badges,
      );
    },
  );
}

class _StatusTab extends ConsumerWidget {
  const _StatusTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.read(vaultonProvider);
    final u = ref.watch(userProvider)!;
    return AsyncBody<Json>(
      load: v.status,
      builder: (ctx, s, reload) {
        Widget tile(String k, Object? val, [IconData? icon]) => ListTile(
          dense: true,
          leading: icon == null ? null : Icon(icon),
          title: Text(k),
          trailing: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              '$val',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: Theme.of(ctx).textTheme.titleSmall,
            ),
          ),
        );
        final ok = toBool(s['backendReachable']);
        final backendError = toStr(s['backendError']);
        final cs = Theme.of(ctx).colorScheme;
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            children: [
              Card(
                color: ok ? null : Theme.of(ctx).colorScheme.errorContainer,
                child: ListTile(
                  leading: Icon(
                    ok ? Icons.check_circle_outline : Icons.error_outline,
                  ),
                  title: Text(
                    ok
                        ? 'Storage Backend Reachable'
                        : 'Storage Backend Unreachable',
                  ),
                  subtitle: Text(
                    'Version ${s['version']} · ${s['environment']} · up ${fmtDuration(Duration(seconds: toInt(s['uptimeSeconds'])))}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: backendError == null || backendError.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'View Backend Error',
                          icon: const Icon(Icons.info_outline),
                          onPressed: () => showDialog<void>(
                            context: ctx,
                            builder: (dialogContext) {
                              final theme = Theme.of(dialogContext);
                              final colors = theme.colorScheme;
                              return AlertDialog(
                                insetPadding: const EdgeInsets.all(16),
                                title: const Text('Backend Diagnostics'),
                                content: SizedBox(
                                  width: 560,
                                  height: (MediaQuery.sizeOf(dialogContext).height -
                                          MediaQuery.viewInsetsOf(dialogContext).bottom -
                                          220)
                                      .clamp(160.0, 560.0)
                                      .toDouble(),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: colors.errorContainer,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Icon(Icons.warning_amber_rounded, color: colors.onErrorContainer),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                'The backend reported an error. Share these details with an administrator if you need help.',
                                                style: TextStyle(color: colors.onErrorContainer),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Expanded(
                                        child: Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: colors.surfaceContainerHigh,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: SingleChildScrollView(
                                            child: SelectableText(
                                              backendError,
                                              style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                actions: [
                                  TextButton.icon(
                                    onPressed: () => copyText(dialogContext, backendError, 'Diagnostics copied.'),
                                    icon: const Icon(Icons.copy_outlined),
                                    label: const Text('Copy Details'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(dialogContext),
                                    child: const Text('Close'),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                ),
              ),
              Section(
                'Overview',
                children: [
                  tile('Users', s['users'], Icons.people_outline),
                  tile('Locations', s['roots'], Icons.dns_outlined),
                  tile('Data Folders', s['dataPoints'], Icons.folder_outlined),
                  tile(
                    'Backup Vaults',
                    s['repoPoints'],
                    Icons.inventory_2_outlined,
                  ),
                  _statusCountsTile(ctx, 'Health', [
                    _StatusCount(
                      Icons.check_circle_outline,
                      'Healthy',
                      toInt(s['pointsHealthy']),
                      cs.primary,
                    ),
                    _StatusCount(
                      Icons.error_outline,
                      'Failed',
                      toInt(s['pointsFailed']),
                      cs.error,
                    ),
                    _StatusCount(
                      Icons.help_outline,
                      'Unknown',
                      toInt(s['pointsUnknown']),
                      cs.outline,
                    ),
                  ], Icons.monitor_heart_outlined),
                  _statusCountsTile(ctx, 'Jobs', [
                    _StatusCount(
                      Icons.schedule,
                      'Waiting',
                      toInt(s['jobsPending']),
                      cs.secondary,
                    ),
                    _StatusCount(
                      Icons.sync,
                      'Running',
                      toInt(s['jobsRunning']),
                      cs.tertiary,
                    ),
                  ], Icons.work_outline),
                  tile(
                    'Failed Jobs (24h)',
                    s['jobsFailedLast24h'],
                    Icons.warning_amber_outlined,
                  ),
                  tile(
                    'Enabled Schedules',
                    s['schedulesEnabled'],
                    Icons.schedule,
                  ),
                  tile(
                    'SMB',
                    toBool(s['smbRunning'])
                        ? 'Running · ${s['smbShares']} shares'
                        : 'Stopped',
                    Icons.folder_shared_outlined,
                  ),
                  tile(
                    'Email',
                    toBool(s['emailEnabled'])
                        ? 'Enabled · ${s['emailPending']} queued'
                        : 'Disabled',
                    Icons.email_outlined,
                  ),
                ],
              ),
              if (u.has(Scopes.adminVfs))
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.mark_email_read_outlined),
                        label: const Text('Send Test Email'),
                        onPressed: () async {
                          await guarded(ctx, v.testEmail);
                          if (ctx.mounted) toast(ctx, 'Test email sent.');
                        },
                      ),
                    ],
                  ),
                ),
            ],
          ),
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
    final draft = await showDialog<_NewUserDraft>(
      context: context,
      builder: (_) => const _NewUserDialog(),
    );
    if (draft == null || !mounted) return;
    final r = await guarded(
      context,
      () => _v.addUser({
        'username': draft.username,
        if (draft.firstName.isNotEmpty) 'firstName': draft.firstName,
        if (draft.lastName.isNotEmpty) 'lastName': draft.lastName,
        if (draft.email.isNotEmpty) 'email': draft.email,
        'sendWelcomeEmail': draft.sendWelcomeEmail,
      }),
    );
    if (r == null || !mounted) return;
    _key.currentState?.refresh();
    _showPassword(
      'Temporary password for ${r['userName']}',
      '${r['temporaryPassword']}',
    );
  }

  void _showPassword(String title, String pw) => showDialog(
    context: context,
    builder: (ctx) {
      final colors = Theme.of(ctx).colorScheme;
      return AlertDialog(
        insetPadding: const EdgeInsets.all(16),
        title: Text(title),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This temporary password is shown only once. The user must change it at first sign-in.',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  pw,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 18),
                ),
              ),
            ],
          ),
        ),
        actions: [
        TextButton(
          onPressed: () => copyText(ctx, pw),
          child: const Text('Copy'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Done'),
        ),
      ],
      );
    },
  );

  Future<void> _scopes(UserAccount u) async {
    final all = await guarded(context, _v.scopes);
    if (all == null || !mounted) return;
    final available = all.where((s) => s.name != 'Users.List').toList();
    final chosen = {...u.scopes};
    var search = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final q = search.toLowerCase();
          final visible = available.where((scope) =>
              scope.name.toLowerCase().contains(q) ||
              scope.description.toLowerCase().contains(q)).toList();
          return AlertDialog(
            title: Text('Permissions for ${u.userName}'),
            insetPadding: const EdgeInsets.all(16),
            content: SizedBox(
              width: 520,
              height: (MediaQuery.sizeOf(ctx).height - MediaQuery.viewInsetsOf(ctx).bottom - 200)
                  .clamp(140.0, 560.0)
                  .toDouble(),
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Find a permission',
                    ),
                    onChanged: (value) => set(() => search = value),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${chosen.length} of ${available.length} permissions selected',
                          style: Theme.of(ctx).textTheme.bodySmall,
                        ),
                      ),
                      TextButton(
                        onPressed: () => set(chosen.clear),
                        child: const Text('Clear all'),
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: visible.isEmpty
                        ? const Center(child: Text('No matching permissions.'))
                        : ListView.builder(
                            itemCount: visible.length,
                            itemBuilder: (context, index) {
                              final scope = visible[index];
                              return CheckboxListTile(
                                controlAffinity: ListTileControlAffinity.leading,
                                title: Text(scope.name),
                                subtitle: Text(scope.description),
                                value: chosen.contains(scope.name),
                                onChanged: (value) => set(
                                  () => value == true
                                      ? chosen.add(scope.name)
                                      : chosen.remove(scope.name),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save Permissions'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    final saved = await guarded(
      context,
      () => _v.setScopes(u.userName, chosen.toList()),
    );
    if (saved == null || !mounted) return;
    _key.currentState?.refresh();
    toast(context, 'Permissions updated.');
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(userProvider)!;
    return Scaffold(
      floatingActionButton: _manage
          ? FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.person_add_alt),
              label: const Text('New User'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search users',
              ),
              onSubmitted: (v) => setState(() => _search = v.trim()),
            ),
          ),
          Expanded(
            child: CursorList<UserAccount>(
              key: ValueKey(_search),
              empty: 'No users.',
              emptyIcon: Icons.people_outline,
              fetch: (c) => _v.users(search: _search, cursor: c),
              itemBuilder: (ctx, u, i) => Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      u.userName.isEmpty ? '?' : u.userName[0].toUpperCase(),
                    ),
                  ),
                  title: Text(u.displayName),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${u.userName}${u.email != null ? ' · ${u.email}' : ''}\nLast sign-in ${fmtDate(u.lastLogin)}',
                      ),
                      Wrap(
                        children: [
                          if (u.isLockedOut)
                            chip(
                              ctx,
                              'Locked',
                              color: Theme.of(ctx).colorScheme.errorContainer,
                            ),
                          if (u.mustChangePassword)
                            chip(ctx, 'Temporary Password'),
                          for (final s in u.scopes) chip(ctx, s),
                        ],
                      ),
                    ],
                  ),
                  isThreeLine: true,
                  trailing: _manage
                      ? PopupMenuButton<String>(
                          onSelected: (a) async {
                            switch (a) {
                              case 'scopes':
                                _scopes(u);
                              case 'lock':
                                await guarded(
                                  context,
                                  () => u.isLockedOut
                                      ? _v.unlockUser(u.userName)
                                      : _v.lockUser(u.userName),
                                );
                                _key.currentState?.refresh();
                              case 'reset':
                                if (await confirm(
                                  context,
                                  'Reset Password?',
                                  'A new temporary password is created and all sessions of ${u.userName} end.',
                                  ok: 'Reset',
                                )) {
                                  final r = await guarded(
                                    context,
                                    () => _v.resetPassword(u.userName),
                                  );
                                  if (r != null && context.mounted) {
                                    _showPassword(
                                      'New password for ${u.userName}',
                                      '${r['temporaryPassword']}',
                                    );
                                  }
                                }
                              case 'revoke':
                                await guarded(
                                  context,
                                  () => _v.revokeSessions(u.userName),
                                );
                                if (context.mounted) {
                                  toast(context, 'Sessions ended.');
                                }
                              case 'del':
                                if (await confirm(
                                  context,
                                  'Delete ${u.userName}?',
                                  'Deletes the user and everything they own.',
                                  ok: 'Delete',
                                  danger: true,
                                )) {
                                  await guarded(
                                    context,
                                    () => _v.deleteUser(u.userName),
                                  );
                                  _key.currentState?.refresh();
                                }
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'scopes',
                              child: Text('Edit Permissions'),
                            ),
                            PopupMenuItem(
                              value: 'lock',
                              child: Text(u.isLockedOut ? 'Unlock' : 'Lock'),
                            ),
                            const PopupMenuItem(
                              value: 'reset',
                              child: Text('Reset Password'),
                            ),
                            const PopupMenuItem(
                              value: 'revoke',
                              child: Text('Revoke Sessions'),
                            ),
                            if (u.userName != me.userName)
                              const PopupMenuItem(
                                value: 'del',
                                child: Text('Delete'),
                              ),
                          ],
                        )
                      : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------- vfs
class _VfsTab extends ConsumerStatefulWidget {
  const _VfsTab();
  @override
  ConsumerState<_VfsTab> createState() => _VfsTabState();
}

class _VfsTabState extends ConsumerState<_VfsTab> {
  final _key = GlobalKey<CursorListState<Json>>();

  Future<void> _resetQuota(Json p) async {
    final user = '${p['user']}';
    final pointId = '${p['pointId']}';
    final pointName = '${p['name']}';
    final ok = await confirm(
      context,
      'Reset Quota Usage?',
      'This permanently resets Vaulton’s tracked quota usage to 0; use only after the remote data has been deleted.',
      ok: 'Reset Usage',
      danger: true,
    );
    if (!ok || !mounted) return;

    await guarded(
      context,
      () => ref.read(vaultonProvider).resetQuota(user, pointId),
    );
    if (!mounted) return;
    await _key.currentState?.refresh();
    if (mounted) toast(context, 'Quota usage reset for $pointName.');
  }

  @override
  Widget build(BuildContext context) {
    final v = ref.read(vaultonProvider);
    return CursorList<Json>(
      key: _key,
      empty: 'No Points',
      fetch: (c) => v.vfs(cursor: c),
      itemBuilder: (ctx, p, i) {
        final err = toStr(p['error']);
        final health = '${p['health'] ?? 'Unknown'}';
        final updatedRaw =
            p['healthUpdatedAt'] ??
            p['updatedAt'] ??
            p['updated'] ??
            p['lastHealthCheck'];
        final updated = updatedRaw == null ? null : toDate(updatedRaw);
        final cs = Theme.of(ctx).colorScheme;
        final remote = toBool(p['remote']);
        return Card(
          child: LayoutBuilder(
            builder: (ctx2, constraints) {
              final narrow = constraints.maxWidth < 420;
              return ListTile(
                contentPadding: const EdgeInsets.only(left: 8, right: 4),
                leading: Icon(
                  err != null ? Icons.error_outline : Icons.storage_outlined,
                  color: err != null ? cs.error : null,
                ),
                title: Text(
                  '${p['name']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        chip(ctx, '${p['user']}'),
                        chip(ctx, remote ? 'Remote' : 'Local'),
                        chip(
                          ctx,
                          updated == null
                              ? health
                              : '$health · ${fmtDate(updated)}',
                          color: err != null ? cs.errorContainer : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${fmtBytes(toInt(p['usedBytes']))} of ${fmtBytes(toInt(p['maxBytes']))} · ${toBool(p['canWrite']) ? 'Read/Write' : 'Read-Only'}',
                    ),
                    if (err != null && err.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 36),
                          ),
                          onPressed: () => showDialog<void>(
                            context: ctx,
                            builder: (dialogContext) => AlertDialog(
                              title: Text('Storage Error · ${p['name']}'),
                              content: SingleChildScrollView(
                                child: SelectableText(err),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(dialogContext),
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          ),
                          icon: const Icon(Icons.info_outline, size: 18),
                          label: const Text('View Error'),
                        ),
                      ),
                    if (narrow && remote)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Wrap(
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _resetQuota(p),
                              icon: const Icon(Icons.restart_alt, size: 18),
                              label: const Text('Reset Quota'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                minimumSize: const Size(0, 36),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                isThreeLine: true,
                trailing: narrow
                    ? IconButton(
                        tooltip: 'Reload User VFS',
                        icon: const Icon(Icons.refresh),
                        onPressed: () async {
                          await guarded(ctx, () => v.reloadVfs('${p['user']}'));
                          if (ctx.mounted) {
                            await _key.currentState?.refresh();
                            toast(ctx, 'Reloaded ${p['user']}.');
                          }
                        },
                      )
                    : Wrap(
                        spacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (remote)
                            OutlinedButton.icon(
                              onPressed: () => _resetQuota(p),
                              icon: const Icon(Icons.restart_alt),
                              label: const Text(
                                'Reset Quota',
                                textAlign: TextAlign.center,
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                minimumSize: const Size(0, 40),
                              ),
                            ),
                          IconButton(
                            tooltip: 'Reload User VFS',
                            icon: const Icon(Icons.refresh),
                            onPressed: () async {
                              await guarded(
                                ctx,
                                () => v.reloadVfs('${p['user']}'),
                              );
                              if (ctx.mounted) {
                                await _key.currentState?.refresh();
                                toast(ctx, 'Reloaded ${p['user']}.');
                              }
                            },
                          ),
                        ],
                      ),
              );
            },
          ),
        );
      },
    );
  }
}

class _LogsTab extends ConsumerStatefulWidget {
  const _LogsTab();
  @override
  ConsumerState<_LogsTab> createState() => _LogsTabState();
}

class _LogsTabState extends ConsumerState<_LogsTab> {
  final _searchCtl = TextEditingController();
  String _search = '';
  String? _priority;
  DateTime? _from;
  DateTime? _to;

  Future<void> _pickDates() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      initialDateRange: _from != null && _to != null
          ? DateTimeRange(
              start: _from!,
              end: _to!.subtract(const Duration(seconds: 1)),
            )
          : null,
    );
    if (range == null) return;
    setState(() {
      _from = DateTime(range.start.year, range.start.month, range.start.day);
      _to = DateTime(
        range.end.year,
        range.end.month,
        range.end.day,
      ).add(const Duration(days: 1));
    });
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = ref.read(vaultonProvider);
    return Column(
      children: [
        LogFilterBar(
          searchController: _searchCtl,
          search: _search,
          priority: _priority,
          onSearch: (s) => setState(() => _search = s),
          onPriority: (p) => setState(() => _priority = p),
          from: _from,
          to: _to,
          onDates: _pickDates,
        ),
        Expanded(
          child: CursorList<Json>(
            key: ValueKey('$_search|$_priority|$_from|$_to'),
            empty: 'No Log Entries',
            fetch: (c) => v.logs(
              search: _search,
              minPriority: _priority,
              from: _from,
              to: _to,
              cursor: c,
              order: 'Desc',
            ),
            itemBuilder: (ctx, e, i) => LogLine(
              time: toDate(e['time']),
              priority: '${e['priority'] ?? 'Info'}',
              message: '${e['message']}',
            ),
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ audit
class _AuditTab extends ConsumerStatefulWidget {
  const _AuditTab();
  @override
  ConsumerState<_AuditTab> createState() => _AuditTabState();
}

class _AuditTabState extends ConsumerState<_AuditTab> {
  final _key = GlobalKey<CursorListState<Json>>();
  final _user = TextEditingController();
  final _path = TextEditingController();
  String _userFilter = '';
  String _pathFilter = '';

  Vaulton get _v => ref.read(vaultonProvider);

  @override
  void dispose() {
    _user.dispose();
    _path.dispose();
    super.dispose();
  }

  void _apply() {
    setState(() {
      _userFilter = _user.text.trim();
      _pathFilter = _path.text.trim();
    });
    _key.currentState?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _user,
                  decoration: const InputDecoration(
                    labelText: 'User',
                    prefixIcon: Icon(Icons.person_outline),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _apply(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _path,
                  decoration: const InputDecoration(
                    labelText: 'Path contains',
                    prefixIcon: Icon(Icons.route_outlined),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _apply(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Apply filters',
                onPressed: _apply,
                icon: const Icon(Icons.filter_alt_outlined),
              ),
            ],
          ),
        ),
        Expanded(
          child: CursorList<Json>(
            key: _key,
            empty: 'No Audit Entries',
            emptyHint: 'Mutating requests and sign-in attempts are recorded here.',
            fetch: (c) => _v.auditPage(
              cursor: c,
              user: _userFilter.isEmpty ? null : _userFilter,
              path: _pathFilter.isEmpty ? null : _pathFilter,
            ),
            itemBuilder: (ctx, e, i) {
              final status = toInt(e['statusCode']);
              final bad = status >= 400;
              final method = '${e['method'] ?? ''}';
              return ListTile(
                dense: true,
                leading: Icon(
                  switch (method) {
                    'GET' => Icons.visibility_outlined,
                    'POST' => Icons.add_circle_outline,
                    'PUT' || 'PATCH' => Icons.edit_outlined,
                    'DELETE' => Icons.delete_outline,
                    _ => Icons.bolt_outlined,
                  },
                  color: bad ? cs.error : cs.primary,
                ),
                title: Text(
                  '$method ${e['path']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
                subtitle: Text(
                  '${e['userName'] ?? 'anonymous'} · ${e['remoteIp'] ?? '—'} · '
                  '${fmtDate(toDate(e['at']))} · ${toInt(e['durationMs'])} ms'
                  '${e['detail'] != null ? '\n${e['detail']}' : ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                isThreeLine: e['detail'] != null,
                trailing: Text(
                  '$status',
                  style: TextStyle(
                    color: bad ? cs.error : cs.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ maintenance
class _MaintenanceTab extends ConsumerWidget {
  const _MaintenanceTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.read(vaultonProvider);
    final cs = Theme.of(context).colorScheme;
    return AsyncBody<Json>(
      load: v.selfBackupStatus,
      builder: (ctx, data, reload) {
        final status = toJson(data['status']);
        final backups = (data['backups'] as List? ?? const [])
            .map(toJson)
            .toList();
        final success = status['lastSuccess'] == true;
        final lastRun = toDate(status['lastRun']);
        final enabled = toBool(data['enabled']);

        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            children: [
              Card(
                color: success || status['lastRun'] == null
                    ? null
                    : cs.errorContainer,
                child: ListTile(
                  leading: Icon(
                    status['lastRun'] == null
                        ? Icons.schedule
                        : success
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                  ),
                  title: Text(
                    status['lastRun'] == null
                        ? 'No Self-Backup Yet'
                        : success
                        ? 'Last Self-Backup Succeeded'
                        : 'Last Self-Backup Failed',
                  ),
                  subtitle: Text(
                    [
                      if (lastRun != null) fmtDate(lastRun),
                      if (status['lastDurationMs'] != null)
                        '${toInt(status['lastDurationMs'])} ms',
                      if (status['lastPath'] != null)
                        '${status['lastPath']}',
                      if (status['lastError'] != null)
                        '${status['lastError']}',
                    ].join(' · '),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              Section(
                'Automatic Copies',
                children: [
                  ListTile(
                    leading: const Icon(Icons.timer_outlined),
                    title: const Text('Interval'),
                    trailing: Text(
                      enabled
                          ? 'Every ${toInt(data['intervalHours'])} h'
                          : 'Disabled',
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.history),
                    title: const Text('Keep'),
                    trailing: Text('${toInt(data['retain'])} copies'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: const Text('Directory'),
                    subtitle: Text('${data['directory'] ?? ''}'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.update),
                    title: const Text('Next Run'),
                    trailing: Text(
                      status['nextRun'] == null
                          ? 'After the next API start'
                          : fmtDate(toDate(status['nextRun'])),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.backup_outlined),
                    label: const Text('Run Backup Now'),
                    onPressed: () async {
                      final r = await guarded(ctx, v.runSelfBackup);
                      if (r == null || !ctx.mounted) return;
                      toast(ctx, 'Self-backup written to ${r['path']}');
                      await reload();
                    },
                  ),
                ),
              ),
              Section(
                'Copies On Disk',
                children: backups.isEmpty
                    ? [
                        const ListTile(
                          leading: Icon(Icons.inbox_outlined),
                          title: Text('No copies yet'),
                        ),
                      ]
                    : [
                        for (final b in backups)
                          ListTile(
                            leading: const Icon(Icons.inventory_2_outlined),
                            title: Text('${b['name']}'),
                            subtitle: Text(
                              '${fmtBytes(toInt(b['bytes']))} · '
                              '${fmtDate(toDate(b['createdAt']))}',
                            ),
                          ),
                      ],
              ),
            ],
          ),
        );
      },
    );
  }
}


class _NewUserDraft {
  const _NewUserDraft({
    required this.username,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.sendWelcomeEmail,
  });

  final String username;
  final String firstName;
  final String lastName;
  final String email;
  final bool sendWelcomeEmail;
}

class _NewUserDialog extends StatefulWidget {
  const _NewUserDialog();

  @override
  State<_NewUserDialog> createState() => _NewUserDialogState();
}

class _NewUserDialogState extends State<_NewUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  bool _sendWelcomeEmail = false;

  @override
  void dispose() {
    _username.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    super.dispose();
  }

  void _create() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      _NewUserDraft(
        username: _username.text.trim(),
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        email: _email.text.trim(),
        sendWelcomeEmail: _sendWelcomeEmail,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AlertDialog(
      insetPadding: const EdgeInsets.all(16),
      title: const Text('Create User'),
      content: SizedBox(
        width: 480,
        height: (MediaQuery.sizeOf(context).height -
                MediaQuery.viewInsetsOf(context).bottom -
                220)
            .clamp(180.0, 500.0)
            .toDouble(),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.person_add_alt_1_outlined, color: cs.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Create a Vaulton account. A temporary password will be generated and shown once after creation.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text('Account', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              TextFormField(
                controller: _username,
                autofocus: true,
                textCapitalization: TextCapitalization.none,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  prefixIcon: Icon(Icons.alternate_email),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a username.'
                    : null,
              ),
              const SizedBox(height: 18),
              Text('Profile', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              TextFormField(
                controller: _firstName,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'First Name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _lastName,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Last Name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Email Address (Optional)',
                  prefixIcon: Icon(Icons.mail_outline),
                ),
                validator: (value) {
                  final email = value?.trim() ?? '';
                  if (email.isNotEmpty &&
                      (!email.contains('@') ||
                          !email.split('@').last.contains('.'))) {
                    return 'Enter a valid email address.';
                  }
                  return null;
                },
                onChanged: (value) => setState(() {
                  if (value.trim().isEmpty) _sendWelcomeEmail = false;
                }),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Send Welcome Email'),
                subtitle: Text(
                  _email.text.trim().isEmpty
                      ? 'Add an email address to enable this option.'
                      : 'Send the account welcome message to this address.',
                ),
                value: _sendWelcomeEmail,
                onChanged: _email.text.trim().isEmpty
                    ? null
                    : (value) => setState(() => _sendWelcomeEmail = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _create,
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Create User'),
        ),
      ],
    );
  }
}
