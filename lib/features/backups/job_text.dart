/// Server errors sometimes arrive as "error: <text>\nMessage:  " with an empty
/// "Message:" line. Strip that noise so only the useful text is shown.
String cleanJobError(String? raw) {
  if (raw == null) return '';
  final emptyMsg = RegExp(r'^message:?$', caseSensitive: false);
  final lines = raw.split(RegExp(r'\r?\n')).map((l) => l.trim()).where((l) => l.isNotEmpty && !emptyMsg.hasMatch(l)).toList();
  if (lines.isEmpty) return '';
  lines[0] = lines[0].replaceFirst(RegExp(r'^error:\s*', caseSensitive: false), '');
  return lines.where((l) => l.isNotEmpty).join('\n').trim();
}
