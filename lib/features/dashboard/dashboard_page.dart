import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../core/scopes.dart';
import '../../core/util.dart';
import '../../core/widgets.dart';
import '../shell/server_badge.dart';
import 'dashboard_data.dart';
import 'dashboard_sections.dart';

/// Landing screen: health, storage, running work, recent jobs and quick actions.
///
/// Each section loads and rebuilds on its own, so a slow request only delays
/// its own part of the page instead of the whole screen.
class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key, this.onNavigate});

  /// Lets quick actions switch the shell to another section by label.
  final void Function(String label)? onNavigate;
  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  final _healthKey = GlobalKey();
  Timer? _poll;
  Timer? _debounce;
  bool _visible = true;

  bool get _canPower => ref.read(userProvider)?.has(Scopes.serverPower) ?? false;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _visible) _reload();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The dashboard sits under other pages (Files, Jobs...) and in a tab stack.
    // When it becomes visible again, reload right away so usage is never stale
    // after an upload, delete or backup done elsewhere.
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible == _visible) return;
    _visible = visible;
    if (visible) _reload();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  /// Asks every section for fresh data. The requests run in parallel and each
  /// section paints as soon as its own answer arrives.
  void _reload() {
    ref.invalidate(allPointsProvider);
    ref.invalidate(dashboardJobsProvider);
    ref.invalidate(dashboardHealthProvider);
    ref.invalidate(dashboardHasLocationsProvider);
  }

  /// Coalesces the burst of epoch bumps an upload produces into one reload.
  void _scheduleReload() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      if (mounted) _reload();
    });
  }

  Future<void> _refresh() async {
    _reload();
    await Future.wait([
      _ignore(ref.read(allPointsProvider.future)),
      _ignore(ref.read(dashboardJobsProvider.future)),
      _ignore(ref.read(dashboardHealthProvider.future)),
      _ignore(ref.read(dashboardHasLocationsProvider.future)),
    ]);
  }

  /// Waits for a provider without letting a failed request break the refresh.
  Future<void> _ignore(Future<Object?> future) async {
    try {
      await future;
    } catch (_) {}
  }

  Future<void> _requestPowerAction(String action, String label) async {
    final confirmed = await confirm(
      context,
      '$label Server?',
      'This will $action the Vaulton host. You will lose access until it is powered back on.',
      ok: label,
      danger: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await ref.read(vaultonProvider).requestPowerAction(action);
      if (mounted) toast(context, '$label request accepted. Check Administration → Configuration for the result.');
    } catch (e) {
      if (mounted) toast(context, ApiException.from(e).message, error: true);
    }
  }

  Future<void> _showHealth() async {
    final health = _healthKey.currentContext;
    if (health == null) {
      widget.onNavigate?.call('Administration');
      return;
    }
    await Scrollable.ensureVisible(
      health,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
      alignment: 0.08,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(epochProvider, (_, _) => _scheduleReload());
    final canPower = _canPower;

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard'), actions: [
        IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _reload),
      ]),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(0, 4, 0, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (MediaQuery.sizeOf(context).width < 800)
                  const Card(margin: EdgeInsets.fromLTRB(16, 4, 16, 4), child: ServerBadge(inline: true)),
                // Each section is its own repaint boundary: scrolling never
                // repaints the cards above or below it.
                const RepaintBoundary(child: DashboardGreeting()),
                const SizedBox(height: 12),
                RepaintBoundary(
                  child: DashboardStats(
                    onNavigate: (l) => widget.onNavigate?.call(l),
                    onShowHealth: _showHealth,
                  ),
                ),
                const SizedBox(height: 4),
                RepaintBoundary(child: DashboardSetup(onNavigate: _navigate)),
                if (canPower)
                  RepaintBoundary(child: _DashboardPower(onAction: _requestPowerAction)),
                RepaintBoundary(child: DashboardQuickActions(onNavigate: _navigate)),
                const RepaintBoundary(child: DashboardUsage()),
                RepaintBoundary(
                  child: KeyedSubtree(key: _healthKey, child: const DashboardHealth()),
                ),
                RepaintBoundary(child: DashboardActivity(onNavigate: _navigate)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  void _navigate(String label) => widget.onNavigate?.call(label);
}

/// Sleep, hibernate and shut down controls.
class _DashboardPower extends StatelessWidget {
  const _DashboardPower({required this.onAction});
  final void Function(String action, String label) onAction;

  @override
  Widget build(BuildContext context) {
    return Section('Server Power', children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            onPressed: () => onAction('sleep', 'Sleep'),
            icon: const Icon(Icons.bedtime_outlined),
            label: const Text('Sleep'),
          ),
          OutlinedButton.icon(
            onPressed: () => onAction('hibernate', 'Hibernate'),
            icon: const Icon(Icons.nights_stay_outlined),
            label: const Text('Hibernate'),
          ),
          FilledButton.tonalIcon(
            onPressed: () => onAction('shutdown', 'Shut Down'),
            icon: const Icon(Icons.power_settings_new_rounded),
            label: const Text('Shut Down'),
          ),
        ]),
      ),
    ]);
  }
}
