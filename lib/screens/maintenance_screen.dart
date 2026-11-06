import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api.dart';
import '../main.dart';
import '../widgets/common.dart';
import '../widgets/resource_screen.dart';

const _green = Color(0xFF1B9E55);
const _grey = Color(0xFF8A94A8);

class MaintenanceScreen extends StatefulWidget {
  final int initialTab; // 0 Upcoming, 1 History, 2 Warranties
  const MaintenanceScreen({super.key, this.initialTab = 0});
  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  late int _tab = widget.initialTab;
  late Future<Map<String, List<dynamic>>> _future = _load();

  Future<Map<String, List<dynamic>>> _load() async => {
        'assets': await Api.list('assets'),
        'tasks': await Api.list('tasks'),
        'repairs': await Api.list('repairs'),
        'warranties': await Api.list('warranties'),
      };
  void _reload() => setState(() {
        _future = _load();
      });

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  Map<String, dynamic>? _asset(List<dynamic> assets, dynamic id) {
    for (final a in assets) {
      if (a['id'] == id) return Map<String, dynamic>.from(a);
    }
    return null;
  }

  String _sub(Map<String, dynamic>? a) =>
      a == null ? '' : [a['brand'], a['model']].where((e) => e != null && '$e'.isNotEmpty).join(' • ');

  Future<void> _add() async {
    final today = DateFormat('yyyy-MM-dd').format(_today);
    late final String title, path;
    late final List<FieldDef> fields;
    Map<String, dynamic>? initial;
    if (_tab == 0) {
      title = 'Maintenance Task';
      path = 'tasks';
      initial = {'start_date': today};
      fields = const [
        FieldDef('asset_id', 'Asset', FType.asset), FieldDef('title', 'Service / Task'),
        FieldDef('due_date', 'Due date', FType.date), FieldDef('notes', 'Notes', FType.multiline),
      ];
    } else if (_tab == 1) {
      title = 'Service Record';
      path = 'repairs';
      fields = const [
        FieldDef('title', 'Title'), FieldDef('asset_id', 'Asset', FType.asset),
        FieldDef('description', 'Description', FType.multiline), FieldDef('cost', 'Cost', FType.number),
        FieldDef('repair_date', 'Date', FType.date), FieldDef('service_provider', 'Service provider'),
      ];
    } else {
      title = 'Warranty';
      path = 'warranties';
      fields = const [
        FieldDef('asset_id', 'Asset', FType.asset), FieldDef('provider', 'Provider'),
        FieldDef('start_date', 'Start date', FType.date), FieldDef('expiry_date', 'Expiry date', FType.date),
        FieldDef('notes', 'Notes', FType.multiline),
      ];
    }
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddForm(title: title, path: path, fields: fields, initial: initial),
    );
    if (ok == true) _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.add, size: 30)),
        body: SafeArea(
          child: FutureBuilder<Map<String, List<dynamic>>>(
            future: _future,
            builder: (c, s) {
              if (!s.hasData) return const Center(child: CircularProgressIndicator());
              return RefreshIndicator(
                onRefresh: () async => _reload(),
                child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 96), children: [
                  _header(),
                  const SizedBox(height: 14),
                  _tabs(),
                  const SizedBox(height: 16),
                  if (_tab == 0) ..._upcoming(s.data!),
                  if (_tab == 1) ..._history(s.data!, all: true),
                  if (_tab == 2) ..._warranties(s.data!),
                ]),
              );
            },
          ),
        ),
      );

  Widget _header() => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36),
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded, color: kNavy),
        ),
        const Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(height: 6),
            Text('Maintenance & Warranty', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: kNavy)),
            Text('Keep your home in top condition', style: TextStyle(color: Color(0xFF5A6785))),
          ]),
        ),
      ]);

  Widget _tabs() {
    const names = ['Upcoming', 'History', 'Warranties'];
    return Row(children: [
      for (var i = 0; i < 3; i++)
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < 2 ? 8 : 0),
            child: GestureDetector(
              onTap: () => setState(() => _tab = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _tab == i ? kBlue : const Color(0xFFEEF1F6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(names[i], style: TextStyle(fontWeight: FontWeight.w700, color: _tab == i ? Colors.white : kNavy)),
              ),
            ),
          ),
        ),
    ]);
  }

  Widget _title(String t, {String? action, VoidCallback? onAction}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Expanded(child: Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kNavy))),
          if (action != null)
            GestureDetector(onTap: onAction, child: Text(action, style: const TextStyle(color: kBlue, fontWeight: FontWeight.w600, fontSize: 13))),
        ]),
      );

  // ---------------- Upcoming ----------------
  double _progress(Map t) {
    final s = DateTime.tryParse('${t['start_date']}');
    final d = DateTime.tryParse('${t['due_date']}');
    if (s == null || d == null) return 0;
    final total = d.difference(s).inDays;
    if (total <= 0) return 1;
    return (_today.difference(s).inDays / total).clamp(0.0, 1.0);
  }

  Color _pctColor(double p) => p >= 0.65 ? _green : (p >= 0.25 ? kBlue : _grey);

  String _dueText(Map t) {
    final d = DateTime.tryParse('${t['due_date']}');
    if (d == null) return 'No due date';
    final n = d.difference(_today).inDays;
    if (n == 0) return 'Due today';
    if (n < 0) return 'Overdue by ${-n} days';
    return 'Due in $n days';
  }

  List<Widget> _upcoming(Map<String, List<dynamic>> d) {
    final assets = d['assets']!;
    final tasks = List<dynamic>.from(d['tasks']!)
      ..sort((a, b) => '${a['due_date']}'.compareTo('${b['due_date']}'));
    return [
      _title('Upcoming Maintenance'),
      if (tasks.isEmpty) _emptyBox(Icons.build_circle_outlined, 'No upcoming maintenance', 'Tap + to schedule a service'),
      for (final t in tasks) _taskCard(Map<String, dynamic>.from(t), _asset(assets, t['asset_id'])),
      if (tasks.isNotEmpty) ...[
        const SizedBox(height: 4),
        _nextReminder(Map<String, dynamic>.from(tasks.first), _asset(assets, tasks.first['asset_id'])),
      ],
      const SizedBox(height: 20),
      ..._history(d, all: false),
    ];
  }

  Widget _taskCard(Map<String, dynamic> t, Map<String, dynamic>? a) {
    final p = _progress(t);
    final c = _pctColor(p);
    final overdue = (DateTime.tryParse('${t['due_date']}')?.isBefore(_today)) ?? false;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _taskActions(t),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: softShadow()),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 76,
              child: Column(children: [
                PhotoThumb(src: a?['photo_url'], w: 76, h: 50),
                const SizedBox(height: 10),
                SizedBox(
                  width: 50,
                  height: 50,
                  child: Stack(alignment: Alignment.center, children: [
                    SizedBox(width: 50, height: 50, child: CircularProgressIndicator(value: p, strokeWidth: 5, backgroundColor: const Color(0xFFE6ECF5), color: c)),
                    Text('${(p * 100).round()}%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c)),
                  ]),
                ),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a?['name'] ?? 'Home task', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kNavy)),
                if (_sub(a).isNotEmpty) Text(_sub(a), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFF5A6785))),
                const SizedBox(height: 10),
                Text('${t['title']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: c)),
                const SizedBox(height: 8),
                Row(children: [
                  Icon(Icons.event_outlined, size: 15, color: overdue ? Colors.red : const Color(0xFF5A6785)),
                  const SizedBox(width: 4),
                  Flexible(child: Text(_dueText(t), overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: overdue ? Colors.red : const Color(0xFF5A6785)))),
                ]),
              ]),
            ),
            const Padding(padding: EdgeInsets.only(top: 30), child: Icon(Icons.chevron_right_rounded, color: _grey)),
          ]),
        ),
      ),
    );
  }

  Widget _nextReminder(Map<String, dynamic> t, Map<String, dynamic>? a) {
    final dd = DateTime.tryParse('${t['due_date']}');
    final n = dd?.difference(_today).inDays;
    final when = n == null ? '' : (n <= 0 ? 'is due now' : 'in $n days');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFE6F6EC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFBFE8CF)),
      ),
      child: Row(children: [
        const CircleAvatar(radius: 20, backgroundColor: Colors.white, child: Icon(Icons.notifications_active_rounded, color: _green)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Next Reminder', style: TextStyle(fontWeight: FontWeight.w800, color: _green)),
            Text('${a?['name'] ?? 'Task'} ${('${t['title']}').toLowerCase()} $when', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: kNavy)),
          ]),
        ),
        const CircleAvatar(radius: 14, backgroundColor: Colors.white, child: Icon(Icons.arrow_forward_rounded, size: 16, color: _green)),
      ]),
    );
  }

  void _taskActions(Map<String, dynamic> t) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text('${t['title']}', style: const TextStyle(fontWeight: FontWeight.w800, color: kNavy)), subtitle: Text(_dueText(t))),
          ListTile(
            leading: const Icon(Icons.check_circle_outline, color: _green),
            title: const Text('Mark as done'),
            onTap: () async {
              Navigator.pop(context);
              await Api.create('repairs', {
                'asset_id': t['asset_id'],
                'title': t['title'],
                'repair_date': DateFormat('yyyy-MM-dd').format(_today),
              });
              await Api.remove('tasks', t['id']);
              _reload();
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('Delete task'),
            onTap: () async {
              Navigator.pop(context);
              await Api.remove('tasks', t['id']);
              _reload();
            },
          ),
        ]),
      ),
    );
  }

  // ---------------- History ----------------
  List<Widget> _history(Map<String, List<dynamic>> d, {required bool all}) {
    final assets = d['assets']!;
    final repairs = List<dynamic>.from(d['repairs']!)
      ..sort((a, b) => '${b['repair_date']}'.compareTo('${a['repair_date']}'));
    final shown = all ? repairs : repairs.take(2).toList();
    return [
      _title('Service History', action: all ? null : 'View all', onAction: () => setState(() => _tab = 1)),
      if (shown.isEmpty) _emptyBox(Icons.history_rounded, 'No service history yet', 'Completed services will show up here'),
      for (final r in shown) _historyTile(Map<String, dynamic>.from(r), _asset(assets, r['asset_id'])),
    ];
  }

  Widget _historyTile(Map<String, dynamic> r, Map<String, dynamic>? a) {
    final dt = DateTime.tryParse('${r['repair_date']}');
    final sub = _sub(a);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: softShadow()),
      child: Row(children: [
        ClipOval(child: PhotoThumb(src: a?['photo_url'], w: 44, h: 44, radius: 22, fallback: Icons.build_rounded)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${r['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, color: kNavy)),
            if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFF5A6785))),
            if (dt != null) Text(DateFormat('d MMM yyyy').format(dt), style: const TextStyle(fontSize: 12, color: Color(0xFF5A6785))),
          ]),
        ),
        const SizedBox(width: 8),
        StatusPill.green('Completed'),
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32),
          icon: const Icon(Icons.close_rounded, size: 18, color: _grey),
          onPressed: () async {
            await Api.remove('repairs', r['id']);
            _reload();
          },
        ),
      ]),
    );
  }

  // ---------------- Warranties ----------------
  List<Widget> _warranties(Map<String, List<dynamic>> d) {
    final assets = d['assets']!;
    final ws = List<dynamic>.from(d['warranties']!)
      ..sort((a, b) => '${a['expiry_date']}'.compareTo('${b['expiry_date']}'));
    return [
      _title('Warranties'),
      if (ws.isEmpty) _emptyBox(Icons.verified_user_outlined, 'No warranties yet', 'Tap + to add a warranty'),
      for (final w in ws) _warrantyTile(Map<String, dynamic>.from(w), _asset(assets, w['asset_id'])),
    ];
  }

  Widget _warrantyTile(Map<String, dynamic> w, Map<String, dynamic>? a) {
    final exp = DateTime.tryParse('${w['expiry_date']}');
    final active = exp != null && !exp.isBefore(_today);
    final left = exp?.difference(_today).inDays;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: softShadow()),
      child: Row(children: [
        PhotoThumb(src: a?['photo_url'], w: 58, h: 58),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a?['name'] ?? 'Asset', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, color: kNavy, fontSize: 15)),
            Text('${w['provider'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFF5A6785))),
            const SizedBox(height: 4),
            Text(exp == null ? '' : 'Valid till ${DateFormat('d MMM yyyy').format(exp)}', style: const TextStyle(fontSize: 12, color: kNavy)),
          ]),
        ),
        const SizedBox(width: 6),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          active ? StatusPill.green('Active') : StatusPill.blue('Expired'),
          if (active && left != null && left <= 90) Padding(padding: const EdgeInsets.only(top: 4), child: Text('$left days left', style: const TextStyle(fontSize: 11, color: Color(0xFFF08A24), fontWeight: FontWeight.w700))),
        ]),
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32),
          icon: const Icon(Icons.close_rounded, size: 18, color: _grey),
          onPressed: () async {
            await Api.remove('warranties', w['id']);
            _reload();
          },
        ),
      ]),
    );
  }

  Widget _emptyBox(IconData icon, String t, String sub) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: kBorder)),
        child: Column(children: [
          Icon(icon, size: 34, color: kBlue.withValues(alpha: 0.7)),
          const SizedBox(height: 8),
          Text(t, style: const TextStyle(fontWeight: FontWeight.w800, color: kNavy)),
          Text(sub, style: const TextStyle(fontSize: 12, color: Color(0xFF5A6785))),
        ]),
      );
}