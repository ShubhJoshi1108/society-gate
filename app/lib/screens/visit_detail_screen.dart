import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';

import '../api.dart';
import '../common.dart';

/// Live view of one visit. Guards see status + "call resident";
/// residents see Approve / Deny / Leave at gate.
class VisitDetailScreen extends StatefulWidget {
  const VisitDetailScreen({super.key, required this.visitId, this.initial});
  final String visitId;
  final RecordModel? initial;

  @override
  State<VisitDetailScreen> createState() => _VisitDetailScreenState();
}

class _VisitDetailScreenState extends State<VisitDetailScreen> {
  RecordModel? _v;
  List<RecordModel> _residents = [];
  UnsubscribeFunc? _unsub;
  bool _busy = false;

  bool get _isGuard => Api.I.role == 'guard' || Api.I.role == 'admin';

  @override
  void initState() {
    super.initState();
    _v = widget.initial;
    _load();
    _subscribe();
  }

  Future<void> _subscribe() async {
    try {
      _unsub = await Api.I.pb.collection('visits').subscribe(widget.visitId, (e) {
        if (e.record != null && mounted) _load();
      }, expand: 'flat');
    } catch (_) {}
  }

  @override
  void dispose() {
    _unsub?.call();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final v = await Api.I.getVisit(widget.visitId);
      if (!mounted) return;
      setState(() => _v = v);
      if (_isGuard && _residents.isEmpty) {
        final r = await Api.I.residentsOf(v.getStringValue('flat'));
        if (mounted) setState(() => _residents = r);
      }
    } catch (e) {
      if (mounted) toast(context, Api.errorText(e));
    }
  }

  Future<void> _decide(String d) async {
    setState(() => _busy = true);
    await runSafe(context, () async {
      await Api.I.decide(widget.visitId, d);
      await _load();
    }, success: statusInfo[d]?.$1);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final v = _v;
    if (v == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final status = v.getStringValue('status');
    final (label, color, icon) = statusInfo[status] ?? (status, Colors.grey, Icons.info);
    final phone = v.getStringValue('visitor_phone');
    final purpose = purposes[v.getStringValue('purpose')]?.$1 ?? '';
    final note = v.getStringValue('purpose_note');
    final photo = Api.I.photoUrl(v);

    return Scaffold(
      appBar: AppBar(title: Text(v.getStringValue('visitor_name'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // Big status banner – easy for guard to read from a distance
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            status == 'pending'
                ? SizedBox(width: 48, height: 48, child: CircularProgressIndicator(color: color))
                : Icon(icon, size: 56, color: color),
            const SizedBox(height: 8),
            Text(
              _isGuard && status == 'approved' ? 'ALLOW ENTRY' : label.toUpperCase(),
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: color),
            ),
            if (status == 'pending')
              Text(_isGuard ? 'Waiting for resident…' : 'Someone is at the gate for you'),
            if (v.getStringValue('decided_at').isNotEmpty) Text('at ${hhmm(v.getStringValue('decided_at'))}'),
          ]),
        ),
        const SizedBox(height: 16),
        if (photo.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(photo, height: 220, fit: BoxFit.cover),
          ),
        Card(
          child: Column(children: [
            ListTile(leading: const Icon(Icons.home), title: const Text('House'), trailing: Text(flatLabelOf(v))),
            ListTile(
              leading: Icon(purposes[v.getStringValue('purpose')]?.$2 ?? Icons.info),
              title: const Text('Purpose'),
              subtitle: Text(note.isEmpty ? purpose : '$purpose · $note'),
            ),
            if (phone.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.phone),
                title: const Text('Visitor mobile'),
                subtitle: Text(phone),
                trailing: IconButton(icon: const Icon(Icons.call), onPressed: () => callNumber(context, phone)),
              ),
            if (v.getStringValue('vehicle_no').isNotEmpty)
              ListTile(
                leading: const Icon(Icons.directions_car),
                title: const Text('Vehicle'),
                trailing: Text(v.getStringValue('vehicle_no')),
              ),
            if (v.getIntValue('people_count') > 1)
              ListTile(
                leading: const Icon(Icons.groups),
                title: const Text('People'),
                trailing: Text('${v.getIntValue('people_count')}'),
              ),
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Arrived'),
              trailing: Text(hhmm(v.getStringValue('created'))),
            ),
            if (v.getStringValue('checked_out_at').isNotEmpty)
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Exited'),
                trailing: Text(hhmm(v.getStringValue('checked_out_at'))),
              ),
            if (v.getStringValue('pass_code').isNotEmpty)
              const ListTile(leading: Icon(Icons.verified), title: Text('Entered with pre-approved pass')),
          ]),
        ),
        const SizedBox(height: 12),

        // Resident actions
        if (!_isGuard && status == 'pending') ...[
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.all(18)),
                onPressed: _busy ? null : () => _decide('approved'),
                icon: const Icon(Icons.check),
                label: const Text('Approve'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.red, padding: const EdgeInsets.all(18)),
                onPressed: _busy ? null : () => _decide('denied'),
                icon: const Icon(Icons.close),
                label: const Text('Deny'),
              ),
            ),
          ]),
          if (v.getStringValue('purpose') == 'delivery') ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _decide('leave_at_gate'),
              icon: const Icon(Icons.inventory_2),
              label: const Text('Leave at gate'),
            ),
          ],
        ],

        // Guard actions
        if (_isGuard) ...[
          if (_residents.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Call resident', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            for (final r in _residents)
              Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(r.getStringValue('name').isEmpty ? 'Resident' : r.getStringValue('name')),
                  subtitle: Text(r.getStringValue('phone')),
                  trailing: IconButton.filledTonal(
                    icon: const Icon(Icons.call),
                    onPressed: r.getStringValue('phone').isEmpty
                        ? null
                        : () => callNumber(context, r.getStringValue('phone')),
                  ),
                ),
              ),
          ],
          if (status == 'approved' && v.getStringValue('checked_out_at').isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.logout),
                label: const Text('Mark exit'),
                onPressed: () => runSafe(context, () async {
                  await Api.I.checkout(v.id);
                  await _load();
                }, success: 'Checked out'),
              ),
            ),
        ],
      ]),
    );
  }
}
