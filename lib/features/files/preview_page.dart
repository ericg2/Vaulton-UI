import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../core/widgets.dart';

const _imageExt = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};
const _textExt = {'txt', 'md', 'json', 'log', 'csv', 'xml', 'yaml', 'yml', 'ini', 'conf', 'sh', 'dart', 'js', 'ts', 'py', 'html', 'css', 'toml', 'cfg'};

String extOf(String name) => name.contains('.') ? name.split('.').last.toLowerCase() : '';
bool canPreview(String name, int size) {
  final e = extOf(name);
  return (_imageExt.contains(e) && size <= 40 * 1024 * 1024) || (_textExt.contains(e) && size <= 1024 * 1024);
}

class PreviewPage extends ConsumerWidget {
  const PreviewPage({super.key, required this.pointId, required this.path, required this.name, this.onDownload, this.snapshotId});
  final String pointId, path, name;

  /// When set, [pointId] is a repository id and the file is read from that snapshot.
  final String? snapshotId;
  final VoidCallback? onDownload;

  Future<Uint8List> _load(WidgetRef ref) async {
    try {
      final r = await ref.read(apiClientProvider).dio.get<List<int>>(snapshotId != null ? '/repos/$pointId/snapshots/${Uri.encodeComponent(snapshotId!)}/content' : '/files/$pointId/content',
          queryParameters: {'path': path}, options: Options(responseType: ResponseType.bytes));
      return Uint8List.fromList(r.data!);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isImage = _imageExt.contains(extOf(name));
    return Scaffold(
      appBar: AppBar(title: Text(name, overflow: TextOverflow.ellipsis), actions: [
        if (onDownload != null) IconButton(icon: const Icon(Icons.download), tooltip: 'Download', onPressed: onDownload),
      ]),
      body: AsyncBody<Uint8List>(
        load: () => _load(ref),
        builder: (c, bytes, _) => isImage
            ? InteractiveViewer(maxScale: 8, child: Center(child: Image.memory(bytes, errorBuilder: (_, _, _) => const EmptyView('Cannot display this image', icon: Icons.broken_image))))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: SelectableText(utf8.decode(bytes, allowMalformed: true), style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
              ),
      ),
    );
  }
}
