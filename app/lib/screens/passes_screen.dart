import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../common.dart';

/// Resident: pre-approve guests. Guest shows the 6-digit code at the gate → entry without a call.
class PassesScreen extends StatefulWidget {
  const PassesScreen({super.key});

  @override
  State<PassesScreen> createState() => _PassesScreenState();
}

class _PassesScreenState extends State<PassesScreen> {
  List<RecordModel> _passes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await Api.I.passes();
      if (mounted) {
        setState(() {
          _passes = p;
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

  bool _active(RecordModel p) {
    final until = parseDate(p.getStringValue('valid_until'));
    final used = p.getIntValue('used_count') > 0 && !p.getBoolValue('multi_use');
    return until != null && until.isAfter(DateTime.now()) && !used;
  }

  String _shareText(RecordModel p) {
    final until = parseDate(p.getStringValue('valid_until'))!;
    return 'Hi ${p.getStringValue('guest_name')}, your gate pass code is ${p.getStringValue('code')}. '
        'Show it to the security guard. Valid till ${until.day}/${until.month} ${two(until.hour)}:${two(until.minute)}.';
  }

  Future<void> _share(RecordModel p) async {
    final text = _shareText(p);
    final phone = p.getStringValue('guest_phone').replaceAll(RegExp(r'[^0-9]'), '');
    final wa = Uri.parse('https://wa.me/${phone.length == 10 ? '91$phone' : phone}?text=${Uri.encodeComponent(text)}');
    final ok = await launchUrl(wa, mode: LaunchMode.externalApplication);
    if (!ok) {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) toast(context, 'Copied – paste it in any chat');
    }
  }

  Future<void> _create() async {
    final created = await showModalBottomSheet<RecordModel>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _NewPassSheet(),
    );
    if (created != null) {
      await _load();
      if (mounted) _showCode(created);
    }
  }

  void _showCode(RecordModel p) => showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Pass for ${p.getStringValue('guest_name')}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            SelectableText(p.getStringValue('code'),
                style: const TextStyle(fontSize: 40, letterSpacing: 8, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Share this code with your guest.'),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
            FilledButton.icon(
              icon: const Icon(Icons.share),
              label: const Text('Share'),
              onPressed: () {
                Navigator.pop(context);
                _share(p);
              },
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _passes.isEmpty
                  ? const EmptyState(Icons.confirmation_number, 'Expecting a guest?\nCreate a pass so they skip the call.')
                  : ListView(children: [
                      for (final p in _passes)
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _active(p) ? Colors.green.withValues(alpha: 0.2) : null,
                            child: Icon(_active(p) ? Icons.check : Icons.history),
                          ),
                          title: Text(p.getStringValue('guest_name')),
                          subtitle: Text(
                            '${p.getStringValue('code')}  •  ${_active(p) ? 'Active' : 'Expired / used'}'
                            '${p.getBoolValue('multi_use') ? '  •  multi-use' : ''}',
                          ),
                          onTap: () => _showCode(p),
                          trailing: PopupMenuButton<String>(
                            onSelected: (a) async {
                              if (a == 'share') _share(p);
                              if (a == 'delete') {
                                await runSafe(context, () async {
                                  await Api.I.deletePass(p.id);
                                  await _load();
                                }, success: 'Pass deleted');
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'share', child: Text('Share')),
                              PopupMenuItem(value: 'delete', child: Text('Delete')),
                            ],
                          ),
                        ),
                      const SizedBox(height: 90),
                    ]),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('New pass'),
      ),
    );
  }
}

class _NewPassSheet extends StatefulWidget {
  const _NewPassSheet();

  @override
  State<_NewPassSheet> createState() => _NewPassSheetState();
}

class _NewPassSheetState extends State<_NewPassSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  int _hours = 24;
  bool _multi = false;
  bool _busy = false;

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      toast(context, 'Enter guest name');
      return;
    }
    setState(() => _busy = true);
    try {
      final until = DateTime.now().add(Duration(hours: _hours)).toUtc();
      final rec = await Api.I.createPass({
        'guest_name': _name.text.trim(),
        'guest_phone': _phone.text.trim(),
        'valid_until': until.toIso8601String(),
        'multi_use': _multi,
      });
      if (mounted) Navigator.pop(context, rec);
    } catch (e) {
      if (mounted) toast(context, Api.errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('New guest pass', style: Theme.of(context).textTheme.titleLarge),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Guest name *'),
        ),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Guest mobile (to share code on WhatsApp)'),
        ),
        const SizedBox(height: 12),
        const Text('Valid for'),
        Wrap(spacing: 8, children: [
          for (final h in const [4, 24, 72, 168])
            ChoiceChip(
              label: Text(h < 24 ? '$h hours' : '${h ~/ 24} day${h > 24 ? 's' : ''}'),
              selected: _hours == h,
              onSelected: (_) => setState(() => _hours = h),
            ),
        ]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Allow multiple entries'),
          subtitle: const Text('e.g. relatives staying for a few days'),
          value: _multi,
          onChanged: (v) => setState(() => _multi = v),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Create pass'),
        ),
      ]),
    );
  }
}
