import 'package:flutter/material.dart';
import '../../core/util.dart';
import '../../platform/local_files.dart';

/// Opens the folder containing a downloaded file. When the OS cannot do that
/// (common on Android, where downloads live in app-private storage) a sheet
/// shows the exact location with a copy button instead of silently doing nothing.
Future<void> revealDownload(BuildContext context, String path) async {
  if (await localFiles.openContainingFolder(path)) return;
  if (!context.mounted) return;
  final exists = await localFiles.length(path) >= 0;
  if (!context.mounted) return;
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final t = Theme.of(ctx).textTheme;
      final cs = Theme.of(ctx).colorScheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(exists ? 'File Location' : 'File not found', style: t.titleLarge),
            const SizedBox(height: 8),
            Text(
              exists
                  ? 'This device cannot open the folder directly. The file is stored here:'
                  : 'The file is no longer at its original location. It may have been moved or deleted.',
              style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
              child: SelectableText(path, style: t.bodySmall?.copyWith(fontFamily: 'monospace')),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              FilledButton.tonalIcon(
                onPressed: () => copyText(ctx, path, 'Path copied'),
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy Path'),
              ),
              if (exists)
                OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await localFiles.open(path);
                    if (!ok && ctx.mounted) toast(ctx, 'No app can open this file', error: true);
                  },
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Open File'),
                ),
            ]),
          ]),
        ),
      );
    },
  );
}

/// Opens a downloaded file, telling the user when nothing can handle it.
Future<void> openDownload(BuildContext context, String path) async {
  final ok = await localFiles.open(path);
  if (!ok && context.mounted) toast(context, 'Cannot open this file. It may have been moved, or no app can handle its type.', error: true);
}
