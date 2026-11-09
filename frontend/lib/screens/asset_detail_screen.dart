import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api.dart';
import '../main.dart';
import '../widgets/common.dart';
import '../widgets/resource_screen.dart';

/// Everything about one asset: details, warranties, service history, tasks and documents.
class AssetDetailScreen extends StatefulWidget {
  final Map<String, dynamic> asset;
  const AssetDetailScreen({super.key, required this.asset});
  @override
  State<AssetDetailScreen> createState() => _AssetDetailScreenState();
}

class _AssetDetailScreenState extends State<AssetDetailScreen> {
  late Future<List<List<dynamic>>> _future = _load();
  Map<String, dynamic> get a => widget.asset;

  static const _warrantyFields = [
    FieldDef('provider', 'Provider'),
    FieldDef('start_date', 'Start date', FType.date),
    FieldDef('expiry_date', 'Expiry date', FType.date),
    FieldDef('notes', 'Notes', FType.multiline),
  ];
  static const _repairFields = [
    FieldDef('title', 'Title'),
    FieldDef('description', 'Description', FType.multiline),
    FieldDef('cost', 'Cost', FType.number),
    FieldDef('repair_date', 'Date', FType.date),
    FieldDef('service_provider', 'Service provider'),
  ];
  static const _taskFields = [
    FieldDef('title', 'Service / Task'),
    FieldDef('due_date', 'Due date', FType.date),
    FieldDef('notes', 'Notes', FType.multiline),
  ];

  /// [warranties, repairs, tasks, documents] of this asset.
  Future<List<List<dynamic>>> _load() async {
    final all = await Future.wait([Api.list('warranties'), Api.list('repairs'), Api.list('tasks'), Api.list('documents')]);
    return [
      for (final l in all) l.where((e) => e['asset_id'] == a['id']).toList(),
    ];
  }

  void _reload() => setState(() {
        _future = _load();
      });

  Future<void> _add(String title, String path, List<FieldDef> fields) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddForm(title: title, path: path, fields: fields, initial: {'asset_id': a['id']}),
    );
    if (ok == true) _reload();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete asset?'),
        content: Text('"${a['name']}" will be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) {
      await Api.remove('assets', a['id']);
      if (mounted) Navigator.pop(context, true);
    }
  }

  static String _date(dynamic v) {
    final d = DateTime.tryParse('${v ?? ''}');
    return d == null ? '-' : DateFormat('d MMM yyyy').format(d);
  }

  static String _money(dynamic v) {
    final n = num.tryParse('${v ?? ''}');
    return n == null ? '-' : '₹${NumberFormat('#,##0').format(n)}';
  }

  static bool _past(dynamic v) {
    final d = DateTime.tryParse('${v ?? ''}');
    if (d == null) return false;
    final n = DateTime.now();
    return d.isBefore(DateTime(n.year, n.month, n.day));
  }

  static const _muted = TextStyle(fontSize: 12, color: Color(0xFF5A6785));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text('${a['name']}'),
          actions: [IconButton(tooltip: 'Delete asset', onPressed: _delete, icon: const Icon(Icons.delete_outline))],
        ),
        body: FutureBuilder<List<List<dynamic>>>(
          future: _future,
          builder: (c, s) {
            if (s.hasError) return Center(child: Text('${s.error}'));
            if (!s.hasData) return const Center(child: CircularProgressIndicator());
            return _body(s.data![0], s.data![1], s.data![2], s.data![3]);
          },
        ),
      );

  Widget _body(List<dynamic> warranties, List<dynamic> repairs, List<dynamic> tasks, List<dynamic> docs) {
    num spend = 0;
    for (final r in repairs) {
      spend += num.tryParse('${r['cost'] ?? ''}') ?? 0;
    }
    repairs.sort((x, y) => '${y['repair_date'] ?? ''}'.compareTo('${x['repair_date'] ?? ''}'));
    warranties.sort((x, y) => '${y['expiry_date'] ?? ''}'.compareTo('${x['expiry_date'] ?? ''}'));
    tasks.sort((x, y) => '${x['due_date'] ?? ''}'.compareTo('${y['due_date'] ?? ''}'));

    final sub = [a['brand'], a['model']].where((e) => e != null && '$e'.isNotEmpty).join(' • ');
    final hasActiveWarranty = warranties.any((w) => !_past(w['expiry_date']));

    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: softShadow()),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            PhotoThumb(src: a['photo_url'], w: 84, h: 84),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${a['name']}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: kNavy)),
                if (sub.isNotEmpty) Text(sub, style: _muted),
                const SizedBox(height: 8),
                if (warranties.isEmpty)
                  StatusPill.grey('No warranty')
                else if (hasActiveWarranty)
                  StatusPill.green('Under Warranty')
                else
                  StatusPill.blue('Warranty Expired'),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            _stat('${repairs.length}', 'Repairs'),
            _stat(_money(spend), 'Repair spend'),
            _stat(_money(a['price']), 'Purchase price'),
          ]),
          const Divider(height: 24),
          _field('Room', a['room']),
          _field('Serial No', a['serial_no']),
          _field('Purchased', a['purchase_date'] == null ? null : _date(a['purchase_date'])),
          _field('Notes', a['notes']),
        ]),
      ),
      _section('Warranty', Icons.verified_user_outlined, () => _add('Warranty', 'warranties', _warrantyFields), 'No warranty added yet.', [
        for (final w in warranties)
          _row(
            title: '${w['provider'] ?? 'Warranty'}',
            subtitle: '${_date(w['start_date'])} → ${_date(w['expiry_date'])}',
            trailing: _past(w['expiry_date']) ? StatusPill.blue('Expired') : StatusPill.green('Active'),
          ),
      ]),
      _section('Service history', Icons.history_rounded, () => _add('Repair', 'repairs', _repairFields), 'No repairs recorded.', [
        for (final r in repairs)
          _row(
            title: '${r['title'] ?? 'Repair'}',
            subtitle: [_date(r['repair_date']), if ('${r['service_provider'] ?? ''}'.isNotEmpty) '${r['service_provider']}'].join(' • '),
            trailing: Text(_money(r['cost']), style: const TextStyle(fontWeight: FontWeight.w700, color: kNavy)),
          ),
      ]),
      _section('Maintenance tasks', Icons.build_circle_outlined, () => _add('Task', 'tasks', _taskFields), 'No tasks scheduled.', [
        for (final t in tasks)
          _row(
            title: '${t['title'] ?? 'Task'}',
            subtitle: 'Due ${_date(t['due_date'])}',
            trailing: _past(t['due_date'])
                ? const StatusPill('Overdue', bg: Color(0xFFFFE5E5), fg: Colors.red)
                : StatusPill.blue('Upcoming'),
          ),
      ]),
      _section('Documents', Icons.description_outlined, null, 'No documents linked. Add one from the Vault tab and pick this asset.', [
        for (final d in docs) _row(title: '${d['title'] ?? 'Document'}', subtitle: '${d['category'] ?? ''}'),
      ]),
    ]);
  }

  Widget _stat(String value, String label) => Expanded(
        child: Column(children: [
          Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: kBlue)),
          Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF8A94A8))),
        ]),
      );

  Widget _field(String label, dynamic value) {
    if (value == null || '$value'.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 90, child: Text(label, style: _muted)),
        Expanded(child: Text('$value', style: const TextStyle(fontWeight: FontWeight.w600, color: kNavy))),
      ]),
    );
  }

  Widget _row({required String title, String? subtitle, Widget? trailing}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: kNavy)),
              if (subtitle != null && subtitle.isNotEmpty) Text(subtitle, style: _muted),
            ]),
          ),
          if (trailing != null) trailing,
        ]),
      );

  Widget _section(String title, IconData icon, VoidCallback? onAdd, String empty, List<Widget> rows) => Container(
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: softShadow()),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 20, color: kBlue),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: kNavy))),
            if (onAdd != null) TextButton.icon(onPressed: onAdd, icon: const Icon(Icons.add, size: 18), label: const Text('Add')),
          ]),
          if (rows.isEmpty)
            Padding(padding: const EdgeInsets.only(bottom: 6, right: 6), child: Text(empty, style: _muted))
          else
            Padding(padding: const EdgeInsets.only(right: 6), child: Column(children: rows)),
        ]),
      );
}