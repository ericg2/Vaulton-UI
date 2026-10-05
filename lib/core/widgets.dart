import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_client.dart';
import 'models.dart';
import 'providers.dart';

class ErrorView extends StatelessWidget {
  const ErrorView(this.error, {super.key, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    final e = ApiException.from(error);
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(e.isForbidden ? Icons.lock_outline : (e.status == null ? Icons.cloud_off_outlined : Icons.error_outline), size: 36, color: cs.error),
          const SizedBox(height: 10),
          Text(e.message, textAlign: TextAlign.center, maxLines: 4, overflow: TextOverflow.ellipsis),
          if (e.status == null) ...[
            const SizedBox(height: 4),
            Text('Make sure the server is running and you are on the right network.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ],
          if (onRetry != null && !e.isForbidden) ...[
            const SizedBox(height: 12),
            FilledButton.tonalIcon(onPressed: onRetry, icon: const Icon(Icons.refresh, size: 18), label: const Text('Try Again')),
          ],
        ]),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView(this.text, {super.key, this.icon = Icons.inbox_outlined, this.hint});
  final String text;
  final IconData icon;

  /// Friendly "what to do next" line shown under the message.
  final String? hint;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: cs.outline),
          const SizedBox(height: 8),
          Text(text, textAlign: TextAlign.center, style: TextStyle(color: cs.outline)),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(hint!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.outline)),
          ],
        ]),
      ),
    );
  }
}

typedef PageFetcher<T> = Future<Paged<T>> Function(String? cursor);

/// Cursor-paginated list with pull-to-refresh and automatic "load more".
/// Give it a new [key] to reset it when filters change.
class CursorList<T> extends StatefulWidget {
  const CursorList({
    super.key,
    required this.fetch,
    required this.itemBuilder,
    this.empty = 'Nothing here yet',
    this.emptyIcon = Icons.inbox_outlined,
    this.padding,
    this.onChanged,
    this.header,
    this.autoRefresh,
    this.emptyHint,
  });
  final PageFetcher<T> fetch;
  final Widget Function(BuildContext, T item, int index) itemBuilder;
  final String empty;
  final IconData emptyIcon;
  final EdgeInsets? padding;
  final void Function(List<T> items)? onChanged;
  final Widget? header;

  /// Optional second line under the empty message explaining what to do next.
  final String? emptyHint;

  /// Silently reloads the first page on this interval while the list is visible.
  final Duration? autoRefresh;

  @override
  State<CursorList<T>> createState() => CursorListState<T>();
}

class CursorListState<T> extends State<CursorList<T>> {
  final List<T> items = [];
  String? _cursor;
  bool _hasMore = true, _loading = false;
  Object? _error;
  int _gen = 0;
  Timer? _timer;
  DateTime _lastUserScroll = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastRefresh = DateTime.fromMillisecondsSinceEpoch(0);
  int _firstPageSize = 0;
  bool _wasVisible = true, _loadedOnce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Coming back to this list (tab switch, or a pushed page was popped):
    // reload quietly so numbers such as data usage are never stale.
    final visible = TickerMode.of(context);
    if (visible && !_wasVisible && _loadedOnce) silentRefresh(force: true);
    _wasVisible = visible;
  }

  @override
  void initState() {
    super.initState();
    load(reset: true);
    final d = widget.autoRefresh;
    if (d != null) {
      _timer = Timer.periodic(d, (_) {
        if (!mounted || _loading || !TickerMode.of(context)) return;
        final now = DateTime.now();
        if (now.difference(_lastUserScroll) < const Duration(seconds: 6)) return;
        if (now.difference(_lastRefresh) < const Duration(seconds: 5)) return;
        // Polling only reloads page one; if the user has scrolled further, leave their list alone.
        if (items.length > _firstPageSize) return;
        silentRefresh();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> refresh() => load(reset: true);

  /// Refreshes the first page without clearing existing rows or showing a spinner.
  /// Used by background polling so the UI does not flicker.
  Future<void> silentRefresh({bool force = false}) async {
    if (_loading) return;
    if (!force && items.length > _firstPageSize && _firstPageSize > 0) return;
    final gen = ++_gen;
    _lastRefresh = DateTime.now();
    try {
      final page = await widget.fetch(null);
      if (!mounted || gen != _gen) return;
      setState(() {
        items
          ..clear()
          ..addAll(page.items);
        _firstPageSize = page.items.length;
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
        _error = null;
      });
      widget.onChanged?.call(List.unmodifiable(items));
    } catch (_) {
      // Keep the current list on a background refresh failure.
    }
  }

  Future<void> load({bool reset = false}) async {
    if (_loading && !reset) return;
    final gen = ++_gen;
    _lastRefresh = DateTime.now();
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _cursor = null;
        _hasMore = true;
      }
    });
    try {
      final page = await widget.fetch(reset ? null : _cursor);
      if (!mounted || gen != _gen) return;
      setState(() {
        _loadedOnce = true;
        if (reset) {
          items.clear();
          _firstPageSize = page.items.length;
        }
        items.addAll(page.items);
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
        _loading = false;
      });
      widget.onChanged?.call(List.unmodifiable(items));
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _error = e;
        _loading = false;
        _hasMore = false;
        if (reset) items.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && items.isEmpty) return ErrorView(_error!, onRetry: refresh);
    if (_loading && items.isEmpty) return const Center(child: CircularProgressIndicator());
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: refresh,
        child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
          if (widget.header != null) widget.header!,
          SizedBox(height: 300, child: FadeSlideIn(child: EmptyView(widget.empty, icon: widget.emptyIcon, hint: widget.emptyHint))),
        ]),
      );
    }
    final hdr = widget.header == null ? 0 : 1;
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollUpdateNotification || n is UserScrollNotification) {
          _lastUserScroll = DateTime.now();
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: refresh,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: widget.padding,
          itemCount: items.length + 1 + hdr,
          itemBuilder: (c, i) {
          if (hdr == 1 && i == 0) return widget.header!;
          i -= hdr;
          if (i < items.length) return widget.itemBuilder(c, items[i], i);
          if (_hasMore) {
            if (!_loading) WidgetsBinding.instance.addPostFrameCallback((_) => load());
            return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
          }
          if (_error != null) return TextButton(onPressed: () => load(), child: const Text('Failed to Load More — Retry'));
          return const SizedBox(height: 88);
          },
        ),
      ),
    );
  }
}

/// Loads a future once (re-load with [reload]) and shows loading / error / data.
class AsyncBody<T> extends StatefulWidget {
  const AsyncBody({super.key, required this.load, required this.builder});
  final Future<T> Function() load;
  final Widget Function(BuildContext, T data, Future<void> Function() reload) builder;
  @override
  State<AsyncBody<T>> createState() => _AsyncBodyState<T>();
}

class _AsyncBodyState<T> extends State<AsyncBody<T>> {
  late Future<T> _f = widget.load();
  Future<void> _reload() async {
    setState(() => _f = widget.load());
    try {
      await _f;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: _f,
        builder: (c, s) {
          final Widget child;
          if (s.connectionState != ConnectionState.done) {
            child = const Center(key: ValueKey('loading'), child: CircularProgressIndicator());
          } else if (s.hasError) {
            child = KeyedSubtree(key: const ValueKey('error'), child: ErrorView(s.error!, onRetry: _reload));
          } else {
            child = KeyedSubtree(key: const ValueKey('data'), child: widget.builder(c, s.data as T, _reload));
          }
          return AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: child);
        },
      );
}

class Section extends StatelessWidget {
  const Section(this.title, {super.key, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
          child: Text(title.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Theme.of(context).colorScheme.primary, letterSpacing: 1)),
        ),
        ...children,
      ]);
}

class UsageBar extends StatelessWidget {
  const UsageBar({super.key, required this.used, required this.max});
  final int used, max;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final over = max > 0 && used > max;
    final f = max > 0 ? (used / max).clamp(0, 1).toDouble() : null;
    // Warn before it is full: amber-ish tertiary at 90%, red when over quota.
    final color = over ? cs.error : (f != null && f >= 0.9 ? cs.tertiary : null);
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: f == null
          ? const LinearProgressIndicator(value: 0, minHeight: 6)
          : TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: f),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: 6, color: color),
            ),
    );
  }
}

/// Fades and slides its child in once when first built; [delay] staggers siblings.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({super.key, required this.child, this.delay = Duration.zero, this.offset = const Offset(0, 0.06)});
  final Widget child;
  final Duration delay;
  final Offset offset;
  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  Timer? _t;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      _t = Timer(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _a,
        child: SlideTransition(position: Tween<Offset>(begin: widget.offset, end: Offset.zero).animate(_a), child: widget.child),
      );
}

Widget chip(BuildContext c, String text, {Color? color, IconData? icon}) {
  final cs = Theme.of(c).colorScheme;
  return Container(
    margin: const EdgeInsets.only(right: 6, top: 4),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: (color ?? cs.secondaryContainer), borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null) ...[Icon(icon, size: 12), const SizedBox(width: 4)],
      Text(text, style: Theme.of(c).textTheme.labelSmall),
    ]),
  );
}


/// Small dismissible tip. Once closed it stays hidden (remembered per [id]).
class HintBanner extends ConsumerStatefulWidget {
  const HintBanner({super.key, required this.id, required this.text, this.icon = Icons.lightbulb_outline});
  final String id, text;
  final IconData icon;
  @override
  ConsumerState<HintBanner> createState() => _HintBannerState();
}

class _HintBannerState extends ConsumerState<HintBanner> {
  late bool _hidden = ref.read(prefsProvider).getBool('hint_${widget.id}') ?? false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: _hidden
          ? const SizedBox(width: double.infinity)
          : Container(
              margin: const EdgeInsets.fromLTRB(12, 6, 12, 4),
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              decoration: BoxDecoration(color: cs.secondaryContainer.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Icon(widget.icon, size: 18, color: cs.onSecondaryContainer),
                const SizedBox(width: 10),
                Expanded(child: Text(widget.text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSecondaryContainer))),
                IconButton(
                  tooltip: 'Dismiss Tip',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close, size: 16, color: cs.onSecondaryContainer),
                  onPressed: () {
                    ref.read(prefsProvider).setBool('hint_${widget.id}', true);
                    setState(() => _hidden = true);
                  },
                ),
              ]),
            ),
    );
  }
}
