import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../core/wake.dart';
import '../../core/util.dart';

/// Wakes the server (when a wake broker is configured) and refreshes status.
Future<void> wakeServerFromUi(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(content: Text('Waking server…'), duration: Duration(seconds: 3)));
  try {
    final ready = await WakeService.ensureReady(ApiClient(ref.read(sessionProvider)));
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(ready ? 'Server is awake.' : 'The server could not be reached after the wake request.')));
    ref.invalidate(serverInfoProvider);
  } catch (e) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text('Could not wake server: ${ApiException.from(e).message}')));
  }
}

class _WakeButton extends ConsumerStatefulWidget {
  const _WakeButton();
  @override
  ConsumerState<_WakeButton> createState() => _WakeButtonState();
}

class _WakeButtonState extends ConsumerState<_WakeButton> {
  bool _busy = false;
  Future<void> _go() async {
    setState(() => _busy = true);
    await wakeServerFromUi(context, ref);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final spinner = const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2));
    return TextButton.icon(
      onPressed: _busy ? null : _go,
      icon: _busy ? spinner : const Icon(Icons.power_settings_new_rounded, size: 18),
      label: const Text('Wake'),
    );
  }
}

/// Compact server identity: host, connection state, version and signed-in user.
class ServerBadge extends ConsumerWidget {
  const ServerBadge({super.key, this.compact = false, this.inline = false});
  final bool compact;

  /// Single-row variant that fills the available width (phone dashboard).
  final bool inline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final infoAsync = ref.watch(serverInfoProvider);
    final info = infoAsync.value;
    final user = ref.watch(userProvider);
    final host = info?.host ?? Uri.tryParse(ref.read(sessionProvider).baseUrl)?.authority ?? '';
    final ok = info?.reachable ?? !infoAsync.hasError;
    final canWake = !ok && ref.watch(sessionProvider).wakeToken?.isNotEmpty == true;
    final dot = Container(width: 9, height: 9, decoration: BoxDecoration(shape: BoxShape.circle, color: ok ? Colors.green : cs.error));
    final tip = [host, if (info?.version != null) 'Version ${info!.version}', if (info?.uptime != null) 'Up ${fmtDuration(info!.uptime!)}'].join(' · ');

    if (compact) {
      return Tooltip(
        message: canWake ? 'Server unreachable · tap to wake' : tip,
        child: InkWell(
          onTap: canWake ? () => wakeServerFromUi(context, ref) : null,
          child: Stack(clipBehavior: Clip.none, children: [
          Icon(Icons.lock_outline_rounded, color: cs.primary, size: 30),
          Positioned(right: -3, bottom: -1, child: dot),
        ]),
        ),
      );
    }
    if (inline) {
      final status = [ok ? 'Connected' : 'Unreachable', if (info?.version != null) 'v${info!.version}'].join(' · ');
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Icon(Icons.lock_outline_rounded, color: cs.primary, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(host.isEmpty ? 'Vaulton' : host, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall),
              Text(status, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
          const SizedBox(width: 12),
          if (canWake) const _WakeButton(),
          dot,
        ]),
      );
    }
    return Container(
      width: 220,
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.lock_outline_rounded, color: cs.primary, size: 28),
          const SizedBox(width: 10),
          Text('Vaulton', style: t.titleLarge),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          dot,
          const SizedBox(width: 8),
          Expanded(child: Text(host, overflow: TextOverflow.ellipsis, style: t.labelLarge)),
        ]),
        const SizedBox(height: 2),
        Text(
          [ok ? 'Connected' : 'Unreachable', if (info?.version != null) 'v${info!.version}', if (info?.environment != null) info!.environment!].join(' · '),
          style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        if (canWake) const Padding(padding: EdgeInsets.only(top: 6), child: _WakeButton()),
        if (info?.uptime != null) Text('Uptime ${fmtDuration(info!.uptime!)}', style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        if (user != null) Padding(padding: const EdgeInsets.only(top: 6), child: Row(children: [
          Icon(Icons.person_outline, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(child: Text(user.userName, overflow: TextOverflow.ellipsis, style: t.bodySmall)),
        ])),
      ]),
    );
  }
}
