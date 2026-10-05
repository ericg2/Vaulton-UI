import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/util.dart';
import '../files/folder_picker.dart';
import 'job_detail_page.dart';
import 'job_widgets.dart';

/// One simple dialog for starting a backup. Pre-select [data] and/or [repo]
/// when launching from a card; anything left out is chosen in the dialog.
Future<RepoJob?> startBackup(BuildContext context, WidgetRef ref, {Point? data, Point? repo}) async {
  final v = ref.read(vaultonProvider);
  final datas = await guarded(context, () => v.datas(limit: 200));
  final repos = await guarded(context, () => v.repos(limit: 200));
  if (datas == null || repos == null || !context.mounted) return null;
  if (datas.items.isEmpty) {
    toast(context, 'Create a data point first (Storage → Data Points)', error: true);
    return null;
  }
  if (repos.items.isEmpty) {
    toast(context, 'Create a repository first (Storage → Repositories)', error: true);
    return null;
  }
  final dm = {for (final d in datas.items) d.name: d};
  final rm = {for (final r in repos.items) r.name: r};
  final f = await formDialog(context, 'Backup Data Point', [
    FieldSpec('data', 'Data Point (What to Backup)', kind: 'choice', options: dm.keys.toList(), initial: data?.name ?? dm.keys.first),
    FieldSpec('repo', 'Repository (Where to Store It)', kind: 'choice', options: rm.keys.toList(), initial: repo?.name ?? rm.keys.first),
    const FieldSpec('path', 'Starting Folder', kind: 'path', initial: '/', required: true, hint: '/ backs up everything'),
    const FieldSpec('dry', 'Dry Run (Test Only)', kind: 'bool'),
  ], ok: 'Start Backup', pick: (v) async {
    final r = await pickFolder(context, initialPointId: dm[v['data']]?.id, initialPath: v['path'], title: 'Choose Folder to Backup');
    return r?.path;
  }, intro: 'Starts right away. You can follow progress in Recent Jobs.');
  if (f == null || !context.mounted) return null;
  final j = await guarded(context, () => v.backup(rm[f['repo']]!.id, {'dataId': dm[f['data']]!.id, 'path': f['path'], 'dryRun': f['dry'] == 'true'}));
  if (j != null) {
    ref.read(epochProvider.notifier).bump();
    if (context.mounted) {
      toast(context, '${kindLabel(j.kind)} Started');
      Navigator.push(context, MaterialPageRoute(builder: (_) => JobDetailPage(jobId: j.id)));
    }
  }
  return j;
}
