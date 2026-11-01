import '../../core/api_client.dart';

/// Server errors sometimes arrive as "error: <text>\nMessage:  " with an empty
/// "Message:" line. Strip that noise so only the useful text is shown.
String cleanJobError(String? raw) {
  if (raw == null) return '';
  raw = friendlyStorageError(raw);
  final emptyMsg = RegExp(r'^message:?$', caseSensitive: false);
  final lines = raw
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !emptyMsg.hasMatch(line))
      .toList();
  if (lines.isEmpty) return '';
  lines[0] = lines[0].replaceFirst(RegExp(r'^error:\s*', caseSensitive: false), '');
  return lines.where((line) => line.isNotEmpty).join('\n').trim();
}
