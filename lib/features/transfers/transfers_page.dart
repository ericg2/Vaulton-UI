import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../background/background_api.dart';
import '../../core/util.dart';
import '../../core/widgets.dart';
import '../../platform/local_files.dart';
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
          ? const EmptyView('No transfers', icon: Icons.swap_vert)
          : ListView(children: [
              if (backgroundSupported)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text('Unfinished transfers keep running in the background when you leave the app.', style: TextStyle(fontSize: 12)),
                ),
              for (final t in tasks) _TaskTile(task: t),
            ]),
    );
  }
}

class _TaskTile extends ConsumerWidget {
  const _TaskTile({required this.task});
  final TransferTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mgr = ref.read(transferProvider.notifier);
    final cs = Theme.of(context).colorScheme;
    final up = task.kind == TKind.upload;
    final exists = task.error?.toLowerCase().contains('exist') ?? false;
    final sub = switch (task.state) {
      TState.running => '${fmtBytes(task.done)}${task.total > 0 ? ' of ${fmtBytes(task.total)}' : ''}',
      TState.queued => task.error ?? 'Waiting',
      TState.done => 'Done · ${fmtBytes(task.total)}',
      TState.failed => task.error ?? 'Failed',
      TState.canceled => 'Cancelled',
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
            if (task.state == TState.done && !up && task.localPath != null && localFiles.supportsFilesystem)
              IconButton(icon: const Icon(Icons.open_in_new), tooltip: 'Open', onPressed: () => localFiles.open(task.localPath!)),
            if (!task.active) IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Remove', onPressed: () => mgr.remove(task.id)),
          ]),
          if (task.state == TState.running)
            Padding(padding: const EdgeInsets.only(right: 8, top: 6), child: LinearProgressIndicator(value: task.fraction)),
        ]),
      ),
    );
  }
}
