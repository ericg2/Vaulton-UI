import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/util.dart';
import '../../platform/local_files.dart';
import 'transfer_actions.dart';
import 'transfer_manager.dart';
import 'transfer_models.dart';

/// Opens a bottom sheet that follows the given downloads live: overall progress,
/// the first few files, and Open / Show in Folder once they finish. The sheet can
/// be swiped away at any time; downloads keep running and stay in Transfers.
Future<void> showDownloadSheet(BuildContext context, List<String> taskIds, {VoidCallback? onOpenTransfers}) {
  if (taskIds.isEmpty) return Future.value();
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => _DownloadSheet(ids: taskIds.toSet(), onOpenTransfers: onOpenTransfers),
  );
}

class _DownloadSheet extends ConsumerWidget {
  const _DownloadSheet({required this.ids, this.onOpenTransfers});
  final Set<String> ids;
  final VoidCallback? onOpenTransfers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final tasks = ref.watch(transferProvider).where((x) => ids.contains(x.id)).toList();
    final mgr = ref.read(transferProvider.notifier);
    if (tasks.isEmpty) {
      return const SafeArea(child: Padding(padding: EdgeInsets.all(24), child: Text('These downloads were removed from the list.')));
    }
    final active = tasks.where((x) => x.active).length;
    final failed = tasks.where((x) => x.state == TState.failed).length;
    final done = tasks.where((x) => x.state == TState.done).toList();
    final total = tasks.fold<int>(0, (a, x) => a + x.total);
    final received = tasks.fold<int>(0, (a, x) => a + (x.state == TState.done && x.total > 0 ? x.total : x.done));
    final fraction = total > 0 ? (received / total).clamp(0, 1).toDouble() : null;
    final finished = active == 0;
    final single = tasks.length == 1 ? tasks.first : null;
    final canReveal = localFiles.supportsFilesystem && done.isNotEmpty && done.first.localPath != null;

    final title = !finished
        ? (tasks.length == 1 ? 'Downloading…' : 'Downloading ${math.min(tasks.length - active + 1, tasks.length)} of ${tasks.length}…')
        : failed > 0
            ? '$failed Download${failed == 1 ? '' : 's'} Failed'
            : 'Download complete';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
              child: !finished
                  ? SizedBox(key: const ValueKey('run'), width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3, value: fraction))
                  : Icon(failed > 0 ? Icons.error_outline : Icons.check_circle, key: ValueKey('end$failed'), size: 28, color: failed > 0 ? cs.error : cs.primary),
            ),
            const SizedBox(width: 14),
            Expanded(child: AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: Text(title, key: ValueKey(title), style: t.titleLarge))),
          ]),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: finished ? 1.0 : (fraction ?? 0)),
              duration: const Duration(milliseconds: 300),
              builder: (_, v, _) => LinearProgressIndicator(value: fraction == null && !finished ? null : v, minHeight: 6),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            total > 0 ? '${fmtBytes(received)} of ${fmtBytes(total)}' : (finished ? '' : 'Starting…'),
            style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          for (final x in tasks.take(4))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Icon(
                  switch (x.state) {
                    TState.done => Icons.check_circle_outline,
                    TState.failed => Icons.error_outline,
                    TState.canceled => Icons.cancel_outlined,
                    _ => Icons.download,
                  },
                  size: 18,
                  color: x.state == TState.failed ? cs.error : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(x.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyMedium)),
                const SizedBox(width: 8),
                Text(
                  switch (x.state) {
                    TState.done => 'Done',
                    TState.failed => 'Failed',
                    TState.canceled => 'Cancelled',
                    TState.queued => 'Waiting',
                    TState.running => x.fraction == null ? '…' : '${(x.fraction! * 100).round()}%',
                  },
                  style: t.labelSmall?.copyWith(color: x.state == TState.failed ? cs.error : cs.onSurfaceVariant),
                ),
              ]),
            ),
          if (tasks.length > 4) Padding(padding: const EdgeInsets.only(top: 2), child: Text('+ ${tasks.length - 4} more', style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant))),
          if (failed > 0 && single?.error != null)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text(single!.error!, maxLines: 3, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: cs.error))),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (!finished) OutlinedButton.icon(onPressed: () { for (final x in tasks.where((x) => x.active)) { mgr.cancel(x.id); } }, icon: const Icon(Icons.close, size: 18), label: const Text('Cancel')),
            if (failed > 0) FilledButton.tonalIcon(onPressed: () { for (final x in tasks.where((x) => x.state == TState.failed)) { mgr.retry(x.id); } }, icon: const Icon(Icons.refresh, size: 18), label: const Text('Retry')),
            if (finished && canReveal && done.length == 1 && done.first.localPath != null)
              FilledButton.icon(onPressed: () => openDownload(context, done.first.localPath!), icon: const Icon(Icons.open_in_new, size: 18), label: const Text('Open')),
            if (finished && canReveal)
              OutlinedButton.icon(onPressed: () => revealDownload(context, done.first.localPath!), icon: const Icon(Icons.folder_open, size: 18), label: const Text('Show in Folder')),
            if (onOpenTransfers != null)
              TextButton(onPressed: () { Navigator.pop(context); onOpenTransfers!(); }, child: const Text('All Transfers')),
            TextButton(onPressed: () => Navigator.pop(context), child: Text(finished ? 'Done' : 'Hide')),
          ]),
          if (!finished)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Downloads continue in Transfers if you close this.', style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ),
        ]),
      ),
    );
  }
}
