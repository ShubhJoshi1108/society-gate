import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';

import '../api.dart';
import '../common.dart';
import 'passes_screen.dart';
import 'settings_screen.dart';
import 'visit_detail_screen.dart';

class ResidentHome extends StatefulWidget {
  const ResidentHome({super.key, required this.onLogout});
  final VoidCallback onLogout;

  @override
  State<ResidentHome> createState() => _ResidentHomeState();
}

class _ResidentHomeState extends State<ResidentHome> {
  int _tab = 0;
  List<RecordModel> _visits = [];
  bool _loading = true;
  UnsubscribeFunc? _unsub;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
    _subscribe();
  }

  Future<void> _subscribe() async {
    try {
      _unsub = await Api.I.watchVisits((_) => _load());
    } catch (_) {}
  }

  @override
  void dispose() {
    _unsub?.call();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final v = await Api.I.visits(perPage: 100);
      if (mounted) {
        setState(() {
          _visits = v;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        toast(context, Api.errorText(e));
      }
    }
  }

  Future<void> _decide(RecordModel v, String d) async {
    setState(() => _busy.add(v.id));
    await runSafe(context, () async {
      await Api.I.decide(v.id, d);
      await _load();
    }, success: '${v.getStringValue('visitor_name')}: ${statusInfo[d]?.$1}');
    if (mounted) setState(() => _busy.remove(v.id));
  }

  void _open(RecordModel v) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => VisitDetailScreen(visitId: v.id, initial: v)));

  Widget _pendingCard(RecordModel v) {
    final busy = _busy.contains(v.id);
    final phone = v.getStringValue('visitor_phone');
    final purpose = purposes[v.getStringValue('purpose')]?.$1 ?? '';
    final note = v.getStringValue('purpose_note');
    return Card(
      color: Colors.orange.withValues(alpha: 0.08),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            onTap: () => _open(v),
            child: Row(children: [
              VisitorAvatar(v, radius: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(v.getStringValue('visitor_name'),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(note.isEmpty ? purpose : '$purpose · $note'),
                  Text('At the gate · ${timeAgo(v.getStringValue('created'))}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ]),
              ),
              if (phone.isNotEmpty)
                IconButton(icon: const Icon(Icons.call), onPressed: () => callNumber(context, phone)),
            ]),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.green),
                onPressed: busy ? null : () => _decide(v, 'approved'),
                child: const Text('Approve'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: busy ? null : () => _decide(v, 'denied'),
                child: const Text('Deny'),
              ),
            ),
            if (v.getStringValue('purpose') == 'delivery') ...[
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : () => _decide(v, 'leave_at_gate'),
                  child: const Text('At gate'),
                ),
              ),
            ],
          ]),
        ]),
      ),
    );
  }

  Widget _visitsTab() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final pending = _visits.where((v) => v.getStringValue('status') == 'pending').toList();
    final rest = _visits.where((v) => v.getStringValue('status') != 'pending').toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: _visits.isEmpty
          ? const EmptyState(Icons.notifications_none, 'No visitors yet')
          : ListView(children: [
              ...pending.map(_pendingCard),
              if (rest.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text('History', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ...rest.map((v) => VisitTile(v, showFlat: false, onTap: () => _open(v))),
            ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = _visits.where((v) => v.getStringValue('status') == 'pending').length;
    return Scaffold(
      appBar: AppBar(
        title: Text(_tab == 0 ? 'Visitors' : 'Guest passes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SettingsScreen(onLogout: widget.onLogout)),
            ),
          ),
        ],
      ),
      body: _tab == 0 ? _visitsTab() : const PassesScreen(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
            icon: Badge(isLabelVisible: pendingCount > 0, label: Text('$pendingCount'), child: const Icon(Icons.door_front_door)),
            label: 'Visitors',
          ),
          const NavigationDestination(icon: Icon(Icons.confirmation_number), label: 'Passes'),
        ],
      ),
    );
  }
}
