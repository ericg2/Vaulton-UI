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
  final loaded = await guarded(context, () async {
    Future<List<Point>> all(Future<Paged<Point>> Function(String?) fetch) async {
      final out = <Point>[];
      String? cursor;
      do {
        final page = await fetch(cursor);
        out.addAll(page.items);
        cursor = page.hasMore ? page.nextCursor : null;
      } while (cursor != null);
      return out;
    }

    return (
      datas: await all((cursor) => v.datas(cursor: cursor, limit: 200)),
      repos: await all((cursor) => v.repos(cursor: cursor, limit: 200)),
    );
  });
  if (loaded == null || !context.mounted) return null;
  if (loaded.datas.isEmpty) {
    toast(context, 'Create a data folder in Storage first.', error: true);
    return null;
  }
  if (loaded.repos.isEmpty) {
    toast(context, 'Create a backup vault in Storage first.', error: true);
    return null;
  }
  final req = await showBackupSheet(
    context,
    datas: loaded.datas,
    repos: loaded.repos,
    data: data,
    repo: repo,
  );
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
