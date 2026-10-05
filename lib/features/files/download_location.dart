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
    builder: (ctx) => AlertDialog(
      title: const Text('Download location'),
      content: const Text('Choose where this download should be stored.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('Cancel')),
        OutlinedButton(onPressed: () => Navigator.pop(ctx, 'custom'), child: const Text('Choose folder')),
        FilledButton(onPressed: () => Navigator.pop(ctx, 'default'), child: const Text('Default')),
      ],
    ),
  );
  if (choice == null || choice == 'cancel' || !context.mounted) return null;
  if (choice == 'default') return localFiles.downloadsDir();

  final picked = await FilePicker.getDirectoryPath(dialogTitle: 'Choose download folder');
  if (picked == null || picked.isEmpty) return null;
  // Dart File cannot write a SAF content URI directly. If a platform returns
  // one, fall back rather than creating an unusable transfer path.
  if (picked.startsWith('content://')) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('That folder cannot be used directly. Please choose a normal device folder.')));
    }
    return null;
  }
  return p.normalize(picked);
}
