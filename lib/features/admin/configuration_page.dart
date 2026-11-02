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
  const ConfigurationTab({super.key});
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
  Object? _loadError;
  Json _email = {};
  Json _rateLimits = {};
  Json _limits = {};

  Vaulton get _v => ref.read(vaultonProvider);

  Future<void> _load() async {
    try {
      final data = await _v.wolSettings();
      final power = await _v.powerSettings();
      final email = await _v.emailSettings();
      final rateLimits = await _v.rateLimitSettings();
      final limits = await _v.operationalLimits();
      if (!mounted) return;
      setState(() {
        _enabled = toBool(data['enabled']);
        _brokerUrl = toStr(data['brokerUrl']) ?? '';
        _wakeBeforeMinutes = toInt(data['wakeBeforeMinutes']);
        _hasAdminToken = toBool(data['hasAdminToken']);
        _hasWakeToken = toBool(data['hasWakeToken']);
        _powerEnabled = toBool(power['enabled']);
        _powerAction = toStr(power['action']) ?? 'Sleep';
        _powerIdleMinutes = toInt(power['idleMinutes']);
        _powerScheduleProtectionMinutes = toInt(
          power['scheduleProtectionMinutes'],
        );
        _hasPowerAgentKey = toBool(power['hasAgentKey']);
        _email = email;
        _rateLimits = rateLimits;
        _limits = limits;
        _loaded = true;
        _loadError = null;
      });
      try {
        final status = await _v.powerAgentStatus();
        if (mounted) setState(() => _powerAgentStatus = status);
      } catch (_) {
        // Best-effort: the page explains an unreachable agent inline.
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e);
      toastError(context, e);
    }
  }

  void _retry() {
    setState(() => _loadError = null);
    _load();
  }

  Future<void> _editEmail() async {
    final f = await formDialog(context, 'Outgoing Email', [
      FieldSpec('enabled', 'Enable Email', kind: 'bool', initial: '${_email['enabled'] == true}'),
      FieldSpec('host', 'SMTP Host', initial: '${_email['host'] ?? ''}'),
      FieldSpec('port', 'SMTP Port', initial: '${_email['port'] ?? 587}'),
      FieldSpec('ssl', 'Use STARTTLS', kind: 'bool', initial: '${_email['enableSsl'] != false}'),
      FieldSpec('username', 'SMTP Username', initial: '${_email['username'] ?? ''}'),
      FieldSpec('password', 'SMTP Password', kind: 'secret', hint: _email['hasPassword'] == true ? 'Leave blank to keep the saved password.' : 'Stored encrypted.'),
      FieldSpec('fromEmail', 'Sender Email', initial: '${_email['fromEmail'] ?? ''}'),
      FieldSpec('fromName', 'Sender Name', initial: '${_email['fromName'] ?? 'Vaulton Alerts'}'),
      FieldSpec('timeout', 'Timeout (Seconds)', initial: '${_email['timeoutSeconds'] ?? 30}'),
      FieldSpec('attempts', 'Maximum Attempts', initial: '${_email['maxAttempts'] ?? 3}'),
    ], ok: 'Save Email Settings',
      intro: 'Configure SMTP for welcome emails, password resets, and notifications.');
    if (f == null || !mounted) return;
    final port = int.tryParse(f['port'] ?? '');
    final timeout = int.tryParse(f['timeout'] ?? '');
    final attempts = int.tryParse(f['attempts'] ?? '');
    if (port == null || timeout == null || attempts == null) {
      toast(context, 'Enter valid numeric SMTP settings.', error: true);
      return;
    }
    final saved = await guarded(context, () => _v.saveEmailSettings({
      'enabled': f['enabled'] == 'true', 'host': f['host'], 'port': port,
      'enableSsl': f['ssl'] == 'true', 'username': f['username'], 'password': f['password'],
      'fromEmail': f['fromEmail'], 'fromName': f['fromName'],
      'timeoutSeconds': timeout, 'maxAttempts': attempts,
    }));
    if (saved == null || !mounted) return;
    setState(() => _email = saved);
    toast(context, 'Email settings saved.');
  }

  Future<void> _testEmail() async {
    final ok = await guarded(context, () async { await _v.testEmail(); return true; });
    if (ok == true && mounted) toast(context, 'Test email sent.');
  }

  Future<void> _editRateLimits() async {
    final f = await formDialog(context, 'API Rate Limits', [
      FieldSpec('authRequests', 'Authentication Requests', initial: '${_rateLimits['authRequests'] ?? 10}'),
      FieldSpec('authWindow', 'Authentication Window (Seconds)', initial: '${_rateLimits['authWindowSeconds'] ?? 60}'),
      FieldSpec('messageRequests', 'Message Requests', initial: '${_rateLimits['messageRequests'] ?? 30}'),
      FieldSpec('messageWindow', 'Message Window (Seconds)', initial: '${_rateLimits['messageWindowSeconds'] ?? 60}'),
    ], ok: 'Save Rate Limits',
      intro: 'Authentication is limited per client IP. Messages are limited per signed-in user. Changes apply immediately.');
    if (f == null || !mounted) return;
    final auth = int.tryParse(f['authRequests'] ?? '');
    final authWindow = int.tryParse(f['authWindow'] ?? '');
    final messages = int.tryParse(f['messageRequests'] ?? '');
    final messageWindow = int.tryParse(f['messageWindow'] ?? '');
    if (auth == null || authWindow == null || messages == null || messageWindow == null) {
      toast(context, 'Enter valid rate-limit values.', error: true);
      return;
    }
    final saved = await guarded(context, () => _v.saveRateLimitSettings({
      'authRequests': auth, 'authWindowSeconds': authWindow,
      'messageRequests': messages, 'messageWindowSeconds': messageWindow,
    }));
    if (saved == null || !mounted) return;
    setState(() => _rateLimits = saved);
    toast(context, 'Rate limits saved.');
  }

  Future<void> _editLimits() async {
    final fields = <(String, String, int)>[
      ('maxSchedulesPerUser', 'Schedules Per User', 50),
      ('minScheduleIntervalMinutes', 'Minimum Schedule Interval (Minutes)', 5),
      ('maxPendingJobsPerUser', 'Pending Jobs Per User', 200),
      ('maxMessageRecipients', 'Message Recipients', 25),
      ('maxBroadcastRecipients', 'Broadcast Recipients', 5000),
      ('jobRetentionDays', 'Job Retention (Days, 0 = Forever)', 90),
      ('messageRetentionDays', 'Message Retention (Days, 0 = Forever)', 0),
      ('logBufferCapacity', 'Log Event Buffer', 5000),
      ('pointEventBufferCapacity', 'Point Event Buffer', 2000),
    ];
    final f = await formDialog(context, 'Operational Limits', [
      for (final field in fields)
        FieldSpec(field.$1, field.$2, initial: '${_limits[field.$1] ?? field.$3}'),
    ], ok: 'Save Limits',
      intro: 'Control per-user quotas, retention, and in-memory event history. Use 0 to keep records indefinitely.');
    if (f == null || !mounted) return;
    final values = <String, int>{};
    for (final field in fields) {
      final value = int.tryParse(f[field.$1] ?? '');
      if (value == null) {
        toast(context, 'Enter valid numbers for every limit.', error: true);
        return;
      }
      values[field.$1] = value;
    }
    final saved = await guarded(context, () => _v.saveOperationalLimits(values));
    if (saved == null || !mounted) return;
    setState(() => _limits = saved);
    toast(context, 'Operational limits saved.');
  }

  Future<void> _editWake() async {
    final f = await formDialog(context, 'Wake-on-LAN', [
      FieldSpec(
        'enabled',
        'Enable Wake-on-LAN',
        kind: 'bool',
        initial: '$_enabled',
      ),
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
      FieldSpec(
        'minutes',
        'Wake Before Job (Minutes)',
        initial: '$_wakeBeforeMinutes',
      ),
    ],
      ok: 'Save Settings',
      intro: 'Configure the Cloudflare Worker connection and how early Vaulton should wake the server before scheduled jobs.',
    );

    if (f == null || !mounted) return;
    final minutes = int.tryParse(f['minutes'] ?? '');
    if (minutes == null || minutes < 0 || minutes > 1440) {
      toast(
        context,
        'Wake-before time must be between 0 and 1440 minutes.',
        error: true,
      );
      return;
    }

    final result = await guarded(
      context,
      () => _v.saveWolSettings({
        'enabled': f['enabled'] == 'true',
        'brokerUrl': f['url'],
        'adminToken': f['admin'],
        'wakeToken': f['wake'],
        'wakeBeforeMinutes': minutes,
      }),
    );
    if (result == null || !mounted) return;
    await _load();
    if (mounted) toast(context, 'Wake-on-LAN settings saved.');
  }

  Future<void> _editPower() async {
    final key = TextEditingController();
    final idle = TextEditingController(text: '$_powerIdleMinutes');
    final protection = TextEditingController(
      text: '$_powerScheduleProtectionMinutes',
    );
    String action = _powerAction;
    bool powerEnabled = _powerEnabled;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Automatic Power Management'),
          content: SizedBox(
            width: 440,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: (MediaQuery.sizeOf(context).height -
                        MediaQuery.viewInsetsOf(context).bottom -
                        180)
                    .clamp(140.0, 560.0)
                    .toDouble(),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Vaulton powers down the host only when it is idle and no scheduled job is about to start. The host agent performs the action.',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Power Action', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enable Automatic Power Management'),
                    value: powerEnabled,
                    onChanged: (v) => setDialogState(() => powerEnabled = v),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: action,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Action'),
                    items: const [
                      DropdownMenuItem(value: 'Sleep', child: Text('Sleep')),
                      DropdownMenuItem(
                        value: 'Hibernate',
                        child: Text('Hibernate'),
                      ),
                      DropdownMenuItem(
                        value: 'Shutdown',
                        child: Text('Shutdown'),
                      ),
                    ],
                    onChanged: (v) =>
                        setDialogState(() => action = v ?? 'Sleep'),
                  ),
                  const SizedBox(height: 16),
                  Text('Idle & Schedule Protection', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
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
                  const SizedBox(height: 16),
                  Text('Host Agent Security', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  LayoutBuilder(
                    builder: (context, c) {
                      final narrow = c.maxWidth < 360;
                      final keyField = Expanded(
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
                      );
                      final generateButton = Padding(
                        padding: EdgeInsets.only(top: narrow ? 0 : 8),
                        child: OutlinedButton(
                          onPressed: () {
                            final bytes = List<int>.generate(
                              32,
                              (_) => Random.secure().nextInt(256),
                            );
                            key.text = base64UrlEncode(bytes);
                          },
                          child: const Text('Generate'),
                        ),
                      );
                      if (narrow) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: key,
                              obscureText: true,
                              decoration: InputDecoration(
                                labelText: 'Host Agent Key',
                                helperText: _hasPowerAgentKey
                                    ? 'Leave blank to keep the existing key.'
                                    : 'Use at least 32 random characters.',
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: generateButton,
                            ),
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          keyField,
                          const SizedBox(width: 8),
                          generateButton,
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'The host agent runs outside Docker and performs the actual power action. Keep the agent key secret.',
                  ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final i = int.tryParse(idle.text);
                final p = int.tryParse(protection.text);
                if (i == null ||
                    i < 5 ||
                    i > 10080 ||
                    p == null ||
                    p < 0 ||
                    p > 10080) {
                  toast(
                    context,
                    'Idle time must be 5–10080 minutes. Schedule protection must be 0–10080.',
                    error: true,
                  );
                  return;
                }
                if (powerEnabled &&
                    !_hasPowerAgentKey &&
                    key.text.trim().length < 32) {
                  toast(
                    context,
                    'Enter a host agent key with at least 32 characters.',
                    error: true,
                  );
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
    if (mounted) toast(context, 'Automatic power settings saved.');
  }

  String _lastPowerActionLabel() {
    final action = toStr(_powerAgentStatus?['lastAction']);
    if (action == null || action.isEmpty) return 'No power action recorded';
    final rawTimestamp = toStr(_powerAgentStatus?['lastActionAt']);
    final timestamp = rawTimestamp == null
        ? null
        : DateTime.tryParse(rawTimestamp)?.toLocal();
    return '${pretty(action)} · ${fmtDate(timestamp)}';
  }

  Future<void> _refreshPowerStatus() async {
    final status = await guarded(context, _v.powerAgentStatus);
    if (!mounted) return;
    setState(() => _powerAgentStatus = status);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final loadError = _loadError;
    if (loadError != null) {
      return Center(child: ErrorView(loadError, onRetry: _retry));
    }
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final cs = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    _enabled ? Icons.wifi_tethering : Icons.wifi_tethering_off,
                    color: _enabled ? cs.primary : null,
                  ),
                  title: const Text('Wake-on-LAN'),
                  subtitle: Text(
                    _enabled
                        ? 'Enabled · ${_brokerUrl.isEmpty ? 'Worker URL not set' : _brokerUrl}'
                        : 'Disabled',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonalIcon(
                      onPressed: _editWake,
                      icon: const Icon(Icons.settings_outlined),
                      label: const Text('Configure'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    _powerEnabled
                        ? Icons.power_settings_new
                        : Icons.power_off_outlined,
                    color: _powerEnabled ? cs.primary : null,
                  ),
                  title: const Text('Power Management'),
                  subtitle: Text(
                    _powerEnabled
                        ? '$_powerAction after $_powerIdleMinutes minutes idle'
                        : 'Disabled',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _editPower,
                          icon: const Icon(Icons.settings_outlined),
                          label: const Text('Configure'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Card(
            child: Column(children: [
              ListTile(
                leading: Icon(_email['enabled'] == true ? Icons.mark_email_read_outlined : Icons.mail_outline),
                title: const Text('Outgoing Email'),
                subtitle: Text(_email['enabled'] == true
                    ? '${_email['host'] ?? 'SMTP configured'} · ${_email['fromEmail'] ?? ''}'
                    : 'Disabled'),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Align(alignment: Alignment.centerRight, child: Wrap(spacing: 8, children: [
                  OutlinedButton.icon(onPressed: _email['enabled'] == true ? _testEmail : null,
                    icon: const Icon(Icons.send_outlined), label: const Text('Send Test')),
                  FilledButton.tonalIcon(onPressed: _editEmail,
                    icon: const Icon(Icons.settings_outlined), label: const Text('Configure')),
                ])),
              ),
            ]),
          ),
          Card(
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.speed_outlined),
                title: const Text('API Rate Limits'),
                subtitle: Text('Auth: ${_rateLimits['authRequests'] ?? 10} / ${_rateLimits['authWindowSeconds'] ?? 60}s · Messages: ${_rateLimits['messageRequests'] ?? 30} / ${_rateLimits['messageWindowSeconds'] ?? 60}s'),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Align(alignment: Alignment.centerRight, child: FilledButton.tonalIcon(
                  onPressed: _editRateLimits, icon: const Icon(Icons.tune), label: const Text('Configure'))),
              ),
            ]),
          ),
          Card(
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.tune_outlined),
                title: const Text('Operational Limits'),
                subtitle: Text('${_limits['maxSchedulesPerUser'] ?? 50} schedules/user · ${_limits['maxPendingJobsPerUser'] ?? 200} pending jobs/user · Job retention: ${_limits['jobRetentionDays'] ?? 90} days'),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Align(alignment: Alignment.centerRight, child: FilledButton.tonalIcon(
                  onPressed: _editLimits, icon: const Icon(Icons.settings_outlined), label: const Text('Configure'))),
              ),
            ]),
          ),
          Section(
            'Wake-on-LAN',
            children: [
              ListTile(
                leading: const Icon(Icons.schedule),
                title: const Text('Automatic Wake'),
                subtitle: Text(
                  _enabled
                      ? (_wakeBeforeMinutes == 0
                            ? 'Wakes when a scheduled job needs it.'
                            : 'Wakes $_wakeBeforeMinutes minutes before a scheduled job.')
                      : 'Enable Wake-on-LAN to wake the server for jobs.',
                ),
              ),
              ListTile(
                leading: Icon(
                  _hasAdminToken
                      ? Icons.check_circle_outline
                      : Icons.warning_amber_outlined,
                ),
                title: const Text('Broker Admin Token'),
                subtitle: Text(
                  _hasAdminToken ? 'Configured' : 'Not configured',
                ),
              ),
              ListTile(
                leading: Icon(
                  _hasWakeToken
                      ? Icons.check_circle_outline
                      : Icons.warning_amber_outlined,
                ),
                title: const Text('Broker Wake Token'),
                subtitle: Text(_hasWakeToken ? 'Configured' : 'Not configured'),
              ),
            ],
          ),
          if (_powerEnabled)
            Card(
              child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Scheduled Jobs'),
                subtitle: Text(
                  _enabled ? 'Wake-on-LAN is set up for scheduled jobs.' : 'Set up Wake-on-LAN so the server can wake for scheduled jobs.',
                ),
              ),
            ),
          Section(
            'Automatic Power Management',
            children: [
              ListTile(
                leading: const Icon(Icons.schedule),
                title: const Text('Schedule Protection'),
                subtitle: Text(
                  _powerEnabled
                      ? 'Blocks power down when a job is due within $_powerScheduleProtectionMinutes minutes.'
                      : 'Enable to power down an idle server.',
                ),
              ),
              ListTile(
                leading: Icon(
                  _hasPowerAgentKey
                      ? Icons.check_circle_outline
                      : Icons.warning_amber_outlined,
                ),
                title: const Text('Host Agent Key'),
                subtitle: Text(
                  _hasPowerAgentKey ? 'Configured' : 'Not configured',
                ),
              ),
              ListTile(
                leading: Icon(
                  _powerAgentStatus != null
                      ? Icons.check_circle_outline
                      : Icons.warning_amber_outlined,
                  color: _powerAgentStatus != null ? cs.primary : cs.error,
                ),
                title: const Text('Host Agent'),
                subtitle: Text(
                  _powerAgentStatus != null
                      ? 'Reachable · ${toStr(_powerAgentStatus?['platform']) ?? 'Unknown'} · Version ${toStr(_powerAgentStatus?['version']) ?? 'Unknown'}'
                      : 'Not responding · Check the agent service, URL, firewall, and shared key',
                ),
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
                  subtitle: Text(_lastPowerActionLabel()),
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
            ],
          ),
        ],
      ),
    );
  }
}
