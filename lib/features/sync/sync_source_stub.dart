import 'package:dio/dio.dart';

class SyncSourceInfo {
  const SyncSourceInfo({required this.kind, required this.location, required this.label});
  final String kind, location, label;
}
class SyncSourceEntry {
  const SyncSourceEntry({required this.relative, required this.size, required this.modified, required this.isDir, required this.location});
  final String relative, location;
  final int size;
  final DateTime modified;
  final bool isDir;
}
abstract class SyncSource {
  Future<List<SyncSourceEntry>> scan({CancelToken? cancel, void Function(SyncSourceEntry)? onEntry});
  Future<Stream<List<int>>> openRead(SyncSourceEntry entry);
  Future<void> delete(SyncSourceEntry entry);
}
Future<SyncSourceInfo?> pickSyncSource() async => null;
SyncSource openSyncSource(SyncSourceInfo info) => throw UnsupportedError('Local folders are unavailable in the browser.');
