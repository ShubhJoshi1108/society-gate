import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';

import '../api.dart';
import '../common.dart';
import 'new_visit_screen.dart';

/// Guard step 1 of 2: type the house number on a big keypad.
/// Shows who lives there so the guard can confirm, then opens the visitor form.
class HouseNumberScreen extends StatefulWidget {
  const HouseNumberScreen({super.key});

  @override
  State<HouseNumberScreen> createState() => _HouseNumberScreenState();
}

class _HouseNumberScreenState extends State<HouseNumberScreen> {
  Map<String, RecordModel> _houses = {};
  bool _loading = true;
  String _typed = '';
  RecordModel? _house;
  List<RecordModel> _residents = [];
  bool _loadingResidents = false;
  int _lookup = 0; // ignores slow replies for a number the guard already changed

  int get _maxHouse => _houses.keys.map((k) => int.tryParse(k) ?? 0).fold(0, (a, b) => a > b ? a : b);

  @override
  void initState() {
    super.initState();
    _loadHouses();
  }

  Future<void> _loadHouses() async {
    try {
      final list = await Api.I.flats();
      if (!mounted) return;
      setState(() {
        _houses = {for (final f in list) f.getStringValue('label'): f};
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      toast(context, Api.errorText(e));
    }
  }

  void _press(String key) {
    setState(() {
      if (key == 'del') {
        if (_typed.isNotEmpty) _typed = _typed.substring(0, _typed.length - 1);
      } else if (key == 'clear') {
        _typed = '';
      } else if (_typed.length < 4) {
        _typed = (_typed + key).replaceFirst(RegExp(r'^0+'), '');
      }
      _house = _houses[_typed];
      _residents = [];
    });
    _loadResidents();
  }

  Future<void> _loadResidents() async {
    final house = _house;
    final ticket = ++_lookup;
    if (house == null) return;
    setState(() => _loadingResidents = true);
    try {
      final r = await Api.I.residentsOf(house.id);
      if (mounted && ticket == _lookup) setState(() => _residents = r);
    } catch (_) {
      // names are only a confirmation aid; carry on without them
    } finally {
      if (mounted && ticket == _lookup) setState(() => _loadingResidents = false);
    }
  }

  Future<void> _next() async {
    final house = _house;
    if (house == null) return;
    final created = await Navigator.push<RecordModel>(
      context,
      MaterialPageRoute(builder: (_) => NewVisitScreen(flat: house, residents: _residents)),
    );
    if (created != null && mounted) Navigator.pop(context, created);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final notFound = _typed.isNotEmpty && _house == null && !_loading;

    return Scaffold(
      appBar: AppBar(title: const Text('Step 1 of 2 · House number')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Column(children: [
                const SizedBox(height: 12),
                Text('Which house is the visitor going to?', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                // Big number display
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 32),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border.all(color: notFound ? cs.error : cs.outline, width: 2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    _typed.isEmpty ? '—' : _typed,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 56, fontWeight: FontWeight.bold, letterSpacing: 4,
                        color: _typed.isEmpty ? cs.outline : null),
                  ),
                ),
                // Confirmation: who lives there
                SizedBox(
                  height: 72,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: _typed.isEmpty
                          ? Text('Houses 1 to $_maxHouse', style: TextStyle(color: cs.outline))
                          : notFound
                              ? Text('No house $_typed in this society',
                                  style: TextStyle(color: cs.error, fontWeight: FontWeight.w600))
                              : _loadingResidents
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                  : _residents.isEmpty
                                      ? const Text('No resident has the app for this house yet.\nYou will need to call them.',
                                          textAlign: TextAlign.center, style: TextStyle(color: Colors.orange))
                                      : Text(
                                          _residents
                                              .map((r) => r.getStringValue('name').isEmpty ? 'Resident' : r.getStringValue('name'))
                                              .join(', '),
                                          textAlign: TextAlign.center,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                        ),
                    ),
                  ),
                ),
                // Keypad
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(children: [
                      for (final row in const [
                        ['1', '2', '3'],
                        ['4', '5', '6'],
                        ['7', '8', '9'],
                        ['clear', '0', 'del'],
                      ])
                        Expanded(
                          child: Row(children: [
                            for (final k in row)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: _Key(label: k, onTap: () => _press(k)),
                                ),
                              ),
                          ]),
                        ),
                    ]),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _house == null ? null : _next,
                      style: FilledButton.styleFrom(padding: const EdgeInsets.all(18)),
                      icon: const Icon(Icons.arrow_forward),
                      label: Text(_house == null ? 'Enter house number' : 'Next: visitor details for House $_typed',
                          style: const TextStyle(fontSize: 16)),
                    ),
                  ),
                ),
              ]),
            ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Widget child = switch (label) {
      'del' => const Icon(Icons.backspace_outlined, size: 28),
      'clear' => const Text('Clear', style: TextStyle(fontSize: 18)),
      _ => Text(label, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w600)),
    };
    return SizedBox.expand(
      child: FilledButton.tonal(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: child,
      ),
    );
  }
}
