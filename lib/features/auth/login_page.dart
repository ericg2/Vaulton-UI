import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/api_client.dart';
import '../../core/session.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});
  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  late final _url = TextEditingController(text: ref.read(sessionProvider).baseUrl);
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _new = TextEditingController();
  final _new2 = TextEditingController();
  final _key = GlobalKey<FormState>();
  bool _busy = false, _temp = false, _show = false;
  String? _pwTitle;

  @override
  void initState() {
    super.initState();
    final last = ref.read(accountsProvider).firstOrNull;
    if (last != null) {
      _url.text = last.url;
      _user.text = last.user;
    }
  }

  void _pick(SavedAccount a) => setState(() {
        _url.text = a.url;
        _user.text = a.user;
        _pass.clear();
        _temp = false;
        _error = null;
      });
  String? _error;

  Future<void> _submit() async {
    if (!_key.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).signIn(_url.text, _user.text.trim(), _pass.text,
          newPassword: _temp ? _new.text : null);
    } catch (e) {
      final ex = ApiException.from(e);
      setState(() {
        final text = '${ex.title ?? ''} ${ex.message}'.toLowerCase();
        if (ex.status == 403 && text.contains('password')) {
          // The server wants a permanent password before it will sign this account in.
          _temp = true;
          _pwTitle = 'Password Change Required';
          _error = null;
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
                selected: a.url == SessionStore.normalizeUrl(_url.text) && a.user.toLowerCase() == _user.text.trim().toLowerCase(),
                leading: CircleAvatar(radius: 16, child: Text(a.user.isEmpty ? '?' : a.user[0].toUpperCase())),
                title: Text(a.user),
                subtitle: Text(a.host),
                onTap: () => _pick(a),
                trailing: IconButton(
                  tooltip: 'Remove From List',
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
    final note = ref.watch(authProvider).message;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _key,
              child: AutofillGroup(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Icon(Icons.lock_outline_rounded, size: 56, color: cs.primary),
                  const SizedBox(height: 12),
                  Text('Vaulton', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 4),
                  Text('Sign In to Your Server', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 24),
                  _recent(cs),
                  if (note != null && _error == null)
                    Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(note, style: TextStyle(color: cs.tertiary))),
                  TextFormField(
                    controller: _url,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(labelText: 'Server Address', prefixIcon: Icon(Icons.dns_outlined), hintText: 'https://vault.example.com'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _user,
                    autofillHints: const [AutofillHints.username],
                    decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.person_outline)),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _pass,
                    obscureText: !_show,
                    autofillHints: const [AutofillHints.password],
                    onFieldSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: _temp ? 'Temporary Password' : 'Password',
                      prefixIcon: const Icon(Icons.key_outlined),
                      suffixIcon: IconButton(icon: Icon(_show ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _show = !_show)),
                    ),
                    validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  if (_temp) ...[
                    Container(
                      margin: const EdgeInsets.only(top: 16, bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: cs.tertiaryContainer, borderRadius: BorderRadius.circular(12)),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(Icons.lock_reset, color: cs.onTertiaryContainer),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(_pwTitle ?? 'Password Change Required', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: cs.onTertiaryContainer)),
                            Text('Choose a permanent password to finish signing in.', style: TextStyle(color: cs.onTertiaryContainer)),
                          ]),
                        ),
                      ]),
                    ),
                    TextFormField(
                      controller: _new,
                      obscureText: !_show,
                      decoration: const InputDecoration(labelText: 'New Password (Min 8 Characters)', prefixIcon: Icon(Icons.password)),
                      validator: (v) => (v == null || v.length < 8) ? 'At least 8 characters' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _new2,
                      obscureText: !_show,
                      decoration: const InputDecoration(labelText: 'Repeat New Password', prefixIcon: Icon(Icons.password)),
                      validator: (v) => v != _new.text ? 'Passwords do not match' : null,
                    ),
                  ],
                  if (_error != null)
                    Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: cs.error))),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: _busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Sign In'),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
