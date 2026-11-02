import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';

class TemporaryPasswordChangePage extends ConsumerStatefulWidget {
  const TemporaryPasswordChangePage({
    super.key,
    required this.username,
    required this.serverUrl,
    required this.temporaryPassword,
    required this.rememberPassword,
  });

  final String username;
  final String serverUrl;
  final String temporaryPassword;
  final bool rememberPassword;

  @override
  ConsumerState<TemporaryPasswordChangePage> createState() =>
      _TemporaryPasswordChangePageState();
}

class _TemporaryPasswordChangePageState
    extends ConsumerState<TemporaryPasswordChangePage> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(authProvider.notifier).signIn(
            widget.serverUrl,
            widget.username,
            widget.temporaryPassword,
            newPassword: _password.text,
          );
      if (!mounted) return;

      final session = ref.read(sessionProvider);
      try {
        if (widget.rememberPassword) {
          await session.savePassword(
            widget.serverUrl,
            widget.username,
            _password.text,
          );
        } else {
          await session.deleteSavedPassword(
            widget.serverUrl,
            widget.username,
          );
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'You are signed in, but the password could not be saved.',
              ),
            ),
          );
        }
      }

      TextInput.finishAutofillContext();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _error = ApiException.from(e).message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Change Password')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight > 48
                    ? constraints.maxHeight - 48
                    : 0,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: _formKey,
                        child: AutofillGroup(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Icon(
                                Icons.lock_reset_rounded,
                                size: 40,
                                color: colors.primary,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Choose a New Password',
                                style: theme.textTheme.headlineSmall,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Your administrator issued a temporary password. '
                                'Choose a permanent password to finish signing in.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 24),
                              TextFormField(
                                controller: _password,
                                autofocus: true,
                                obscureText: !_showPassword,
                                autofillHints: const [AutofillHints.newPassword],
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  labelText: 'New Password',
                                  helperText: 'At least 8 characters.',
                                  prefixIcon: const Icon(Icons.password),
                                  suffixIcon: IconButton(
                                    tooltip: _showPassword
                                        ? 'Hide Password'
                                        : 'Show Password',
                                    onPressed: () => setState(
                                      () => _showPassword = !_showPassword,
                                    ),
                                    icon: Icon(
                                      _showPassword
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                    ),
                                  ),
                                ),
                                validator: (value) =>
                                    value == null || value.length < 8
                                        ? 'Use at least 8 characters.'
                                        : null,
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _confirmation,
                                obscureText: !_showPassword,
                                autofillHints: const [AutofillHints.newPassword],
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _submit(),
                                decoration: const InputDecoration(
                                  labelText: 'Confirm New Password',
                                  prefixIcon: Icon(Icons.password),
                                ),
                                validator: (value) =>
                                    value != _password.text
                                        ? 'Passwords do not match.'
                                        : null,
                              ),
                              if (_error != null) ...[
                                const SizedBox(height: 16),
                                Text(
                                  _error!,
                                  style: TextStyle(color: colors.error),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                              const SizedBox(height: 24),
                              FilledButton(
                                onPressed: _busy ? null : _submit,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  child: _busy
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text('Change Password and Sign In'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
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
