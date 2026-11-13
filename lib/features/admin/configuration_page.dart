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
  Json _startup = {};
  Json _notifications = {};
  Json _encryption = {};

  Vaulton get _v => ref.read(vaultonProvider);

  Future<void> _load() async {
    try {
      final data = await _v.wolSettings();
      final power = await _v.powerSettings();
      final email = await _v.emailSettings();
      final rateLimits = await _v.rateLimitSettings();
      final limits = await _v.operationalLimits();
      final startup = await _v.startupSettings();
      final notifications = await _v.notificationSettings();
      final encryption = await _v.encryptionSettings();
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
        _startup = startup;
        _notifications = notifications;
        _encryption = encryption;
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

  Future<void> _editEncryption() async {
    final currentlyEnabled = _encryption['enabled'] == true;
    final repo = await confirm(
      context,
      currentlyEnabled ? 'Disable Data Folder Encryption?' : 'Enable Data Folder Encryption?',
      currentlyEnabled
          ? 'New Data Folders can no longer be password-protected. Folders already protected will stay protected and can still be unlocked.'
          : 'New Data Folders can be protected with a password. Existing folders will not be changed. You can turn this off later, and folders already protected will remain protected.',
      ok: currentlyEnabled ? 'Disable' : 'Enable',
    );
    if (repo != true || !mounted) return;
    final saved = await guarded(context, () => _v.saveEncryptionSettings({'enabled': !currentlyEnabled}));
    if (saved == null || !mounted) return;
    setState(() => _encryption = saved);
    toast(context, currentlyEnabled ? 'Folder protection disabled for new folders.' : 'Folder protection enabled for new folders.');
  }

  Future<void> _editEmail() async {
    final f = await formDialog(context, 'Outgoing Email', [
      FieldSpec('enabled', 'Enable Email', kind: 'bool', initial: '${_email['enabled'] == true}'),
      FieldSpec('host', 'SMTP Host', initial: '${_email['host'] ?? ''}'),
      FieldSpec('port', 'SMTP Port', initial: '${_email['port'] ?? 587}', hint: 'STARTTLS is supported (usually port 587). Implicit TLS on port 465 is not supported.'),
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
      FieldSpec('apiRequests', 'General API Requests Per Account', initial: '${_rateLimits['apiRequests'] ?? 1200}'),
      FieldSpec('apiWindow', 'General API Window (Seconds)', initial: '${_rateLimits['apiWindowSeconds'] ?? 60}'),
    ], ok: 'Save Rate Limits',
      intro: 'Authentication is limited per client IP, messages per signed-in user, and general API requests per account (or IP before sign-in). The general limit protects storage and file endpoints, but it limits request frequency rather than bytes transferred. Changes apply immediately.');
    if (f == null || !mounted) return;
    final auth = int.tryParse(f['authRequests'] ?? '');
    final authWindow = int.tryParse(f['authWindow'] ?? '');
    final messages = int.tryParse(f['messageRequests'] ?? '');
    final messageWindow = int.tryParse(f['messageWindow'] ?? '');
    final api = int.tryParse(f['apiRequests'] ?? '');
    final apiWindow = int.tryParse(f['apiWindow'] ?? '');
    if (auth == null || authWindow == null || messages == null || messageWindow == null ||
        api == null || apiWindow == null) {
      toast(context, 'Enter valid rate-limit values.', error: true);
      return;
    }
    final saved = await guarded(context, () => _v.saveRateLimitSettings({
      'authRequests': auth, 'authWindowSeconds': authWindow,
      'messageRequests': messages, 'messageWindowSeconds': messageWindow,
      'apiRequests': api, 'apiWindowSeconds': apiWindow,
    }));
    if (saved == null || !mounted) return;
    setState(() => _rateLimits = saved);
    toast(context, 'Rate limits saved.');
  }

  Future<void> _editLimits() async {
    final fields = <(String, String, int)>[
      ('maxSchedulesPerUser', 'Schedules Per User', 50),
      ('minScheduleIntervalMinutes', 'Minimum Schedule Interval (Minutes)', 5),
      ('maxPendingJobsPerUser', 'Unfinished Jobs Per User (0 = Unlimited)', 200),
      ('maxPendingJobs', 'Maximum Unfinished Jobs Across Server (0 = Unlimited)', 1000),
      ('maxConcurrentJobs', 'Maximum Concurrent Server Jobs (0 = Unlimited)', 8),
      ('maxConcurrentJobsPerUser', 'Maximum Concurrent Jobs Per User (0 = Unlimited)', 2),
      ('maxConcurrentTransfers', 'Maximum Concurrent File Transfers Across Server (0 = Unlimited)', 8),
      ('maxConcurrentTransfersPerUser', 'Maximum Concurrent File Transfers Per User (0 = Unlimited)', 2),
      ('maxTransferBytesPerSecond', 'Maximum API Transfer Bandwidth Across Server (Bytes/Sec, 0 = Unlimited)', 0),
      ('maxTransferBytesPerSecondPerUser', 'Maximum API Transfer Bandwidth Per User (Bytes/Sec, 0 = Unlimited)', 0),
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
      intro: 'Control queue limits, global and per-user job concurrency, simultaneous file transfers, retention, and in-memory event history. Use 0 for unlimited concurrency or to keep records indefinitely.');
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

  Future<void> _editUserLimits() async {
    final users = <UserAccount>[];
    String? cursor;
    do {
      final page = await guarded(
        context,
        () => _v.users(cursor: cursor, limit: 200),
      );
      if (page == null) return;
      users.addAll(page.items);
      cursor = page.nextCursor;
    } while (cursor != null);
    if (!mounted) return;
    if (users.isEmpty) return toast(context, 'There are no user accounts to configure.');

    final selection = await formDialog(
      context,
      'Choose a User',
      [
        FieldSpec(
          'userName',
          'User',
          kind: 'choice',
          initial: users.first.userName,
          options: users.map((user) => user.userName).toList(),
        ),
      ],
      ok: 'Continue',
      intro: 'Choose the account whose job queue, job concurrency, and file-transfer limits you want to override.',
    );
    if (selection == null || !mounted) return;
    final userName = selection['userName'] ?? '';
    final current = await guarded(context, () => _v.userResourceLimits(userName));
    if (current == null || !mounted) return;
    final concurrencyOverride = current['concurrencyOverride'];
    final pendingOverride = current['pendingOverride'];
    final transferOverride = current['transferOverride'];
    final bandwidthOverride = current['bandwidthOverride'];
    final f = await formDialog(
      context,
      'Resource Limits · $userName',
      [
        FieldSpec(
          'concurrency',
          'Maximum Concurrent Jobs',
          initial: concurrencyOverride == null ? '' : '$concurrencyOverride',
          hint: '0 = Unlimited. Blank uses the server default.',
          number: true,
        ),
        FieldSpec(
          'pending',
          'Maximum Unfinished Jobs',
          initial: pendingOverride == null ? '' : '$pendingOverride',
          hint: '0 = Unlimited. Blank uses the server default.',
          number: true,
        ),
        FieldSpec(
          'transfers',
          'Maximum Concurrent File Transfers',
          initial: transferOverride == null ? '' : '$transferOverride',
          hint: '0 = Unlimited. Blank uses the server default.',
          number: true,
        ),
        FieldSpec(
          'bandwidth',
          'Maximum API Transfer Bandwidth (Bytes/Sec)',
          initial: bandwidthOverride == null ? '' : '$bandwidthOverride',
          hint: '0 = Unlimited. Blank uses the server default. 1048576 = 1 MiB/s.',
          number: true,
        ),
      ],
      ok: 'Save Limits',
      intro: 'Effective defaults: ${current['effectiveConcurrencyLimit']} concurrent jobs, ${current['effectivePendingLimit']} unfinished jobs, ${current['effectiveTransferLimit']} concurrent file transfers, and ${current['effectiveBandwidthLimit']} bytes/sec. Blank fields inherit the defaults.',
    );
    if (f == null || !mounted) return;
    final concurrencyRaw = (f['concurrency'] ?? '').trim();
    final pendingRaw = (f['pending'] ?? '').trim();
    final transferRaw = (f['transfers'] ?? '').trim();
    final bandwidthRaw = (f['bandwidth'] ?? '').trim();
    final concurrency = concurrencyRaw.isEmpty ? null : int.tryParse(concurrencyRaw);
    final pending = pendingRaw.isEmpty ? null : int.tryParse(pendingRaw);
    final transfers = transferRaw.isEmpty ? null : int.tryParse(transferRaw);
    final bandwidth = bandwidthRaw.isEmpty ? null : int.tryParse(bandwidthRaw);
    if ((concurrencyRaw.isNotEmpty && (concurrency == null || concurrency < 0 || concurrency > 1000)) ||
        (pendingRaw.isNotEmpty && (pending == null || pending < 0 || pending > 100000)) ||
        (transferRaw.isNotEmpty && (transfers == null || transfers < 0 || transfers > 1000)) ||
        (bandwidthRaw.isNotEmpty && (bandwidth == null || bandwidth < 0 || bandwidth > 1000000000000))) {
      toast(context, 'Enter valid job, transfer-concurrency, and bandwidth limits.', error: true);
      return;
    }
    await guarded(
      context,
      () => _v.saveUserResourceLimits(userName, concurrency, pending, transfers, bandwidth),
    );
    if (mounted) toast(context, 'Resource limits updated.');
  }

  Future<void> _viewResourceUsage() async {
    final rows = await guarded(context, _v.adminResourceUsage);
    if (rows == null || !mounted) return;
    final totalRunning = rows.fold<int>(0, (sum, row) => sum + (row['runningJobs'] as num? ?? 0).toInt());
    final totalQueued = rows.fold<int>(0, (sum, row) => sum + (row['queuedJobs'] as num? ?? 0).toInt());
    final totalTransfers = rows.fold<int>(0, (sum, row) => sum + (row['activeTransfers'] as num? ?? 0).toInt());
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Resource Usage'),
        content: SizedBox(
          width: 520,
          child: rows.isEmpty
              ? const Text('No user accounts found.')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Server Total'),
                      subtitle: Text('$totalRunning running · $totalQueued queued · $totalTransfers active transfers'),
                      trailing: Text(
                        '${(_limits['maxConcurrentJobs'] ?? 8) == 0 ? '∞' : (_limits['maxConcurrentJobs'] ?? 8)} concurrent\n${(_limits['maxPendingJobs'] ?? 1000) == 0 ? '∞' : (_limits['maxPendingJobs'] ?? 1000)} pending\n${(_limits['maxConcurrentTransfers'] ?? 8) == 0 ? '∞' : (_limits['maxConcurrentTransfers'] ?? 8)} transfers',
                        textAlign: TextAlign.end,
                      ),
                    ),
                    const Divider(height: 12),
                    for (final row in rows)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('${row['userName']}'),
                        subtitle: Text('${row['runningJobs']} running · ${row['queuedJobs']} queued · ${row['activeTransfers']} active transfers'),
                        trailing: Text(
                          '${row['maxConcurrentJobs'] == 0 ? '∞' : row['maxConcurrentJobs']} concurrent\n${row['maxPendingJobs'] == 0 ? '∞' : row['maxPendingJobs']} pending\n${row['maxConcurrentTransfers'] == 0 ? '∞' : row['maxConcurrentTransfers']} transfers',
                        ),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _editNotifications() async {
    final f = await formDialog(context, 'Webhook Notifications', [
      FieldSpec('url', 'Webhook URL', initial: '${_notifications['webhookUrl'] ?? ''}',
        hint: 'HTTP or HTTPS endpoint. Leave blank to disable webhooks.'),
      FieldSpec('secret', 'Signing Secret', kind: 'secret',
        hint: _notifications['hasWebhookSecret'] == true ? 'Leave blank to keep the saved secret.' : 'Optional. Requests are signed with HMAC-SHA256.'),
      FieldSpec('jobs', 'Notify on Job Failures', kind: 'bool', initial: '${_notifications['notifyJobFailures'] != false}'),
      FieldSpec('backups', 'Notify on Self-Backup Failures', kind: 'bool', initial: '${_notifications['notifySelfBackupFailures'] != false}'),
      FieldSpec('timeout', 'Request Timeout (Seconds)', initial: '${_notifications['timeoutSeconds'] ?? 10}'),
      FieldSpec('attempts', 'Maximum Attempts', initial: '${_notifications['maxAttempts'] ?? 3}'),
    ], ok: 'Save Notifications',
      intro: 'Vaulton sends JSON webhooks for configured failure events. The signing secret is encrypted at rest.');
    if (f == null || !mounted) return;
    final timeout = int.tryParse(f['timeout'] ?? '');
    final attempts = int.tryParse(f['attempts'] ?? '');
    if (timeout == null || attempts == null) {
      toast(context, 'Enter valid timeout and retry values.', error: true);
      return;
    }
    final saved = await guarded(context, () => _v.saveNotificationSettings({
      'webhookUrl': f['url'], 'webhookSecret': f['secret'],
      'notifyJobFailures': f['jobs'] == 'true',
      'notifySelfBackupFailures': f['backups'] == 'true',
      'timeoutSeconds': timeout, 'maxAttempts': attempts,
    }));
    if (saved == null || !mounted) return;
    setState(() => _notifications = saved);
    toast(context, 'Notification settings saved.');
  }

  Future<void> _editStartupSettings() async {
    final paths = (_startup['monitorPaths'] as List? ?? const []).join(', ');
    final f = await formDialog(context, 'Advanced Server Settings', [
      FieldSpec('receive', 'gRPC Receive Limit (Bytes)', initial: '${_startup['maxReceiveMessageSizeBytes'] ?? 33554432}'),
      FieldSpec('send', 'gRPC Send Limit (Bytes)', initial: '${_startup['maxSendMessageSizeBytes'] ?? 33554432}'),
      FieldSpec('chunk', 'Upload Chunk Size (Bytes)', initial: '${_startup['chunkSizeBytes'] ?? 1048576}'),
      FieldSpec('poll', 'Backend Poll Interval (Milliseconds)', initial: '${_startup['pollIntervalMs'] ?? 1000}'),
      FieldSpec('sync', 'VFS Sync Interval (Milliseconds)', initial: '${_startup['vfsSyncIntervalMs'] ?? 30000}'),
      FieldSpec('timeout', 'gRPC Call Timeout (Seconds)', initial: '${_startup['callTimeoutSeconds'] ?? 30}'),
      FieldSpec('paths', 'Storage Monitor Paths (comma separated)', initial: paths),
      FieldSpec('freePercent', 'Minimum Free Space (Percent)', initial: '${_startup['minimumFreePercent'] ?? 5}'),
      FieldSpec('freeBytes', 'Minimum Free Space (Bytes)', initial: '${_startup['minimumFreeBytes'] ?? 1073741824}'),
      FieldSpec('alertInterval', 'Storage Alert Interval (Minutes)', initial: '${_startup['alertIntervalMinutes'] ?? 15}'),
      FieldSpec('backupEnabled', 'Enable Automatic Self-Backups', kind: 'bool', initial: '${_startup['selfBackupEnabled'] != false}'),
      FieldSpec('backupInterval', 'Self-Backup Interval (Hours)', initial: '${_startup['selfBackupIntervalHours'] ?? 24}'),
      FieldSpec('backupRetain', 'Self-Backup Copies to Keep', initial: '${_startup['selfBackupRetain'] ?? 7}'),
      FieldSpec('backupDirectory', 'Self-Backup Directory', initial: '${_startup['selfBackupDirectory'] ?? 'App_Data/backups'}'),
      FieldSpec('backupDelay', 'Self-Backup Startup Delay (Seconds)', initial: '${_startup['selfBackupStartupDelaySeconds'] ?? 60}'),
      FieldSpec('auditEnabled', 'Enable Audit Logging', kind: 'bool', initial: '${_startup['auditEnabled'] != false}'),
      FieldSpec('auditRetention', 'Audit Retention (Days, 0 = Forever)', initial: '${_startup['auditRetentionDays'] ?? 180}'),
      FieldSpec('auditReads', 'Include Successful Read Requests', kind: 'bool', initial: '${_startup['auditIncludeReads'] == true}'),
      FieldSpec('metricsEnabled', 'Enable Metrics Endpoint', kind: 'bool', initial: '${_startup['metricsEnabled'] == true}'),
      FieldSpec('metricsPaths', 'Include Route Labels in Metrics', kind: 'bool', initial: '${_startup['metricsIncludePaths'] == true}'),
      FieldSpec('logLevel', 'Minimum Log Level', kind: 'choice', initial: '${_startup['logLevel'] ?? 'Information'}',
        options: const ['Verbose', 'Debug', 'Information', 'Warning', 'Error', 'Fatal']),
      FieldSpec('corsOrigins', 'Allowed Browser Origins (comma separated)', initial: ((_startup['corsOrigins'] as List?) ?? const []).join(', ')),
      FieldSpec('forwardedHeaders', 'Trust Reverse Proxy Headers', kind: 'bool', initial: '${_startup['useForwardedHeaders'] == true}'),
      FieldSpec('knownProxies', 'Trusted Proxy IP Addresses (comma separated)', initial: ((_startup['knownProxies'] as List?) ?? const []).join(', ')),
      FieldSpec('exposeOpenApi', 'Expose OpenAPI Documentation', kind: 'bool', initial: '${_startup['exposeOpenApi'] == true}'),
      FieldSpec('smbEnabled', 'Enable SMB File Sharing', kind: 'bool', initial: '${_startup['smbEnabled'] != false}'),
      FieldSpec('smbBindAddress', 'SMB Bind Address', initial: '${_startup['smbBindAddress'] ?? '0.0.0.0'}'),
      FieldSpec('accessTokenMinutes', 'Access Token Lifetime (Minutes)', initial: '${_startup['accessTokenMinutes'] ?? 30}'),
      FieldSpec('refreshTokenDays', 'Refresh Token Lifetime (Days)', initial: '${_startup['refreshTokenDays'] ?? 14}'),
    ], ok: 'Save Server Settings',
      intro: 'These settings control backend performance, storage alerts, self-backups, audit, metrics, logging, browser access, reverse proxies, SMB, and token lifetimes. Changes require an API restart. Deployment environment variables override saved values. The metrics and OpenAPI endpoints can expose operational details; use them only on trusted networks. A wildcard CORS origin allows every website. Only trust proxy IPs you control.');
    if (f == null || !mounted) return;
    int? number(String key) => int.tryParse(f[key] ?? '');
    final receive = number('receive'), send = number('send'), chunk = number('chunk');
    final poll = number('poll'), sync = number('sync'), timeout = number('timeout');
    final freeBytes = number('freeBytes'), alert = number('alertInterval');
    final backupInterval = number('backupInterval'), backupRetain = number('backupRetain');
    final backupDelay = number('backupDelay'), auditRetention = number('auditRetention');
    final accessTokenMinutes = number('accessTokenMinutes'), refreshTokenDays = number('refreshTokenDays');
    final freePercent = double.tryParse(f['freePercent'] ?? '');
    if ([receive, send, chunk, poll, sync, timeout, freeBytes, alert, backupInterval,
      backupRetain, backupDelay, auditRetention, accessTokenMinutes, refreshTokenDays].any((v) => v == null) || freePercent == null) {
      toast(context, 'Enter valid numeric values for all server settings.', error: true);
      return;
    }
    final saved = await guarded(context, () => _v.saveStartupSettings({
      'maxReceiveMessageSizeBytes': receive!, 'maxSendMessageSizeBytes': send!,
      'chunkSizeBytes': chunk!, 'pollIntervalMs': poll!, 'vfsSyncIntervalMs': sync!,
      'callTimeoutSeconds': timeout!,
      'monitorPaths': (f['paths'] ?? '').split(',').map((x) => x.trim()).where((x) => x.isNotEmpty).toList(),
      'minimumFreePercent': freePercent, 'minimumFreeBytes': freeBytes!,
      'alertIntervalMinutes': alert!,
      'selfBackupEnabled': f['backupEnabled'] == 'true',
      'selfBackupIntervalHours': backupInterval!, 'selfBackupRetain': backupRetain!,
      'selfBackupDirectory': f['backupDirectory'], 'selfBackupStartupDelaySeconds': backupDelay!,
      'auditEnabled': f['auditEnabled'] == 'true', 'auditRetentionDays': auditRetention!,
      'auditIncludeReads': f['auditReads'] == 'true',
      'metricsEnabled': f['metricsEnabled'] == 'true', 'metricsIncludePaths': f['metricsPaths'] == 'true',
      'logLevel': f['logLevel'],
      'corsOrigins': (f['corsOrigins'] ?? '').split(',').map((x) => x.trim()).where((x) => x.isNotEmpty).toList(),
      'useForwardedHeaders': f['forwardedHeaders'] == 'true',
      'knownProxies': (f['knownProxies'] ?? '').split(',').map((x) => x.trim()).where((x) => x.isNotEmpty).toList(),
      'exposeOpenApi': f['exposeOpenApi'] == 'true',
      'smbEnabled': f['smbEnabled'] == 'true', 'smbBindAddress': f['smbBindAddress'],
      'accessTokenMinutes': accessTokenMinutes!,
      'refreshTokenDays': refreshTokenDays!,
    }));
    if (saved == null || !mounted) return;
    setState(() => _startup = saved);
    toast(context, 'Server settings saved. Restart the API to apply them.');
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
          Card(
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.speed_outlined),
                title: const Text('Resource Governance'),
                subtitle: Text('${_limits['maxPendingJobs'] ?? 1000} unfinished jobs · ${_limits['maxPendingJobsPerUser'] ?? 200} per user · ${_limits['maxConcurrentJobs'] ?? 8} active globally · ${_limits['maxConcurrentJobsPerUser'] ?? 2} per user'),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _viewResourceUsage,
                        icon: const Icon(Icons.analytics_outlined),
                        label: const Text('View Usage'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _editUserLimits,
                        icon: const Icon(Icons.tune),
                        label: const Text('User Overrides'),
                      ),
                    ],
                  ),
                ),
              ),
            ]),
          ),
          Card(
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.notifications_active_outlined),
                title: const Text('Webhook Notifications'),
                subtitle: Text((_notifications['webhookUrl'] ?? '').toString().isEmpty
                    ? 'Disabled'
                    : '${_notifications['webhookUrl']}'),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Align(alignment: Alignment.centerRight, child: FilledButton.tonalIcon(
                  onPressed: _editNotifications,
                  icon: const Icon(Icons.settings_outlined), label: const Text('Configure'))),
              ),
            ]),
          ),
          Card(
            child: Column(children: [
              ListTile(
                leading: Icon(_encryption['enabled'] == true ? Icons.lock_outlined : Icons.lock_open_outlined, color: _encryption['enabled'] == true ? cs.primary : null),
                title: const Text('Folder Protection'),
                subtitle: Text(_encryption['enabled'] == true ? 'On · New folders can be protected with a password.' : 'Off · New folders will not be password-protected.'),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Align(alignment: Alignment.centerRight, child: FilledButton.tonalIcon(
                  onPressed: _editEncryption,
                  icon: const Icon(Icons.settings_outlined), label: const Text('Configure'))),
              ),
            ]),
          ),
          Card(
            child: Column(children: [
              const ListTile(
                leading: Icon(Icons.tune_outlined),
                title: Text('Advanced Server Settings'),
                subtitle: Text('gRPC, storage alerts, self-backups, audit, metrics, logging, security, SMB, and token lifetimes. Requires an API restart.'),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Align(alignment: Alignment.centerRight, child: FilledButton.tonalIcon(
                  onPressed: _editStartupSettings,
                  icon: const Icon(Icons.settings_outlined), label: const Text('Configure'))),
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
