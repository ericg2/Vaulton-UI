import 'package:flutter_test/flutter_test.dart';

import 'package:vaulton/features/backups/backup_summary.dart';

void main() {
  test('Summarizes a backup in a few readable rows', () {
    final rows = formatBackupSummary({
      'filesNew': 6954,
      'filesChanged': 0,
      'filesUnmodified': 0,
      'totalFilesProcessed': 6954,
      'totalBytesProcessed': 213000000000,
      'dirsNew': 717,
      'dirsChanged': 0,
      'dirsUnmodified': 0,
      'totalDirsProcessed': 717,
      'dataBlobs': 102083,
      'treeBlobs': 709,
      'bytesAdded': 143000000000,
      'backupStart': '2026-11-18T19:51:22.4734684+00:00',
      'backupEnd': '2026-11-18T20:12:25.9089644+00:00',
    });

    final values = {for (final row in rows) row.label: row.value};
    expect(rows.length, lessThanOrEqualTo(7));
    expect(values['Files'], '6,954 new');
    expect(values['Folders'], '717 new');
    expect(values['Blobs'], '102,083 data · 709 tree');
    expect(values['Data stored'], '133 GiB');
    expect(values['Duration'], '21m');
    expect(values.containsKey('Files Changed'), isFalse);
    expect(values.containsKey('Dirs Unmodified'), isFalse);
  });

  test('Shows a short no-change summary', () {
    final rows = formatBackupSummary({
      'filesNew': 0,
      'filesChanged': 0,
      'filesUnmodified': 12,
      'totalFilesProcessed': 12,
      'dirsUnmodified': 2,
      'totalDirsProcessed': 2,
      'bytesAdded': 0,
    });

    final values = {for (final row in rows) row.label: row.value};
    expect(values['Files'], '12 unchanged');
    expect(values['Folders'], '2 unchanged');
    expect(values.containsKey('Data stored'), isFalse);
  });
}
