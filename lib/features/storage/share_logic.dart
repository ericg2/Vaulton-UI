// Pure Dart (no Flutter imports) so it is trivial to unit-test.

const int kGiB = 1024 * 1024 * 1024;

const Map<String, double> capacityFactors = {
  'MiB': 1024 * 1024,
  'GiB': 1024 * 1024 * 1024,
  'TiB': 1024 * 1024 * 1024 * 1024,
};

int? capacityToBytes(String text, String unit) {
  final v = double.tryParse(text.trim().replaceAll(',', '.'));
  if (v == null || v.isNaN || v.isInfinite || v < 0) return null;
  return (v * (capacityFactors[unit] ?? capacityFactors['GiB']!)).round();
}

String bytesToCapacity(int bytes, String unit) {
  final f = capacityFactors[unit] ?? capacityFactors['GiB']!;
  return bytes == 0 ? '' : (bytes / f).toStringAsFixed(12).replaceFirst(RegExp(r'\\.?0+
}


/// "12.5" -> bytes. Empty/invalid -> null.
int? gbToBytes(String s) {
  final v = double.tryParse(s.trim().replaceAll(',', '.'));
  return v == null ? null : (v * kGiB).round();
}

/// Bytes -> text for a GB field. 0 is shown as an empty field.
String bytesToGb(int b) => b == 0 ? '' : (b / kGiB).toStringAsFixed(12).replaceFirst(RegExp(r'\\.?0+

/// Result of reading a quota text field.
typedef QuotaResult = ({int bytes, String? error});

/// Empty means 0 (no explicit quota). Anything else must be a non-negative number of GiB.
QuotaResult parseQuota(String text) {
  final t = text.trim().replaceAll(',', '.');
  if (t.isEmpty) return (bytes: 0, error: null);
  final v = double.tryParse(t);
  if (v == null || v.isNaN || v.isInfinite) return (bytes: 0, error: 'Enter a number');
  if (v < 0) return (bytes: 0, error: 'Cannot be negative');
  return (bytes: (v * kGiB).round(), error: null);
}

/// Case-insensitive key used to compare user names.
String normUser(String s) => s.trim().toLowerCase();

/// A user that can be picked in the share editor.
class ShareUser {
  const ShareUser({required this.userName, this.displayName, this.email, this.isLockedOut = false});
  final String userName;
  final String? displayName;
  final String? email;
  final bool isLockedOut;

  bool get hasDistinctDisplayName => displayName != null && displayName!.trim().isNotEmpty && normUser(displayName!) != normUser(userName);

  /// Main line: the person's name, or the user name when they have none.
  String get title => hasDistinctDisplayName ? displayName!.trim() : userName;

  /// Second line: "@user · email".
  String get subtitle {
    final parts = <String>[if (hasDistinctDisplayName) '@$userName', if (email != null && email!.trim().isNotEmpty) email!.trim()];
    return parts.join(' · ');
  }

  String get initial => title.isEmpty ? '?' : title[0].toUpperCase();

  /// True when every word of [query] appears in the name, user name or e-mail.
  bool matches(String query) {
    final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return true;
    final hay = '${userName.toLowerCase()} ${(displayName ?? '').toLowerCase()} ${(email ?? '').toLowerCase()}';
    return words.every(hay.contains);
  }
}

/// Users that can still be added: not already shared, not excluded (owner / yourself),
/// sorted by name with locked accounts last.
List<ShareUser> availableUsers({
  required Iterable<ShareUser> all,
  required Iterable<String> taken,
  Iterable<String> exclude = const [],
}) {
  final skip = {for (final n in [...taken, ...exclude]) normUser(n)};
  final out = [for (final u in all) if (!skip.contains(normUser(u.userName))) u];
  out.sort((a, b) {
    if (a.isLockedOut != b.isLockedOut) return a.isLockedOut ? 1 : -1;
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });
  return out;
}

/// Filters [users] by a free-text query (see [ShareUser.matches]).
List<ShareUser> filterUsers(Iterable<ShareUser> users, String query) => [for (final u in users) if (u.matches(query)) u];

/// Finds a user by exact (case-insensitive) user name.
ShareUser? findUser(Iterable<ShareUser> users, String userName) {
  final k = normUser(userName);
  for (final u in users) {
    if (normUser(u.userName) == k) return u;
  }
  return null;
}

/// True when the quotas handed out add up to more than the root's capacity.
bool overAllocated(int capacity, int allocated) => capacity > 0 && allocated > capacity;

typedef ShareEntry = ({String userName, int maxBytes});

/// Request body for PUT /roots/{id}/shares. Blank names are dropped and
/// duplicates (case-insensitive) keep their last value.
List<Map<String, dynamic>> buildSharePayload(Iterable<ShareEntry> entries) {
  final byKey = <String, ShareEntry>{};
  for (final e in entries) {
    final name = e.userName.trim();
    if (name.isEmpty) continue;
    byKey[normUser(name)] = (userName: name, maxBytes: e.maxBytes);
  }
  return [for (final e in byKey.values) {'userName': e.userName, 'maxBytes': e.maxBytes}];
}
), '');
}


/// "12.5" -> bytes. Empty/invalid -> null.
int? gbToBytes(String s) {
  final v = double.tryParse(s.trim().replaceAll(',', '.'));
  return v == null ? null : (v * kGiB).round();
}

/// Bytes -> text for a GB field. 0 is shown as an empty field.
String bytesToGb(int b) => b == 0 ? '' : (b / kGiB).toStringAsFixed(b % kGiB == 0 ? 0 : 2);

/// Result of reading a quota text field.
typedef QuotaResult = ({int bytes, String? error});

/// Empty means 0 (no explicit quota). Anything else must be a non-negative number of GiB.
QuotaResult parseQuota(String text) {
  final t = text.trim().replaceAll(',', '.');
  if (t.isEmpty) return (bytes: 0, error: null);
  final v = double.tryParse(t);
  if (v == null || v.isNaN || v.isInfinite) return (bytes: 0, error: 'Enter a number');
  if (v < 0) return (bytes: 0, error: 'Cannot be negative');
  return (bytes: (v * kGiB).round(), error: null);
}

/// Case-insensitive key used to compare user names.
String normUser(String s) => s.trim().toLowerCase();

/// A user that can be picked in the share editor.
class ShareUser {
  const ShareUser({required this.userName, this.displayName, this.email, this.isLockedOut = false});
  final String userName;
  final String? displayName;
  final String? email;
  final bool isLockedOut;

  bool get hasDistinctDisplayName => displayName != null && displayName!.trim().isNotEmpty && normUser(displayName!) != normUser(userName);

  /// Main line: the person's name, or the user name when they have none.
  String get title => hasDistinctDisplayName ? displayName!.trim() : userName;

  /// Second line: "@user · email".
  String get subtitle {
    final parts = <String>[if (hasDistinctDisplayName) '@$userName', if (email != null && email!.trim().isNotEmpty) email!.trim()];
    return parts.join(' · ');
  }

  String get initial => title.isEmpty ? '?' : title[0].toUpperCase();

  /// True when every word of [query] appears in the name, user name or e-mail.
  bool matches(String query) {
    final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return true;
    final hay = '${userName.toLowerCase()} ${(displayName ?? '').toLowerCase()} ${(email ?? '').toLowerCase()}';
    return words.every(hay.contains);
  }
}

/// Users that can still be added: not already shared, not excluded (owner / yourself),
/// sorted by name with locked accounts last.
List<ShareUser> availableUsers({
  required Iterable<ShareUser> all,
  required Iterable<String> taken,
  Iterable<String> exclude = const [],
}) {
  final skip = {for (final n in [...taken, ...exclude]) normUser(n)};
  final out = [for (final u in all) if (!skip.contains(normUser(u.userName))) u];
  out.sort((a, b) {
    if (a.isLockedOut != b.isLockedOut) return a.isLockedOut ? 1 : -1;
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });
  return out;
}

/// Filters [users] by a free-text query (see [ShareUser.matches]).
List<ShareUser> filterUsers(Iterable<ShareUser> users, String query) => [for (final u in users) if (u.matches(query)) u];

/// Finds a user by exact (case-insensitive) user name.
ShareUser? findUser(Iterable<ShareUser> users, String userName) {
  final k = normUser(userName);
  for (final u in users) {
    if (normUser(u.userName) == k) return u;
  }
  return null;
}

/// True when the quotas handed out add up to more than the root's capacity.
bool overAllocated(int capacity, int allocated) => capacity > 0 && allocated > capacity;

typedef ShareEntry = ({String userName, int maxBytes});

/// Request body for PUT /roots/{id}/shares. Blank names are dropped and
/// duplicates (case-insensitive) keep their last value.
List<Map<String, dynamic>> buildSharePayload(Iterable<ShareEntry> entries) {
  final byKey = <String, ShareEntry>{};
  for (final e in entries) {
    final name = e.userName.trim();
    if (name.isEmpty) continue;
    byKey[normUser(name)] = (userName: name, maxBytes: e.maxBytes);
  }
  return [for (final e in byKey.values) {'userName': e.userName, 'maxBytes': e.maxBytes}];
}
), '');

/// Result of reading a quota text field.
typedef QuotaResult = ({int bytes, String? error});

/// Empty means 0 (no explicit quota). Anything else must be a non-negative number of GiB.
QuotaResult parseQuota(String text) {
  final t = text.trim().replaceAll(',', '.');
  if (t.isEmpty) return (bytes: 0, error: null);
  final v = double.tryParse(t);
  if (v == null || v.isNaN || v.isInfinite) return (bytes: 0, error: 'Enter a number');
  if (v < 0) return (bytes: 0, error: 'Cannot be negative');
  return (bytes: (v * kGiB).round(), error: null);
}

/// Case-insensitive key used to compare user names.
String normUser(String s) => s.trim().toLowerCase();

/// A user that can be picked in the share editor.
class ShareUser {
  const ShareUser({required this.userName, this.displayName, this.email, this.isLockedOut = false});
  final String userName;
  final String? displayName;
  final String? email;
  final bool isLockedOut;

  bool get hasDistinctDisplayName => displayName != null && displayName!.trim().isNotEmpty && normUser(displayName!) != normUser(userName);

  /// Main line: the person's name, or the user name when they have none.
  String get title => hasDistinctDisplayName ? displayName!.trim() : userName;

  /// Second line: "@user · email".
  String get subtitle {
    final parts = <String>[if (hasDistinctDisplayName) '@$userName', if (email != null && email!.trim().isNotEmpty) email!.trim()];
    return parts.join(' · ');
  }

  String get initial => title.isEmpty ? '?' : title[0].toUpperCase();

  /// True when every word of [query] appears in the name, user name or e-mail.
  bool matches(String query) {
    final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return true;
    final hay = '${userName.toLowerCase()} ${(displayName ?? '').toLowerCase()} ${(email ?? '').toLowerCase()}';
    return words.every(hay.contains);
  }
}

/// Users that can still be added: not already shared, not excluded (owner / yourself),
/// sorted by name with locked accounts last.
List<ShareUser> availableUsers({
  required Iterable<ShareUser> all,
  required Iterable<String> taken,
  Iterable<String> exclude = const [],
}) {
  final skip = {for (final n in [...taken, ...exclude]) normUser(n)};
  final out = [for (final u in all) if (!skip.contains(normUser(u.userName))) u];
  out.sort((a, b) {
    if (a.isLockedOut != b.isLockedOut) return a.isLockedOut ? 1 : -1;
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });
  return out;
}

/// Filters [users] by a free-text query (see [ShareUser.matches]).
List<ShareUser> filterUsers(Iterable<ShareUser> users, String query) => [for (final u in users) if (u.matches(query)) u];

/// Finds a user by exact (case-insensitive) user name.
ShareUser? findUser(Iterable<ShareUser> users, String userName) {
  final k = normUser(userName);
  for (final u in users) {
    if (normUser(u.userName) == k) return u;
  }
  return null;
}

/// True when the quotas handed out add up to more than the root's capacity.
bool overAllocated(int capacity, int allocated) => capacity > 0 && allocated > capacity;

typedef ShareEntry = ({String userName, int maxBytes});

/// Request body for PUT /roots/{id}/shares. Blank names are dropped and
/// duplicates (case-insensitive) keep their last value.
List<Map<String, dynamic>> buildSharePayload(Iterable<ShareEntry> entries) {
  final byKey = <String, ShareEntry>{};
  for (final e in entries) {
    final name = e.userName.trim();
    if (name.isEmpty) continue;
    byKey[normUser(name)] = (userName: name, maxBytes: e.maxBytes);
  }
  return [for (final e in byKey.values) {'userName': e.userName, 'maxBytes': e.maxBytes}];
}
), '');
}


/// "12.5" -> bytes. Empty/invalid -> null.
int? gbToBytes(String s) {
  final v = double.tryParse(s.trim().replaceAll(',', '.'));
  return v == null ? null : (v * kGiB).round();
}

/// Bytes -> text for a GB field. 0 is shown as an empty field.
String bytesToGb(int b) => b == 0 ? '' : (b / kGiB).toStringAsFixed(b % kGiB == 0 ? 0 : 2);

/// Result of reading a quota text field.
typedef QuotaResult = ({int bytes, String? error});

/// Empty means 0 (no explicit quota). Anything else must be a non-negative number of GiB.
QuotaResult parseQuota(String text) {
  final t = text.trim().replaceAll(',', '.');
  if (t.isEmpty) return (bytes: 0, error: null);
  final v = double.tryParse(t);
  if (v == null || v.isNaN || v.isInfinite) return (bytes: 0, error: 'Enter a number');
  if (v < 0) return (bytes: 0, error: 'Cannot be negative');
  return (bytes: (v * kGiB).round(), error: null);
}

/// Case-insensitive key used to compare user names.
String normUser(String s) => s.trim().toLowerCase();

/// A user that can be picked in the share editor.
class ShareUser {
  const ShareUser({required this.userName, this.displayName, this.email, this.isLockedOut = false});
  final String userName;
  final String? displayName;
  final String? email;
  final bool isLockedOut;

  bool get hasDistinctDisplayName => displayName != null && displayName!.trim().isNotEmpty && normUser(displayName!) != normUser(userName);

  /// Main line: the person's name, or the user name when they have none.
  String get title => hasDistinctDisplayName ? displayName!.trim() : userName;

  /// Second line: "@user · email".
  String get subtitle {
    final parts = <String>[if (hasDistinctDisplayName) '@$userName', if (email != null && email!.trim().isNotEmpty) email!.trim()];
    return parts.join(' · ');
  }

  String get initial => title.isEmpty ? '?' : title[0].toUpperCase();

  /// True when every word of [query] appears in the name, user name or e-mail.
  bool matches(String query) {
    final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return true;
    final hay = '${userName.toLowerCase()} ${(displayName ?? '').toLowerCase()} ${(email ?? '').toLowerCase()}';
    return words.every(hay.contains);
  }
}

/// Users that can still be added: not already shared, not excluded (owner / yourself),
/// sorted by name with locked accounts last.
List<ShareUser> availableUsers({
  required Iterable<ShareUser> all,
  required Iterable<String> taken,
  Iterable<String> exclude = const [],
}) {
  final skip = {for (final n in [...taken, ...exclude]) normUser(n)};
  final out = [for (final u in all) if (!skip.contains(normUser(u.userName))) u];
  out.sort((a, b) {
    if (a.isLockedOut != b.isLockedOut) return a.isLockedOut ? 1 : -1;
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });
  return out;
}

/// Filters [users] by a free-text query (see [ShareUser.matches]).
List<ShareUser> filterUsers(Iterable<ShareUser> users, String query) => [for (final u in users) if (u.matches(query)) u];

/// Finds a user by exact (case-insensitive) user name.
ShareUser? findUser(Iterable<ShareUser> users, String userName) {
  final k = normUser(userName);
  for (final u in users) {
    if (normUser(u.userName) == k) return u;
  }
  return null;
}

/// True when the quotas handed out add up to more than the root's capacity.
bool overAllocated(int capacity, int allocated) => capacity > 0 && allocated > capacity;

typedef ShareEntry = ({String userName, int maxBytes});

/// Request body for PUT /roots/{id}/shares. Blank names are dropped and
/// duplicates (case-insensitive) keep their last value.
List<Map<String, dynamic>> buildSharePayload(Iterable<ShareEntry> entries) {
  final byKey = <String, ShareEntry>{};
  for (final e in entries) {
    final name = e.userName.trim();
    if (name.isEmpty) continue;
    byKey[normUser(name)] = (userName: name, maxBytes: e.maxBytes);
  }
  return [for (final e in byKey.values) {'userName': e.userName, 'maxBytes': e.maxBytes}];
}
