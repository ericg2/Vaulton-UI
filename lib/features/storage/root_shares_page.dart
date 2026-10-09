import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/util.dart';
import '../../core/vaulton.dart';
import '../../core/widgets.dart';
import 'share_logic.dart';

/// Who a storage root is shared with, and how much of it each person may use.
///
/// * People come from a searchable dropdown (name, user name or e-mail); users that already
///   have access, and the owner, are left out.
/// * Quotas are validated, and the total is compared with the root's capacity.
class RootSharesPage extends ConsumerStatefulWidget {
  const RootSharesPage({super.key, required this.root});
  final Root root;

  @override
  ConsumerState<RootSharesPage> createState() => _RootSharesPageState();
}

class _ShareRow {
  _ShareRow(this.userName, this.originalBytes)
      : quota = TextEditingController(text: bytesToGb(originalBytes)) {
    _rememberExact(originalBytes);
  }

  final String userName;
  final int originalBytes;
  final TextEditingController quota;
  final FocusNode focus = FocusNode();
  String unit = 'GiB';
  int? _exactBytes;
  String? _exactText, _exactUnit;

  int get bytes {
    if (_exactBytes != null && quota.text.trim() == _exactText && unit == _exactUnit) {
      return _exactBytes!;
    }
    return capacityToBytes(quota.text, unit) ?? 0;
  }

  bool get overInvalid => quota.text.trim().isNotEmpty && capacityToBytes(quota.text, unit) == null;
  bool overLimit(int maxBytes) => !overInvalid && bytes > maxBytes;

  void textChanged() {
    _exactBytes = null;
    _exactText = null;
    _exactUnit = null;
  }

  void setUnit(String nextUnit) {
    final exact = bytes;
    unit = nextUnit;
    setExactBytes(exact);
  }

  void setExactBytes(int value) {
    _exactBytes = value.clamp(0, 1 << 62).toInt();
    quota.text = bytesToCapacity(_exactBytes!, unit);
    _rememberExact(_exactBytes!);
  }

  void _rememberExact(int bytes) {
    _exactBytes = bytes;
    _exactText = quota.text.trim();
    _exactUnit = unit;
  }

  void dispose() {
    quota.dispose();
    focus.dispose();
  }
}

class _RootSharesPageState extends ConsumerState<RootSharesPage> {
  static const _pageSize = 100;

  final _rows = <_ShareRow>[];
  TextEditingController? _fieldCtl; // controller of the dropdown's text field
  List<ShareUser>? _directory;
  bool _loading = true, _saving = false;
  int _pointAllocated = 0;
  Object? _error;
  String _initial = '';
  int _pickerEpoch = 0;

  Vaulton get _v => ref.read(vaultonProvider);
  Root get _root => widget.root;

  Set<String> get _excluded {
    final me = ref.read(userProvider);
    return {normUser(_root.userName), if (me != null) normUser(me.userName)};
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  String _snapshot() => ([for (final r in _rows) '${normUser(r.userName)}|${r.bytes}']..sort()).join(';');
  bool get _dirty => !_loading && _error == null && _snapshot() != _initial;
  int get _allocated => _rows.fold(0, (sum, r) => sum + r.bytes);
  int get _shareCapacity => _root.maxBytes > 0 ? (_root.maxBytes - _pointAllocated).clamp(0, _root.maxBytes).toInt() : 0;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([_v.shares(_root.id), _loadDirectory(), _loadPointAllocation()]);
      final shares = results[0] as List<Json>;
      final dir = results[1] as List<ShareUser>;
      final pointAllocated = results[2] as int;
      if (!mounted) return;
      setState(() {
        _rows
          ..clear()
          ..addAll([for (final s in shares) _ShareRow('${s['userName']}', toInt(s['maxBytes']))]);
        _directory = dir;
        _pointAllocated = pointAllocated;
        _initial = _snapshot();
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<int> _loadPointAllocation() async {
    var total = 0;
    for (final fetch in <Future<Paged<Point>> Function(String?)>[(cursor) => _v.datas(cursor: cursor, limit: 200), (cursor) => _v.repos(cursor: cursor, limit: 200)]) {
      String? cursor;
      do {
        final page = await fetch(cursor);
        for (final p in page.items.where((x) => x.rootId == _root.id)) {
          total += p.maxBytes;
        }
        cursor = page.hasMore ? page.nextCursor : null;
      } while (cursor != null);
    }
    return total;
  }

  Future<List<ShareUser>> _loadDirectory() async {
    try {
      final out = <ShareUser>[];
      String? cursor;
      do {
        final p = await _v.users(cursor: cursor, limit: _pageSize);
        for (final a in p.items) {
          out.add(ShareUser(userName: a.userName, displayName: a.displayName, email: a.email, isLockedOut: a.isLockedOut));
        }
        cursor = p.hasMore ? p.nextCursor : null;
      } while (cursor != null);
      return out;
    } catch (e) {
      rethrow;
    }
  }

  void _addName(String raw) {
    final name = raw.trim();
    if (name.isEmpty) return;
    final key = normUser(name);
    if (_excluded.contains(key)) return toast(context, 'That user already owns this location', error: true);
    if (_rows.any((r) => normUser(r.userName) == key)) return toast(context, '“$name” is already in the list', error: true);

    var canonical = name;
    final dir = _directory;
    if (dir != null) {
      var match = findUser(dir, name);
      if (match == null) {
        // A partial entry is fine when it points at exactly one remaining user.
        final cands = filterUsers(availableUsers(all: dir, taken: _rows.map((r) => r.userName), exclude: _excluded), name);
        if (cands.length == 1) match = cands.single;
      }
      if (match != null) {
        canonical = match.userName;
      } else {
        return toast(context, 'No user matches “$name”', error: true);
      }
    }

    final row = _ShareRow(canonical, 0);
    setState(() {
      _rows.add(row);
      _pickerEpoch++; // rebuilds the dropdown so the same person can be picked again later
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) row.focus.requestFocus();
    });
  }

  void _remove(_ShareRow r) {
    setState(() => _rows.remove(r));
    WidgetsBinding.instance.addPostFrameCallback((_) => r.dispose());
  }

  Future<void> _save() async {
    if (_rows.any((r) => r.overInvalid || r.overLimit(_shareCapacity))) {
      return toast(context, 'Fix the highlighted limits first', error: true);
    }
    if (_allocated > _shareCapacity) {
      return toast(context, 'Share limits exceed the available location capacity.', error: true);
    }
    final payload = buildSharePayload([for (final r in _rows) (userName: r.userName, maxBytes: r.bytes)]);
    setState(() => _saving = true);
    final res = await guarded(context, () => _v.setShares(_root.id, payload));
    if (!mounted) return;
    setState(() => _saving = false);
    if (res == null) return;
    _initial = _snapshot();
    toast(context, 'Sharing updated');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await confirm(context, 'Discard changes?', 'You have unsaved sharing changes.', ok: 'Discard', danger: true);
        if (discard && mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Share “${_root.name}”', overflow: TextOverflow.ellipsis),
          actions: [
            if (!_loading && _error == null)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: FilledButton(
                  onPressed: _saving || !_dirty ? null : _save,
                  child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
                ),
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ErrorView(_error!, onRetry: _load)
                : _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dir = _directory;
    final avail = dir == null ? const <ShareUser>[] : availableUsers(all: dir, taken: _rows.map((r) => r.userName), exclude: _excluded);
    final allocated = _allocated;
    final over = overAllocated(_shareCapacity, allocated);
    final note = theme.textTheme.bodySmall?.copyWith(color: cs.outline);

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 32),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Space allocation', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              UsageBar(used: _pointAllocated + allocated, max: _root.maxBytes),
              const SizedBox(height: 6),
              Text(
                _root.maxBytes > 0 ? '${fmtBytes(_pointAllocated + allocated)} allocated of ${fmtBytes(_root.maxBytes)}' : '${fmtBytes(_pointAllocated + allocated)} allocated',
                style: theme.textTheme.bodySmall,
              ),
              if (_pointAllocated > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Your data folders and backup vaults reserve ${fmtBytes(_pointAllocated)}. All share quotas together can use up to ${fmtBytes(_shareCapacity)}.',
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
                  ),
                ),
              if (over)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Limits add up to more than the available space.', style: theme.textTheme.bodySmall?.copyWith(color: cs.error)),
                ),
            ]),
          ),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 4), child: _picker(avail)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            avail.isEmpty
                ? 'There are no additional users available to add.'
                : 'Pick a person, then set how much of the location they may use.',
            style: note,
          ),
        ),
        if (_rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(children: [
              Icon(Icons.group_outlined, size: 40, color: cs.outline),
              const SizedBox(height: 8),
              Text('Not shared with anyone yet', style: TextStyle(color: cs.outline)),
            ]),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('SHARED WITH (${_rows.length})', style: theme.textTheme.labelMedium?.copyWith(color: cs.primary, letterSpacing: 1)),
          ),
          for (final r in _rows) _rowTile(context, r, dir),
        ],
      ],
    );
  }

  Widget _rowTile(BuildContext context, _ShareRow r, List<ShareUser>? dir) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final u = dir == null ? null : findUser(dir, r.userName);
    final unknown = dir != null && u == null;
    final sub = unknown ? 'Not in the user list' : (u?.subtitle ?? '');
    final otherAllocated = _rows
        .where((other) => !identical(other, r))
        .fold<int>(0, (sum, other) => sum + other.bytes);
    final maxForRow = (_shareCapacity - otherAllocated).clamp(0, _shareCapacity).toInt();
    String amountText(int bytes) => '${bytes == 0 ? '0.00' : bytesToCapacity(bytes, r.unit)} ${r.unit}';
    return Card(
      key: ObjectKey(r),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: LayoutBuilder(builder: (context, box) {
          final narrow = box.maxWidth < 520;
          final who = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(child: Text(u?.initial ?? (r.userName.isEmpty ? '?' : r.userName[0].toUpperCase()))),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(u?.title ?? r.userName, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                  if (sub.isNotEmpty)
                    Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: unknown ? cs.error : cs.outline)),
                  if (u?.isLockedOut == true) chip(context, 'Locked', color: cs.errorContainer),
                ]),
              ),
            ),
          ]);
          final remove = IconButton(tooltip: 'Remove', icon: const Icon(Icons.remove_circle_outline), onPressed: () => _remove(r));
          final quotaInput = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: TextField(
                controller: r.quota,
                focusNode: r.focus,
                enabled: !_saving,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(labelText: 'Space Limit', isDense: true, errorText: r.overInvalid ? 'Enter a valid capacity' : (r.overLimit(_shareCapacity) ? 'Over remaining capacity' : null)),
                onChanged: (_) {
                  r.textChanged();
                  setState(() {});
                },
              )),
              const SizedBox(width: 6),
              SizedBox(width: 78, child: DropdownButtonFormField<String>(
                initialValue: r.unit,
                decoration: const InputDecoration(labelText: 'Unit', isDense: true),
                items: [for (final u in capacityFactors.keys) DropdownMenuItem(value: u, child: Text(u))],
                onChanged: _saving ? null : (u) {
                  if (u == null) return;
                  setState(() => r.setUnit(u));
                },
              )),
          ]);
          final quota = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            quotaInput,
            Row(children: [
              Expanded(
                child: Tooltip(
                  message: 'Exact limit: ${r.bytes} bytes\\nMaximum for this user: $maxForRow bytes',
                  child: Text(
                    '${amountText(r.bytes)} of ${amountText(maxForRow)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
                  ),
                ),
              ),
              Tooltip(
                message: 'Assigns the exact remaining capacity; the field is rounded to two decimals.',
                child: TextButton(
                  onPressed: _saving || r.bytes == maxForRow ? null : () => setState(() => r.setExactBytes(maxForRow)),
                  child: const Text('Use Remaining'),
                ),
              ),
            ]),
            Slider(
              value: r.bytes.clamp(0, maxForRow).toDouble(),
              min: 0,
              max: maxForRow > 0 ? maxForRow.toDouble() : 1,
              divisions: maxForRow > 0 ? (maxForRow < 1000 ? maxForRow : 1000) : null,
              label: maxForRow > 0
                  ? '${((r.bytes.clamp(0, maxForRow) / maxForRow) * 100).round()}%'
                  : '0%',
              onChanged: _saving || maxForRow <= 0
                  ? null
                  : (value) => setState(() => r.setExactBytes(value.round())),
            ),
          ]);
          if (narrow) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: who), remove]),
              const SizedBox(height: 8),
              Padding(padding: const EdgeInsets.only(right: 8), child: quota),
            ]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: who),
            const SizedBox(width: 8),
            SizedBox(width: 280, child: quota),
            remove,
          ]);
        }),
      ),
    );
  }

  Widget _picker(List<ShareUser> avail) {
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Expanded(
        child: LayoutBuilder(
          builder: (context, box) => Autocomplete<ShareUser>(
            key: ValueKey(_pickerEpoch),
            displayStringForOption: (u) => u.userName,
            optionsBuilder: (v) => filterUsers(avail, v.text),
            onSelected: (u) => _addName(u.userName),
            fieldViewBuilder: (context, controller, focus, onSubmitted) {
              _fieldCtl = controller;
              return TextField(
                controller: controller,
                focusNode: focus,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Add User',
                  hintText: 'Search by name or email',
                  prefixIcon: Icon(Icons.person_add_alt),
                  suffixIcon: Icon(Icons.arrow_drop_down),
                ),
                onSubmitted: (_) => onSubmitted(),
              );
            },
            optionsViewBuilder: (context, onSelected, options) => Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: 280, maxWidth: box.maxWidth),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (context, i) {
                      final u = options.elementAt(i);
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(radius: 16, child: Text(u.initial)),
                        title: Text(u.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: u.subtitle.isEmpty ? null : Text(u.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: u.isLockedOut ? const Icon(Icons.lock_outline, size: 16) : null,
                        onTap: () => onSelected(u),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(width: 8),
      IconButton.filledTonal(tooltip: 'Add', icon: const Icon(Icons.add), onPressed: () => _addName(_fieldCtl?.text ?? '')),
    ]);
  }
}
