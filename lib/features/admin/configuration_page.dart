import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/models.dart';
import '../../core/vaulton.dart';
import '../../core/util.dart';
import '../../core/widgets.dart';

class ConfigurationTab extends ConsumerStatefulWidget {
  const ConfigurationTab();
  @override
  ConsumerState<ConfigurationTab> createState() => _ConfigurationTabState();
}

class _ConfigurationTabState extends ConsumerState<ConfigurationTab> {
  bool _enabled = false;
  String _brokerUrl = '';
  int _wakeBeforeMinutes = 5;
  bool _hasAdminToken = false;
  bool _hasWakeToken = false;
  bool _loaded = false;
  bool _powerEnabled = false;
  String _powerAction = 'Sleep';
  int _powerIdleMinutes = 30;
  int _powerScheduleProtectionMinutes = 120;
  bool _hasPowerAgentKey = false;
  Json? _powerAgentStatus;
  Json? _powerDecision;

  Vaulton get _v => ref.read(vaultonProvider);

  Future<void> _load() async {
    final data = await guarded(context, _v.wolSettings);
    if (data == null || !mounted) return;
    final power = await guarded(context, _v.powerSettings);
    if (power == null || !mounted) return;
    setState(() {
      _enabled = toBool(data['enabled']);
      _brokerUrl = toStr(data['brokerUrl']) ?? '';
      _wakeBeforeMinutes = toInt(data['wakeBeforeMinutes']);
      _hasAdminToken = toBool(data['hasAdminToken']);
      _hasWakeToken = toBool(data['hasWakeToken']);
      _powerEnabled = toBool(power['enabled']);
      _powerAction = toStr(power['action']) ?? 'Sleep';
      _powerIdleMinutes = toInt(power['idleMinutes']);
      _powerScheduleProtectionMinutes = toInt(power['scheduleProtectionMinutes']);
      _hasPowerAgentKey = toBool(power['hasAgentKey']);
      _loaded = true;
    });
    final status = await guarded(context, _v.powerAgentStatus);
    final decision = await guarded(context, _v.powerDecision);
    if (!mounted) return;
    setState(() {
      _powerAgentStatus = status;
      _powerDecision = decision;
    });
  }

  Future<void> _editWake() async {
    final f = await formDialog(context, 'Wake-on-LAN', [
      FieldSpec('enabled', 'Enable Wake-on-LAN', kind: 'bool', initial: '$_enabled'),
      FieldSpec('url', 'Cloudflare Worker URL', initial: _brokerUrl),
      FieldSpec(
        'admin',
        'Worker admin token',
        kind: 'secret',
        hint: 'Leave blank to keep the current token. Tokens are encrypted.',
      ),
      FieldSpec(
        'wake',
        'Worker wake token',
        kind: 'secret',
        hint: 'Leave blank to keep the current token. Tokens are encrypted.',
      ),
      FieldSpec('minutes', 'Wake Before Job (Minutes)', initial: '$_wakeBeforeMinutes'),
    ], ok: 'Save');

    if (f == null || !mounted) return;
    final minutes = int.tryParse(f['minutes'] ?? '');
    if (minutes == null || minutes < 0 || minutes > 1440) {
      toast(context, 'Wake-before time must be between 0 and 1440 minutes', error: true);
      return;
    }

    final result = await guarded(context, () => _v.saveWolSettings({
      'enabled': f['enabled'] == 'true',
      'brokerUrl': f['url'],
      'adminToken': f['admin'],
      'wakeToken': f['wake'],
      'wakeBeforeMinutes': minutes,
    }));
    if (result == null || !mounted) return;
    await _load();
    if (mounted) toast(context, 'Wake-on-LAN settings saved');
  }

  Future<void> _editPower() async {
    final key = TextEditingController();
    final idle = TextEditingController(text: '$_powerIdleMinutes');
    final protection = TextEditingController(text: '$_powerScheduleProtectionMinutes');
    String action = _powerAction;
    bool powerEnabled = _powerEnabled;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Automatic Power Management'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enable Automatic Power Management'),
                    value: powerEnabled,
                    onChanged: (v) => setDialogState(() => powerEnabled = v),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: action,
                    decoration: const InputDecoration(labelText: 'Action'),
                    items: const [
                      DropdownMenuItem(value: 'Sleep', child: Text('Sleep')),
                      DropdownMenuItem(value: 'Hibernate', child: Text('Hibernate')),
                      DropdownMenuItem(value: 'Shutdown', child: Text('Shutdown')),
                    ],
                    onChanged: (v) => setDialogState(() => action = v ?? 'Sleep'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: idle,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Idle Time',
                      suffixText: 'minutes',
                      helperText: 'No active or pending jobs for this long.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: protection,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Schedule Protection',
                      suffixText: 'minutes',
                      helperText: 'A scheduled job inside this window prevents power down.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: key,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: 'Host Agent Key',
                            helperText: _hasPowerAgentKey
                                ? 'Leave blank to keep the existing key.'
                                : 'Use at least 32 random characters.',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: OutlinedButton(
                          onPressed: () {
                            final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
                            key.text = base64UrlEncode(bytes);
                          },
                          child: const Text('Generate'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'The host agent runs outside Docker and performs the actual power action. Keep the agent key secret.',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final i = int.tryParse(idle.text);
                final p = int.tryParse(protection.text);
                if (i == null || i < 5 || i > 10080 || p == null || p < 0 || p > 10080) {
                  toast(context, 'Idle time must be 5–10080 minutes. Schedule protection must be 0–10080.', error: true);
                  return;
                }
                if (powerEnabled && !_hasPowerAgentKey && key.text.trim().length < 32) {
                  toast(context, 'Enter a host agent key with at least 32 characters.', error: true);
                  return;
                }
                Navigator.pop(dialogContext, {
                  'enabled': powerEnabled,
                  'action': action,
                  'idleMinutes': i,
                  'scheduleProtectionMinutes': p,
                  'agentKey': key.text.trim(),
                });
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    key.dispose();
    idle.dispose();
    protection.dispose();

    if (result == null || !mounted) return;
    final saved = await guarded(context, () => _v.savePowerSettings(result));
    if (saved == null || !mounted) return;
    await _load();
    if (mounted) toast(context, 'Automatic power settings saved');
  }

  Future<void> _refreshPowerStatus() async {
    final status = await guarded(context, _v.powerAgentStatus);
    if (!mounted) return;
    setState(() => _powerAgentStatus = status);
  }

  Future<void> _testPowerDecision() async {
    final decision = await guarded(context, _v.powerDecision);
    if (decision == null || !mounted) return;
    final execute = toBool(decision['execute']);
    final reason = toStr(decision['blockReason']);
    final action = toStr(decision['action']);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Power Management Test'),
        content: Text(
          execute
              ? 'The server currently meets the conditions for ${action ?? _powerAction.toLowerCase()}. This test does not send a power command.'
              : 'Power down is currently blocked${reason == null || reason.isEmpty ? '.' : ': $reason.'}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final cs = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          Card(
            child: Column(children: [
              ListTile(
                leading: Icon(_enabled ? Icons.wifi_tethering : Icons.wifi_tethering_off, color: _enabled ? cs.primary : null),
                title: const Text('Wake-on-LAN'),
                subtitle: Text(_enabled ? 'Enabled · ${_brokerUrl.isEmpty ? 'Worker URL not set' : _brokerUrl}' : 'Disabled'),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(onPressed: _editWake, icon: const Icon(Icons.settings_outlined), label: const Text('Configure')),
                ),
              ),
            ]),
          ),
          Card(
            child: Column(children: [
              ListTile(
                leading: Icon(_powerEnabled ? Icons.power_settings_new : Icons.power_off_outlined, color: _powerEnabled ? cs.primary : null),
                title: const Text('Power Management'),
                subtitle: Text(_powerEnabled
                    ? '${_powerAction} after ${_powerIdleMinutes} minutes idle'
                    : 'Disabled'),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    if (_powerEnabled)
                      OutlinedButton.icon(onPressed: _testPowerDecision, icon: const Icon(Icons.fact_check_outlined), label: const Text('Test')),
                    FilledButton.tonalIcon(onPressed: _editPower, icon: const Icon(Icons.settings_outlined), label: const Text('Configure')),
                  ]),
                ),
              ),
            ]),
          ),
          Section('Wake-on-LAN', children: [
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Automatic Wake'),
              subtitle: Text(_enabled
                  ? (_wakeBeforeMinutes == 0
                      ? 'Wakes when a scheduled job needs it.'
                      : 'Wakes $_wakeBeforeMinutes minutes before a scheduled job.')
                  : 'Enable Wake-on-LAN to wake the server for jobs.'),
            ),
            ListTile(
              leading: Icon(_hasAdminToken ? Icons.check_circle_outline : Icons.warning_amber_outlined),
              title: const Text('Broker Admin Token'),
              subtitle: Text(_hasAdminToken ? 'Configured' : 'Not configured'),
            ),
            ListTile(
              leading: Icon(_hasWakeToken ? Icons.check_circle_outline : Icons.warning_amber_outlined),
              title: const Text('Broker Wake Token'),
              subtitle: Text(_hasWakeToken ? 'Configured' : 'Not configured'),
            ),
          ]),
          if (_powerEnabled)
            Card(
              child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Scheduled Jobs'),
                subtitle: Text(_enabled
                    ? 'Wake-on-LAN is set up for scheduled jobs.'
                    : 'Set up Wake-on-LAN so the server can wake for scheduled jobs.'),
              ),
            ),
          Section('Automatic Power Management', children: [
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Schedule Protection'),
              subtitle: Text(_powerEnabled
                  ? 'Blocks power down when a job is due within ${_powerScheduleProtectionMinutes} minutes.'
                  : 'Enable to power down an idle server.'),
            ),
            ListTile(
              leading: Icon(_hasPowerAgentKey ? Icons.check_circle_outline : Icons.warning_amber_outlined),
              title: const Text('Host Agent Key'),
              subtitle: Text(_hasPowerAgentKey ? 'Configured' : 'Not configured'),
            ),
            ListTile(
              leading: Icon(
                _powerAgentStatus != null ? Icons.check_circle_outline : Icons.warning_amber_outlined,
                color: _powerAgentStatus != null ? cs.primary : cs.error,
              ),
              title: const Text('Host Agent'),
              subtitle: Text(_powerAgentStatus != null
                  ? 'Reachable · ${toStr(_powerAgentStatus?['platform']) ?? 'Unknown'} · Version ${toStr(_powerAgentStatus?['version']) ?? 'Unknown'}'
                  : 'Not responding · Check the agent service, URL, firewall, and shared key'),
              trailing: IconButton(
                tooltip: 'Refresh Agent Status',
                onPressed: _refreshPowerStatus,
                icon: const Icon(Icons.refresh),
              ),
            ),
            if (_powerAgentStatus != null) ...[
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('Last Power Action'),
                subtitle: Text(
                  _powerAgentStatus?['lastAction'] == null
                      ? 'No power action recorded'
                      : '${pretty('${_powerAgentStatus?['lastAction']}')} · ${fmtDate(DateTime.tryParse('${_powerAgentStatus?['lastActionAt'] ?? ''}')?.toLocal())}',
                ),
              ),
              if ((toStr(_powerAgentStatus?['lastError']) ?? '').isNotEmpty)
                ListTile(
                  leading: Icon(Icons.error_outline, color: cs.error),
                  title: const Text('Last Agent Error'),
                  subtitle: Text(
                    toStr(_powerAgentStatus?['lastError'])!,
                    style: TextStyle(color: cs.error),
                  ),
                  isThreeLine: true,
                ),
            ],
          ]),
        ],
      ),
    );
  }
}
