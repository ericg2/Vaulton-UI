import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../background/background_api.dart';
import '../../core/util.dart';
import '../../core/widgets.dart';
import '../../platform/local_files.dart';
import 'transfer_actions.dart';
import 'transfer_manager.dart';
import 'transfer_models.dart';

class TransfersPage extends ConsumerWidget {
  const TransfersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(transferProvider);
    final mgr = ref.read(transferProvider.notifier);
    final tasks = [...all]..sort((a, b) {
        int rank(TransferTask t) => t.state == TState.running ? 0 : t.state == TState.queued ? 1 : t.state == TState.failed ? 2 : 3;
        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : b.createdAt.compareTo(a.createdAt);
      });
    final active = tasks.where((t) => t.active).length;
    return Scaffold(
      appBar: AppBar(
        title: Text(active > 0 ? 'Transfers ($active active)' : 'Transfers'),
        actions: [
          if (active > 0) IconButton(tooltip: 'Cancel All', icon: const Icon(Icons.stop_circle_outlined), onPressed: mgr.cancelAll),
          IconButton(tooltip: 'Clear Finished', icon: const Icon(Icons.clear_all), onPressed: mgr.clearFinished),
        ],
      ),
      body: tasks.isEmpty
          ? const EmptyView('No Transfers Yet', icon: Icons.swap_vert, hint: 'Uploads and downloads appear here so you can follow, retry or cancel them.')
          : ListView.builder(
              itemCount: tasks.length + 1,
              itemBuilder: (c, i) {
                if (i == 0) {
                  return Column(children: [
                    if (backgroundSupported)
                      const HintBanner(id: 'transfers_bg', icon: Icons.cloud_sync_outlined, text: 'Unfinished transfers keep running in the background when you leave the app.')
                    else
                      const HintBanner(id: 'transfers_basic', text: 'Failed transfers retry automatically a few times. Use the refresh button to try again, or the trash icon to remove an entry.'),
                  ]);
                }
                final t = tasks[i - 1];
                return _TaskTile(key: ValueKey(t.id), task: t);
              },
            ),
    );
  }
}

class _TaskTile extends ConsumerWidget {
  const _TaskTile({super.key, required this.task});
  final TransferTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mgr = ref.read(transferProvider.notifier);
    final cs = Theme.of(context).colorScheme;
    final up = task.kind == TKind.upload;
    final exists = task.error?.toLowerCase().contains('exist') ?? false;
    final activityDate = task.state == TState.done ? (task.completedAt ?? task.createdAt) : task.createdAt;
    final date = fmtDate(activityDate);
    final sub = switch (task.state) {
      TState.running => '$date · ${fmtBytes(task.done)}${task.total > 0 ? ' of ${fmtBytes(task.total)}' : ''}',
      TState.queued => '$date · ${task.error ?? 'Waiting'}',
      TState.done => '$date · ${up ? 'Uploaded' : 'Downloaded'} ${fmtBytes(task.total)}',
      TState.failed => '$date · ${task.error ?? 'Failed'}',
      TState.canceled => '$date · Cancelled',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(up ? Icons.upload : Icons.download, color: task.state == TState.failed ? cs.error : cs.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(task.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: task.state == TState.failed ? cs.error : cs.onSurfaceVariant)),
              ]),
            ),
            if (task.origin != 'manual') chip(context, switch (task.origin) { 'photos' => 'Photos', 'snapshot' => 'Backup', _ => 'Folder sync' }),
            if (task.active) IconButton(icon: const Icon(Icons.close), tooltip: 'Cancel', onPressed: () => mgr.cancel(task.id)),
            if (task.state == TState.failed || task.state == TState.canceled) ...[
              if (exists && up) TextButton(onPressed: () => mgr.retry(task.id, overwrite: true), child: const Text('Overwrite')),
              IconButton(icon: const Icon(Icons.refresh), tooltip: 'Retry', onPressed: () => mgr.retry(task.id)),
            ],
            // Only finished downloads have something to open or reveal.
            if (!up && task.state == TState.done && task.localPath != null && localFiles.supportsFilesystem) ...[
              IconButton(icon: const Icon(Icons.open_in_new), tooltip: 'Open File', onPressed: () => openDownload(context, task.localPath!)),
              IconButton(icon: const Icon(Icons.folder_open), tooltip: 'Show in Folder', onPressed: () => revealDownload(context, task.localPath!)),
            ],
            if (!task.active) IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Remove', onPressed: () => mgr.remove(task.id)),
          ]),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: task.state == TState.running
                ? Padding(
                    padding: const EdgeInsets.only(right: 8, top: 6),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: task.fraction ?? 0),
                        duration: const Duration(milliseconds: 250),
                        builder: (_, v, _) => LinearProgressIndicator(value: task.fraction == null ? null : v, minHeight: 5),
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ]),
      ),
    );
  }
}
