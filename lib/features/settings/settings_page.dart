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
const kAppVersion = '1.3.19';

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
                    final f = await formDialog(
                      context,
                      'Edit Profile',
                      [
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
                      ],
                      intro: 'Update your name and email address.',
                    );
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
                      'Use fewer transfers on slower or limited connections.',
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
                subtitle: const Text('Updates the password used for shared folders and signs out your other sessions.'),
                onTap: () async {
                  final f = await formDialog(
                    context,
                    'Change Password',
                    [
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
                    ],
                    ok: 'Change Password',
                    intro: 'Choose at least 8 characters; if you have encrypted Data Folders, use at least 12. Changing it signs out your other sessions and also updates the password used for shared folders.',
                  );
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
                    ref.read(authProvider.notifier).updateAccountPassword(f['new']!);
                    final rememberedUser = session.userName;
                    if (rememberedUser != null &&
                        await session.savedPassword(session.baseUrl, rememberedUser) != null) {
                      await session.savePassword(session.baseUrl, rememberedUser, f['new']!);
                    }
                    if (context.mounted) toast(context, 'Password changed.');
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: const Text('Two-Factor Authentication'),
                subtitle: const Text('Use an authenticator app and recovery codes.'),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => _TwoFactorDialog(v: v),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.key_outlined),
                title: const Text('API Tokens'),
                subtitle: const Text('For scripts and integrations.'),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => _ApiTokensDialog(
                    v: v,
                    availableScopes: u?.scopes ?? const [],
                  ),
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
      insetPadding: const EdgeInsets.all(16),
      title: const Text('Recovery Codes'),
      content: SizedBox(
        width: 420,
        height: (MediaQuery.sizeOf(ctx).height -
                MediaQuery.viewInsetsOf(ctx).bottom -
                220)
            .clamp(180.0, 520.0)
            .toDouble(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.shield_outlined),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Save these codes somewhere private. Each code works once, and they cannot be viewed again after closing this window.',
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
                  color: Theme.of(ctx).colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    codes.join('\n'),
                    style: const TextStyle(fontFamily: 'monospace', height: 1.7),
                  ),
                ),
              ),
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
    final f = await formDialog(
      context,
      'Regenerate Recovery Codes',
      [
        const FieldSpec('password', 'Account Password', kind: 'secret', required: true),
      ],
      ok: 'Regenerate Codes',
      intro: 'Your current recovery codes will stop working. Store the new codes somewhere safe; they are shown only once.',
    );
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
    final f = await formDialog(
      context,
      'Disable Two-Factor Authentication',
      [
        const FieldSpec('password', 'Account Password', kind: 'secret', required: true),
        const FieldSpec('code', 'Authenticator or Recovery Code', required: true),
      ],
      ok: 'Disable Two-Factor',
      intro: 'This removes the extra sign-in verification from your account. Enter your password and a current authenticator or recovery code to continue.',
    );
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
          Text(
            '1. Open your authenticator app and add a new account.',
            style: t.bodyMedium,
          ),
          const SizedBox(height: 6),
          Text(
            '2. Enter this setup key, then type the six-digit code from the app.',
            style: t.bodyMedium,
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText(
              _secret!,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 18,
                letterSpacing: 1.5,
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () => copyText(context, _secret!, 'Setup key copied.'),
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copy Setup Key'),
                ),
                if (_uri != null)
                  TextButton.icon(
                    onPressed: () => copyText(context, _uri!, 'Setup link copied.'),
                    icon: const Icon(Icons.link),
                    label: const Text('Copy Setup Link'),
                  ),
              ],
            ),
          ),
          TextField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(
              labelText: 'Six-digit code',
              prefixIcon: Icon(Icons.shield_outlined),
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _enable,
            icon: const Icon(Icons.check),
            label: const Text('Verify and Enable'),
          ),
        ],
      );
    }

    return AlertDialog(
      title: const Text('Two-Factor Authentication'),
      insetPadding: const EdgeInsets.all(16),
      content: SizedBox(
        width: 420,
        height: (MediaQuery.sizeOf(context).height -
                MediaQuery.viewInsetsOf(context).bottom -
                200)
            .clamp(120.0, 520.0)
            .toDouble(),
        child: SingleChildScrollView(child: body),
      ),
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
  const _ApiTokensDialog({required this.v, required this.availableScopes});
  final Vaulton v;
  final List<String> availableScopes;

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
    try {
      final allScopes = await widget.v.scopes();
      if (!mounted) return;
      final allowedScopes = allScopes
          .where((scope) => widget.availableScopes.contains(scope.name))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      if (allowedScopes.isEmpty) {
        toast(context, 'No API token permissions are available for this account.', error: true);
        return;
      }

      final draft = await showDialog<_ApiTokenDraft>(
        context: context,
        builder: (_) => _CreateApiTokenDialog(scopes: allowedScopes),
      );
      if (draft == null || !mounted) return;

      final created = await widget.v.createApiToken(
        draft.name,
        scopes: draft.scopes,
        expiresInDays: draft.expiresInDays,
      );
      if (!mounted) return;
      final secret = '${created['secret']}';
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          insetPadding: const EdgeInsets.all(16),
          title: const Text('Token Created'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.key_outlined),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Copy this token and store it securely. Vaulton cannot show it again after this dialog closes.',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SelectableText(
                    secret,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
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

    final maxHeight = (MediaQuery.sizeOf(context).height -
            MediaQuery.viewInsetsOf(context).bottom -
            200)
        .clamp(160.0, 560.0)
        .toDouble();
    return AlertDialog(
      insetPadding: const EdgeInsets.all(16),
      title: const Text('API Tokens'),
      content: SizedBox(
        width: 500,
        height: maxHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.key_outlined),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'API tokens let scripts and integrations access Vaulton. Give each token only the permissions it needs, and revoke it if it is no longer used.',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(child: body),
          ],
        ),
      ),
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

class _ApiTokenDraft {
  const _ApiTokenDraft({
    required this.name,
    required this.scopes,
    required this.expiresInDays,
  });

  final String name;
  final List<String> scopes;
  final int? expiresInDays;
}

class _CreateApiTokenDialog extends StatefulWidget {
  const _CreateApiTokenDialog({required this.scopes});

  final List<({String name, String description})> scopes;

  @override
  State<_CreateApiTokenDialog> createState() => _CreateApiTokenDialogState();
}

class _CreateApiTokenDialogState extends State<_CreateApiTokenDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _days = TextEditingController();
  final Set<String> _selected = {};

  @override
  void dispose() {
    _name.dispose();
    _days.dispose();
    super.dispose();
  }

  void _create() {
    if (!_formKey.currentState!.validate() || _selected.isEmpty) return;
    final scopes = _selected.toList()..sort();
    Navigator.of(context).pop(
      _ApiTokenDraft(
        name: _name.text.trim(),
        scopes: scopes,
        expiresInDays: int.tryParse(_days.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final maxHeight = (MediaQuery.sizeOf(context).height -
            MediaQuery.viewInsetsOf(context).bottom -
            180)
        .clamp(120.0, 600.0)
        .toDouble();

    return AlertDialog(
      title: const Text('New API Token'),
      content: SizedBox(
        width: 520,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _name,
                    autofocus: true,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Token Name',
                      hintText: 'For example, nightly backup',
                    ),
                    validator: (value) =>
                        value == null || value.trim().isEmpty
                            ? 'Enter a name for this token.'
                            : null,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Permissions',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Choose only the access this integration needs. '
                    'The token cannot have more permissions than your account.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                  for (final scope in widget.scopes)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _selected.contains(scope.name),
                      title: Text(scope.name),
                      subtitle: Text(scope.description),
                      onChanged: (checked) => setState(() {
                        if (checked == true) {
                          _selected.add(scope.name);
                        } else {
                          _selected.remove(scope.name);
                        }
                      }),
                    ),
                  if (_selected.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Select at least one permission.',
                        style: TextStyle(color: colors.error),
                      ),
                    ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _days,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Expires In Days (Optional)',
                      helperText: 'Leave blank for no expiration. Use 1–365 days.',
                    ),
                    validator: (value) {
                      final raw = value?.trim() ?? '';
                      if (raw.isEmpty) return null;
                      final days = int.tryParse(raw);
                      return days == null || days < 1 || days > 365
                          ? 'Enter a value from 1 to 365.'
                          : null;
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selected.isEmpty ? null : _create,
          child: const Text('Create Token'),
        ),
      ],
    );
  }
}
