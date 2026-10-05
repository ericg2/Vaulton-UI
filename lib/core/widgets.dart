import 'dart:async';
import 'package:flutter/material.dart';
import 'api_client.dart';
import 'models.dart';

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
          Icon(e.isForbidden ? Icons.lock_outline : Icons.error_outline, size: 40, color: cs.error),
          const SizedBox(height: 12),
          Text(e.message, textAlign: TextAlign.center),
          if (onRetry != null && !e.isForbidden) ...[
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
          ],
        ]),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView(this.text, {super.key, this.icon = Icons.inbox_outlined});
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 8),
          Text(text, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
        ]),
      );
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
  });
  final PageFetcher<T> fetch;
  final Widget Function(BuildContext, T item, int index) itemBuilder;
  final String empty;
  final IconData emptyIcon;
  final EdgeInsets? padding;
  final void Function(List<T> items)? onChanged;
  final Widget? header;

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

  @override
  void initState() {
    super.initState();
    load(reset: true);
    final d = widget.autoRefresh;
    if (d != null) {
      _timer = Timer.periodic(d, (_) {
        if (mounted && !_loading && TickerMode.of(context)) load(reset: true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> refresh() => load(reset: true);

  Future<void> load({bool reset = false}) async {
    if (_loading && !reset) return;
    final gen = ++_gen;
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
        if (reset) items.clear();
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
      return RefreshIndicator(onRefresh: refresh, child: ListView(children: [
      SizedBox(height: 300, child: EmptyView(widget.empty, icon: widget.emptyIcon))]));
    }
    final hdr = widget.header == null ? 0 : 1;
    return RefreshIndicator(
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
          if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (s.hasError) return ErrorView(s.error!, onRetry: _reload);
          return widget.builder(c, s.data as T, _reload);
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
    final over = max > 0 && used > max;
    final f = max > 0 ? (used / max).clamp(0, 1).toDouble() : null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: f,
        minHeight: 6,
        color: over ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }
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
