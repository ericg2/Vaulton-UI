import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'update_service.dart';
import '../../core/providers.dart';
import '../../core/util.dart';
import '../../core/widgets.dart';
import '../../platform/desktop_window.dart';
import '../transfers/transfer_manager.dart';

/// Keep in sync with `version:` in pubspec.yaml.
const kAppVersion = '1.3.18';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final c = ref.read(settingsProvider.notifier);
    final u = ref.watch(userProvider);
    final v = ref.read(vaultonProvider);
    final session = ref.read(sessionProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          if (u != null)
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  child: Text(
                    u.userName.isEmpty ? '?' : u.userName[0].toUpperCase(),
                  ),
                ),
                title: Text(u.displayName),
                subtitle: Text(u.userName),
                trailing: IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit Profile',
                  onPressed: () async {
                    final f = await formDialog(context, 'Profile', [
                      FieldSpec(
                        'first',
                        'First Name',
                        initial: u.firstName ?? '',
                      ),
                      FieldSpec('last', 'Last Name', initial: u.lastName ?? ''),
                      FieldSpec('email', 'Email', initial: u.email ?? ''),
                      FieldSpec(
                        'notif',
                        'Email Notifications',
                        kind: 'bool',
                        initial: '${u.emailNotifications}',
                      ),
                    ]);
                    if (f == null) return;
                    await guarded(
                      context,
                      () => v.patchUser(u.userName, {
                        'firstName': f['first'],
                        'lastName': f['last'],
                        'emailAddress': f['email'],
                        'emailNotifications': f['notif'] == 'true',
                      }),
                    );
                    await ref.read(authProvider.notifier).refreshUser();
                  },
                ),
              ),
            ),
          Section(
            'Appearance',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<ThemeMode>(
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('System'),
                      icon: Icon(Icons.brightness_auto),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text('Light'),
                      icon: Icon(Icons.light_mode_outlined),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text('Dark'),
                      icon: Icon(Icons.dark_mode_outlined),
                    ),
                  ],
                  selected: {s.themeMode},
                  onSelectionChanged: (v) => c.setTheme(v.first),
                ),
              ),
            ],
          ),
          Section(
            'Transfers',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Simultaneous Transfers',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ),
                        Text(
                          '${s.concurrency}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    Slider(
                      value: s.concurrency.toDouble(),
                      min: 1,
                      max: 8,
                      divisions: 7,
                      label: '${s.concurrency}',
                      onChanged: (v) => c.setConcurrency(v.round()),
                    ),
                    Text(
                      'Files transferred at once. Lower this on slow or metered connections.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              // Desktop only: on Android, scoped storage stops the app from writing to an
              // arbitrary folder, so downloads always go to the app's own storage there.
              if (isDesktop)
                ListTile(
                  title: const Text('Download Folder'),
                  subtitle: Text(
                    s.downloadDir ?? 'Default (Downloads/Vaulton)',
                  ),
                  leading: const Icon(Icons.folder_outlined),
                  trailing: s.downloadDir == null
                      ? null
                      : IconButton(
                          tooltip: 'Reset',
                          icon: const Icon(Icons.restore),
                          onPressed: () => c.setDownloadDir(null),
                        ),
                  onTap: () async {
                    final d = await FilePicker.getDirectoryPath();
                    if (d != null) c.setDownloadDir(d);
                  },
                ),
              if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
                const ListTile(
                  leading: Icon(Icons.folder_outlined),
                  title: Text('Download Location'),
                  subtitle: Text(
                    'App storage. Open finished downloads from Transfers.',
                  ),
                ),
              if (kIsWeb ||
                  (!isDesktop &&
                      defaultTargetPlatform != TargetPlatform.android))
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: const Text('Download Location'),
                  subtitle: Text(
                    kIsWeb
                        ? 'Browser downloads. Check your browser download folder.'
                        : 'App storage.',
                  ),
                ),
            ],
          ),
          Section(
            'Security',
            children: [
              ListTile(
                leading: const Icon(Icons.password_outlined),
                title: const Text('Change Password'),
                subtitle: const Text(
                  'Also used for SMB shares. Signs out other sessions.',
                ),
                onTap: () async {
                  final f = await formDialog(context, 'Change Password', [
                    const FieldSpec(
                      'cur',
                      'Current Password',
                      kind: 'secret',
                      required: true,
                    ),
                    const FieldSpec(
                      'new',
                      'New Password',
                      kind: 'secret',
                      required: true,
                    ),
                  ]);
                  if (f == null) return;
                  if (f['new']!.length < 8)
                    return toast(
                      context,
                      'Use at least 8 characters.',
                      error: true,
                    );
                  final t = await guarded(
                    context,
                    () => v.changePassword(f['cur']!, f['new']!),
                  );
                  if (t != null) {
                    await session.setTokens(t);
                    if (context.mounted) toast(context, 'Password changed.');
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.devices_other_outlined),
                title: const Text('Sign Out Everywhere'),
                onTap: () async {
                  if (!await confirm(
                    context,
                    'Sign Out Everywhere?',
                    'This ends every session, including this one.',
                    ok: 'Sign Out',
                  ))
                    return;
                  await guarded(context, v.logoutAll);
                  ref.read(transferProvider.notifier).reset();
                  await session.clear();
                  ref.read(authProvider.notifier).sessionExpired();
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Sign Out'),
                onTap: () async {
                  if (ref.read(transferProvider.notifier).hasActive &&
                      !await confirm(
                        context,
                        'Transfers in Progress',
                        'Signing out cancels unfinished transfers.',
                        ok: 'Sign Out',
                        danger: true,
                      )) {
                    return;
                  }
                  ref.read(transferProvider.notifier).reset();
                  await ref.read(authProvider.notifier).signOut();
                },
              ),
            ],
          ),
          Section(
            'About',
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Vaulton Client'),
                subtitle: const Text('Version $kAppVersion'),
                trailing:
                    !kIsWeb &&
                        (defaultTargetPlatform == TargetPlatform.android ||
                            defaultTargetPlatform == TargetPlatform.windows ||
                            defaultTargetPlatform == TargetPlatform.linux)
                    ? IconButton(
                        tooltip: 'Check for Updates',
                        icon: const Icon(Icons.system_update_alt),
                        onPressed: () =>
                            UpdateService.checkAndInstall(context, kAppVersion),
                      )
                    : null,
                onTap:
                    !kIsWeb &&
                        (defaultTargetPlatform == TargetPlatform.android ||
                            defaultTargetPlatform == TargetPlatform.windows ||
                            defaultTargetPlatform == TargetPlatform.linux)
                    ? () => UpdateService.checkAndInstall(context, kAppVersion)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
