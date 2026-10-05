import 'package:flutter/material.dart';

enum _Freq { minutes, hours, hourly, daily, weekly, monthly, custom }

const _freqLabels = {
  _Freq.minutes: 'Every few minutes',
  _Freq.hours: 'Every few hours',
  _Freq.hourly: 'Hourly',
  _Freq.daily: 'Daily',
  _Freq.weekly: 'Weekly',
  _Freq.monthly: 'Monthly',
  _Freq.custom: 'Custom (Cron)',
};

// Chips run Monday-first; values are cron weekday numbers (0 = Sunday).
const _days = [('Mon', 1), ('Tue', 2), ('Wed', 3), ('Thu', 4), ('Fri', 5), ('Sat', 6), ('Sun', 0)];

/// Friendly schedule editor that reads and writes a standard 5-field cron string
/// through [controller]. Anything it can't express falls back to "Custom".
class CronField extends StatefulWidget {
  const CronField({super.key, required this.controller});
  final TextEditingController controller;
  @override
  State<CronField> createState() => _CronFieldState();
}

class _CronFieldState extends State<CronField> {
  _Freq _f = _Freq.daily;
  int _every = 15, _minute = 0, _dom = 1;
  TimeOfDay _time = const TimeOfDay(hour: 2, minute: 0);
  final Set<int> _wd = {1, 2, 3, 4, 5};

  @override
  void initState() {
    super.initState();
    _parse(widget.controller.text.trim());
    _emit(notify: false);
  }

  void _parse(String c) {
    final p = c.split(RegExp(r'\s+'));
    if (p.length != 5) {
      _f = _Freq.daily;
      return;
    }
    final m = int.tryParse(p[0]), h = int.tryParse(p[1]), d = int.tryParse(p[2]);
    final step = RegExp(r'^\*/(\d+)$');
    if (step.hasMatch(p[0]) && p[1] == '*' && p[2] == '*' && p[3] == '*' && p[4] == '*') {
      _f = _Freq.minutes;
      _every = int.parse(step.firstMatch(p[0])!.group(1)!);
    } else if (m != null && step.hasMatch(p[1]) && p[2] == '*' && p[3] == '*' && p[4] == '*') {
      _f = _Freq.hours;
      _minute = m;
      _every = int.parse(step.firstMatch(p[1])!.group(1)!);
    } else if (m != null && p[1] == '*' && p[2] == '*' && p[3] == '*' && p[4] == '*') {
      _f = _Freq.hourly;
      _minute = m;
    } else if (m != null && h != null && p[2] == '*' && p[3] == '*' && p[4] == '*') {
      _f = _Freq.daily;
      _time = TimeOfDay(hour: h, minute: m);
    } else if (m != null && h != null && p[2] == '*' && p[3] == '*' && RegExp(r'^[0-7](,[0-7])*$').hasMatch(p[4])) {
      _f = _Freq.weekly;
      _time = TimeOfDay(hour: h, minute: m);
      _wd
        ..clear()
        ..addAll(p[4].split(',').map((e) => int.parse(e) % 7));
    } else if (m != null && h != null && d != null && d >= 1 && d <= 28 && p[3] == '*' && p[4] == '*') {
      _f = _Freq.monthly;
      _time = TimeOfDay(hour: h, minute: m);
      _dom = d;
    } else {
      _f = _Freq.custom;
    }
  }

  String _build() {
    switch (_f) {
      case _Freq.minutes:
        return '*/$_every * * * *';
      case _Freq.hours:
        return '$_minute */$_every * * *';
      case _Freq.hourly:
        return '$_minute * * * *';
      case _Freq.daily:
        return '${_time.minute} ${_time.hour} * * *';
      case _Freq.weekly:
        final d = (_wd.isEmpty ? {1} : _wd).toList()..sort();
        return '${_time.minute} ${_time.hour} * * ${d.length == 7 ? '*' : d.join(',')}';
      case _Freq.monthly:
        return '${_time.minute} ${_time.hour} $_dom * *';
      case _Freq.custom:
        return widget.controller.text;
    }
  }

  void _emit({bool notify = true}) {
    if (_f != _Freq.custom) widget.controller.text = _build();
    if (notify) setState(() {});
  }

  String _describe(BuildContext context) {
    final t = MaterialLocalizations.of(context).formatTimeOfDay(_time);
    return switch (_f) {
      _Freq.minutes => 'Runs every $_every minute${_every == 1 ? '' : 's'}',
      _Freq.hours => 'Runs every $_every hour${_every == 1 ? '' : 's'}, at ${_minute.toString().padLeft(2, '0')} minutes past',
      _Freq.hourly => 'Runs every hour, ${_minute.toString().padLeft(2, '0')} minutes past',
      _Freq.daily => 'Runs every day at $t',
      _Freq.weekly => 'Runs ${_wd.length == 7 ? 'every day' : 'every ${[for (final d in _days) if (_wd.contains(d.$2)) d.$1].join(', ')}'} at $t',
      _Freq.monthly => 'Runs on day $_dom of every month at $t',
      _Freq.custom => 'Custom cron expression',
    };
  }

  Widget _numberDropdown(String label, int value, List<int> options, void Function(int) onChanged, {String Function(int)? fmt}) =>
      DropdownButtonFormField<int>(
        initialValue: options.contains(value) ? value : options.first,
        decoration: InputDecoration(labelText: label),
        items: [for (final o in options) DropdownMenuItem(value: o, child: Text(fmt?.call(o) ?? '$o'))],
        onChanged: (v) {
          onChanged(v!);
          _emit();
        },
      );

  Widget _timeButton() => OutlinedButton.icon(
        icon: const Icon(Icons.access_time),
        label: Text(MaterialLocalizations.of(context).formatTimeOfDay(_time)),
        onPressed: () async {
          final r = await showTimePicker(context: context, initialTime: _time);
          if (r != null) {
            _time = r;
            _emit();
          }
        },
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cron = widget.controller.text;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      DropdownButtonFormField<_Freq>(
        initialValue: _f,
        decoration: const InputDecoration(labelText: 'Frequency'),
        items: [for (final f in _Freq.values) DropdownMenuItem(value: f, child: Text(_freqLabels[f]!))],
        onChanged: (v) {
          if (v == null) return;
          if (v == _Freq.custom) widget.controller.text = _build();
          _f = v;
          _emit();
        },
      ),
      const SizedBox(height: 12),
      if (_f == _Freq.minutes) _numberDropdown('Every', _every, const [1, 2, 5, 10, 15, 20, 30], (v) => _every = v, fmt: (n) => '$n minute${n == 1 ? '' : 's'}'),
      if (_f == _Freq.hours) ...[
        _numberDropdown('Every', _every, const [1, 2, 3, 4, 6, 8, 12], (v) => _every = v, fmt: (n) => '$n hour${n == 1 ? '' : 's'}'),
        const SizedBox(height: 12),
        _numberDropdown('At minute', _minute, const [0, 5, 10, 15, 20, 30, 45], (v) => _minute = v, fmt: (n) => ':${n.toString().padLeft(2, '0')}'),
      ],
      if (_f == _Freq.hourly) _numberDropdown('At minute', _minute, const [0, 5, 10, 15, 20, 30, 45], (v) => _minute = v, fmt: (n) => ':${n.toString().padLeft(2, '0')}'),
      if (_f == _Freq.daily) _timeButton(),
      if (_f == _Freq.weekly) ...[
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final d in _days)
            FilterChip(
              label: Text(d.$1),
              selected: _wd.contains(d.$2),
              onSelected: (s) {
                if (s) {
                  _wd.add(d.$2);
                } else if (_wd.length > 1) {
                  _wd.remove(d.$2);
                }
                _emit();
              },
            ),
        ]),
        const SizedBox(height: 12),
        _timeButton(),
      ],
      if (_f == _Freq.monthly) ...[
        _numberDropdown('Day of Month', _dom, [for (var i = 1; i <= 28; i++) i], (v) => _dom = v),
        const SizedBox(height: 12),
        _timeButton(),
      ],
      if (_f == _Freq.custom)
        TextFormField(
          controller: widget.controller,
          decoration: const InputDecoration(labelText: 'Cron expression *', hintText: 'min hour day month weekday'),
          onChanged: (_) => setState(() {}),
          validator: (v) => (v == null || v.trim().split(RegExp(r'\s+')).length < 5) ? 'Needs 5 fields' : null,
        ),
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(12)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.schedule, size: 18, color: cs.onSecondaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_describe(context), style: TextStyle(color: cs.onSecondaryContainer, fontWeight: FontWeight.w600)),
                Text(cron, style: TextStyle(color: cs.onSecondaryContainer, fontFamily: 'monospace', fontSize: 12)),
              ]),
            ),
          ]),
        ),
      ),
    ]);
  }
}
