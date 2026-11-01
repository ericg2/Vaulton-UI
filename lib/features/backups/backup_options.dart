import 'package:flutter/material.dart';
import '../../core/chip_input.dart';
import '../../core/models.dart';
import '../files/folder_picker.dart';

/// Everything the person chose in the backup sheet.
class BackupRequest {
  BackupRequest({required this.data, required this.repo, required this.path, required this.tags, required this.include, required this.skip, this.maxFileSize, required this.dryRun});
  final Point data, repo;
  final String path;
  final List<String> tags, include, skip;
  final int? maxFileSize;
  final bool dryRun;

  Map<String, dynamic> toBody() => {
        'dataId': data.id,
        'path': path,
        'tags': tags,
        'globs': include,
        'ignoreGlobs': skip,
        if (maxFileSize != null) 'maxFileSize': maxFileSize,
        'dryRun': dryRun,
      };
}

class _Preset {
  const _Preset(this.label, this.icon, this.patterns);
  final String label;
  final IconData icon;
  final List<String> patterns;
}

const _includePresets = [
  _Preset('Photos', Icons.photo_outlined, ['*.jpg', '*.jpeg', '*.png', '*.heic', '*.gif', '*.webp']),
  _Preset('Videos', Icons.movie_outlined, ['*.mp4', '*.mov', '*.mkv', '*.avi']),
  _Preset('Documents', Icons.description_outlined, ['*.pdf', '*.doc', '*.docx', '*.xls', '*.xlsx', '*.ppt', '*.pptx', '*.txt', '*.odt']),
  _Preset('Music', Icons.music_note_outlined, ['*.mp3', '*.flac', '*.wav', '*.m4a']),
];

const _skipPresets = [
  _Preset('Temporary files', Icons.hourglass_empty, ['*.tmp', '*.temp', '~\$*']),
  _Preset('Logs and caches', Icons.cached, ['*.log', '.cache', 'Cache']),
  _Preset('System clutter', Icons.visibility_off_outlined, ['.DS_Store', 'Thumbs.db', 'desktop.ini']),
  _Preset('Developer folders', Icons.code, ['node_modules', '.git']),
];

const _sizeChoices = <(String, int?)>[
  ('No limit', null),
  ('100 MB', 100 * 1024 * 1024),
  ('500 MB', 500 * 1024 * 1024),
  ('1 GB', 1024 * 1024 * 1024),
  ('5 GB', 5 * 1024 * 1024 * 1024),
];

/// Bottom sheet for starting a backup. Pass [data] / [repo] to pre-select them.
Future<BackupRequest?> showBackupSheet(BuildContext context, {required List<Point> datas, required List<Point> repos, Point? data, Point? repo}) {
  return showModalBottomSheet<BackupRequest>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) => _BackupSheet(datas: datas, repos: repos, data: data, repo: repo),
  );
}

class _BackupSheet extends StatefulWidget {
  const _BackupSheet({required this.datas, required this.repos, this.data, this.repo});
  final List<Point> datas, repos;
  final Point? data, repo;
  @override
  State<_BackupSheet> createState() => _BackupSheetState();
}

class _BackupSheetState extends State<_BackupSheet> {
  late Point _data = widget.datas.firstWhere((d) => d.id == widget.data?.id, orElse: () => widget.datas.first);
  late Point _repo = widget.repos.firstWhere((r) => r.id == widget.repo?.id, orElse: () => widget.repos.first);
  String _path = '/';
  bool _onlySome = false, _dry = false;
  final _includeKinds = <String>{};
  final _skipKinds = <String>{};
  List<String> _customInclude = [], _customSkip = [], _labels = [];
  int? _maxSize;

  List<String> _expand(Set<String> kinds, List<_Preset> presets) => [
        for (final p in presets)
          if (kinds.contains(p.label)) ...p.patterns,
      ];

  Future<void> _chooseFolder() async {
    final r = await pickFolder(context, initialPointId: _data.id, initialPath: _path, title: 'Choose a folder to back up');
    if (r != null && mounted) setState(() => _path = r.path);
  }

  void _start() {
    final include = _onlySome ? {..._expand(_includeKinds, _includePresets), ..._customInclude}.toList() : <String>[];
    final skip = {..._expand(_skipKinds, _skipPresets), ..._customSkip}.toList();
    Navigator.pop(
      context,
      BackupRequest(data: _data, repo: _repo, path: _path.isEmpty ? '/' : _path, tags: _labels, include: include, skip: skip, maxFileSize: _maxSize, dryRun: _dry),
    );
  }

  Widget _heading(String title, String help) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: t.titleSmall),
        Text(help, style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]),
    );
  }

  Widget _kinds(List<_Preset> presets, Set<String> selected) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final p in presets)
          FilterChip(
            avatar: Icon(p.icon, size: 18),
            label: Text(p.label),
            selected: selected.contains(p.label),
            onSelected: (v) => setState(() => v ? selected.add(p.label) : selected.remove(p.label)),
          ),
      ]);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Start a Backup', style: t.headlineSmall),
              const SizedBox(height: 4),
              Text('Saves a snapshot, a restorable copy of your files as they are now.',
                  style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 16),
              if (widget.datas.length > 1)
                DropdownButtonFormField<Point>(
                  isExpanded: true,
                  initialValue: _data,
                  decoration: const InputDecoration(labelText: 'Backup From', prefixIcon: Icon(Icons.folder_outlined)),
                  items: [for (final d in widget.datas) DropdownMenuItem(value: d, child: Text(d.name))],
                  onChanged: (d) => setState(() {
                    if (d != null) {
                      _data = d;
                      _path = '/';
                    }
                  }),
                ),
              if (widget.datas.length > 1) const SizedBox(height: 12),
              if (widget.repos.length > 1)
                DropdownButtonFormField<Point>(
                  isExpanded: true,
                  initialValue: _repo,
                  decoration: const InputDecoration(labelText: 'Save To', prefixIcon: Icon(Icons.inventory_2_outlined)),
                  items: [for (final r in widget.repos) DropdownMenuItem(value: r, child: Text(r.name))],
                  onChanged: (r) => setState(() => _repo = r ?? _repo),
                ),
              if (widget.repos.length > 1) const SizedBox(height: 12),
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.folder_open),
                  title: Text(_path == '/' ? 'Everything' : _path),
                  subtitle: Text(_path == '/' ? 'Backs up all of “${_data.name}”' : 'Only this folder and what’s inside it'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _chooseFolder,
                ),
              ),
              _heading('What to include', 'Back up everything, or only certain kinds of files.'),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('Everything')),
                  ButtonSegment(value: true, label: Text('Only Certain Files')),
                ],
                selected: {_onlySome},
                onSelectionChanged: (s) => setState(() => _onlySome = s.first),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _onlySome
                    ? Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          _kinds(_includePresets, _includeKinds),
                          const SizedBox(height: 12),
                          ChipInput(label: 'Other File Types', hint: 'For example *.csv', values: _customInclude, onChanged: (v) => setState(() => _customInclude = v)),
                        ]),
                      )
                    : const SizedBox(width: double.infinity),
              ),
              _heading('What to skip', 'Leave out files you don’t need to keep.'),
              _kinds(_skipPresets, _skipKinds),
              const SizedBox(height: 12),
              ChipInput(label: 'Other files or folders to skip', hint: 'For example *.iso or Downloads', values: _customSkip, onChanged: (v) => setState(() => _customSkip = v)),
              _heading('Skip very large files', 'Files bigger than this won’t be backed up.'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final c in _sizeChoices)
                  ChoiceChip(label: Text(c.$1), selected: _maxSize == c.$2, onSelected: (_) => setState(() => _maxSize = c.$2)),
              ]),
              _heading('Labels', 'Optional. Add a word or two to help you find this snapshot later.'),
              ChipInput(label: 'Add a Label', hint: 'For example Before upgrade', values: _labels, onChanged: (v) => setState(() => _labels = v)),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Test Run Only'),
                subtitle: const Text('See what would be backed up without saving anything.'),
                value: _dry,
                onChanged: (v) => setState(() => _dry = v),
              ),
            ]),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: _start,
                icon: const Icon(Icons.backup_outlined),
                label: Text(_dry ? 'Start Test Run' : 'Start Backup'),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

// ============================================================ RETENTION

class RetentionRequest {
  RetentionRequest(this.policy, this.dryRun);
  final Map<String, int> policy;
  final bool dryRun;
}

class _Plan {
  const _Plan(this.label, this.help, this.icon, this.values);
  final String label, help;
  final IconData icon;
  final Map<String, int> values;
}

const _plans = [
  _Plan('Space first', 'Keep at least 10% of the vault quota free; older snapshots are removed only as needed.', Icons.storage_outlined, {'reservePercent': 10}),
  _Plan('Recent', 'Last 10 snapshots and one a day for a week.', Icons.bolt_outlined, {'keepLast': 10, 'keepDaily': 7}),
  _Plan('Balanced', 'Daily for a week, weekly for a month, monthly for half a year.', Icons.balance, {'keepDaily': 7, 'keepWeekly': 4, 'keepMonthly': 6}),
  _Plan('Long term', 'Adds a full year of months, plus three yearly snapshots.', Icons.history_toggle_off, {'keepDaily': 7, 'keepWeekly': 4, 'keepMonthly': 12, 'keepYearly': 3}),
];

const _ruleKeys = ['keepLast', 'keepHourly', 'keepDaily', 'keepWeekly', 'keepMonthly', 'keepYearly', 'keepWithinDays', 'reservePercent'];

String _s(int n, String one, [String? many]) => n == 1 ? one : (many ?? '${one}s');

/// Plain-language sentence for a policy.
String describeRetention(Map<String, int> p) {
  int g(String k) => p[k] ?? 0;
  final parts = <String>[
    if (g('keepLast') > 0) 'the latest ${g('keepLast')} ${_s(g('keepLast'), 'snapshot')}',
    if (g('keepHourly') > 0) 'one per hour for ${g('keepHourly')} ${_s(g('keepHourly'), 'hour')}',
    if (g('keepDaily') > 0) 'one per day for ${g('keepDaily')} ${_s(g('keepDaily'), 'day')}',
    if (g('keepWeekly') > 0) 'one per week for ${g('keepWeekly')} ${_s(g('keepWeekly'), 'week')}',
    if (g('keepMonthly') > 0) 'one per month for ${g('keepMonthly')} ${_s(g('keepMonthly'), 'month')}',
    if (g('keepYearly') > 0) 'one per year for ${g('keepYearly')} ${_s(g('keepYearly'), 'year')}',
    if (g('keepWithinDays') > 0) 'everything from the last ${g('keepWithinDays')} ${_s(g('keepWithinDays'), 'day')}',
  ];
  var text = parts.isEmpty
      ? (g('reservePercent') > 0
          ? 'Removes older snapshots only as needed to maintain free space.'
          : 'Nothing selected yet.')
      : 'Keeps ${parts.length == 1 ? parts.first : '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}'}.';
  if (g('reservePercent') > 0) {
    text += parts.isEmpty
        ? ' Targets ${g('reservePercent')}% of the vault quota free.'
        : ' Also targets ${g('reservePercent')}% of the vault quota free.';
  }
  return text;
}

/// Sheet for choosing how long to keep snapshots.
Future<RetentionRequest?> showRetentionSheet(BuildContext context, {bool forSchedule = false, Map<String, dynamic>? initial}) => showModalBottomSheet<RetentionRequest>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => _RetentionSheet(forSchedule: forSchedule, initial: initial),
    );

class _RetentionSheet extends StatefulWidget {
  const _RetentionSheet({this.forSchedule = false, this.initial});
  final bool forSchedule;
  final Map<String, dynamic>? initial;
  @override
  State<_RetentionSheet> createState() => _RetentionSheetState();
}

class _RetentionSheetState extends State<_RetentionSheet> {
  int _plan = 0; // index into _plans, or -1 for custom
  late Map<String, int> _v = {for (final k in _ruleKeys) k: _plans[0].values[k] ?? 0};
  late bool _preview = !widget.forSchedule;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    if (init != null && init.isNotEmpty) {
      _v = {for (final k in _ruleKeys) k: int.tryParse('${init[k] ?? 0}') ?? 0};
      _plan = _plans.indexWhere((p) => _ruleKeys.every((k) => (p.values[k] ?? 0) == _v[k]));
    }
  }

  void _pick(int i) => setState(() {
        _plan = i;
        _v = {for (final k in _ruleKeys) k: _plans[i].values[k] ?? 0};
      });

  void _set(String k, int n) => setState(() {
        _v[k] = n;
        _plan = -1;
      });

  Widget _rule(String key, String title, String help, {String unit = '', int max = 999}) =>
      CountStepper(title: title, help: help, value: _v[key] ?? 0, onChanged: (n) => _set(key, n), unit: unit, max: max);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final empty = _v.values.every((n) => n == 0);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.forSchedule ? 'Automatic Cleanup Plan' : 'Clean up old snapshots once', style: t.headlineSmall),
            const SizedBox(height: 4),
            Text('${widget.forSchedule ? 'This plan runs on a schedule, so your vault stays tidy on its own.' : 'This runs once and isn’t remembered. Use automatic cleanup to repeat it.'} Snapshots outside these rules are forgotten, then the repository is pruned so only data no remaining snapshot needs is reclaimed. Shared data remains while another snapshot references it; pruning reclaims only data that is no longer needed. Locked snapshots and the newest snapshot in each backup series are always kept. Preview cleanup to see candidate snapshots before deleting anything.',
                style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 16),
            for (var i = 0; i < _plans.length; i++)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: _plan == i ? cs.secondaryContainer : null,
                child: ListTile(
                  leading: Icon(_plans[i].icon),
                  title: Text(_plans[i].label),
                  subtitle: Text(_plans[i].help),
                  trailing: _plan == i ? const Icon(Icons.check_circle) : null,
                  onTap: () => _pick(i),
                ),
              ),
            Card(
              margin: EdgeInsets.zero,
              color: _plan == -1 ? cs.secondaryContainer : null,
              child: ExpansionTile(
                initiallyExpanded: false,
                shape: const Border(),
                collapsedShape: const Border(),
                leading: const Icon(Icons.tune),
                title: const Text('Custom'),
                subtitle: const Text('Set each rule yourself.'),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [
                  _rule('keepLast', 'Latest snapshots', 'Always keep the newest few'),
                  _rule('keepHourly', 'Hourly', 'One per hour, for this many hours'),
                  _rule('keepDaily', 'Daily', 'One per day, for this many days'),
                  _rule('keepWeekly', 'Weekly', 'One per week, for this many weeks'),
                  _rule('keepMonthly', 'Monthly', 'One per month, for this many months'),
                  _rule('keepYearly', 'Yearly', 'One per year, for this many years'),
                  _rule('keepWithinDays', 'Recent days', 'Keep everything from the last few days'),
                  _rule('reservePercent', 'Free space', 'Primary rule: remove older snapshots as needed to keep this much of the vault quota free. Date rules can be added as extra safeguards.', unit: '%', max: 50),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Container(
                key: ValueKey(describeRetention(_v)),
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.info_outline, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(describeRetention(_v), style: t.bodyMedium)),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            if (!widget.forSchedule)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Preview First'),
              subtitle: const Text('Previews what would be removed. Nothing is deleted.'),
              value: _preview,
              onChanged: (v) => setState(() => _preview = v),
            ),
          ]),
        ),
      ),
      const Divider(height: 1),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed:
                  empty
                      ? null
                      : () => Navigator.pop(
                        context,
                        RetentionRequest(Map.of(_v), _preview),
                      ),
              icon: Icon(
                widget.forSchedule
                    ? Icons.check
                    : (_preview
                        ? Icons.visibility_outlined
                        : Icons.auto_delete_outlined),
              ),
              label: Text(
                widget.forSchedule
                    ? 'Use This Plan'
                    : (_preview ? 'Preview cleanup' : 'Clean up now'),
              ),
            ),
          ],
        ),
      ),
    ]);
  }
}
