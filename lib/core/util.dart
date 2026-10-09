import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'api_client.dart';
import 'cron_picker.dart';

String fmtBytes(int b) {
  if (b < 1024) return '${b.toStringAsFixed(2)} B';
  const u = ['KiB', 'MiB', 'GiB', 'TiB', 'PiB'];
  double v = b / 1024;
  var i = 0;
  while (v >= 1024 && i < u.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(2)} ${u[i]}';
}

String fmtDate(DateTime? d) => d == null ? '—' : DateFormat.yMMMd().add_jm().format(d);
String fmtShort(DateTime? d) {
  if (d == null) return '—';
  final n = DateTime.now();
  if (d.year == n.year && d.month == n.month && d.day == n.day) return DateFormat.jm().format(d);
  return DateFormat.yMMMd().format(d);
}

String fmtDuration(Duration d) {
  final days = d.inDays;
  final hours = d.inHours % 24;
  final minutes = d.inMinutes % 60;
  if (days > 0) return '${days}d ${hours.toString().padLeft(2, '0')}h ${minutes.toString().padLeft(2, '0')}m';
  if (d.inHours > 0) return '${d.inHours}h ${minutes.toString().padLeft(2, '0')}m';
  return '${minutes}m';
}

String pretty(String camel) {
  final s = camel.replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}');
  final fixed = s.replaceAllMapped(RegExp(r'\b(id|url|ssl|tls|api|uri|ip)\b', caseSensitive: false), (m) => m[1]!.toUpperCase());
  return fixed.isEmpty ? fixed : fixed[0].toUpperCase() + fixed.substring(1);
}

/// Remote paths are '/'-rooted.
String joinPath(String a, String b) {
  final left = a.endsWith('/') ? a.substring(0, a.length - 1) : a;
  final right = b.startsWith('/') ? b.substring(1) : b;
  return '$left/$right';
}

String parentPath(String p) {
  final i = p.lastIndexOf('/');
  return i <= 0 ? '/' : p.substring(0, i);
}

String baseName(String p) {
  final i = p.lastIndexOf('/');
  return i < 0 ? p : p.substring(i + 1);
}

/// Compact, auto-dismissing message. Errors get an icon and a short timeout
/// instead of a tall block; long messages are clamped to three lines.
void toast(BuildContext c, String m, {bool error = false}) {
  final cs = Theme.of(c).colorScheme;
  final wide = MediaQuery.sizeOf(c).width > 640;
  final fg = error ? cs.onErrorContainer : cs.onInverseSurface;
  ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Row(children: [
        if (error) ...[Icon(Icons.error_outline, size: 18, color: fg), const SizedBox(width: 10)],
        Expanded(child: Text(m, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg))),
      ]),
      backgroundColor: error ? cs.errorContainer : null,
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: error ? 4 : 2),
      dismissDirection: DismissDirection.down,
      margin: wide ? null : const EdgeInsets.fromLTRB(12, 0, 12, 80),
      width: wide ? 420 : null,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    ));
}

void toastError(BuildContext c, Object e) => toast(c, ApiException.from(e).message, error: true);

Future<bool> confirm(BuildContext c, String title, String body,
    {String ok = 'Confirm', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: c,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error, foregroundColor: Theme.of(ctx).colorScheme.onError) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<void> copyText(BuildContext c, String text, [String msg = 'Copied']) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (c.mounted) toast(c, msg);
}

/// Runs [fn], showing errors as a toast. Returns null on failure.
Future<T?> guarded<T>(BuildContext c, Future<T> Function() fn) async {
  try {
    return await fn();
  } catch (e) {
    if (c.mounted) toastError(c, e);
    return null;
  }
}

// ---------------------------------------------------------------- forms
class FieldSpec {
  const FieldSpec(this.key, this.label,
      {this.initial = '', this.kind = 'text', this.required = false, this.hint, this.options = const [], this.number = false,
       this.maxBytes, this.initialUnit = 'GiB', this.initialBytes});
  final String key, label, initial, kind; // text | secret | multiline | bool | choice | path | cron | capacity
  final bool required, number;
  final String? hint;
  final List<String> options;
  final int? maxBytes, initialBytes;
  final String initialUnit;
}

/// Generic form dialog. Returns the values (bool fields => 'true'/'false').
Future<Map<String, String>?> formDialog(BuildContext context, String title, List<FieldSpec> fields,
    {String ok = 'Save', String? intro, Future<String?> Function(Map<String, String> values)? pick}) {
  final ctrls = {for (final f in fields) f.key: TextEditingController(text: f.initial)};
  final bools = {for (final f in fields.where((f) => f.kind == 'bool')) f.key: f.initial == 'true'};
  final choices = {for (final f in fields.where((f) => f.kind == 'choice')) f.key: f.initial.isEmpty ? f.options.first : f.initial};
  final capUnits = {for (final f in fields.where((f) => f.kind == 'capacity')) f.key: f.initialUnit};
  final capExactBytes = <String, int?>{for (final f in fields.where((f) => f.kind == 'capacity')) f.key: f.initialBytes};
  final capExactText = <String, String?>{
    for (final f in fields.where((f) => f.kind == 'capacity' && f.initialBytes != null)) f.key: f.initial.trim(),
  };
  final capExactUnit = <String, String?>{
    for (final f in fields.where((f) => f.kind == 'capacity' && f.initialBytes != null)) f.key: f.initialUnit,
  };
  final formKey = GlobalKey<FormState>();
  return showDialog<Map<String, String>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 460,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (intro != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(intro)),
                for (final f in fields)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: switch (f.kind) {
                      'bool' => SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(f.label),
                          value: bools[f.key]!,
                          onChanged: (v) => set(() => bools[f.key] = v)),
                      'choice' => DropdownButtonFormField<String>(
                          initialValue: choices[f.key],
                          decoration: InputDecoration(labelText: f.label),
                          items: [for (final o in f.options) DropdownMenuItem(value: o, child: Text(o))],
                          onChanged: (v) => set(() => choices[f.key] = v!)),
                      'capacity' => _CapacityField(
                          controller: ctrls[f.key]!,
                          unit: capUnits[f.key]!,
                          exactBytes: capExactBytes[f.key] != null &&
                                  capExactText[f.key] == ctrls[f.key]!.text.trim() &&
                                  capExactUnit[f.key] == capUnits[f.key]
                              ? capExactBytes[f.key]
                              : null,
                          maxBytes: f.maxBytes,
                          required: f.required,
                          label: f.label,
                          onUnitChanged: (u, bytes) => set(() {
                            capUnits[f.key] = u;
                            capExactBytes[f.key] = bytes;
                            capExactText[f.key] = bytes == null ? null : ctrls[f.key]!.text.trim();
                            capExactUnit[f.key] = bytes == null ? null : u;
                          }),
                          onExactBytesChanged: (bytes) => set(() {
                            capExactBytes[f.key] = bytes;
                            capExactText[f.key] = bytes == null ? null : ctrls[f.key]!.text.trim();
                            capExactUnit[f.key] = bytes == null ? null : capUnits[f.key];
                          }),
                          onValueChanged: () => set(() {}),
                        ),
                      'cron' => CronField(controller: ctrls[f.key]!),
                      'path' => TextFormField(
                          controller: ctrls[f.key],
                          decoration: InputDecoration(
                            labelText: f.label + (f.required ? ' *' : ''),
                            hintText: f.hint,
                            suffixIcon: pick == null
                                ? null
                                : IconButton(
                                    tooltip: 'Browse',
                                    icon: const Icon(Icons.folder_open),
                                    onPressed: () async {
                                      final cur = {
                                        for (final x in fields)
                                          x.key: switch (x.kind) {
                                            'bool' => '${bools[x.key]}',
                                            'choice' => choices[x.key]!,
                                            _ => ctrls[x.key]!.text.trim(),
                                          }
                                      };
                                      final r = await pick(cur);
                                      if (r != null) ctrls[f.key]!.text = r;
                                    }),
                          ),
                          validator: f.required ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null : null,
                        ),
                      _ => TextFormField(
                          controller: ctrls[f.key],
                          obscureText: f.kind == 'secret',
                          minLines: f.kind == 'multiline' ? 3 : 1,
                          maxLines: f.kind == 'multiline' ? 6 : 1,
                          keyboardType: f.number ? TextInputType.number : null,
                          decoration: InputDecoration(labelText: f.label + (f.required ? ' *' : ''), hintText: f.hint),
                          validator: f.required ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null : null,
                        ),
                    },
                  ),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              for (final f in fields.where((f) => f.kind == 'capacity')) {
                final raw = ctrls[f.key]!.text.trim();
                final n = double.tryParse(raw.replaceAll(',', '.'));
                final hasExact = capExactBytes[f.key] != null &&
                    capExactText[f.key] == raw &&
                    capExactUnit[f.key] == capUnits[f.key];
                final bytes = raw.isEmpty
                    ? 0
                    : hasExact
                        ? capExactBytes[f.key]!
                        : (n != null && n.isFinite && n >= 0
                            ? (n * (_capacityFactors[capUnits[f.key]!] ?? _capacityFactors['GiB']!)).round()
                            : -1);
                if ((f.required && raw.isEmpty) || bytes < 0 || (f.maxBytes != null && bytes > f.maxBytes!)) return;
              }
              Navigator.pop(ctx, {
                for (final f in fields)
                  f.key: switch (f.kind) {
                    'bool' => '${bools[f.key]}',
                    'choice' => choices[f.key]!,
                    'capacity' => capExactBytes[f.key] != null &&
                            capExactText[f.key] == ctrls[f.key]!.text.trim() &&
                            capExactUnit[f.key] == capUnits[f.key]
                        ? capExactBytes[f.key]!.toString()
                        : _capacityBytesText(ctrls[f.key]!.text, capUnits[f.key]!),
                    _ => ctrls[f.key]!.text.trim(),
                  }
              });
            },
            child: Text(ok),
          ),
        ],
      ),
    ),
  );
}


const _capacityFactors = <String, double>{
  'MiB': 1024 * 1024,
  'GiB': 1024 * 1024 * 1024,
  'TiB': 1024 * 1024 * 1024 * 1024,
};

String _capacityBytesText(String text, String unit) {
  final n = double.tryParse(text.trim().replaceAll(',', '.'));
  if (n == null || n < 0 || !n.isFinite) return '';
  return (n * (_capacityFactors[unit] ?? _capacityFactors['GiB']!)).round().toString();
}

class _CapacityField extends StatefulWidget {
  const _CapacityField({required this.controller, required this.unit, required this.exactBytes,
      required this.maxBytes, required this.required, required this.label,
      required this.onUnitChanged, required this.onExactBytesChanged, required this.onValueChanged});
  final TextEditingController controller;
  final String unit;
  final int? exactBytes, maxBytes;
  final bool required;
  final String label;
  final void Function(String unit, int? exactBytes) onUnitChanged;
  final ValueChanged<int?> onExactBytesChanged;
  final VoidCallback onValueChanged;

  @override
  State<_CapacityField> createState() => _CapacityFieldState();
}

class _CapacityFieldState extends State<_CapacityField> {
  String? get _error {
    final text = widget.controller.text.trim();
    if (text.isEmpty) return widget.required ? 'Required' : null;
    final n = double.tryParse(text.replaceAll(',', '.'));
    if (n == null || !n.isFinite || n < 0) return 'Enter a valid capacity';
    if (widget.maxBytes != null) {
      final bytes = widget.exactBytes ?? (n * (_capacityFactors[widget.unit] ?? _capacityFactors['GiB']!)).round();
      if (bytes > widget.maxBytes!) return 'Over maximum (${_formatCapacity(widget.maxBytes!)})';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final over = error?.startsWith('Over maximum') == true;
    final cs = Theme.of(context).colorScheme;
    final raw = double.tryParse(widget.controller.text.trim().replaceAll(',', '.'));
    final exactBytes = widget.exactBytes ?? (raw != null && raw.isFinite && raw >= 0
        ? (raw * (_capacityFactors[widget.unit] ?? _capacityFactors['GiB']!)).round()
        : null);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: TextField(
          controller: widget.controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) {
            widget.onExactBytesChanged(null);
            widget.onValueChanged();
            setState(() {});
          },
          decoration: InputDecoration(
            labelText: '${widget.label}${widget.required ? ' *' : ''}',
            errorText: error,
            errorMaxLines: 2,
            helperText: exactBytes == null ? null : 'Exact: ${NumberFormat.decimalPattern().format(exactBytes)} bytes',
            prefixIcon: over ? Icon(Icons.warning_amber_rounded, color: cs.error) : null,
          ),
        ),
      ),
      const SizedBox(width: 8),
      SizedBox(
        width: 88,
        child: DropdownButtonFormField<String>(
          initialValue: widget.unit,
          decoration: const InputDecoration(labelText: 'Unit'),
          items: [for (final u in _capacityFactors.keys) DropdownMenuItem(value: u, child: Text(u))],
          onChanged: (u) {
            if (u == null || u == widget.unit) return;
            final text = widget.controller.text.trim();
            final current = double.tryParse(text.replaceAll(',', '.'));
            int? bytes;
            if (current != null && current.isFinite && current >= 0) {
              final oldFactor = _capacityFactors[widget.unit] ?? _capacityFactors['GiB']!;
              final newFactor = _capacityFactors[u] ?? _capacityFactors['GiB']!;
              bytes = widget.exactBytes ?? (current * oldFactor).round();
              widget.controller.text = text.isEmpty ? '' : (bytes / newFactor).toStringAsFixed(2);
            }
            widget.onUnitChanged(u, bytes);
            widget.onValueChanged();
            setState(() {});
          },
        ),
      ),
    ]);
  }
}

String _formatCapacity(int bytes) {
  for (final e in const [('TiB', 1099511627776), ('GiB', 1073741824), ('MiB', 1048576)]) {
    if (bytes.abs() >= e.$2) return '${(bytes / e.$2).toStringAsFixed(bytes % e.$2 == 0 ? 0 : 2)} ${e.$1}';
  }
  return '$bytes B';
}

Future<String?> promptText(BuildContext c, String title, String label,
    {String initial = '', String ok = 'OK'}) async {
  final r = await formDialog(c, title, [FieldSpec('v', label, initial: initial, required: true)], ok: ok);
  return r?['v'];
}

List<String> splitList(String s) =>
    s.split(RegExp(r'[,\n]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

int? parseMegabytes(String s) {
  final v = double.tryParse(s.trim());
  return v == null ? null : (v * 1024 * 1024).round();
}
