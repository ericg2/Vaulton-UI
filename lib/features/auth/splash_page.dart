import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';

/// Shown while a saved session is being verified on app start. It replaces the
/// old behaviour of flashing the login form before jumping to the home screen.
class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});
  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();
  Timer? _slow;
  bool _showCancel = false;

  @override
  void initState() {
    super.initState();
    // If the server is slow, offer a way out instead of leaving the user stuck.
    _slow = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _showCancel = true);
    });
  }

  @override
  void dispose() {
    _slow?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final host = Uri.tryParse(ref.read(sessionProvider).baseUrl)?.authority ?? '';
    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.6, end: 1),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutBack,
            builder: (_, v, child) => Opacity(opacity: v.clamp(0, 1).toDouble(), child: Transform.scale(scale: v, child: child)),
            child: SizedBox(
              width: 120,
              height: 120,
              child: Stack(alignment: Alignment.center, children: [
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, _) => Container(
                    width: 72 + 48 * _pulse.value,
                    height: 72 + 48 * _pulse.value,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: cs.primary.withValues(alpha: 0.16 * (1 - _pulse.value))),
                  ),
                ),
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: cs.primaryContainer),
                  child: Icon(Icons.lock_outline_rounded, size: 38, color: cs.onPrimaryContainer),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 20),
          Text('Vaulton', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(host.isEmpty ? 'Signing You In…' : 'Connecting to $host…', style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 20),
          SizedBox(width: 120, child: ClipRRect(borderRadius: BorderRadius.circular(4), child: const LinearProgressIndicator(minHeight: 3))),
          const SizedBox(height: 16),
          AnimatedOpacity(
            opacity: _showCancel ? 1 : 0,
            duration: const Duration(milliseconds: 300),
            child: IgnorePointer(
              ignoring: !_showCancel,
              child: TextButton(onPressed: () => ref.read(authProvider.notifier).cancelRestore(), child: const Text('Taking Long? Cancel')),
            ),
          ),
        ]),
      ),
    );
  }
}
