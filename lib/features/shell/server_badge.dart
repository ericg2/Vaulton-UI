import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/util.dart';
import '../../core/wake.dart';

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
    final info = ref.watch(serverInfoProvider).value;
    final user = ref.watch(userProvider);
    final host = info?.host ?? Uri.tryParse(ref.read(sessionProvider).baseUrl)?.authority ?? '';
    final ok = info?.reachable ?? true;
    final dot = Container(width: 9, height: 9, decoration: BoxDecoration(shape: BoxShape.circle, color: ok ? Colors.green : cs.error));
    final tip = [host, if (info?.version != null) 'Version ${info!.version}', if (info?.uptime != null) 'Up ${fmtDuration(info!.uptime!)}'].join(' · ');

    if (compact) {
      return Tooltip(
        message: tip,
        child: Stack(clipBehavior: Clip.none, children: [
          Icon(Icons.lock_outline_rounded, color: cs.primary, size: 30),
          Positioned(right: -3, bottom: -1, child: dot),
        ]),
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
        if (info?.uptime != null) Text('Uptime ${fmtDuration(info!.uptime!)}', style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        if (!ok && ref.read(sessionProvider).wakeToken?.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  try {
                    await WakeService.wake(ref.read(sessionProvider));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Wake request sent')),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Couldn’t wake server: $e')),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.power_settings_new_rounded),
                label: const Text('Wake Server'),
              ),
            ),
          ),
        if (user != null) Padding(padding: const EdgeInsets.only(top: 6), child: Row(children: [
          Icon(Icons.person_outline, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(child: Text(user.userName, overflow: TextOverflow.ellipsis, style: t.bodySmall)),
        ])),
      ]),
    );
  }
}
