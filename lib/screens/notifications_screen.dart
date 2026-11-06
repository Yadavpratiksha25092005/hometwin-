import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../notifications.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Reminder>? _list;
  Set<String> _read = {};
  bool _on = true;

  @override
  void initState() {
    super.initState();
    _load();
    Notifications.enabled.then((v) {
      if (mounted) setState(() => _on = v);
    });
  }

  Future<void> _load() async {
    final list = await Notifications.upcoming();
    final read = await Notifications.readKeys();
    if (mounted) setState(() {
      _list = list;
      _read = read;
    });
  }

  int get _unread => (_list ?? const <Reminder>[]).where((r) => !_read.contains(r.key)).length;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Notifications'),
          actions: [
            TextButton(
              onPressed: _unread == 0
                  ? null
                  : () async {
                      await Notifications.markAllRead();
                      await _load();
                    },
              child: const Text('Mark all read'),
            ),
          ],
        ),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          Card(
            child: Column(children: [
              SwitchListTile(
                title: const Text('Reminder notifications'),
                subtitle: const Text('Maintenance tasks and warranty expiry, shown at 9:00 AM'),
                value: _on,
                onChanged: (v) async {
                  setState(() => _on = v);
                  await Notifications.setEnabled(v);
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.notifications_active_outlined, color: kBlue),
                title: const Text('Send test notification'),
                onTap: () async {
                  await Notifications.showTest();
                },
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Text(
              _unread == 0 ? 'Upcoming reminders' : 'Upcoming reminders ($_unread new)',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kNavy),
            ),
          ),
          if (_list == null)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else if (_list!.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('Nothing due in the next 30 days.', style: TextStyle(color: Color(0xFF5A6785)))),
            )
          else
            for (final r in _list!) _item(r),
        ]),
      );

  Widget _item(Reminder r) {
    final unread = !_read.contains(r.key);
    return Card(
      color: unread ? const Color(0xFFEFF5FF) : null,
      child: ListTile(
        onTap: unread
            ? () async {
                await Notifications.markRead(r);
                await _load();
              }
            : null,
        leading: Icon(
          r.kind == 'task' ? Icons.build_circle_outlined : Icons.verified_user_outlined,
          color: r.daysLeft < 0 ? Colors.red : kBlue,
        ),
        title: Row(children: [
          Expanded(child: Text(r.title, style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.w500))),
          if (unread) Container(width: 9, height: 9, margin: const EdgeInsets.only(left: 6), decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
        ]),
        subtitle: Text('${r.kind == 'task' ? 'Maintenance' : 'Warranty'} • ${DateFormat('d MMM yyyy').format(r.date)}'),
        trailing: Text(
          r.when,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: r.daysLeft < 0 ? Colors.red : kNavy),
        ),
      ),
    );
  }
}