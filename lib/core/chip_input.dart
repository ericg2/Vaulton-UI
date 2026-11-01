import 'package:flutter/material.dart';

/// Type a value, press enter or comma, and it becomes a removable chip.
/// Replaces comma-separated text boxes.
class ChipInput extends StatefulWidget {
  const ChipInput({super.key, required this.values, required this.onChanged, required this.label, this.hint});
  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  final String label;
  final String? hint;

  @override
  State<ChipInput> createState() => _ChipInputState();
}

class _ChipInputState extends State<ChipInput> {
  final _c = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final parts = _c.text.split(RegExp(r'[,\n]')).map((e) => e.trim()).where((e) => e.isNotEmpty);
    final next = [...widget.values];
    for (final p in parts) {
      if (!next.contains(p)) next.add(p);
    }
    _c.clear();
    if (next.length != widget.values.length) widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (widget.values.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final v in widget.values)
              InputChip(
                label: Text(v),
                visualDensity: VisualDensity.compact,
                onDeleted: () => widget.onChanged([...widget.values]..remove(v)),
              ),
          ]),
        ),
      TextField(
        controller: _c,
        focusNode: _focus,
        autocorrect: false,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          suffixIcon: IconButton(tooltip: 'Add', icon: const Icon(Icons.add), onPressed: _commit),
        ),
        onChanged: (t) {
          if (t.endsWith(',')) _commit();
        },
        onSubmitted: (_) {
          _commit();
          _focus.requestFocus();
        },
      ),
    ]);
  }
}

/// A small − / + counter. Zero means "off".
class CountStepper extends StatelessWidget {
  const CountStepper({super.key, required this.title, required this.help, required this.value, required this.onChanged, this.max = 999, this.unit = ''});
  final String title, help, unit;
  final int value, max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: t.bodyLarge),
            Text(help, style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ]),
        ),
        IconButton.outlined(
          tooltip: 'Decrease',
          visualDensity: VisualDensity.compact,
          onPressed: value > 0 ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove, size: 18),
        ),
        SizedBox(
          width: 56,
          child: Text(value == 0 ? 'Off' : '$value$unit', textAlign: TextAlign.center, style: t.titleSmall?.copyWith(color: value == 0 ? cs.outline : cs.primary)),
        ),
        IconButton.outlined(
          tooltip: 'Increase',
          visualDensity: VisualDensity.compact,
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add, size: 18),
        ),
      ]),
    );
  }
}
