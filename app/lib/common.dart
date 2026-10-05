import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';

const purposes = <String, (String, IconData)>{
  'guest': ('Guest', Icons.person),
  'delivery': ('Delivery', Icons.local_shipping),
  'cab': ('Cab', Icons.local_taxi),
  'service': ('Service / Repair', Icons.build),
  'maid': ('Daily help', Icons.cleaning_services),
  'other': ('Other', Icons.more_horiz),
};

const statusInfo = <String, (String, Color, IconData)>{
  'pending': ('Waiting', Colors.orange, Icons.hourglass_top),
  'approved': ('Approved', Colors.green, Icons.check_circle),
  'denied': ('Denied', Colors.red, Icons.cancel),
  'leave_at_gate': ('Leave at gate', Colors.blue, Icons.inventory_2),
  'expired': ('No response', Colors.grey, Icons.timer_off),
};

/// "245" -> "House 245" (labels like "A-101" are shown as they are).
String houseLabel(String label) => RegExp(r'^[0-9]+$').hasMatch(label) ? 'House $label' : label;

String flatLabelOf(RecordModel visit) {
  final label = visit.get<String>('expand.flat.label', '');
  return label.isEmpty ? '' : houseLabel(label);
}

DateTime? parseDate(String s) {
  if (s.isEmpty) return null;
  return DateTime.tryParse(s.replaceFirst(' ', 'T'))?.toLocal();
}

String timeAgo(String created) {
  final d = parseDate(created);
  if (d == null) return '';
  final diff = DateTime.now().difference(d);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return '${d.day}/${d.month}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}

String two(int n) => n.toString().padLeft(2, '0');

String hhmm(String s) {
  final d = parseDate(s);
  return d == null ? '' : '${two(d.hour)}:${two(d.minute)}';
}

Future<void> callNumber(BuildContext context, String phone) async {
  if (phone.isEmpty) return;
  final ok = await launchUrl(Uri(scheme: 'tel', path: phone));
  if (!ok && context.mounted) toast(context, 'Cannot open dialer');
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

Future<void> runSafe(BuildContext context, Future<void> Function() fn, {String? success}) async {
  try {
    await fn();
    if (success != null && context.mounted) toast(context, success);
  } catch (e) {
    if (context.mounted) toast(context, Api.errorText(e));
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = statusInfo[status] ?? (status, Colors.grey, Icons.info);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
      ]),
    );
  }
}

class VisitorAvatar extends StatelessWidget {
  const VisitorAvatar(this.visit, {super.key, this.radius = 24});
  final RecordModel visit;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final url = Api.I.photoUrl(visit);
    final p = purposes[visit.getStringValue('purpose')];
    return CircleAvatar(
      radius: radius,
      backgroundImage: url.isEmpty ? null : NetworkImage(url),
      child: url.isEmpty ? Icon(p?.$2 ?? Icons.person, size: radius) : null,
    );
  }
}

/// Compact visit row used in lists.
class VisitTile extends StatelessWidget {
  const VisitTile(this.visit, {super.key, this.onTap, this.trailing, this.showFlat = true});
  final RecordModel visit;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool showFlat;

  @override
  Widget build(BuildContext context) {
    final purpose = purposes[visit.getStringValue('purpose')]?.$1 ?? '';
    final note = visit.getStringValue('purpose_note');
    final sub = [
      if (showFlat) flatLabelOf(visit),
      purpose + (note.isEmpty ? '' : ' · $note'),
      timeAgo(visit.getStringValue('created')),
    ].where((s) => s.isNotEmpty).join('  •  ');
    return ListTile(
      onTap: onTap,
      leading: VisitorAvatar(visit),
      title: Text(visit.getStringValue('visitor_name'), style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(sub),
      trailing: trailing ?? StatusChip(visit.getStringValue('status')),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.icon, this.text, {super.key});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => ListView(children: [
        const SizedBox(height: 120),
        Icon(icon, size: 64, color: Colors.grey),
        const SizedBox(height: 12),
        Center(child: Text(text, style: const TextStyle(color: Colors.grey))),
      ]);
}
