import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/scopes.dart';
import '../../core/source_schemas.dart';
import '../../core/util.dart';
import '../../core/vaulton.dart';
import '../../core/widgets.dart';
import '../backups/backup_flow.dart';
import '../backups/jobs_page.dart';
import '../backups/repo_page.dart';
import '../backups/snapshot_browser.dart';
import '../files/files_page.dart';
import '../transfers/transfer_manager.dart';
import 'root_shares_page.dart';
import 'share_logic.dart';

/// Desktop / wide layout: a normal tabbed page.
class StoragePage extends StatelessWidget {
  const StoragePage({super.key, this.initialTab = 0});
  final int initialTab;
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    initialIndex: initialTab.clamp(0, 2).toInt(),
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Storage'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Data Folders'),
            Tab(text: 'Backup Vaults'),
            Tab(text: 'Locations'),
          ],
        ),
      ),
      body: const TabBarView(
        children: [PointsTab(repo: false), PointsTab(repo: true), RootsTab()],
      ),
    ),
  );
}

/// Height of the fixed Storage header (status bar + toolbar + tab strip).
double storageHeaderHeight(BuildContext context) =>
    MediaQuery.paddingOf(context).top + kToolbarHeight + 48;

/// Phone layout: each storage tab is its own page in the shell's PageView, so one
/// continuous swipe moves Dashboard > Files > Transfers > Data Folders > Backup Vaults >
/// Locations > More. The header is NOT part of the page: the shell draws one shared
/// [StorageHeader] that stays put while the three tab bodies slide underneath it.
class StorageSection extends StatelessWidget {
  const StorageSection({super.key, required this.index});
  final int index;
  @override
  Widget build(BuildContext context) => MediaQuery.removePadding(
    context: context,
    removeTop: true,
    child: Padding(
      padding: EdgeInsets.only(top: storageHeaderHeight(context)),
      child: switch (index) {
        0 => const PointsTab(repo: false),
        1 => const PointsTab(repo: true),
        _ => const RootsTab(),
      },
    ),
  );
}

/// Shared header for the three storage pages. It slides in/out with the page swipe
/// while moving between the storage pages and the neighbouring pages, but stays fixed
/// while swiping between the storage tabs themselves.
class StorageHeader extends StatelessWidget {
  const StorageHeader({
    super.key,
    required this.pages,
    required this.basePage,
    required this.onSelect,
  });
  final PageController pages;
  final int basePage;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final height = storageHeaderHeight(context);
    return AnimatedBuilder(
      animation: pages,
      builder: (context, child) {
        var p = pages.initialPage.toDouble();
        if (pages.hasClients && pages.position.haveDimensions) {
          p = pages.page ?? p;
        }
        final first = basePage.toDouble(), last = basePage + 2.0;
        final dx = p < first
            ? (first - p) * width
            : (p > last ? -(p - last) * width : 0.0);
        if (dx.abs() >= width) return const SizedBox.shrink();
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: SizedBox(
        height: height,
        width: width,
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          child: AppBar(
            title: const Text('Storage'),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: StorageTabStrip(
                pages: pages,
                basePage: basePage,
                onSelect: onSelect,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tab strip whose indicator follows the finger while the shell's pages are swiped.
class StorageTabStrip extends StatelessWidget {
  const StorageTabStrip({
    super.key,
    required this.pages,
    required this.basePage,
    required this.onSelect,
  });
  final PageController pages;
  final int basePage;
  final ValueChanged<int> onSelect;
  static const _labels = ['Data Folders', 'Backup Vaults', 'Locations'];

  double _position() {
    if (!pages.hasClients || !pages.position.haveDimensions) {
      return pages.initialPage.toDouble();
    }
    return pages.page ?? pages.initialPage.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 48,
      child: AnimatedBuilder(
        animation: pages,
        builder: (context, _) {
          final t = (_position() - basePage).clamp(0.0, 2.0);
          return LayoutBuilder(
            builder: (context, box) {
              final w = box.maxWidth / 3;
              const barW = 56.0;
              return Stack(
                children: [
                  Row(
                    children: [
                      for (var i = 0; i < 3; i++)
                        SizedBox(
                          width: w,
                          child: InkWell(
                            onTap: () => onSelect(i),
                            child: Center(
                              child: Text(
                                _labels[i],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(
                                      color: Color.lerp(
                                        cs.onSurfaceVariant,
                                        cs.primary,
                                        (1 - (t - i).abs()).clamp(0.0, 1.0),
                                      ),
                                    ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  Positioned(
                    left: t * w + (w - barW) / 2,
                    bottom: 0,
                    child: Container(
                      width: barW,
                      height: 3,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

// ================================================================== ROOTS
const typeLabels = <String, String>{
  'fs': 'Local Disk', 's3': 'Amazon S3', 'azblob': 'Azure Blob Storage',
  'azdls': 'Azure Data Lake Storage', 'azfile': 'Azure Files',
  'b2': 'Backblaze B2', 'gcs': 'Google Cloud Storage', 'gdrive': 'Google Drive',
  'onedrive': 'Microsoft OneDrive', 'dropbox': 'Dropbox', 'ftp': 'FTP Server',
  'webdav': 'WebDAV Server', 'pcloud': 'pCloud', 'alluxio': 'Alluxio',
  'cos': 'Cloud Object Storage', 'd1': 'Cloudflare D1', 'dbfs': 'Databricks File System',
};
String _sourceLabel(String scheme) => typeLabels[scheme] ?? pretty(scheme);
String _sourceDescription(String scheme) => {"fs":"Use a directory on the Vaulton server. Select a folder under /mnt.","s3":"Connect to an S3-compatible object storage service.","azblob":"Store files in an Azure Blob Storage container.","azdls":"Connect to an Azure Data Lake Storage filesystem.","azfile":"Connect to an Azure file share.","b2":"Connect to a Backblaze B2 bucket.","gcs":"Connect to a Google Cloud Storage bucket.","gdrive":"Connect to a Google Drive account.","onedrive":"Connect to a Microsoft OneDrive account.","dropbox":"Connect to a Dropbox account.","ftp":"Connect to an FTP server.","webdav":"Connect to a WebDAV server.","pcloud":"Connect to pCloud storage.","alluxio":"Connect to an Alluxio filesystem.","cos":"Connect to a compatible cloud object storage service.","d1":"Connect to a Cloudflare D1 database.","dbfs":"Connect to a Databricks File System."}[scheme] ?? 'Connect an external storage service.';

class RootsTab extends ConsumerStatefulWidget {
  const RootsTab({super.key});
  @override
  ConsumerState<RootsTab> createState() => _RootsTabState();
}

class _RootsTabState extends ConsumerState<RootsTab> {
  final _key = GlobalKey<CursorListState<Root>>();
  Vaulton get _v => ref.read(vaultonProvider);

  Future<String?> _pickLocalPath(String? initialPath) async {
    Json? current;
    var loading = true;
    var started = false;
    String? error;
    bool allowedPath(String path) =>
        (path == '/mnt' || path.startsWith('/mnt/')) &&
        !path.split('/').contains('..');
    final requestedPath = initialPath?.trim() ?? '';
    final startPath = allowedPath(requestedPath) ? requestedPath : '/mnt';

    Future<void> load(
      String? path,
      void Function(void Function()) update,
    ) async {
      if (path != null && !allowedPath(path)) return;
      update(() {
        loading = true;
        error = null;
      });
      try {
        final result = await _v.browseLocal(path);
        update(() {
          current = result;
          loading = false;
        });
      } catch (e) {
        update(() {
          error = e.toString();
          loading = false;
        });
      }
    }

    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, update) {
          if (current == null && loading && !started) {
            started = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (ctx.mounted && current == null && loading) {
                load(startPath.isEmpty ? null : startPath, update);
              }
            });
          }
          final dirs = (current?['directories'] as List? ?? const [])
              .map(toJson)
              .where((d) => allowedPath('${d['path'] ?? ''}'))
              .toList();
          final path = '${current?['currentPath'] ?? ''}';
          final parent = toStr(current?['parentPath']);
          final available = toInt(current?['availableBytes']);
          final total = toInt(current?['capacityBytes']);
          return AlertDialog(
            insetPadding: const EdgeInsets.all(16),
            title: const Text('Choose Server Directory'),
            content: SizedBox(
              width: double.maxFinite,
              height: (MediaQuery.sizeOf(ctx).height -
                      MediaQuery.viewInsetsOf(ctx).bottom -
                      200)
                  .clamp(120.0, 420.0)
                  .toDouble(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Choose a folder under /mnt. System directories are excluded.',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.folder_open_outlined),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            path.isEmpty ? '/mnt' : path,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(ctx).textTheme.titleSmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (available > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 8),
                      child: Text(
                        '${fmtBytes(available)} available of ${fmtBytes(total)}',
                        style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  const Divider(),
                  Expanded(
                    child: loading
                        ? const Center(child: CircularProgressIndicator())
                        : error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.folder_off_outlined,
                                    size: 32,
                                    color: Theme.of(ctx).colorScheme.error,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Could not load this directory.',
                                    style: Theme.of(ctx).textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    error!,
                                    textAlign: TextAlign.center,
                                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  OutlinedButton.icon(
                                    onPressed: () => load(path.isEmpty ? null : path, update),
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('Try Again'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : dirs.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.folder_open_outlined, size: 32),
                                SizedBox(height: 8),
                                Text('No subdirectories in this folder.'),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: dirs.length,
                            itemBuilder: (_, i) {
                              final d = dirs[i];
                              return ListTile(
                                dense: true,
                                leading: const Icon(Icons.folder_outlined),
                                title: Text(
                                  '${d['name']}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () => load('${d['path']}', update),
                              );
                            },
                          ),
                  ),
                  if (!loading && error == null)
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: path == '/mnt' || parent == null || parent.isEmpty || !allowedPath(parent)
                              ? null
                              : () => load(parent, update),
                          icon: const Icon(Icons.arrow_upward),
                          label: const Text('Parent Folder'),
                        ),
                        TextButton.icon(
                          onPressed: path.isEmpty
                              ? null
                              : () async {
                                  final name = await promptText(
                                    ctx,
                                    'New Folder',
                                    'Folder Name',
                                    ok: 'Create Folder',
                                    intro: 'Create a directory inside the selected server folder.',
                                  );
                                  if (name == null ||
                                      name.trim().isEmpty ||
                                      !ctx.mounted) {
                                    return;
                                  }
                                  try {
                                    await _v.createLocalDirectory(
                                      path,
                                      name.trim(),
                                    );
                                    await load(path, update);
                                  } catch (_) {
                                    if (ctx.mounted) {
                                      toast(
                                        ctx,
                                        'Could not create folder. Check the path and permissions.',
                                        error: true,
                                      );
                                    }
                                  }
                                },
                          icon: const Icon(Icons.create_new_folder_outlined),
                          label: const Text('New Folder'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: !allowedPath(path)
                    ? null
                    : () => Navigator.pop(dialogContext, path),
                icon: const Icon(Icons.check),
                label: const Text('Select Folder'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<Map<String, dynamic>?> _sourceForm(
    String scheme,
    Map<String, dynamic>? existing,
  ) async {
    final fields = kSourceSchemas[scheme]!;
    final r = await formDialog(
      context,
      '${_sourceLabel(scheme)} Connection',
      [
        for (final f in fields)
          FieldSpec(
            f.key,
            pretty(f.key),
            kind: scheme == 'fs' && f.key == 'root'
                ? 'path'
                : (f.kind == 'b'
                      ? 'bool'
                      : (f.kind == 'k' ? 'secret' : 'text')),
            required:
                f.required && f.kind != 'k' || (f.required && existing == null),
            initial: existing?[f.key] == null || f.kind == 'k'
                ? ''
                : '${existing![f.key]}',
          ),
      ],
      ok: existing != null ? 'Save Connection' : 'Continue',
      intro: '${_sourceDescription(scheme)} ${existing != null ? 'Leave secret fields blank to keep saved credentials.' : 'Enter the connection details below.'}',
      pick: scheme == 'fs' ? (values) => _pickLocalPath(values['root']) : null,
    );
    if (r == null) return null;
    if (scheme == 'fs') {
      final root = r['root']?.trim() ?? '';
      final valid = (root == '/mnt' || root.startsWith('/mnt/')) && !root.split('/').contains('..');
      if (!valid) {
        toast(context, 'Choose a directory under /mnt.', error: true);
        return null;
      }
    }
    final src = <String, dynamic>{'scheme': scheme};
    for (final f in fields) {
      final val = r[f.key]!;
      if (f.kind == 'b') {
        src[f.key] = val == 'true';
      } else if (val.isNotEmpty) {
        src[f.key] = val;
      }
    }
    return src;
  }

  Future<void> _create() async {
    final name = TextEditingController();
    var scheme = 'fs';
    var allowData = true;
    var allowRepo = true;
    final details = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final schemes = typeLabels.keys.where((s) => s != 'fs').toList()..sort();
          schemes.insert(0, 'fs');
          final cs = Theme.of(ctx).colorScheme;
          final tt = Theme.of(ctx).textTheme;
          return Padding(
            padding: EdgeInsets.fromLTRB(
              20, 4, 20, MediaQuery.viewInsetsOf(ctx).bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 25,
                        backgroundColor: cs.primaryContainer,
                        child: Icon(Icons.dns_outlined, color: cs.onPrimaryContainer),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('New Location', style: tt.headlineSmall),
                            const SizedBox(height: 2),
                            Text(
                              'Connect storage for your data folders and backup vaults.',
                              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Text('Location Name', style: tt.titleSmall),
                  const SizedBox(height: 8),
                  TextField(
                    controller: name,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setSheetState(() {}),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'e.g. Home Storage',
                      prefixIcon: Icon(Icons.drive_file_rename_outline),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('Storage Type', style: tt.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    'Choose where Vaulton should store your files.',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 300),
                    decoration: BoxDecoration(
                      border: Border.all(color: cs.outlineVariant),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: RadioGroup<String>(
                      groupValue: scheme,
                      onChanged: (value) {
                        if (value != null) setSheetState(() => scheme = value);
                      },
                      child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final item in schemes)
                          RadioListTile<String>(
                            value: item,
                            title: Text(_sourceLabel(item)),
                            subtitle: Text(
                              _sourceDescription(item),
                              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                      ],
                    ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('What Can This Location Hold?', style: tt.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    'You can change these permissions later.',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 6),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.folder_outlined),
                    title: const Text('Data Folders'),
                    subtitle: const Text('Store files that you upload and manage in Vaulton.'),
                    value: allowData,
                    onChanged: (value) => setSheetState(() => allowData = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.inventory_2_outlined),
                    title: const Text('Backup Vaults'),
                    subtitle: const Text('Store encrypted backup repositories.'),
                    value: allowRepo,
                    onChanged: (value) => setSheetState(() => allowRepo = value),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: name.text.trim().isEmpty
                              ? null
                              : () => Navigator.pop(sheetContext, {
                                  'name': name.text.trim(),
                                  'scheme': scheme,
                                  'data': allowData,
                                  'repo': allowRepo,
                                }),
                          icon: const Icon(Icons.arrow_forward),
                          label: const Text('Continue'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    name.dispose();
    if (details == null || !mounted) return;

    final selectedScheme = details['scheme'] as String;
    final src = await _sourceForm(selectedScheme, null);
    if (src == null || !mounted) return;

    Json? detected;
    if (selectedScheme == 'fs') {
      detected = await guarded(
        context,
        () => _v.browseLocal(src['root'] as String?),
      );
      if (detected == null || !mounted) return;
    }

    final available = toInt(detected?['availableBytes']);
    int? maxBytes;
    if (selectedScheme == 'fs' && available > 0) {
      maxBytes = await _capacityDialog(
        currentBytes: available,
        detected: detected,
        isLocal: true,
      );
    } else {
      final capacity = await formDialog(
        context,
        'Location Capacity',
        [
          FieldSpec(
            'capacity',
            'Location Capacity',
            kind: 'capacity',
            initial: '',
            required: true,
            initialUnit: 'GiB',
          ),
        ],
        ok: 'Create Location',
        intro: selectedScheme == 'fs'
            ? 'Vaulton could not detect available disk space. Set the maximum capacity it may allocate.'
            : 'Set the maximum capacity Vaulton may allocate to this remote location. Provider capacity cannot be detected reliably.',
      );
      if (capacity != null) maxBytes = int.tryParse(capacity['capacity'] ?? '');
    }
    if (maxBytes == null || maxBytes <= 0 || !mounted) return;

    final created = await guarded(
      context,
      () => _v.createRoot({
        'name': details['name'],
        'source': src,
        'maxBytes': maxBytes,
        'isDataAllowed': details['data'],
        'isRepoAllowed': details['repo'],
      }),
    );
    if (created != null) {
      _key.currentState?.refresh();
      if (mounted) toast(context, 'Location created.');
    }
  }

  Future<int?> _capacityDialog({required int currentBytes, Json? detected, required bool isLocal}) async {
    final available = toInt(detected?['availableBytes']);
    final total = toInt(detected?['capacityBytes']);
    if (!isLocal || available <= 0) {
      final result = await formDialog(
        context, 'Location Capacity',
        [FieldSpec('capacity', 'Capacity (GiB)', kind: 'capacity',
          initial: bytesToCapacity(currentBytes, 'GiB'), required: true,
          initialBytes: currentBytes, initialUnit: 'GiB')],
        ok: 'Save Capacity',
        intro: 'Remote storage capacity is a manual allocation limit. Vaulton cannot reliably detect the provider’s total capacity.',
      );
      if (result == null) return null;
      return int.tryParse(result['capacity'] ?? '');
    }
    var override = currentBytes > available;
    var value = currentBytes.clamp(1, available).toDouble();
    final custom = TextEditingController(text: bytesToGb(currentBytes));
    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Location Capacity'),
          content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Detected free space: ${fmtBytes(available)} of ${fmtBytes(total)}.'),
              const SizedBox(height: 12),
              Row(children: [const Expanded(child: Text('Allocated capacity')), Text(fmtBytes(override ? (int.tryParse(custom.text) ?? 0) * 1024 * 1024 * 1024 : value.round()))]),
              Slider(value: value, min: 1, max: available.toDouble().clamp(2, double.maxFinite).toDouble(),
                onChanged: override ? null : (v) => setDialogState(() => value = v)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero, title: const Text('Allow a custom limit'),
                subtitle: const Text('The limit may exceed currently available disk space.'),
                value: override, onChanged: (v) => setDialogState(() => override = v),
              ),
              if (override) TextField(
                controller: custom, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Custom capacity', suffixText: 'GiB'),
              ),
              if (override) Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Warning: Vaulton may allocate more space than the disk currently has free.',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              ),
            ],
          ))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(onPressed: () {
              final bytes = override
                ? ((double.tryParse(custom.text) ?? 0) * 1024 * 1024 * 1024).round()
                : value.round();
              if (bytes <= 0) return;
              Navigator.pop(dialogContext, bytes);
            }, child: const Text('Save')),
          ],
        ),
      ),
    );
    custom.dispose();
    return result;
  }

  Future<void> _edit(Root root) async {
    final scheme = '${root.source?['scheme'] ?? ''}';
    if (!kSourceSchemas.containsKey(scheme)) return toast(context, 'Unknown connection type.', error: true);
    final src = await _sourceForm(scheme, root.source);
    if (src == null || !mounted) return;
    Json? detected;
    if (scheme == 'fs') {
      detected = await guarded(context, () => _v.browseLocal(src['root'] as String?));
      if (detected == null || !mounted) return;
    }
    final r = await formDialog(context, 'Edit ${root.name}', [
      FieldSpec('name', 'Name', initial: root.name, required: true),
      FieldSpec('data', 'Allow Data Folders', kind: 'bool', initial: '${root.isDataAllowed}'),
      FieldSpec('repo', 'Allow Backup Vaults', kind: 'bool', initial: '${root.isRepoAllowed}'),
    ], ok: 'Save Location', intro: 'Update the connection and location settings.');
    if (r == null || !mounted) return;
    final maxBytes = await _capacityDialog(currentBytes: root.maxBytes, detected: detected, isLocal: scheme == 'fs');
    if (maxBytes == null || maxBytes <= 0 || !mounted) return;
    await guarded(context, () => _v.patchRoot(root.id, {
      'name': r['name'], 'source': src, 'maxBytes': maxBytes,
      'isDataAllowed': r['data'] == 'true', 'isRepoAllowed': r['repo'] == 'true',
    }));
    _key.currentState?.refresh();
  }

  Future<void> _shares(Root root) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => RootSharesPage(root: root)),
    );
    _key.currentState?.silentRefresh(force: true);
  }

  /// Tapping a location shows what it is, who can use it, and what you can do with it.
  void _openRoot(Root root) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (sheetCtx) {
        void then(VoidCallback run) {
          Navigator.pop(sheetCtx);
          run();
        }

        return _RootSheet(
          root: root,
          vaulton: _v,
          onShare: () => then(() => _shares(root)),
          onEdit: () => then(() => _edit(root)),
          onDelete: () => then(() => _delete(root)),
        );
      },
    );
  }

  Future<void> _delete(Root root) async {
    if (!await confirm(
      context,
      'Delete Location “${root.name}”?',
      'Not allowed while it still holds data folders or backup vaults. Files in the underlying storage are kept.',
      ok: 'Delete',
      danger: true,
    )) {
      return;
    }
    await guarded(context, () => _v.deleteRoot(root.id));
    _key.currentState?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      epochProvider,
      (_, _) => _key.currentState?.silentRefresh(force: true),
    );
    final u = ref.watch(userProvider)!;
    final canCreate = u.has(Scopes.rootsManage);
    return Scaffold(
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: const Text('New Location'),
            )
          : null,
      body: CursorList<Root>(
        key: _key,
        empty: 'No locations yet.',
        emptyHint: canCreate
            ? 'Add a location to connect a disk, network share, or cloud account.'
            : 'Ask an administrator to share a location with you.',
        emptyIcon: Icons.storage_outlined,
        autoRefresh: const Duration(seconds: 30),
        fetch: (c) => _v.roots(cursor: c),
        itemBuilder: (ctx, r, i) {
          final allocated = r.allocatedBytes;
          final scheme = '${r.source?['scheme'] ?? ''}';
          return Card(
            child: InkWell(
              onTap: () => _openRoot(r),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 4, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.dns_outlined,
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            r.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(ctx).textTheme.titleMedium,
                          ),
                        ),
                        if (r.isOwner)
                          PopupMenuButton<String>(
                            onSelected: (a) {
                              switch (a) {
                                case 'edit':
                                  _edit(r);
                                case 'share':
                                  _shares(r);
                                case 'del':
                                  _delete(r);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('Edit')),
                              PopupMenuItem(
                                value: 'share',
                                child: Text('Share'),
                              ),
                              PopupMenuDivider(),
                              PopupMenuItem(
                                value: 'del',
                                child: Text('Delete'),
                              ),
                            ],
                          ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Wrap(
                        children: [
                          if (scheme.isNotEmpty)
                            chip(ctx, _sourceLabel(scheme)),
                          chip(
                            ctx,
                            r.isOwner ? 'Owner' : 'Shared by ${r.userName}',
                          ),
                          if (r.isDataAllowed) chip(ctx, 'Data Folders'),
                          if (r.isRepoAllowed) chip(ctx, 'Backup Vaults'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (r.isOwner) ...[
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: UsageBar(used: allocated, max: r.maxBytes),
                      ),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Text(
                          '${fmtBytes(allocated)} allocated · ${fmtBytes(r.freeBytes)} free of ${fmtBytes(r.maxBytes)}',
                          style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ] else ...[
                      // Non-owners only see their own share: the bar shows the
                      // consumed portion (max minus free), not the free space.
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: UsageBar(
                          used: (r.maxBytes - r.freeBytes).clamp(0, r.maxBytes),
                          max: r.maxBytes,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.only(left: 34, right: 12),
                        child: Text(
                          'Available to you: ${fmtBytes(r.freeBytes)}',
                          style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ================================================================= POINTS
class PointsTab extends ConsumerStatefulWidget {
  const PointsTab({super.key, required this.repo});
  final bool repo;
  @override
  ConsumerState<PointsTab> createState() => _PointsTabState();
}

class _PointsTabState extends ConsumerState<PointsTab> {
  final _key = GlobalKey<CursorListState<Point>>();
  Vaulton get _v => ref.read(vaultonProvider);
  List<Root> _roots = const [];

  @override
  void initState() {
    super.initState();
    _loadRoots();
  }

  Future<void> _loadRoots() async {
    try {
      final roots = await _v.roots(limit: 200);
      if (mounted) setState(() => _roots = roots.items);
    } catch (_) {}
  }

  Future<void> _create() async {
    final roots = await guarded(context, () => _v.roots(limit: 200));
    if (roots == null || !mounted) return;
    final usable = roots.items
        .where((r) => widget.repo ? r.isRepoAllowed : r.isDataAllowed)
        .toList();
    if (usable.isEmpty) {
      return toast(
        context,
        'No location allows ${widget.repo ? 'backup vaults' : 'data folders'}. Add or share one first.',
        error: true,
      );
    }
    var encryptionEnabled = false;
    if (!widget.repo) {
      try {
        encryptionEnabled = await _v.dataFolderEncryptionEnabled();
      } catch (_) {}
    }
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) =>
          _NewPointSheet(repo: widget.repo, roots: usable, vaulton: _v, encryptionEnabled: encryptionEnabled),
    );
    if (created == true && mounted) {
      _key.currentState?.refresh();
      ref.invalidate(pointNamesProvider);
      ref.read(epochProvider.notifier).bump();
    }
  }

  Future<void> _edit(Point p) async {
    final root = await guarded(context, () => _v.root(p.rootId));
    if (root == null || !mounted) return;
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => _EditPointSheet(point: p, root: root, repo: widget.repo),
    );
    if (result == null || !mounted) return;
    final saved = await guarded(
      context,
      () =>
          widget.repo ? _v.patchRepo(p.id, result) : _v.patchData(p.id, result),
    );
    if (saved != null && mounted) {
      _key.currentState?.refresh();
      toast(
        context,
        '${widget.repo ? 'Backup vault' : 'Data folder'} updated.',
      );
    }
  }

  Future<void> _delete(Point p) async {
    if (!await confirm(
      context,
      'Delete “${p.name}”?',
      widget.repo
          ? 'Its schedules and job history are removed. Stored backups are kept.'
          : p.isEncrypted
              ? 'This removes the folder’s active encryption key from Vaulton. The encrypted files remain in the storage location and cannot be opened from this server. Older server backups may still contain the key, so this is not guaranteed cryptographic erasure. Copy anything you need before continuing.'
              : 'Its schedules are removed. Files in the underlying storage are kept.',
      ok: !widget.repo && p.isEncrypted ? 'Delete Permanently' : 'Delete',
      danger: true,
    )) {
      return;
    }
    final deleted = await guarded<bool>(context, () async {
      if (widget.repo) {
        await _v.deleteRepo(p.id);
      } else {
        await _v.deleteData(
          p.id,
          confirmEncryptedKeyRemoval: p.isEncrypted,
        );
      }
      return true;
    });
    if (deleted != true || !mounted) return;
    if (!widget.repo) ref.read(transferProvider.notifier).clearForPoint(p.id);
    _key.currentState?.refresh();
    ref.invalidate(pointNamesProvider);
    ref.read(epochProvider.notifier).bump();
  }

  @override
  Widget build(BuildContext context) {
    // Upload / delete / move finished somewhere else: refresh usage numbers in place.
    ref.listen(epochProvider, (_, _) {
      _key.currentState?.silentRefresh(force: true);
      _loadRoots();
    });
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: Text('New ${widget.repo ? 'Backup Vault' : 'Data Folder'}'),
      ),
      body: CursorList<Point>(
        key: _key,
        empty: 'No ${widget.repo ? 'backup vaults' : 'data folders'} yet.',
        emptyHint: widget.repo
            ? 'Create a backup vault in a storage location. You can choose it when you back up a data folder.'
            : 'Create a data folder in a storage location. You can upload files to it and choose it as the source for backups.',
        emptyIcon: widget.repo
            ? Icons.inventory_2_outlined
            : Icons.folder_outlined,
        autoRefresh: const Duration(seconds: 30),
        fetch: (c) => widget.repo ? _v.repos(cursor: c) : _v.datas(cursor: c),
        itemBuilder: (ctx, p, i) => _pointCard(ctx, p),
      ),
    );
  }

  void _openRepo(Point p, {int tab = 0}) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => RepoPage(repoId: p.id, repo: p, initialTab: tab),
    ),
  );

  Future<void> _unlockDataFolder(BuildContext ctx, Point point) async {
    final password = TextEditingController();
    final recovery = TextEditingController();
    var useRecovery = false;
    var busy = false;
    final result = await showDialog<bool>(
      context: ctx,
      builder: (dialogContext) => StatefulBuilder(builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('Unlock Data Folder'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!useRecovery) TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
          if (useRecovery) TextField(controller: recovery, obscureText: true, decoration: const InputDecoration(labelText: 'Recovery Key')),
          Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: busy ? null : () => setDialogState(() => useRecovery = !useRecovery), child: Text(useRecovery ? 'Use Password' : 'Use Recovery Key'))),
        ]),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: busy ? null : () async {
            setDialogState(() => busy = true);
            try {
              if (useRecovery) {
                await _v.recoverData(point.id, recovery.text.trim());
              } else {
                await _v.unlockData(point.id, password.text);
              }
              if (dialogContext.mounted) Navigator.pop(dialogContext, true);
            } catch (e) {
              setDialogState(() => busy = false);
              toast(dialogContext, e.toString(), error: true);
            }
          }, child: Text(busy ? 'Unlocking…' : 'Unlock')),
        ],
      )),
    );
    password.dispose();
    recovery.dispose();
    if (result == true && mounted) _key.currentState?.refresh();
  }

  Future<void> _changeDataPassword(BuildContext ctx, Point point) async {
    final currentPassword = TextEditingController();
    final newPassword = TextEditingController();
    final confirmPassword = TextEditingController();
    var busy = false;
    var error = '';

    final changed = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> submit() async {
            if (busy) return;
            if (currentPassword.text.isEmpty) {
              setDialogState(() => error = 'Enter the current password.');
              return;
            }
            if (newPassword.text.trim().isEmpty) {
              setDialogState(() => error = 'Enter a new password.');
              return;
            }
            if (newPassword.text.runes.length < 12) {
              setDialogState(() => error = 'Use at least 12 characters.');
              return;
            }
            if (newPassword.text != confirmPassword.text) {
              setDialogState(() => error = 'The new passwords do not match.');
              return;
            }
            setDialogState(() {
              busy = true;
              error = '';
            });
            try {
              await _v.changeDataPassword(
                point.id,
                currentPassword.text,
                newPassword.text,
              );
              if (dialogContext.mounted) Navigator.pop(dialogContext, true);
            } catch (e) {
              setDialogState(() {
                busy = false;
                error = e.toString();
              });
            }
          }

          return PopScope(
            canPop: !busy,
            child: AlertDialog(
              title: const Text('Change Data Folder Password'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: currentPassword,
                    obscureText: true,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Current Password'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: newPassword,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'New Password'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmPassword,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Confirm New Password'),
                    onSubmitted: (_) => submit(),
                  ),
                  if (error.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        error,
                        style: TextStyle(color: Theme.of(dialogContext).colorScheme.error),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Your files are not re-encrypted. Your existing recovery key remains valid.',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: busy ? null : submit,
                  child: Text(busy ? 'Changing…' : 'Change Password'),
                ),
              ],
            ),
          );
        },
      ),
    );

    currentPassword.dispose();
    newPassword.dispose();
    confirmPassword.dispose();
    if (changed == true && ctx.mounted) {
      _key.currentState?.refresh();
      toast(ctx, 'Data Folder password changed.');
    }
  }

  Future<void> _rotateRecoveryKey(BuildContext ctx, Point point) async {
    final password = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Regenerate Recovery Key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the Data Folder password. The current recovery key will stop working, and a new key will be shown once.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Data Folder Password'),
              onSubmitted: (_) => Navigator.pop(dialogContext, true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Regenerate Key'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      password.dispose();
      return;
    }

    try {
      final updated = await _v.rotateDataRecoveryKey(point.id, password.text);
      final recoveryKey = updated.recoveryKey;
      if (recoveryKey == null || recoveryKey.isEmpty) {
        throw Exception('The server did not return a new recovery key.');
      }
      if (!ctx.mounted) return;

      await showDialog<void>(
        context: ctx,
        barrierDismissible: false,
        builder: (dialogContext) {
          var canDismiss = false;
          return StatefulBuilder(
            builder: (dialogContext, setDialogState) => PopScope(
              canPop: canDismiss,
              child: AlertDialog(
                title: const Text('Save Your New Recovery Key'),
                content: SelectableText(
                  'Your previous recovery key is no longer valid. Store this new key somewhere safe. It will only be shown once.\n\n$recoveryKey',
                ),
                actions: [
                  FilledButton(
                    onPressed: () {
                      setDialogState(() => canDismiss = true);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      });
                    },
                    child: const Text('I Have Saved It'),
                  ),
                ],
              ),
            ),
          );
        },
      );
      if (mounted) _key.currentState?.refresh();
    } catch (e) {
      if (ctx.mounted) toast(ctx, e.toString(), error: true);
    } finally {
      password.dispose();
    }
  }

  Future<void> _manageDataEncryption(BuildContext ctx, Point point) async {
    if (!point.isEncrypted) return;
    if (point.isUnlocked) {
      final confirmed = await showDialog<bool>(
        context: ctx,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Lock Data Folder?'),
          content: const Text('Further reads and writes will be blocked until the folder is unlocked again. An operation already in progress may finish.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Lock Folder')),
          ],
        ),
      );
      if (confirmed != true) return;
      try {
        await _v.lockData(point.id);
        if (mounted) _key.currentState?.refresh();
      } catch (e) {
        if (mounted) toast(context, e.toString(), error: true);
      }
    } else {
      await _unlockDataFolder(ctx, point);
    }
  }

  Widget _pointCard(BuildContext ctx, Point p) {
    final cs = Theme.of(ctx).colorScheme;
    final tt = Theme.of(ctx).textTheme;
    final locationName =
        _roots.where((r) => r.id == p.rootId).map((r) => r.name).firstOrNull ??
        (p.rootId.length > 8 ? p.rootId.substring(0, 8) : p.rootId);
    final canOpenData = widget.repo || !p.isEncrypted || p.isUnlocked;
    final actions = widget.repo
        ? <Widget>[
            FilledButton.tonalIcon(
              onPressed: () => Navigator.push(
                ctx,
                MaterialPageRoute(builder: (_) => SnapshotBrowserPage(repo: p)),
              ),
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Browse'),
            ),
            FilledButton.icon(
              onPressed: () => startBackup(ctx, ref, repo: p),
              icon: const Icon(Icons.backup_outlined),
              label: const Text('Backup'),
            ),
          ]
        : <Widget>[
            FilledButton.tonalIcon(
              onPressed: canOpenData ? () => Navigator.push(
                ctx,
                MaterialPageRoute(builder: (_) => FilesPage(initialPointId: p.id)),
              ) : () => _unlockDataFolder(ctx, p),
              icon: Icon(canOpenData ? Icons.folder_open_outlined : Icons.lock_open_outlined),
              label: Text(canOpenData ? 'Open' : 'Unlock'),
            ),
            FilledButton.icon(
              onPressed: canOpenData ? () => startBackup(ctx, ref, data: p) : null,
              icon: const Icon(Icons.backup_outlined),
              label: const Text('Backup'),
            ),
          ];
    return Card(
      child: InkWell(
        onTap: () {
          if (widget.repo) {
            _openRepo(p);
          } else if (canOpenData) {
            Navigator.push(ctx, MaterialPageRoute(builder: (_) => FilesPage(initialPointId: p.id)));
          } else {
            _unlockDataFolder(ctx, p);
          }
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    widget.repo
                        ? Icons.inventory_2_outlined
                        : Icons.folder_outlined,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.titleMedium,
                        ),
                        Text(
                          locationName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        if (!widget.repo && p.isEncrypted)
                          Text(
                            p.isUnlocked ? 'Encrypted · Unlocked' : 'Encrypted · Locked',
                            style: tt.bodySmall?.copyWith(
                              color: p.isUnlocked ? cs.primary : cs.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  chip(
                    ctx,
                    p.healthLabel,
                    color: p.isError ? cs.errorContainer : null,
                    inline: true,
                  ),
                  PopupMenuButton<String>(
                    onSelected: (a) {
                      switch (a) {
                        case 'edit':
                          _edit(p);
                        case 'security':
                          _manageDataEncryption(ctx, p);
                        case 'recovery':
                          _rotateRecoveryKey(ctx, p);
                        case 'password':
                          _changeDataPassword(ctx, p);
                        case 'jobs':
                          if (widget.repo) {
                            _openRepo(p, tab: 1);
                          } else {
                            Navigator.push(
                              ctx,
                              MaterialPageRoute(
                                builder: (_) => DataJobsPage(data: p),
                              ),
                            );
                          }
                        case 'snaps':
                          _openRepo(p, tab: 0);
                        case 'sched':
                          _openRepo(p, tab: 2);
                        case 'del':
                          _delete(p);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      if (!widget.repo && p.isEncrypted) ...[
                        PopupMenuItem(value: 'security', child: Text(p.isUnlocked ? 'Lock Folder' : 'Unlock Folder')),
                        const PopupMenuItem(value: 'password', child: Text('Change Password')),
                        const PopupMenuItem(value: 'recovery', child: Text('Regenerate Recovery Key')),
                      ],
                      if (widget.repo)
                        const PopupMenuItem(
                          value: 'snaps',
                          child: Text('Snapshots'),
                        ),
                      const PopupMenuItem(value: 'jobs', child: Text('Jobs')),
                      if (widget.repo)
                        const PopupMenuItem(
                          value: 'sched',
                          child: Text('Schedules'),
                        ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(value: 'del', child: Text('Delete')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    UsageBar(used: p.usedBytes, max: p.maxBytes),
                    const SizedBox(height: 6),
                    Text(
                      '${fmtBytes(p.usedBytes)} of ${fmtBytes(p.maxBytes)}',
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    if (p.error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          p.error!,
                          style: TextStyle(color: cs.error, fontSize: 12),
                        ),
                      ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, box) {
                        if (box.maxWidth < 320) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              actions[0],
                              const SizedBox(height: 8),
                              actions[1],
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: actions[0]),
                            const SizedBox(width: 8),
                            Expanded(child: actions[1]),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditPointSheet extends StatefulWidget {
  const _EditPointSheet({
    required this.point,
    required this.root,
    required this.repo,
  });
  final Point point;
  final Root root;
  final bool repo;

  @override
  State<_EditPointSheet> createState() => _EditPointSheetState();
}

class _EditPointSheetState extends State<_EditPointSheet> {
  late final TextEditingController _name;
  late final TextEditingController _capacity;
  late final int _availableBytes;
  String _unit = 'GiB';
  final bool _saving = false;
  int? _exactBytes;
  String? _exactText, _exactUnit;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.point.name);
    _availableBytes = widget.root.freeBytes + widget.point.maxBytes;
    _capacity = TextEditingController(
      text: bytesToCapacity(widget.point.maxBytes, _unit),
    );
    _rememberExact(widget.point.maxBytes);
  }

  @override
  void dispose() {
    _name.dispose();
    _capacity.dispose();
    super.dispose();
  }

  int get _bytes {
    if (_exactBytes != null &&
        _capacity.text.trim() == _exactText &&
        _unit == _exactUnit) {
      return _exactBytes!;
    }
    final n = double.tryParse(_capacity.text.trim().replaceAll(',', '.'));
    if (n == null || !n.isFinite || n < 0) return 0;
    return (n * (capacityFactors[_unit] ?? capacityFactors['GiB']!)).round();
  }

  void _rememberExact(int bytes) {
    _exactBytes = bytes;
    _exactText = _capacity.text.trim();
    _exactUnit = _unit;
  }

  void _setBytes(int bytes) {
    _capacity.text = bytesToCapacity(bytes, _unit);
    _rememberExact(bytes);
  }

  String get _error {
    if (_name.text.trim().isEmpty) return 'Enter a name.';
    if (_capacity.text.trim().isEmpty || _bytes < 4096) {
      return 'Enter a valid space limit.';
    }
    if (_bytes > _availableBytes) {
      return 'Limit exceeds the capacity available to you.';
    }
    return '';
  }

  void _save() {
    if (_error.isNotEmpty) {
      toast(context, _error, error: true);
      return;
    }
    Navigator.pop(context, {'name': _name.text.trim(), 'maxBytes': _bytes});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final max = _availableBytes > 0 ? _availableBytes : widget.point.maxBytes;
    final fraction = (_bytes / max).clamp(0.0, 1.0).toDouble();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Edit ${widget.repo ? 'Backup Vault' : 'Data Folder'}',
              style: t.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Change the name or space limit.',
              style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _name,
              enabled: !_saving,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 18),
            Text('Space Limit', style: t.titleSmall),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, box) {
                final amount = Expanded(
                  child: TextField(
                    controller: _capacity,
                    enabled: !_saving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Amount',
                      border: const OutlineInputBorder(),
                      errorText:
                          _capacity.text.isNotEmpty &&
                              (_bytes < 4096 || _bytes > max)
                          ? 'Outside available capacity'
                          : null,
                      helperText: null,
                    ),
                    onChanged: (_) => setState(() {
                      _exactBytes = null;
                      _exactText = null;
                      _exactUnit = null;
                    }),
                  ),
                );
                final unit = SizedBox(
                  width: 96,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _unit,
                    decoration: const InputDecoration(
                      labelText: 'Unit',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'B', child: Text('B')),
                      DropdownMenuItem(value: 'GiB', child: Text('GiB')),
                      DropdownMenuItem(value: 'TiB', child: Text('TiB')),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) {
                            if (value == null) return;
                            final bytes = _bytes;
                            setState(() {
                              _unit = value;
                              _setBytes(bytes);
                            });
                          },
                  ),
                );
                if (box.maxWidth < 360) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [amount, const SizedBox(height: 10), unit],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [amount, const SizedBox(width: 10), unit],
                );
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Allocation',
                    style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
                Text('${(fraction * 100).round()}%', style: t.titleSmall),
              ],
            ),
            Slider(
              value: fraction,
              min: 0,
              max: 1,
              divisions: 100,
              label: '${(fraction * 100).round()}%',
              onChanged: _saving || max <= 0
                  ? null
                  : (value) => setState(() => _setBytes((value * max).round())),
            ),
            Text(
              'Available to this folder: ${fmtBytes(max)}.',
              style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.check),
                    label: const Text('Save Changes'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NewPointSheet extends StatefulWidget {
  const _NewPointSheet({
    required this.repo,
    required this.roots,
    required this.vaulton,
    required this.encryptionEnabled,
  });
  final bool repo, encryptionEnabled;
  final List<Root> roots;
  final Vaulton vaulton;
  @override
  State<_NewPointSheet> createState() => _NewPointSheetState();
}

class _NewPointSheetState extends State<_NewPointSheet> {
  late Root _root;
  final _name = TextEditingController(),
      _capacity = TextEditingController(),
      _password = TextEditingController(),
      _passwordConfirm = TextEditingController();
  String _unit = 'GiB';
  bool _showPassword = false,
      _encryptData = false,
      _saving = false,
      _capacityTouched = false,
      _passwordTouched = false;
  int? _exactCapacityBytes;
  String? _exactCapacityText, _exactCapacityUnit;

  @override
  void initState() {
    super.initState();
    _root = widget.roots.first;
  }

  @override
  void dispose() {
    _name.dispose();
    _capacity.dispose();
    _password.dispose();
    _passwordConfirm.dispose();
    super.dispose();
  }

  int get _capacityBytesValue {
    if (_exactCapacityBytes != null &&
        _capacity.text.trim() == _exactCapacityText &&
        _unit == _exactCapacityUnit) {
      return _exactCapacityBytes!;
    }
    final n = double.tryParse(_capacity.text.trim().replaceAll(',', '.'));
    if (n == null || !n.isFinite || n < 0) return 0;
    return (n * (capacityFactors[_unit] ?? capacityFactors['GiB']!)).round();
  }

  void _clearExactCapacity() {
    _exactCapacityBytes = null;
    _exactCapacityText = null;
    _exactCapacityUnit = null;
  }

  void _setExactCapacity(int bytes) {
    _capacity.text = bytesToCapacity(bytes, _unit);
    _exactCapacityBytes = bytes;
    _exactCapacityText = _capacity.text.trim();
    _exactCapacityUnit = _unit;
  }

  String get _capacityError {
    final raw = _capacity.text.trim();
    if (raw.isEmpty) return 'Enter a space limit.';
    final n = double.tryParse(raw.replaceAll(',', '.'));
    if (n == null || !n.isFinite || n < 0 || _capacityBytesValue < 4096) {
      return 'Enter a valid space limit.';
    }
    if (_root.freeBytes <= 0) {
      return 'No allocatable capacity remains for you on this location.';
    }
    if (_capacityBytesValue > _root.freeBytes) {
      return 'The limit exceeds the capacity available to you on this location.';
    }
    return '';
  }

  String get _passwordError {
    if (widget.repo) return _password.text.isNotEmpty && _password.text.length < 8 ? 'Use at least 8 characters.' : '';
    if (!_encryptData) return '';
    if (_password.text.trim().isEmpty) return 'Enter a password.';
    if (_password.text.runes.length < 12) return 'Use at least 12 characters.';
    if (_password.text != _passwordConfirm.text) return 'Passwords do not match.';
    return '';
  }
  Future<void> _save() async {
    final name = _name.text.trim();
    setState(() {
      _capacityTouched = true;
      _passwordTouched = true;
    });
    if (name.isEmpty || _capacityError.isNotEmpty || _passwordError.isNotEmpty) {
      return;
    }
    final maxBytes = _capacityBytesValue;
    setState(() => _saving = true);
    try {
      final created = widget.repo
          ? await widget.vaulton.createRepo({
              'rootId': _root.id,
              'name': name,
              'maxBytes': maxBytes,
              'password': _password.text,
            })
          : await widget.vaulton.createData({
              'rootId': _root.id,
              'name': name,
              'maxBytes': maxBytes,
              if (_encryptData) 'encryptionPassword': _password.text,
            });
      if (mounted) {
        final recoveryKey = created.recoveryKey;
        if (recoveryKey != null && recoveryKey.isNotEmpty) {
          await showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) {
              var canDismiss = false;
              return StatefulBuilder(
                builder: (dialogContext, setDialogState) => PopScope(
                  canPop: canDismiss,
                  child: AlertDialog(
                    title: const Text('Save Your Recovery Key'),
                    content: SelectableText(
                      'This key is shown only once. Store it somewhere safe. Anyone with this key can unlock this Data Folder.\n\n$recoveryKey',
                    ),
                    actions: [
                      FilledButton(
                        onPressed: () {
                          setDialogState(() => canDismiss = true);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (dialogContext.mounted) Navigator.pop(dialogContext);
                          });
                        },
                        child: const Text('I Have Saved It'),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        }
        if (mounted) Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        toast(context, e.toString(), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme, t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundColor: widget.repo
                      ? cs.secondaryContainer
                      : cs.primaryContainer,
                  child: Icon(
                    widget.repo
                        ? Icons.inventory_2_outlined
                        : Icons.folder_outlined,
                    color: widget.repo
                        ? cs.onSecondaryContainer
                        : cs.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.repo ? 'New Backup Vault' : 'New Data Folder',
                        style: t.headlineSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.repo
                            ? 'An encrypted place for your backups.'
                            : 'A dedicated space for your files.',
                        style: t.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Location', style: t.titleSmall),
            const SizedBox(height: 8),
            DropdownButtonFormField<Root>(
              initialValue: _root,
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.dns_outlined),
              ),
              items: [
                for (final r in widget.roots)
                  DropdownMenuItem(
                    value: r,
                    child: Text(r.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: _saving ? null : (r) => setState(() => _root = r!),
            ),
            const SizedBox(height: 6),
            Text(
              _root.isOwner
                  ? '${fmtBytes(_root.freeBytes)} available to allocate of ${fmtBytes(_root.maxBytes)}.'
                  : '${fmtBytes(_root.freeBytes)} available to you on this shared location.',
              style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            if (!_root.isOwner) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.shield_outlined, color: cs.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _encryptData
                            ? 'This folder is encrypted at rest. The server administrator can still access files while it is unlocked.'
                            : 'Files in this Data Folder are not independently encrypted. The location owner or server administrator may be able to access them outside Vaulton.',
                        style: t.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (!widget.repo && widget.encryptionEnabled) ...[
              const SizedBox(height: 16),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _encryptData,
                onChanged: _saving ? null : (value) => setState(() => _encryptData = value),
                title: const Text('Encrypt This Data Folder'),
                subtitle: const Text('Protects file contents, names, and folder metadata at rest.'),
              ),
              if (_encryptData) ...[
                Text('Choose a password with at least 12 characters. You will need it to unlock this folder. Save the recovery key shown after creation; it cannot be shown again.', style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 10),
                TextField(
                  controller: _password,
                  enabled: !_saving,
                  obscureText: !_showPassword,
                  onChanged: (_) => setState(() => _passwordTouched = true),
                  decoration: InputDecoration(
                    labelText: 'Encryption Password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _showPassword = !_showPassword)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _passwordConfirm,
                  enabled: !_saving,
                  obscureText: !_showPassword,
                  onChanged: (_) => setState(() => _passwordTouched = true),
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
                    border: const OutlineInputBorder(),
                    errorText: _passwordTouched && _passwordError.isNotEmpty ? _passwordError : null,
                  ),
                ),
                const SizedBox(height: 8),
                Text('Encryption is set up on a new empty Data Folder; existing folders are not converted. To protect existing files, create a new encrypted folder and copy them into it using SMB or another file-transfer tool. The server administrator can still access files while the folder is unlocked.', style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ],
            const SizedBox(height: 18),
            TextField(
              controller: _name,
              enabled: !_saving,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Documents',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text('Space Limit', style: t.titleSmall),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, box) {
                final amount = Expanded(
                  child: TextField(
                    controller: _capacity,
                    enabled: !_saving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() {
                      _clearExactCapacity();
                      _capacityTouched = true;
                    }),
                    decoration: InputDecoration(
                      labelText: 'Amount',
                      border: const OutlineInputBorder(),
                      errorText: (!_capacityTouched || _capacityError.isEmpty)
                          ? null
                          : _capacityError,
                      helperText: null,
                    ),
                  ),
                );
                final unit = SizedBox(
                  width: 96,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _unit,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Unit',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'B', child: Text('B')),
                      DropdownMenuItem(value: 'GiB', child: Text('GiB')),
                      DropdownMenuItem(value: 'TiB', child: Text('TiB')),
                    ],
                    onChanged: _saving
                        ? null
                        : (v) {
                            if (v == null) return;
                            final raw = double.tryParse(
                              _capacity.text.trim().replaceAll(',', '.'),
                            );
                            final valid =
                                _capacity.text.trim().isEmpty ||
                                (raw != null && raw.isFinite && raw >= 0);
                            final bytes = _capacityBytesValue;
                            setState(() {
                              _unit = v;
                              if (valid) {
                                _setExactCapacity(bytes);
                              } else {
                                _clearExactCapacity();
                              }
                            });
                          },
                  ),
                );
                if (box.maxWidth < 360) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [amount, const SizedBox(height: 10), unit],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [amount, const SizedBox(width: 10), unit],
                );
              },
            ),
            if (_root.freeBytes > 0) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    'Allocation',
                    style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const Spacer(),
                  Text(
                    '${((_capacityBytesValue / _root.freeBytes) * 100).clamp(0, 100).round()}%',
                    style: t.titleSmall,
                  ),
                ],
              ),
              Slider(
                value: (_capacityBytesValue / _root.freeBytes)
                    .clamp(0, 1)
                    .toDouble(),
                min: 0,
                max: 1,
                divisions: 100,
                label:
                    '${((_capacityBytesValue / _root.freeBytes) * 100).clamp(0, 100).round()}%',
                onChanged: _saving
                    ? null
                    : (v) {
                        final bytes = (v * _root.freeBytes).round();
                        setState(() {
                          _capacityTouched = true;
                          _setExactCapacity(bytes);
                        });
                      },
              ),
              Text(
                'Available to allocate: ${fmtBytes(_root.freeBytes)}.',
                style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
            if (widget.repo) ...[
              const SizedBox(height: 18),
              TextField(
                controller: _password,
                enabled: !_saving,
                obscureText: !_showPassword,
                onChanged: (_) => setState(() {
                  _passwordTouched = true;
                }),
                decoration: InputDecoration(
                  labelText: 'Vault Password',
                  hintText: 'At least 8 characters.',
                  border: const OutlineInputBorder(),
                  errorText: (!_passwordTouched || _passwordError.isEmpty)
                      ? null
                      : _passwordError,
                  suffixIcon: IconButton(
                    tooltip: _showPassword ? 'Hide Password' : 'Show Password',
                    icon: Icon(
                      _showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: _saving
                        ? null
                        : () => setState(() => _showPassword = !_showPassword),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'This password is required to open the backup vault.',
                style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(_saving ? 'Creating…' : 'Create'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Everything that has touched one data folder, with a one-tap backup button.
class DataJobsPage extends ConsumerWidget {
  const DataJobsPage({super.key, required this.data});
  final Point data;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: Text('Jobs · ${data.name}')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => startBackup(context, ref, data: data),
      icon: const Icon(Icons.backup),
      label: const Text('Backup'),
    ),
    body: JobsList(dataId: data.id),
  );
}

/// Details for one storage location, including who it is shared with.
class _RootSheet extends StatefulWidget {
  const _RootSheet({
    required this.root,
    required this.vaulton,
    required this.onShare,
    required this.onEdit,
    required this.onDelete,
  });
  final Root root;
  final Vaulton vaulton;
  final VoidCallback onShare, onEdit, onDelete;
  @override
  State<_RootSheet> createState() => _RootSheetState();
}

class _RootSheetState extends State<_RootSheet> {
  List<Json>? _shares;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (widget.root.isOwner) {
      widget.vaulton
          .shares(widget.root.id)
          .then((v) {
            if (mounted) setState(() => _shares = v);
          })
          .catchError((_) {
            if (mounted) setState(() => _failed = true);
          });
    }
  }

  Widget _row(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 12),
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final r = widget.root;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final allocated = r.allocatedBytes;
    final rawScheme = '${r.source?['scheme'] ?? ''}';
    final scheme = _sourceLabel(rawScheme);
    final holds = [
      if (r.isDataAllowed) 'Data Folders',
      if (r.isRepoAllowed) 'Backup Vaults',
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: cs.secondaryContainer,
                child: Icon(Icons.dns_outlined, color: cs.onSecondaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.name,
                      style: t.titleLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      r.isOwner ? 'Owned by You' : 'Shared by ${r.userName}',
                      style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (r.isOwner) ...[
            UsageBar(used: allocated, max: r.maxBytes),
            const SizedBox(height: 6),
            Text(
              '${fmtBytes(allocated)} allocated · ${fmtBytes(r.freeBytes)} free of ${fmtBytes(r.maxBytes)}',
              style: t.bodySmall,
            ),
          ] else ...[
            UsageBar(used: r.freeBytes, max: r.maxBytes),
            const SizedBox(height: 6),
            Text(
              'Available to you: ${fmtBytes(r.freeBytes)}',
              style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 8),
          if (scheme.isNotEmpty)
            _row(Icons.cable_outlined, 'Connection Type', scheme),
          _row(
            Icons.inventory_2_outlined,
            'Can Hold',
            holds.isEmpty ? 'Nothing Yet' : holds.join(' and '),
          ),
          const Divider(height: 28),
          Text('Who Can Use It', style: t.titleSmall),
          const SizedBox(height: 8),
          if (!r.isOwner)
            Text(
              'Only the owner can manage access.',
              style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            )
          else if (_failed)
            Text(
              'Couldn’t load sharing.',
              style: t.bodyMedium?.copyWith(color: cs.error),
            )
          else if (_shares == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            )
          else if (_shares!.isEmpty)
            Text(
              'Not shared. Only you can use this location.',
              style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            )
          else
            for (final s in _shares!)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: CircleAvatar(
                  radius: 16,
                  child: Text(
                    '${s['userName']}'.isEmpty
                        ? '?'
                        : '${s['userName']}'[0].toUpperCase(),
                  ),
                ),
                title: Text('${s['userName']}'),
                trailing: Text(
                  'Up to ${fmtBytes(toInt(s['maxBytes']))}',
                  style: t.bodySmall,
                ),
              ),
          if (r.isOwner) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: widget.onShare,
                icon: const Icon(Icons.group_add_outlined),
                label: Text(
                  _shares != null && _shares!.isNotEmpty
                      ? 'Manage Sharing'
                      : 'Share This Location',
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: widget.onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit Location'),
                ),
                TextButton.icon(
                  onPressed: widget.onDelete,
                  style: TextButton.styleFrom(foregroundColor: cs.error),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
