import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pocketbase/pocketbase.dart';

import '../api.dart';
import '../common.dart';

/// Guard step 2 of 2: visitor details for the house chosen on the keypad.
/// With [passMode] the house comes from the guest's pass code instead.
class NewVisitScreen extends StatefulWidget {
  const NewVisitScreen({super.key, this.passMode = false, this.flat, this.residents = const []})
      : assert(passMode || flat != null, 'Pick a house first');
  final bool passMode;
  final RecordModel? flat;
  final List<RecordModel> residents;

  @override
  State<NewVisitScreen> createState() => _NewVisitScreenState();
}

class _NewVisitScreenState extends State<NewVisitScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _note = TextEditingController();
  final _vehicle = TextEditingController();
  final _code = TextEditingController();
  int _people = 1;
  String _purpose = 'guest';
  Uint8List? _photo;
  bool _busy = false;

  Future<void> _takePhoto() async {
    final x = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 900, imageQuality: 70);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    setState(() => _photo = bytes);
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final body = <String, dynamic>{
        'visitor_name': _name.text.trim(),
        'visitor_phone': _phone.text.trim(),
        'purpose': _purpose,
        'purpose_note': _note.text.trim(),
        'vehicle_no': _vehicle.text.trim().toUpperCase(),
        'people_count': _people,
      };
      if (widget.passMode) {
        body['pass_code'] = _code.text.trim();
      } else {
        body['flat'] = widget.flat!.id;
      }
      final rec = await Api.I.createVisit(body, photo: _photo);
      if (mounted) Navigator.pop(context, rec);
    } catch (e) {
      if (mounted) toast(context, Api.errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pass = widget.passMode;
    return Scaffold(
      appBar: AppBar(title: Text(pass ? 'Guest with pass code' : 'Step 2 of 2 · Visitor details')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (pass) ...[
            TextFormField(
              controller: _code,
              keyboardType: TextInputType.number,
              maxLength: 6,
              style: const TextStyle(fontSize: 28, letterSpacing: 8),
              textAlign: TextAlign.center,
              decoration: const InputDecoration(labelText: '6-digit pass code', border: OutlineInputBorder()),
              validator: (v) => (v ?? '').trim().length == 6 ? null : 'Enter 6 digits',
            ),
            const Text('Name and house are filled from the pass. Add a photo/vehicle if you like.',
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
          ] else ...[
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: ListTile(
                leading: const Icon(Icons.home, size: 32),
                title: Text(houseLabel(widget.flat!.getStringValue('label')),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                subtitle: Text(widget.residents.isEmpty
                    ? 'No resident has the app yet'
                    : widget.residents
                        .map((r) => r.getStringValue('name').isEmpty ? 'Resident' : r.getStringValue('name'))
                        .join(', ')),
                trailing: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Change')),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GestureDetector(
              onTap: _takePhoto,
              child: CircleAvatar(
                radius: 36,
                backgroundImage: _photo == null ? null : MemoryImage(_photo!),
                child: _photo == null ? const Icon(Icons.add_a_photo) : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(children: [
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: pass ? 'Visitor name (optional)' : 'Visitor name *'),
                  validator: (v) => pass || (v ?? '').trim().isNotEmpty ? null : 'Required',
                ),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Mobile number'),
                  validator: (v) {
                    final s = (v ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                    return s.isEmpty || s.length >= 10 ? null : 'Enter a valid number';
                  },
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          const Text('Purpose', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in purposes.entries)
              ChoiceChip(
                avatar: Icon(e.value.$2, size: 18),
                label: Text(e.value.$1),
                selected: _purpose == e.key,
                onSelected: (_) => setState(() => _purpose = e.key),
              ),
          ]),
          TextFormField(
            controller: _note,
            decoration: InputDecoration(
              labelText: _purpose == 'delivery' ? 'Company (Amazon, Swiggy…)' : 'Details (optional)',
            ),
          ),
          TextFormField(
            controller: _vehicle,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Vehicle number (optional)'),
          ),
          const SizedBox(height: 12),
          Row(children: [
            const Text('People'),
            const Spacer(),
            IconButton(onPressed: _people > 1 ? () => setState(() => _people--) : null, icon: const Icon(Icons.remove)),
            Text('$_people', style: const TextStyle(fontSize: 18)),
            IconButton(onPressed: () => setState(() => _people++), icon: const Icon(Icons.add)),
          ]),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _submit,
            style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(pass ? Icons.verified : Icons.send),
            label: Text(pass ? 'Verify pass & allow' : 'Send for approval'),
          ),
        ]),
      ),
    );
  }
}
