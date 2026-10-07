import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/util.dart';
import '../../core/widgets.dart';

class _ConfigurationTab extends ConsumerStatefulWidget {
  const _ConfigurationTab();
  @override
  ConsumerState<_ConfigurationTab> createState() => _ConfigurationTabState();
}

class _ConfigurationTabState extends ConsumerState<_ConfigurationTab> {
  bool _enabled = false;
  String _brokerUrl = '';
  int _wakeBeforeMinutes = 5;
  bool _hasAdminToken = false;
  bool _hasWakeToken = false;
  bool _loaded = false;

  Vaulton get _v => ref.read(vaultonProvider);

  Future<void> _load() async {
    final data = await guarded(context, _v.wolSettings);
    if (data == null || !mounted) return;
    setState(() {
      _enabled = toBool(data['enabled']);
      _brokerUrl = toStr(data['brokerUrl']) ?? '';
      _wakeBeforeMinutes = toInt(data['wakeBeforeMinutes']);
      _hasAdminToken = toBool(data['hasAdminToken']);
      _hasWakeToken = toBool(data['hasWakeToken']);
      _loaded = true;
    });
  }

  Future<void> _editWake() async {
    final f = await formDialog(context, 'Wake-on-LAN', [
      FieldSpec('enabled', 'Enable Wake-on-LAN', kind: 'bool', initial: '$_enabled'),
      FieldSpec('url', 'Cloudflare Worker URL', initial: _brokerUrl),
      FieldSpec('admin', 'Worker admin token', kind: 'secret', hint: 'Leave blank to keep the existing token.'),
      FieldSpec('wake', 'Worker wake token', kind: 'secret', help: 'Leave blank to keep the existing token.'),
      FieldSpec('minutes', 'Wake before scheduled job (minutes)', initial: '$_wakeBeforeMinutes'),
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
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: Icon(_enabled ? Icons.wifi_tethering : Icons.wifi_tethering_off, color: _enabled ? cs.primary : null),
              title: const Text('Wake-on-LAN'),
              subtitle: Text(_enabled ? 'Enabled · ${_brokerUrl.isEmpty ? 'Worker URL not set' : _brokerUrl}' : 'Disabled'),
              trailing: FilledButton.tonalIcon(
                onPressed: _editWake,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Configure'),
              ),
            ),
          ),
          Section('Wake-on-LAN', children: [
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Automatic Wake'),
              subtitle: Text(_enabled
                  ? (_wakeBeforeMinutes == 0
                      ? 'The server will wake when a scheduled job needs it.'
                      : 'The server will wake $_wakeBeforeMinutes minutes before a scheduled job needs it.')
                  : 'Enable Wake-on-LAN to wake the server for scheduled jobs.'),
            ),
            ListTile(
              leading: Icon(_hasAdminToken ? Icons.check_circle_outline : Icons.warning_amber_outlined),
              title: const Text('Broker Admin Token'),
              subtitle: Text(_hasAdminToken ? 'Configured securely.' : 'Not configured.'),
            ),
            ListTile(
              leading: Icon(_hasWakeToken ? Icons.check_circle_outline : Icons.warning_amber_outlined),
              title: const Text('Broker Wake Token'),
              subtitle: Text(_hasWakeToken ? 'Configured securely.' : 'Not configured.'),
            ),
          ]),
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('The broker tokens are encrypted in Vaulton’s persistent application data and are never shown after they are saved.'),
          ),
        ],
      ),
    );
  }
}
