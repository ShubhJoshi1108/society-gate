import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../common.dart';

/// Notification setup (via the free, open-source ntfy app) + account info.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.onLogout});
  final VoidCallback onLogout;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, dynamic>? _push;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await Api.I.pushInfo();
      setState(() => _push = p);
    } catch (e) {
      setState(() => _error = Api.errorText(e));
    }
  }

  String get _server => (_push?['server'] as String? ?? '').replaceAll(RegExp(r'/$'), '');
  String get _topic => _push?['topic'] as String? ?? '';

  Future<void> _subscribe() async {
    final host = Uri.parse(_server).host;
    final deep = Uri.parse('ntfy://$host/$_topic');
    final ok = await launchUrl(deep, mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!ok && mounted) {
      toast(context, 'Install the ntfy app first, then tap again.');
      await launchUrl(Uri.parse('https://play.google.com/store/apps/details?id=io.heckel.ntfy'),
          mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = Api.I.me;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(me.getStringValue('name').isEmpty ? me.getStringValue('email') : me.getStringValue('name')),
            subtitle: Text('${me.getStringValue('role').toUpperCase()}  •  ${Api.I.serverUrl}'),
          ),
        ),
        const SizedBox(height: 16),
        Text('Notifications', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text(
          'Alerts are delivered by ntfy – a free, open-source notification app. '
          'It works even when Society Gate is closed, and lets you Approve / Deny '
          'right from the notification.',
        ),
        const SizedBox(height: 12),
        if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
        if (_push == null && _error == null) const LinearProgressIndicator(),
        if (_push != null) ...[
          _step('1', 'Install ntfy', 'Google Play or F-Droid (free)', () {
            launchUrl(Uri.parse('https://play.google.com/store/apps/details?id=io.heckel.ntfy'),
                mode: LaunchMode.externalApplication);
          }, 'Install'),
          _step('2', 'Subscribe to your alerts', 'Opens ntfy with your private channel', _subscribe, 'Subscribe'),
          _step('3', 'Send a test alert', 'You should get a notification within seconds', () {
            runSafe(context, Api.I.pushTest, success: 'Test sent');
          }, 'Test'),
          const SizedBox(height: 12),
          ExpansionTile(
            title: const Text('Manual setup'),
            subtitle: const Text('If the Subscribe button does not work'),
            children: [
              ListTile(
                title: const Text('Server'),
                subtitle: SelectableText(_server),
                trailing: IconButton(icon: const Icon(Icons.copy), onPressed: () => _copy(_server)),
              ),
              ListTile(
                title: const Text('Topic (keep private)'),
                subtitle: SelectableText(_topic),
                trailing: IconButton(icon: const Icon(Icons.copy), onPressed: () => _copy(_topic)),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Text('In ntfy: tap + → enter Topic → "Use another server" → paste Server → Subscribe. '
                    'Then in ntfy settings, set this channel to "Max priority" and allow it to bypass Do-Not-Disturb.'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        OutlinedButton.icon(
          icon: const Icon(Icons.logout),
          label: const Text('Log out'),
          onPressed: () async {
            await Api.I.logout();
            if (!context.mounted) return;
            Navigator.of(context).popUntil((r) => r.isFirst);
            widget.onLogout();
          },
        ),
      ]),
    );
  }

  void _copy(String s) {
    Clipboard.setData(ClipboardData(text: s));
    toast(context, 'Copied');
  }

  Widget _step(String n, String title, String sub, VoidCallback onTap, String action) => Card(
        child: ListTile(
          leading: CircleAvatar(child: Text(n)),
          title: Text(title),
          subtitle: Text(sub),
          trailing: FilledButton.tonal(onPressed: onTap, child: Text(action)),
        ),
      );
}
