import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'update_service.dart';
import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../core/util.dart';
import '../../core/vaulton.dart';
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
                  if (f['new']!.length < 8) {
                    return toast(
                      context,
                      'Use at least 8 characters.',
                      error: true,
                    );
                  }
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
                leading: const Icon(Icons.shield_outlined),
                title: const Text('Two-Factor Authentication'),
                subtitle: const Text(
                  'Protect sign-in with an authenticator app and recovery codes.',
                ),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => _TwoFactorDialog(v: v),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.key_outlined),
                title: const Text('API Tokens'),
                subtitle: const Text(
                  'Scoped credentials for scripts, automation and integrations.',
                ),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => _ApiTokensDialog(v: v),
                ),
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
                  )) {
                    return;
                  }
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

Future<void> _showRecoveryCodes(
  BuildContext context,
  List<String> codes,
) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Recovery Codes'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Store these somewhere safe. Each code works once and they are shown only now.',
            ),
            const SizedBox(height: 12),
            SelectableText(
              codes.join('\n'),
              style: const TextStyle(fontFamily: 'monospace', height: 1.5),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: codes.join('\n')));
            if (ctx.mounted) toast(ctx, 'Recovery codes copied.');
          },
          icon: const Icon(Icons.copy_all_outlined),
          label: const Text('Copy'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}

class _TwoFactorDialog extends StatefulWidget {
  const _TwoFactorDialog({required this.v});
  final Vaulton v;

  @override
  State<_TwoFactorDialog> createState() => _TwoFactorDialogState();
}

class _TwoFactorDialogState extends State<_TwoFactorDialog> {
  final _code = TextEditingController();
  bool _loading = true;
  bool _enabled = false;
  int _remaining = 0;
  String? _secret;
  String? _uri;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await widget.v.twoFactorStatus();
      if (!mounted) return;
      setState(() {
        _enabled = s['enabled'] == true;
        _remaining = (s['recoveryCodesRemaining'] as num?)?.toInt() ?? 0;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ApiException.from(e).message;
      });
    }
  }

  Future<void> _startSetup() async {
    try {
      final s = await widget.v.setupTwoFactor();
      if (!mounted) return;
      setState(() {
        _secret = '${s['secret']}';
        _uri = '${s['otpAuthUri']}';
        _error = null;
      });
    } catch (e) {
      if (mounted) toast(context, ApiException.from(e).message, error: true);
    }
  }

  Future<void> _enable() async {
    final code = _code.text.trim();
    if (code.isEmpty) {
      toast(context, 'Enter the six-digit code.', error: true);
      return;
    }
    try {
      final codes = await widget.v.enableTwoFactor(code);
      if (!mounted) return;
      await _showRecoveryCodes(context, codes);
      await _load();
      if (mounted) toast(context, 'Two-factor authentication enabled.');
    } catch (e) {
      if (mounted) toast(context, ApiException.from(e).message, error: true);
    }
  }

  Future<void> _regenerate() async {
    final f = await formDialog(context, 'Regenerate Recovery Codes', [
      const FieldSpec('password', 'Account Password', kind: 'secret', required: true),
    ]);
    if (f == null) return;
    try {
      final codes = await widget.v.regenerateRecoveryCodes(f['password']!);
      if (!mounted) return;
      await _showRecoveryCodes(context, codes);
      await _load();
    } catch (e) {
      if (mounted) toast(context, ApiException.from(e).message, error: true);
    }
  }

  Future<void> _disable() async {
    final f = await formDialog(context, 'Disable Two-Factor', [
      const FieldSpec('password', 'Account Password', kind: 'secret', required: true),
      const FieldSpec('code', 'Authenticator or Recovery Code', required: true),
    ]);
    if (f == null) return;
    try {
      await widget.v.disableTwoFactor(f['password']!, f['code']!);
      await _load();
      if (mounted) toast(context, 'Two-factor authentication disabled.');
    } catch (e) {
      if (mounted) toast(context, ApiException.from(e).message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    Widget body;
    if (_loading) {
      body = const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_error != null) {
      body = Text(_error!, style: TextStyle(color: cs.error));
    } else if (_enabled) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user, color: cs.primary),
              const SizedBox(width: 8),
              Text('Enabled', style: t.titleMedium),
            ],
          ),
          const SizedBox(height: 8),
          Text('$_remaining recovery code${_remaining == 1 ? '' : 's'} remaining.'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _regenerate,
                icon: const Icon(Icons.refresh),
                label: const Text('New Recovery Codes'),
              ),
              OutlinedButton.icon(
                onPressed: _disable,
                icon: const Icon(Icons.shield_outlined),
                label: const Text('Disable'),
              ),
            ],
          ),
        ],
      );
    } else if (_secret == null) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Add Vaulton to an authenticator app. You will get a six-digit code to confirm setup.',
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _startSetup,
            icon: const Icon(Icons.qr_code_2),
            label: const Text('Start Setup'),
          ),
        ],
      );
    } else {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Enter this secret in your authenticator app:'),
          const SizedBox(height: 8),
          SelectableText(
            _secret!,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 18, letterSpacing: 1.5),
          ),
          const SizedBox(height: 8),
          Text(
            _uri ?? '',
            style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Six-digit code',
              prefixIcon: Icon(Icons.shield_outlined),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _enable,
            icon: const Icon(Icons.check),
            label: const Text('Enable Two-Factor'),
          ),
        ],
      );
    }

    return AlertDialog(
      title: const Text('Two-Factor Authentication'),
      content: SizedBox(width: 420, child: body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _ApiTokensDialog extends StatefulWidget {
  const _ApiTokensDialog({required this.v});
  final Vaulton v;

  @override
  State<_ApiTokensDialog> createState() => _ApiTokensDialogState();
}

class _ApiTokensDialogState extends State<_ApiTokensDialog> {
  List<Map<String, dynamic>> _tokens = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final tokens = await widget.v.apiTokens();
      if (!mounted) return;
      setState(() {
        _tokens = tokens;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ApiException.from(e).message;
      });
    }
  }

  Future<void> _create() async {
    final f = await formDialog(context, 'New API Token', [
      const FieldSpec('name', 'Name', required: true),
      const FieldSpec('days', 'Expires in days (optional)'),
    ]);
    if (f == null) return;

    final days = int.tryParse(f['days'] ?? '');
    try {
      final created = await widget.v.createApiToken(
        f['name']!,
        expiresInDays: days,
      );
      if (!mounted) return;
      final secret = '${created['secret']}';
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Token Created'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Copy this token now. It cannot be shown again.',
                ),
                const SizedBox(height: 12),
                SelectableText(
                  secret,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: secret));
                if (ctx.mounted) toast(ctx, 'Token copied.');
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      await _load();
    } catch (e) {
      if (mounted) toast(context, ApiException.from(e).message, error: true);
    }
  }

  Future<void> _revoke(Map<String, dynamic> token) async {
    if (!await confirm(
      context,
      'Revoke Token?',
      'Any script using "${token['name']}" will stop working immediately.',
      ok: 'Revoke',
      danger: true,
    )) {
      return;
    }
    try {
      await widget.v.revokeApiToken('${token['id']}');
      await _load();
      if (mounted) toast(context, 'Token revoked.');
    } catch (e) {
      if (mounted) toast(context, ApiException.from(e).message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget body;
    if (_loading) {
      body = const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_error != null) {
      body = Text(_error!, style: TextStyle(color: cs.error));
    } else if (_tokens.isEmpty) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('No API tokens yet. Create one for a script or integration.'),
      );
    } else {
      body = SizedBox(
        width: 480,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: _tokens.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final token = _tokens[i];
            final scopes = '${token['scopes'] ?? ''}';
            final expires = token['expiresAt'];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.key_outlined),
              title: Text('${token['name']}'),
              subtitle: Text(
                [
                  if (scopes.isNotEmpty) scopes,
                  if (expires != null) 'expires $expires',
                  if (token['lastUsedAt'] != null) 'last used ${token['lastUsedAt']}',
                ].join(' · '),
              ),
              trailing: IconButton(
                tooltip: 'Revoke',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _revoke(token),
              ),
            );
          },
        ),
      );
    }

    return AlertDialog(
      title: const Text('API Tokens'),
      content: SizedBox(width: 480, child: body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: _create,
          icon: const Icon(Icons.add),
          label: const Text('New Token'),
        ),
      ],
    );
  }
}
