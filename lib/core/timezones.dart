import 'package:flutter_timezone/flutter_timezone.dart';

const _common = [
  'UTC', 'America/New_York', 'America/Chicago', 'America/Denver', 'America/Phoenix', 'America/Los_Angeles', 'America/Anchorage',
  'Pacific/Honolulu', 'America/Toronto', 'America/Vancouver', 'America/Mexico_City', 'America/Sao_Paulo', 'America/Argentina/Buenos_Aires',
  'Europe/London', 'Europe/Dublin', 'Europe/Lisbon', 'Europe/Paris', 'Europe/Berlin', 'Europe/Madrid', 'Europe/Rome', 'Europe/Amsterdam',
  'Europe/Zurich', 'Europe/Stockholm', 'Europe/Warsaw', 'Europe/Athens', 'Europe/Helsinki', 'Europe/Istanbul', 'Europe/Moscow',
  'Africa/Cairo', 'Africa/Johannesburg', 'Africa/Lagos', 'Africa/Nairobi', 'Asia/Dubai', 'Asia/Jerusalem', 'Asia/Karachi', 'Asia/Kolkata',
  'Asia/Dhaka', 'Asia/Bangkok', 'Asia/Jakarta', 'Asia/Singapore', 'Asia/Hong_Kong', 'Asia/Shanghai', 'Asia/Manila', 'Asia/Seoul', 'Asia/Tokyo',
  'Australia/Perth', 'Australia/Adelaide', 'Australia/Sydney', 'Australia/Brisbane', 'Pacific/Auckland',
];

String? _cached;

/// The device's IANA time zone (e.g. "America/New_York"), or null if it can't be determined.
Future<String?> deviceTimeZone() async {
  if (_cached != null) return _cached;
  try {
    final dynamic tz = await FlutterTimezone.getLocalTimezone();
    final id = tz is String ? tz : '${(tz as dynamic).identifier}';
    if (id.isNotEmpty) return _cached = id;
  } catch (_) {}
  return null;
}

/// Dropdown options: the device zone first, then [extra] (e.g. a schedule's current zone), then common zones.
List<String> timeZoneOptions({String? device, String? extra}) {
  final out = <String>[];
  for (final z in [device, extra, ..._common]) {
    if (z != null && z.isNotEmpty && !out.contains(z)) out.add(z);
  }
  return out;
}
