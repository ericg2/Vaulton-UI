import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/util.dart';
import '../../core/widgets.dart';
import '../../platform/desktop_window.dart';
import '../transfers/transfer_manager.dart';

/// Keep in sync with `version:` in pubspec.yaml.
const kAppVersion = '1.3.0';

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
      body: ListView(children: [
        if (u != null)
          Card(
            child: ListTile(
              leading: CircleAvatar(child: Text(u.userName.isEmpty ? '?' : u.userName[0].toUpperCase())),
              title: Text(u.displayName),
              subtitle: Text('${u.userName} · ${session.baseUrl}'),
              trailing: IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Edit Profile', onPressed: () async {
                final f = await formDialog(context, 'Profile', [
                  FieldSpec('first', 'First name', initial: u.firstName ?? ''),
                  FieldSpec('last', 'Last name', initial: u.lastName ?? ''),
                  FieldSpec('email', 'Email', initial: u.email ?? ''),
                  FieldSpec('notif', 'Email notifications', kind: 'bool', initial: '${u.emailNotifications}'),
                ]);
                if (f == null) return;
                await guarded(context, () => v.patchUser(u.userName, {
                      'firstName': f['first'], 'lastName': f['last'], 'emailAddress': f['email'], 'emailNotifications': f['notif'] == 'true'}));
                await ref.read(authProvider.notifier).refreshUser();
              }),
            ),
          ),
        Section('Appearance', children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto)),
                ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_outlined)),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined)),
              ],
              selected: {s.themeMode},
              onSelectionChanged: (v) => c.setTheme(v.first),
            ),
          ),
        ]),
        Section('Transfers', children: [
          ListTile(
            title: const Text('Simultaneous Transfers'),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Slider(value: s.concurrency.toDouble(), min: 1, max: 8, divisions: 7, label: '${s.concurrency}', onChanged: (v) => c.setConcurrency(v.round())),
              Text('How many files upload or download at once. Lower it on slow or metered connections.', style: Theme.of(context).textTheme.bodySmall),
            ]),
            trailing: Text('${s.concurrency}'),
          ),
          // Desktop only: on Android, scoped storage stops the app from writing to an
          // arbitrary folder, so downloads always go to the app's own storage there.
          if (isDesktop)
            ListTile(
              title: const Text('Download Folder'),
              subtitle: Text(s.downloadDir ?? 'Default (Vaulton folder in Downloads)'),
              trailing: s.downloadDir == null ? null : IconButton(icon: const Icon(Icons.restore), onPressed: () => c.setDownloadDir(null)),
              onTap: () async {
                final d = await FilePicker.getDirectoryPath();
                if (d != null) c.setDownloadDir(d);
              },
            ),
          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
            const ListTile(
              leading: Icon(Icons.folder_outlined),
              title: Text('Download Location'),
              subtitle: Text('App storage. Open a finished download from Transfers to view, share or save it elsewhere.'),
            ),
        ]),
        Section('Security', children: [
          ListTile(
            leading: const Icon(Icons.password),
            title: const Text('Change Password'),
            subtitle: const Text('Also used for SMB file shares. Other sessions are signed out.'),
            onTap: () async {
              final f = await formDialog(context, 'Change Password', [
                const FieldSpec('cur', 'Current password', kind: 'secret', required: true),
                const FieldSpec('new', 'New password (min 8)', kind: 'secret', required: true),
              ]);
              if (f == null) return;
              if (f['new']!.length < 8) return toast(context, 'New password must be at least 8 characters', error: true);
              final t = await guarded(context, () => v.changePassword(f['cur']!, f['new']!));
              if (t != null) {
                await session.setTokens(t);
                if (context.mounted) toast(context, 'Password changed');
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.devices_other),
            title: const Text('Sign Out Everywhere'),
            onTap: () async {
              if (!await confirm(context, 'Sign out of all devices?', 'Every session of your account ends, including this one.', ok: 'Sign Out')) return;
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
                  !await confirm(context, 'Transfers in Progress', 'Signing out cancels unfinished transfers.', ok: 'Sign Out', danger: true)) {
                return;
              }
              ref.read(transferProvider.notifier).reset();
              await ref.read(authProvider.notifier).signOut();
            },
          ),
        ]),
        Section('About', children: [
          ListTile(leading: const Icon(Icons.info_outline), title: const Text('Vaulton Client'), subtitle: const Text('Version $kAppVersion')),
        ]),
      ]),
    );
  }
}
