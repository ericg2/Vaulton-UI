import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/util.dart';
import 'backup_options.dart';
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
    toast(context, 'Create a data folder in Storage first.', error: true);
    return null;
  }
  if (repos.items.isEmpty) {
    toast(context, 'Create a backup vault in Storage first.', error: true);
    return null;
  }
  final req = await showBackupSheet(context, datas: datas.items, repos: repos.items, data: data, repo: repo);
  if (req == null || !context.mounted) return null;
  final j = await guarded(context, () => v.backup(req.repo.id, req.toBody()));
  if (j != null) {
    ref.read(epochProvider.notifier).bump();
    if (context.mounted) {
      toast(context, '${kindLabel(j.kind)} started');
      Navigator.push(context, MaterialPageRoute(builder: (_) => JobDetailPage(jobId: j.id)));
    }
  }
  return j;
}
