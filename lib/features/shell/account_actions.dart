import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/util.dart';
import '../transfers/transfer_manager.dart';

/// Signs out (after a confirmation if transfers are running) and returns to the
/// login screen, where previously used servers/accounts are listed for quick sign-in.
Future<void> signOutFlow(BuildContext context, WidgetRef ref) async {
  final busy = ref.read(transferProvider.notifier).hasActive;
  final ok = await confirm(
    context,
    'Sign Out?',
    busy ? 'Unfinished transfers will be cancelled. You can sign back in from the login screen.' : 'You can sign back in or switch accounts from the login screen.',
    ok: 'Sign Out',
    danger: busy,
  );
  if (!ok) return;
  ref.read(transferProvider.notifier).reset();
  await ref.read(authProvider.notifier).signOut();
}
