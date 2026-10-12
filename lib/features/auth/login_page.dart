import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../core/wake.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});
  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat(reverse: true);
  final _passFocus = FocusNode();
  final _host = TextEditingController();
  final _port = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _new = TextEditingController();
  final _new2 = TextEditingController();
  final _key = GlobalKey<FormState>();
  bool _busy = false, _temp = false, _show = false, _rememberPassword = false;
  // The host/port fields stay tucked away once a server is chosen; tap the server card to edit.
  bool _editServer = true;
  String _busyLabel = 'Signing In…';
  String? _pwTitle;
  String? _error;

  @override
  void dispose() {
    _breath.dispose();
    _passFocus.dispose();
    for (final c in [_host, _port, _user, _pass, _new, _new2]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final last = ref.read(accountsProvider).firstOrNull;
    if (last != null) {
      _setServerUrl(last.url);
      _user.text = last.user;
      _editServer = false;
      _loadSavedPassword(last.url, last.user);
    }
  }

  // ---------------------------------------------------------------- server helpers

  void _setServerUrl(String url) {
    final normalized = SessionStore.normalizeUrl(url);
    final uri = Uri.tryParse(normalized);
    if (uri == null) return;
    _host.text = uri.host.isEmpty ? normalized : uri.host;
    _port.text = uri.hasPort ? uri.port.toString() : '5141';
  }

  String _serverUrl() {
    final host = _host.text.trim();
    final port = _port.text.trim();
    if (host.isEmpty) return '';
    final current = SessionStore.normalizeUrl(ref.read(sessionProvider).baseUrl);
    final scheme = current.startsWith('https://') ? 'https' : 'http';
    return port.isEmpty ? '$scheme://$host' : '$scheme://$host:$port';
  }

  String? _currentHost() {
    final host = _host.text.trim();
    return host.isEmpty ? null : host;
  }

  String? _currentPort() {
    final port = _port.text.trim();
    return port.isEmpty ? null : port;
  }

  String _hostFor(String url) {
    final u = Uri.tryParse(SessionStore.normalizeUrl(url));
    return (u == null || u.host.isEmpty) ? url : u.host;
  }

  String? _portFor(String url) {
    final u = Uri.tryParse(SessionStore.normalizeUrl(url));
    return (u != null && u.hasPort) ? u.port.toString() : null;
  }

  Future<void> _loadSavedPassword(String url, String user) async {
    final pw = await ref.read(sessionProvider).savedPassword(url, user);
    if (!mounted) return;
    if (_serverUrl() == SessionStore.normalizeUrl(url) && _user.text.trim().toLowerCase() == user.trim().toLowerCase()) {
      setState(() {
        _pass.text = pw ?? '';
        _rememberPassword = pw != null && pw.isNotEmpty;
      });
    }
  }

  void _pick(SavedAccount a) {
    setState(() {
      _setServerUrl(a.url);
      _user.text = a.user;
      _pass.clear();
      _temp = false;
      _error = null;
      _rememberPassword = false;
    });
    _loadSavedPassword(a.url, a.user);
  }

  void _addServer() {
    setState(() {
      _host.clear();
      _port.text = '5141';
      _user.clear();
      _pass.clear();
      _temp = false;
      _error = null;
      _rememberPassword = false;
      _editServer = true;
    });
  }

  // ---------------------------------------------------------------- sheets

  void _help() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final t = Theme.of(ctx).textTheme;
        Widget tip(IconData i, String title, String body) => ListTile(leading: Icon(i), title: Text(title), subtitle: Text(body));
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 8), child: Text('Need Help Signing In?', style: t.titleLarge)),
            tip(Icons.storage, 'Server Address', 'Use the address your administrator gave you, e.g. 192.168.1.10 with port 5141. Servers you sign in to are saved for next time.'),
            tip(Icons.power_settings_new, 'Wake Support', 'If a server has a saved wake configuration, it is woken automatically before signing in.'),
            tip(Icons.wifi_off, 'Cannot Reach the Server', 'Check that you are on the right network (or VPN) and that the server is running.'),
            tip(Icons.key, 'Forgot Your Password', 'Ask an administrator to reset it. You will then sign in with a temporary password and choose a new one.'),
            const SizedBox(height: 8),
          ]),
        );
      },
    );
  }

  void _serversSheet() {
    final session = ref.read(sessionProvider);
    final accounts = ref.read(accountsProvider).toList();
    // One entry per distinct server, keeping the order accounts were last used in.
    final servers = <String, List<SavedAccount>>{};
    for (final a in accounts) {
      servers.putIfAbsent(SessionStore.normalizeUrl(a.url), () => []).add(a);
    }
    final currentUrl = SessionStore.normalizeUrl(_serverUrl());
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final t = Theme.of(ctx).textTheme;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 8), child: Text('Saved Servers', style: t.titleLarge)),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final e in servers.entries)
                    ListTile(
                      selected: e.key == currentUrl,
                      leading: Icon(e.key == currentUrl ? Icons.check_circle : Icons.storage),
                      title: Text(_hostFor(e.key)),
                      subtitle: Row(children: [
                        Flexible(child: Text(e.value.length == 1 ? e.value.first.user : '${e.value.length} Accounts', overflow: TextOverflow.ellipsis)),
                        if (_portFor(e.key) != null) ...[const SizedBox(width: 10), Text('Port ${_portFor(e.key)}', style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant))],
                      ]),
                      trailing: _wakePill(session.hasWakeConfigFor(e.key), cs, t),
                      onTap: () {
                        Navigator.pop(ctx);
                        _pick(e.value.first);
                      },
                    ),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('Add Another Server'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _addServer();
                    },
                  ),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------- submit

  Future<void> _submit() async {
    if (_host.text.trim().isEmpty && !_editServer) {
      // Reveal the (empty) server fields so the validator has something to point at.
      setState(() => _editServer = true);
      WidgetsBinding.instance.addPostFrameCallback((_) => _key.currentState?.validate());
      return;
    }
    if (!_key.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _busyLabel = 'Signing In…';
      _error = null;
    });
    // Grab everything we need up front: signing in swaps this page out.
    final session = ref.read(sessionProvider);
    final auth = ref.read(authProvider.notifier);
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      final username = _user.text.trim();
      final url = _serverUrl();
      final password = _temp ? _new.text : _pass.text;
      final remember = _rememberPassword;
      // Set the target URL before checking readiness so automatic wake targets the
      // address entered on this screen, not a previously saved server.
      await session.setBaseUrl(url);
      if (!_temp && session.hasWakeConfigFor(url)) {
        setState(() => _busyLabel = 'Waking Server…');
        final ready = await WakeService.ensureReady(ApiClient(session));
        if (!ready) {
          if (mounted) {
            setState(() => _error = 'The server did not come online. Check your network and wake configuration, then try again.');
          }
          return;
        }
      }
      if (mounted) setState(() => _busyLabel = 'Signing In…');
      // signIn() swaps this screen out on success, so only captured values are used afterwards.
      await auth.signIn(url, username, _pass.text, newPassword: _temp ? _new.text : null);
      TextInput.finishAutofillContext();
      if (remember) {
        await session.savePassword(url, username, password);
      } else {
        await session.deleteSavedPassword(url, username);
      }
    } catch (e) {
      if (!mounted) return;
      final ex = ApiException.from(e);
      setState(() {
        final text = '${ex.title ?? ''} ${ex.message}'.toLowerCase();
        if (ex.status == 403 && text.contains('password')) {
          // The server wants a permanent password before it will sign this account in.
          _temp = true;
          _pwTitle = 'Password Change Required';
          _error = null;
        } else if (ex.status == 401) {
          _error = 'Incorrect username or password.';
        } else {
          _error = ex.message;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------- widgets

  Widget _wakePill(bool on, ColorScheme cs, TextTheme t) {
    final fg = on ? cs.onPrimaryContainer : cs.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: on ? cs.primaryContainer : Colors.transparent,
        border: on ? null : Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(on ? Icons.power_settings_new : Icons.power_off, size: 14, color: fg),
        const SizedBox(width: 4),
        Text(on ? 'Wake Ready' : 'No Wake', style: t.labelSmall?.copyWith(color: fg)),
      ]),
    );
  }

  Widget _serverCard(ColorScheme cs, TextTheme t, bool wakeConfigured, bool hasSaved) {
    final label = _currentHost();
    final port = _currentPort();
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ListTile(
            onTap: () => setState(() => _editServer = !_editServer),
            leading: const Icon(Icons.storage),
            title: Text(label ?? 'Add a Server', maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: label == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(children: [
                      _wakePill(wakeConfigured, cs, t),
                      if (port != null) ...[const SizedBox(width: 10), Text('Port $port', style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant))],
                    ]),
                  ),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (hasSaved) IconButton(tooltip: 'Saved Servers', icon: const Icon(Icons.unfold_more), onPressed: _serversSheet),
              Icon(_editServer ? Icons.expand_less : Icons.edit, size: 20),
              const SizedBox(width: 4),
            ]),
          ),
          if (_editServer)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: TextFormField(
                    controller: _host,
                    onChanged: (_) => setState(() {}),
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: 'Server Address', hintText: '192.168.1.10', isDense: true),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your server address' : null,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 88,
                  child: TextFormField(
                    controller: _port,
                    onChanged: (_) => setState(() {}),
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Port', hintText: '5141', isDense: true),
                    validator: (v) {
                      final value = v?.trim() ?? '';
                      if (value.isEmpty) return null;
                      final port = int.tryParse(value);
                      return port == null || port < 1 || port > 65535 ? 'Invalid port' : null;
                    },
                  ),
                ),
              ]),
            ),
        ]),
      ),
    );
  }

  /// Saved accounts for the server currently selected, as removable chips.
  Widget _accountChips(ColorScheme cs) {
    final current = SessionStore.normalizeUrl(_serverUrl());
    final mine = ref.watch(accountsProvider).where((a) => SessionStore.normalizeUrl(a.url) == current).take(6).toList();
    if (mine.isEmpty) return const SizedBox.shrink();
    final typed = _user.text.trim().toLowerCase();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(spacing: 8, runSpacing: 4, children: [
        for (final a in mine)
          InputChip(
            avatar: CircleAvatar(child: Text(a.user.isEmpty ? '?' : a.user[0].toUpperCase(), style: const TextStyle(fontSize: 11))),
            label: Text(a.user),
            selected: a.user.toLowerCase() == typed,
            showCheckmark: false,
            onPressed: () => _pick(a),
            deleteIcon: const Icon(Icons.close, size: 16),
            deleteButtonTooltipMessage: 'Forget This Account',
            onDeleted: () => ref.read(accountsProvider.notifier).forget(a),
          ),
      ]),
    );
  }

  Widget _banner(ColorScheme cs, IconData icon, Color bg, Color fg, Widget child, {EdgeInsets margin = EdgeInsets.zero}) => Container(
        margin: margin,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 10),
          Expanded(child: child),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final note = ref.watch(authProvider.select((a) => a.message));
    final hasSaved = ref.watch(accountsProvider).isNotEmpty;
    final wakeConfigured = ref.watch(sessionProvider).hasWakeConfigFor(_serverUrl());
    const gap = SizedBox(height: 12);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: (box.maxHeight - 16).clamp(0.0, double.infinity)),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Form(
                    key: _key,
                    child: AutofillGroup(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        // Compact header: logo + title on the left, help on the right.
                        Row(children: [
                          AnimatedBuilder(
                            animation: _breath,
                            builder: (_, child) => Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: cs.primaryContainer,
                                boxShadow: [BoxShadow(color: cs.primary.withValues(alpha: 0.08 + 0.12 * _breath.value), blurRadius: 8 + 12 * _breath.value, spreadRadius: 1.5 * _breath.value)],
                              ),
                              child: child,
                            ),
                            child: Icon(Icons.lock_outline_rounded, size: 22, color: cs.onPrimaryContainer),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('Vaulton', style: t.titleLarge),
                              Text('Sign In to Your Server', style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                            ]),
                          ),
                          IconButton(tooltip: 'Help', icon: const Icon(Icons.help), onPressed: _help),
                        ]),
                        const SizedBox(height: 16),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child: (note != null && _error == null)
                              ? _banner(cs, Icons.info, cs.tertiaryContainer, cs.onTertiaryContainer, Text(note, style: TextStyle(color: cs.onTertiaryContainer)), margin: const EdgeInsets.only(bottom: 12))
                              : const SizedBox(width: double.infinity),
                        ),
                        _serverCard(cs, t, wakeConfigured, hasSaved),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child: _accountChips(cs),
                        ),
                        gap,
                        TextFormField(
                          controller: _user,
                          onChanged: (_) => setState(() {}),
                          autofillHints: const [AutofillHints.username],
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          onFieldSubmitted: (_) => _passFocus.requestFocus(),
                          decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.person)),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your username' : null,
                        ),
                        gap,
                        TextFormField(
                          controller: _pass,
                          focusNode: _passFocus,
                          obscureText: !_show,
                          autofillHints: const [AutofillHints.password],
                          textInputAction: _temp ? TextInputAction.next : TextInputAction.done,
                          onFieldSubmitted: (_) => _temp ? null : _submit(),
                          decoration: InputDecoration(
                            labelText: _temp ? 'Temporary Password' : 'Password',
                            prefixIcon: const Icon(Icons.key),
                            suffixIcon: IconButton(
                              tooltip: _show ? 'Hide Password' : 'Show Password',
                              icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
                              onPressed: () => setState(() => _show = !_show),
                            ),
                          ),
                          validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
                        ),
                        // Password-change section slides open when the server asks for it.
                        AnimatedSize(
                          duration: const Duration(milliseconds: 320),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child: !_temp
                              ? const SizedBox(width: double.infinity)
                              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                  _banner(
                                    cs,
                                    Icons.lock_reset,
                                    cs.tertiaryContainer,
                                    cs.onTertiaryContainer,
                                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(_pwTitle ?? 'Password Change Required', style: t.titleSmall?.copyWith(color: cs.onTertiaryContainer)),
                                      Text('Enter the temporary password above, then choose a permanent one.', style: t.bodySmall?.copyWith(color: cs.onTertiaryContainer)),
                                    ]),
                                    margin: const EdgeInsets.only(top: 12, bottom: 12),
                                  ),
                                  TextFormField(
                                    controller: _new,
                                    obscureText: !_show,
                                    textInputAction: TextInputAction.next,
                                    decoration: const InputDecoration(labelText: 'New Password', prefixIcon: Icon(Icons.password), helperText: 'At least 8 characters'),
                                    validator: (v) => (v == null || v.length < 8) ? 'At least 8 characters' : null,
                                  ),
                                  gap,
                                  TextFormField(
                                    controller: _new2,
                                    obscureText: !_show,
                                    textInputAction: TextInputAction.done,
                                    onFieldSubmitted: (_) => _submit(),
                                    decoration: const InputDecoration(labelText: 'Repeat New Password', prefixIcon: Icon(Icons.password)),
                                    validator: (v) => v != _new.text ? 'Passwords do not match' : null,
                                  ),
                                ]),
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: _rememberPassword,
                          onChanged: (v) => setState(() => _rememberPassword = v ?? false),
                          title: const Text('Remember Password on This Device'),
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child: _error == null
                              ? const SizedBox(width: double.infinity)
                              : _banner(cs, Icons.error, cs.errorContainer, cs.onErrorContainer, Text(_error!, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onErrorContainer)), margin: const EdgeInsets.only(bottom: 4)),
                        ),
                        const SizedBox(height: 8),
                        FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: _busy
                                  ? Row(key: const ValueKey('busy'), mainAxisSize: MainAxisSize.min, children: [const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)), const SizedBox(width: 10), Text(_busyLabel)])
                                  : Text(_temp ? 'Change Password and Sign In' : 'Sign In', key: ValueKey(_temp)),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}