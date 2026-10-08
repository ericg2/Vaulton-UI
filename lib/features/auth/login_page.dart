import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/api_client.dart';
import '../../core/session.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});
  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> with TickerProviderStateMixin {
  late final AnimationController _in = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..forward();
  late final AnimationController _breath = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat(reverse: true);
  final _passFocus = FocusNode();
  late final _host = TextEditingController();
  late final _port = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _new = TextEditingController();
  final _new2 = TextEditingController();
  final _key = GlobalKey<FormState>();
  bool _busy = false, _temp = false, _show = false, _rememberPassword = false;
  String? _pwTitle;

  @override
  void dispose() {
    _in.dispose();
    _breath.dispose();
    _passFocus.dispose();
    for (final c in [_host, _port, _user, _pass, _new, _new2]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Staggered fade + slide-up used for every block of the form.
  Widget _stagger(int i, Widget child) {
    final start = (i * 0.09).clamp(0.0, 0.7).toDouble();
    final end = (start + 0.4).clamp(0.0, 1.0).toDouble();
    final a = _in.drive(CurveTween(curve: Interval(start, end, curve: Curves.easeOutCubic)));
    return FadeTransition(
      opacity: a,
      child: SlideTransition(position: a.drive(Tween(begin: const Offset(0, 0.12), end: Offset.zero)), child: child),
    );
  }

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

  void _help() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final t = Theme.of(ctx).textTheme;
        Widget tip(IconData i, String title, String body) => ListTile(
              leading: Icon(i),
              title: Text(title),
              subtitle: Text(body),
            );
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 8), child: Text('Need help signing in?', style: t.titleLarge)),
            tip(Icons.dns_outlined, 'Server address', 'Use the address your administrator gave you, e.g. https://vault.example.com or 192.168.1.10:5141. Without a scheme, http:// is assumed.'),
            tip(Icons.wifi_off_outlined, 'Cannot reach the server', 'Check that you are on the right network (or VPN) and that the server is running.'),
            tip(Icons.key_outlined, 'Forgot your password', 'Ask an administrator to reset it. You will then sign in with a temporary password and choose a new one.'),
            const SizedBox(height: 8),
          ]),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    final last = ref.read(accountsProvider).firstOrNull;
    if (last != null) {
      _setServerUrl(last.url);
      _user.text = last.user;
      _loadSavedPassword(last.url, last.user);
    }
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
  String? _error;

  Future<void> _submit() async {
    if (!_key.currentState!.validate()) return;
    setState(() {
      _busy = true;
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
          _pwTitle = 'Password change required';
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

  Widget _recent(ColorScheme cs) {
    final list = ref.watch(accountsProvider);
    if (list.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text('Recent Accounts', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Column(children: [
            for (final a in list.take(5))
              ListTile(
                dense: true,
                selected: a.url == SessionStore.normalizeUrl(_serverUrl()) && a.user.toLowerCase() == _user.text.trim().toLowerCase(),
                leading: CircleAvatar(radius: 16, child: Text(a.user.isEmpty ? '?' : a.user[0].toUpperCase())),
                title: Text(a.user),
                subtitle: Text(a.host),
                onTap: () => _pick(a),
                trailing: IconButton(
                  tooltip: 'Remove from List',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => ref.read(accountsProvider.notifier).forget(a),
                ),
              ),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final note = ref.watch(authProvider.select((a) => a.message));
    final t = Theme.of(context).textTheme;
    const gap = SizedBox(height: 12);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _key,
                child: AutofillGroup(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    // Logo: pops in, then gently breathes.
                    _stagger(
                      0,
                      Center(
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.5, end: 1),
                          duration: const Duration(milliseconds: 800),
                          curve: Curves.easeOutBack,
                          builder: (_, v, child) => Transform.scale(scale: v, child: child),
                          child: AnimatedBuilder(
                            animation: _breath,
                            builder: (_, child) => Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: cs.primaryContainer,
                                boxShadow: [BoxShadow(color: cs.primary.withValues(alpha: 0.10 + 0.14 * _breath.value), blurRadius: 14 + 18 * _breath.value, spreadRadius: 2 * _breath.value)],
                              ),
                              child: child,
                            ),
                            child: Icon(Icons.lock_outline_rounded, size: 32, color: cs.onPrimaryContainer),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _stagger(1, Text('Vaulton', textAlign: TextAlign.center, style: t.headlineSmall)),
                    const SizedBox(height: 4),
                    _stagger(1, Text('Sign in to your server', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant))),
                    const SizedBox(height: 16),
                    _stagger(2, AnimatedSize(duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic, alignment: Alignment.topCenter, child: _recent(cs))),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: (note != null && _error == null)
                          ? Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(color: cs.tertiaryContainer, borderRadius: BorderRadius.circular(12)),
                              child: Row(children: [
                                Icon(Icons.info_outline, size: 18, color: cs.onTertiaryContainer),
                                const SizedBox(width: 12),
                                Expanded(child: Text(note, style: TextStyle(color: cs.onTertiaryContainer))),
                              ]),
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                    _stagger(
                      3,
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          child: TextFormField(
                            controller: _host,
                            keyboardType: TextInputType.url,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              labelText: 'Server Address',
                              prefixIcon: Icon(Icons.dns_outlined),
                              hintText: '192.168.1.10',
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your server address' : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 104,
                          child: TextFormField(
                            controller: _port,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.next,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(labelText: 'Port', hintText: '5141'),
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
                    gap,
                    _stagger(
                      5,
                      TextFormField(
                        controller: _user,
                        autofillHints: const [AutofillHints.username],
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        onFieldSubmitted: (_) => _passFocus.requestFocus(),
                        decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.person_outline)),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your username' : null,
                      ),
                    ),
                    gap,
                    _stagger(
                      6,
                      TextFormField(
                        controller: _pass,
                        focusNode: _passFocus,
                        obscureText: !_show,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: _temp ? TextInputAction.next : TextInputAction.done,
                        onFieldSubmitted: (_) => _temp ? null : _submit(),
                        decoration: InputDecoration(
                          labelText: _temp ? 'Temporary Password' : 'Password',
                          prefixIcon: const Icon(Icons.key_outlined),
                          suffixIcon: IconButton(
                            tooltip: _show ? 'Hide Password' : 'Show Password',
                            icon: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              transitionBuilder: (c, a) => RotationTransition(turns: Tween<double>(begin: 0.85, end: 1).animate(a), child: FadeTransition(opacity: a, child: c)),
                              child: Icon(_show ? Icons.visibility_off : Icons.visibility, key: ValueKey(_show)),
                            ),
                            onPressed: () => setState(() => _show = !_show),
                          ),
                        ),
                        validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
                      ),
                    ),
                    // Password-change section slides open when the server asks for it.
                    AnimatedSize(
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: !_temp
                          ? const SizedBox(width: double.infinity)
                          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              Container(
                                margin: const EdgeInsets.only(top: 16, bottom: 12),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: cs.tertiaryContainer, borderRadius: BorderRadius.circular(12)),
                                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Icon(Icons.lock_reset, size: 20, color: cs.onTertiaryContainer),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(_pwTitle ?? 'Password Change Required', style: t.titleSmall?.copyWith(color: cs.onTertiaryContainer)),
                                      Text('Enter the temporary password, then choose a permanent one.', style: TextStyle(color: cs.onTertiaryContainer)),
                                    ]),
                                  ),
                                ]),
                              ),
                              TextFormField(
                                controller: _new,
                                obscureText: !_show,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(labelText: 'New Password', prefixIcon: Icon(Icons.password_outlined), helperText: 'At least 8 characters'),
                                validator: (v) => (v == null || v.length < 8) ? 'At least 8 characters' : null,
                              ),
                              gap,
                              TextFormField(
                                controller: _new2,
                                obscureText: !_show,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _submit(),
                                decoration: const InputDecoration(labelText: 'Repeat New Password', prefixIcon: Icon(Icons.password_outlined)),
                                validator: (v) => v != _new.text ? 'Passwords do not match' : null,
                              ),
                            ]),
                    ),
                    _stagger(
                      7,
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _rememberPassword,
                        onChanged: (v) => setState(() => _rememberPassword = v ?? false),
                        title: const Text('Remember Password'),
                        subtitle: const Text('Stored on this device.'),
                      ),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: _error == null
                            ? const SizedBox(width: double.infinity, key: ValueKey('noerr'))
                            : Container(
                                key: ValueKey(_error),
                                margin: const EdgeInsets.only(top: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(12)),
                                child: Row(children: [
                                  Icon(Icons.error_outline, size: 18, color: cs.onErrorContainer),
                                  const SizedBox(width: 12),
                                  Expanded(child: Text(_error!, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onErrorContainer))),
                                ]),
                              ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _stagger(
                      8,
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: _busy
                                ? const SizedBox(key: ValueKey('busy'), height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : Text(_temp ? 'Change Password and Sign In' : 'Sign In', key: ValueKey(_temp)),
                          ),
                        ),
                      ),
                    ),
                    _stagger(9, Center(child: TextButton.icon(onPressed: _help, icon: const Icon(Icons.help_outline), label: const Text('Need Help?')))),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
