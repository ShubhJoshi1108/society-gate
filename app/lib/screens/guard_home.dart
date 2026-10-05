import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';

import '../api.dart';
import '../common.dart';
import 'house_number_screen.dart';
import 'new_visit_screen.dart';
import 'settings_screen.dart';
import 'visit_detail_screen.dart';

class GuardHome extends StatefulWidget {
  const GuardHome({super.key, required this.onLogout});
  final VoidCallback onLogout;

  @override
  State<GuardHome> createState() => _GuardHomeState();
}

class _GuardHomeState extends State<GuardHome> {
  List<RecordModel> _today = [];
  List<RecordModel> _inside = [];
  bool _loading = true;
  UnsubscribeFunc? _unsub;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribe();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) => mounted ? setState(() {}) : null);
  }

  Future<void> _subscribe() async {
    try {
      _unsub = await Api.I.watchVisits((_) => _load());
    } catch (_) {
      // realtime is optional; pull-to-refresh still works
    }
  }

  @override
  void dispose() {
    _unsub?.call();
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day).toUtc();
      final pb = Api.I.pb;
      final today = await Api.I.visits(filter: pb.filter('created >= {:d}', {'d': midnight}));
      final inside = await Api.I.visits(
        filter: "status = 'approved' && checked_out_at = ''",
        perPage: 200,
      );
      if (!mounted) return;
      setState(() {
        _today = today;
        _inside = inside;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        toast(context, Api.errorText(e));
      }
    }
  }

  void _open(RecordModel v) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => VisitDetailScreen(visitId: v.id, initial: v)),
      );

  Future<void> _newVisit({bool withPass = false}) async {
    final created = await Navigator.push<RecordModel>(
      context,
      MaterialPageRoute(
        builder: (_) => withPass ? const NewVisitScreen(passMode: true) : const HouseNumberScreen(),
      ),
    );
    if (created != null && mounted) _open(created);
  }

  @override
  Widget build(BuildContext context) {
    final pending = _today.where((v) => v.getStringValue('status') == 'pending').toList();
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gate'),
          actions: [
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => SettingsScreen(onLogout: widget.onLogout)),
              ),
            ),
          ],
          bottom: TabBar(tabs: [
            Tab(text: 'Today (${_today.length})'),
            Tab(text: 'Inside (${_inside.length})'),
          ]),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(children: [
                RefreshIndicator(
                  onRefresh: _load,
                  child: _today.isEmpty
                      ? const EmptyState(Icons.door_front_door, 'No visitors yet today')
                      : ListView(children: [
                          if (pending.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                              child: Text('Waiting for approval (${pending.length})',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                            ),
                          ...pending.map((v) => VisitTile(v, onTap: () => _open(v))),
                          if (pending.isNotEmpty) const Divider(),
                          ..._today
                              .where((v) => v.getStringValue('status') != 'pending')
                              .map((v) => VisitTile(v, onTap: () => _open(v))),
                          const SizedBox(height: 90),
                        ]),
                ),
                RefreshIndicator(
                  onRefresh: _load,
                  child: _inside.isEmpty
                      ? const EmptyState(Icons.groups, 'Nobody inside right now')
                      : ListView(children: [
                          ..._inside.map((v) => VisitTile(
                                v,
                                onTap: () => _open(v),
                                trailing: FilledButton.tonal(
                                  onPressed: () => runSafe(context, () async {
                                    await Api.I.checkout(v.id);
                                    await _load();
                                  }, success: '${v.getStringValue('visitor_name')} checked out'),
                                  child: const Text('Exit'),
                                ),
                              )),
                          const SizedBox(height: 90),
                        ]),
                ),
              ]),
        floatingActionButton: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
          FloatingActionButton.small(
            heroTag: 'pass',
            tooltip: 'Guest has a pass code',
            onPressed: () => _newVisit(withPass: true),
            child: const Icon(Icons.pin),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'new',
            onPressed: _newVisit,
            icon: const Icon(Icons.person_add),
            label: const Text('New visitor'),
          ),
        ]),
      ),
    );
  }
}
