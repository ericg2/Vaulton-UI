import 'package:intl/intl.dart';

/// One compact row in the backup summary card.
class BackupSummaryRow {
  const BackupSummaryRow(this.label, this.value);
  final String label;
  final String value;
}

/// Turns the raw rustic counters into a short, human-readable summary.
///
/// Zero counters and derived duplicates are dropped; related counts are grouped
/// into one row each so the card stays scannable on a phone.
List<BackupSummaryRow> formatBackupSummary(Map<String, dynamic> summary) {
  final rows = <BackupSummaryRow>[];

  int countOf(String key) {
    final value = summary[key];
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  String count(int value) => NumberFormat.decimalPattern('en_US').format(value);

  void addCounts(String label, int total, List<(int, String)> parts) {
    final shown = parts.where((part) => part.$1 > 0).map((part) => '${count(part.$1)} ${part.$2}').toList();
    if (shown.isEmpty) return;
    final changeTotal = parts.fold<int>(0, (sum, part) => sum + part.$1);
    rows.add(BackupSummaryRow(
      label,
      total > changeTotal ? '${count(total)} processed · ${shown.join(' · ')}' : shown.join(' · '),
    ));
  }

  addCounts('Files', countOf('totalFilesProcessed'), [
    (countOf('filesNew'), 'new'),
    (countOf('filesChanged'), 'changed'),
    (countOf('filesUnmodified'), 'unchanged'),
  ]);
  addCounts('Folders', countOf('totalDirsProcessed'), [
    (countOf('dirsNew'), 'new'),
    (countOf('dirsChanged'), 'changed'),
    (countOf('dirsUnmodified'), 'unchanged'),
  ]);

  final scanned = countOf('totalBytesProcessed');
  if (scanned > 0) rows.add(BackupSummaryRow('Data scanned', _bytes(scanned)));

  final stored = countOf('bytesAdded');
  if (stored > 0) rows.add(BackupSummaryRow('Data stored', _bytes(stored)));

  final blobs = <String>[];
  final dataBlobs = countOf('dataBlobs');
  final treeBlobs = countOf('treeBlobs');
  if (dataBlobs > 0) blobs.add('${count(dataBlobs)} data');
  if (treeBlobs > 0) blobs.add('${count(treeBlobs)} tree');
  if (blobs.isNotEmpty) rows.add(BackupSummaryRow('Blobs', blobs.join(' · ')));

  final start = _timeOf(summary['backupStart']);
  final end = _timeOf(summary['backupEnd']);
  final formatter = DateFormat.yMMMd().add_jm();
  if (start != null) rows.add(BackupSummaryRow('Started', formatter.format(start)));
  if (end != null) rows.add(BackupSummaryRow('Finished', formatter.format(end)));
  if (start != null && end != null && end.isAfter(start)) {
    rows.add(BackupSummaryRow('Duration', _duration(end.difference(start))));
  }

  return rows;
}

DateTime? _timeOf(dynamic value) {
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value)?.toLocal();
  return null;
}

String _bytes(int value) {
  if (value.abs() < 1024) return '$value B';
  const units = ['KiB', 'MiB', 'GiB', 'TiB', 'PiB'];
  var number = value.toDouble();
  var unit = -1;
  while (number >= 1024 && unit < units.length - 1) {
    number /= 1024;
    unit++;
  }
  final digits = number >= 100 ? 0 : number >= 10 ? 1 : 2;
  return '${number.toStringAsFixed(digits)} ${units[unit]}';
}

String _duration(Duration d) {
  final minutes = d.inMinutes % 60;
  if (d.inHours > 0) return '${d.inHours}h ${minutes.toString().padLeft(2, '0')}m';
  return '${d.inMinutes}m';
}
