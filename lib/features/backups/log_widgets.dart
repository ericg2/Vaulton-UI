import 'package:flutter/material.dart';
import '../../core/util.dart';

const logPriorityOptions = <(String label, String? value)>[
  ('All Priorities', null),
  ('Debug', 'Debug'),
  ('Info', 'Info'),
  ('Warning', 'Warn'),
  ('Error', 'Error'),
];

String logPriorityLabel(String? value) => value == null
    ? 'All Priorities'
    : (value == 'Warn' ? 'Warning' : value);

Color logPriorityColor(BuildContext context, String value) {
  final cs = Theme.of(context).colorScheme;
  final p = value.toLowerCase();
  if (p.contains('err') || p.contains('crit') || p.contains('fatal')) return cs.error;
  if (p.contains('warn')) return cs.tertiary;
  if (p.contains('debug') || p.contains('trace')) return cs.outline;
  return cs.primary;
}

bool logPriorityMatches(String value, String? minimum) {
  if (minimum == null || minimum == 'Debug') return true;
  final p = value.toLowerCase();
  final rank = p.contains('err') || p.contains('crit') || p.contains('fatal')
      ? 3
      : p.contains('warn')
          ? 2
          : p.contains('info')
              ? 1
              : 0;
  final wanted = minimum == 'Error' ? 3 : minimum == 'Warn' ? 2 : 1;
  return rank >= wanted;
}

class LogFilterBar extends StatelessWidget {
  const LogFilterBar({
    super.key,
    required this.searchController,
    required this.search,
    required this.priority,
    required this.onSearch,
    required this.onPriority,
    this.from,
    this.to,
    this.onDates,
    this.onCopy,
    this.copyEnabled = false,
  });

  final TextEditingController searchController;
  final String search;
  final String? priority;
  final ValueChanged<String> onSearch;
  final ValueChanged<String?> onPriority;
  final DateTime? from;
  final DateTime? to;
  final VoidCallback? onDates;
  final VoidCallback? onCopy;
  final bool copyEnabled;

  @override
  Widget build(BuildContext context) {
    final dateLabel = from == null
        ? 'Any Date'
        : '${fmtDate(from)} – ${fmtDate(to!.subtract(const Duration(seconds: 1)))}';
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 560;
        return Padding(
          padding: EdgeInsets.fromLTRB(narrow ? 8 : 12, 8, narrow ? 8 : 12, 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              SizedBox(
                width: narrow ? constraints.maxWidth - 16 : 280,
                child: TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Search Log',
                    suffixIcon: search.isEmpty ? null : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () { searchController.clear(); onSearch(''); },
                    ),
                  ),
                  onSubmitted: onSearch,
                ),
              ),
              for (final option in logPriorityOptions)
                ChoiceChip(
                  label: Text(option.$1),
                  selected: priority == option.$2,
                  onSelected: (_) => onPriority(option.$2),
                ),
              if (onDates != null)
                OutlinedButton.icon(
                  onPressed: onDates,
                  icon: const Icon(Icons.date_range),
                  label: Text(dateLabel),
                ),
              if (onCopy != null)
                IconButton(
                  tooltip: 'Copy Visible Lines',
                  icon: const Icon(Icons.copy_all_outlined),
                  onPressed: copyEnabled ? onCopy : null,
                ),
            ],
          ),
        );
      },
    );
  }
}}

class LogLine extends StatelessWidget {
  const LogLine({super.key, required this.time, required this.priority, required this.message});

  final DateTime? time;
  final String priority;
  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = logPriorityColor(context, priority);
    final p = priority.length > 4 ? priority.substring(0, 4).toUpperCase() : priority.toUpperCase();
    return Container(
      color: priority.toLowerCase().contains('err') ? cs.errorContainer.withValues(alpha: 0.35) : null,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 68,
            child: Text(
              time == null ? '--:--:--' : _hms(time!),
              style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: cs.outline),
            ),
          ),
          SizedBox(
            width: 56,
            child: Text(
              p,
              style: TextStyle(fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.bold, color: color),
            ),
          ),
          Expanded(child: Text(message, style: TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: color))),
        ],
      ),
    );
  }
}

String _hms(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
