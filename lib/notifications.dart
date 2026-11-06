import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'api.dart';

/// One upcoming reminder (a maintenance task or a warranty expiry).
class Reminder {
  final String kind; // 'task' | 'warranty'
  final int id;
  final String title;
  final DateTime date; // due / expiry date (date only)
  const Reminder(this.kind, this.id, this.title, this.date);

  /// Stable id used to remember that the reminder was read.
  String get key => '$kind:$id:${date.toIso8601String().substring(0, 10)}';

  int get daysLeft {
    final n = DateTime.now();
    return date.difference(DateTime(n.year, n.month, n.day)).inDays;
  }

  String get when {
    final d = daysLeft;
    if (d < 0) return kind == 'task' ? 'Overdue by ${-d} days' : 'Expired ${-d} days ago';
    if (d == 0) return kind == 'task' ? 'Due today' : 'Expires today';
    return kind == 'task' ? 'Due in $d days' : 'Expires in $d days';
  }
}

class Notifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static const _prefKey = 'notifications_enabled';
  static const _hour = 9; // reminders show at 9:00 AM
  static const _taskOffsets = [1, 0]; // days before due date
  static const _warrantyOffsets = [30, 7, 0]; // days before expiry

  static const _channel = AndroidNotificationDetails(
    'reminders',
    'Reminders',
    channelDescription: 'Maintenance and warranty reminders',
    importance: Importance.high,
    priority: Priority.high,
  );
  static const _details = NotificationDetails(android: _channel);

  static Future<void> init() async {
    if (_ready || kIsWeb) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _ready = true;
  }

  static Future<bool> get enabled async =>
      (await SharedPreferences.getInstance()).getBool(_prefKey) ?? true;

  static Future<void> setEnabled(bool v) async {
    await (await SharedPreferences.getInstance()).setBool(_prefKey, v);
    if (v) {
      await requestPermission();
      await sync();
    } else {
      await cancelAll();
    }
  }

  /// Asks for the Android 13+ notification permission. Returns true if allowed.
  static Future<bool> requestPermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? true;
  }

  static Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }

  static Future<void> showTest() async {
    await requestPermission();
    await _plugin.show(
      id: 1,
      title: 'Home Digital Twin',
      body: 'Notifications are working.',
      notificationDetails: _details,
    );
  }

  // ---------- read / unread ----------
  static const _readPref = 'read_reminders';

  static Future<Set<String>> readKeys() async =>
      ((await SharedPreferences.getInstance()).getStringList(_readPref) ?? const <String>[]).toSet();

  static Future<void> markRead(Reminder r) async {
    final p = await SharedPreferences.getInstance();
    final s = (p.getStringList(_readPref) ?? const <String>[]).toSet()..add(r.key);
    await p.setStringList(_readPref, s.toList());
  }

  static Future<void> markAllRead() async {
    final p = await SharedPreferences.getInstance();
    final s = (p.getStringList(_readPref) ?? const <String>[]).toSet();
    for (final r in await upcoming()) {
      s.add(r.key);
    }
    await p.setStringList(_readPref, s.toList());
  }

  static Future<int> unreadCount() async {
    final read = await readKeys();
    return (await upcoming()).where((r) => !read.contains(r.key)).length;
  }

  static DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse('$v');

  /// All upcoming reminders: tasks due in the next 30 days (or overdue by up to 7)
  /// and warranties expiring in the next 30 days (or expired within 7 days).
  static Future<List<Reminder>> upcoming() async {
    final out = <Reminder>[];
    for (final t in await Api.list('tasks')) {
      final d = _date(t['due_date']);
      if (d == null) continue;
      out.add(Reminder('task', (t['id'] as num).toInt(), '${t['title'] ?? 'Maintenance task'}', DateTime(d.year, d.month, d.day)));
    }
    final assets = await Api.list('assets');
    for (final w in await Api.list('warranties')) {
      final d = _date(w['expiry_date']);
      if (d == null) continue;
      String name = '${w['provider'] ?? 'Warranty'}';
      for (final a in assets) {
        if (a['id'] == w['asset_id']) {
          name = '${a['name']}';
          break;
        }
      }
      out.add(Reminder('warranty', (w['id'] as num).toInt(), name, DateTime(d.year, d.month, d.day)));
    }
    out.removeWhere((r) => r.daysLeft > 30 || r.daysLeft < -7);
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  }

  /// Re-creates every scheduled reminder from the current data.
  /// Cheap, so it is called on app start and after any task/warranty change.
  static bool _syncing = false, _syncAgain = false;

  static Future<void> sync() async {
    if (_syncing) {
      _syncAgain = true; // run once more when the current pass finishes
      return;
    }
    _syncing = true;
    try {
      do {
        _syncAgain = false;
        await _sync();
      } while (_syncAgain);
    } finally {
      _syncing = false;
    }
  }

  static Future<void> _sync() async {
    try {
      await init();
      await _plugin.cancelAll();
      if (!await enabled) return;

      final now = DateTime.now();
      final items = <Reminder>[];
      for (final t in await Api.list('tasks')) {
        final d = _date(t['due_date']);
        if (d == null) continue;
        items.add(Reminder('task', (t['id'] as num).toInt(), '${t['title'] ?? 'Maintenance task'}', DateTime(d.year, d.month, d.day)));
      }
      final assets = await Api.list('assets');
      for (final w in await Api.list('warranties')) {
        final d = _date(w['expiry_date']);
        if (d == null) continue;
        String name = '${w['provider'] ?? 'Warranty'}';
        for (final a in assets) {
          if (a['id'] == w['asset_id']) {
            name = '${a['name']}';
            break;
          }
        }
        items.add(Reminder('warranty', (w['id'] as num).toInt(), name, DateTime(d.year, d.month, d.day)));
      }

      for (final r in items) {
        final offsets = r.kind == 'task' ? _taskOffsets : _warrantyOffsets;
        final base = r.kind == 'task' ? 1000000 : 2000000;
        for (var k = 0; k < offsets.length; k++) {
          final day = r.date.subtract(Duration(days: offsets[k]));
          final at = DateTime(day.year, day.month, day.day, _hour);
          if (!at.isAfter(now)) continue;
          final o = offsets[k];
          final title = r.kind == 'task' ? 'Maintenance reminder' : 'Warranty reminder';
          final body = r.kind == 'task'
              ? (o == 0 ? '${r.title} is due today' : '${r.title} is due tomorrow')
              : (o == 0 ? '${r.title} warranty expires today' : '${r.title} warranty expires in $o days');
          await _plugin.zonedSchedule(
            id: base + r.id * 10 + k,
            title: title,
            body: body,
            // Local time converted to the same instant in UTC, so no device timezone lookup is needed.
            scheduledDate: tz.TZDateTime.from(at, tz.UTC),
            notificationDetails: _details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          );
        }
      }
    } catch (e) {
      debugPrint('Notifications.sync failed: $e');
    }
  }
}