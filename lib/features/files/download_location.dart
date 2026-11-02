import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../core/providers.dart';
import '../../platform/local_files.dart';

/// Chooses the local base directory for a download. Android deliberately asks
/// every time so the user can choose Default or a custom folder without having
/// to change a global setting first.
Future<String?> chooseDownloadBase(BuildContext context, WidgetRef ref) async {
  if (kIsWeb) return '';
  final settings = ref.read(settingsProvider);
  final isAndroid = defaultTargetPlatform == TargetPlatform.android;
  if (!isAndroid) {
    return settings.downloadDir ?? await localFiles.downloadsDir();
  }

  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      Widget option({
        required String value,
        required IconData icon,
        required String title,
        required String description,
        bool recommended = false,
      }) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        color: recommended ? cs.secondaryContainer : null,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.pop(ctx, value),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(icon, color: recommended ? cs.onSecondaryContainer : cs.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(ctx).textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(description, style: Theme.of(ctx).textTheme.bodySmall),
                    ],
                  ),
                ),
                if (recommended)
                  Icon(Icons.check_circle, color: cs.onSecondaryContainer),
                if (!recommended) const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      );
      return AlertDialog(
        insetPadding: const EdgeInsets.all(16),
        title: const Text('Download Location'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Choose where the downloaded files should be saved.'),
              const SizedBox(height: 14),
              option(
                value: 'default',
                icon: Icons.download_outlined,
                title: 'Default Downloads Folder',
                description: 'Save to the standard Downloads folder on this device.',
                recommended: true,
              ),
              option(
                value: 'custom',
                icon: Icons.folder_open_outlined,
                title: 'Choose Another Folder',
                description: 'Pick a different folder for this download.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Cancel'),
          ),
        ],
      );
    },
  );
  if (choice == null || choice == 'cancel' || !context.mounted) return null;
  if (choice == 'default') return localFiles.downloadsDir();

  final picked = await FilePicker.getDirectoryPath(dialogTitle: 'Choose Download Folder');
  if (picked == null || picked.isEmpty) return null;
  // Dart File cannot write a SAF content URI directly. If a platform returns
  // one, fall back rather than creating an unusable transfer path.
  if (picked.startsWith('content://')) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('That folder can’t be used. Choose a regular folder.')));
    }
    return null;
  }
  return p.normalize(picked);
}
