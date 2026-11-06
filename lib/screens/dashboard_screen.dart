import 'package:flutter/material.dart';
import '../api.dart';
import '../main.dart';
import '../notifications.dart';
import 'notifications_screen.dart';

class DashboardScreen extends StatefulWidget {
  final void Function(int tab) goTab;
  final void Function(int tab) onMaintenance; // 0 Upcoming, 1 History, 2 Warranties
  final VoidCallback onViewHome, onAr;
  const DashboardScreen({super.key, required this.goTab, required this.onMaintenance, required this.onViewHome, required this.onAr});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final Future<List<dynamic>> _rem = Api.reminders();
  late Future<int> _unread = Notifications.unreadCount();
  late final Future<List<int>> _counts = Future.wait([
    Api.list('assets').then((l) => l.length),
    Api.list('warranties').then((l) => l.length),
    Api.list('tasks').then((l) => l.length),
  ]);

  String get _greeting {
    final h = DateTime.now().hour;
    return h < 12 ? 'Good morning' : (h < 17 ? 'Good afternoon' : 'Good evening');
  }

  // Smooth fade + slide-up entrance for each section.
  Widget _in(int i, Widget child) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 450 + i * 90),
        curve: Curves.easeOutCubic,
        builder: (_, v, c) => Opacity(
          opacity: v,
          child: Transform.translate(offset: Offset(0, 24 * (1 - v)), child: c),
        ),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final name = (Api.userName ?? '').trim();
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.center,
          colors: [Color(0xFFFFF1D0), kBg],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            _in(0, _header(name)),
            const SizedBox(height: 18),
            _in(1, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$_greeting,', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w500, color: kNavy, height: 1.1)),
              Text('${name.isEmpty ? 'there' : name} ☀️',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: kNavy, height: 1.15)),
              const SizedBox(height: 6),
              const Text('Your home is healthy and running smoothly.', style: TextStyle(color: Color(0xFF5A6785))),
            ])),
            const SizedBox(height: 14),
            _in(2, _hero()),
            const SizedBox(height: 16),
            _in(3, _stats()),
            const SizedBox(height: 16),
            _in(4, _banner()),
            const SizedBox(height: 22),
            _in(5, _section('Quick Actions')),
            const SizedBox(height: 10),
            _in(5, _quickActions()),
            const SizedBox(height: 22),
            _in(6, _section('Upcoming Reminders')),
            const SizedBox(height: 10),
            _in(6, _reminders()),
          ],
        ),
      ),
    );
  }

  Widget _section(String t) =>
      Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kNavy));

  Widget _header(String name) => Row(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: _shadow(0.08)),
          child: const Icon(Icons.home_work_rounded, color: kBlue, size: 28),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Home Digital Twin', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kNavy)),
            Text('Your Home. Smarter. Together.', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Color(0xFF5A6785))),
          ]),
        ),
        Stack(children: [
          IconButton(
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
              if (mounted) {
                setState(() {
                  _unread = Notifications.unreadCount();
                });
              }
            },
            icon: const Icon(Icons.notifications_none_rounded, color: kNavy),
          ),
          Positioned(
            right: 10,
            top: 10,
            child: FutureBuilder<int>(
              future: _unread,
              builder: (_, s) => (s.data ?? 0) == 0
                  ? const SizedBox.shrink()
                  : Container(width: 9, height: 9, decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5))),
            ),
          ),
        ]),
        GestureDetector(
          onTap: () => widget.goTab(4),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [kBlue, Color(0xFF6BA8FF)])),
            child: CircleAvatar(
              radius: 17,
              backgroundColor: kBlue,
              child: Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ]);

  List<BoxShadow> _shadow([double a = 0.10]) =>
      [BoxShadow(color: kNavy.withValues(alpha: a), blurRadius: 18, offset: const Offset(0, 8))];

  Widget _hero() => Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(28), boxShadow: _shadow(0.14)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Stack(children: [
            Image.asset('assets/images/house.jpg', height: 280, width: double.infinity, fit: BoxFit.cover),
            // soft bottom fade so the button stays readable
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, kNavy.withValues(alpha: 0.35)],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              top: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(20)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.favorite_rounded, color: Color(0xFF1B9E55), size: 14),
                  SizedBox(width: 5),
                  Text('Home health 98%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kNavy)),
                ]),
              ),
            ),
            Positioned(
              right: 12,
              bottom: 12,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: kNavy,
                  elevation: 4,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: widget.onViewHome,
                icon: const Icon(Icons.view_in_ar, size: 18),
                label: const Text('View 3D Home'),
              ),
            ),
          ]),
        ),
      );

  Widget _stats() => FutureBuilder<List<int>>(
        future: _counts,
        builder: (c, s) {
          final v = s.data ?? [0, 0, 0];
          return Row(children: [
            _stat(Icons.inventory_2_rounded, '${v[0]}', 'Assets', const [Color(0xFFE3EEFF), Color(0xFFF2F7FF)], kBlue, 1),
            const SizedBox(width: 10),
            _stat(Icons.verified_user_rounded, '${v[1]}', 'Warranties', const [Color(0xFFDDF4E7), Color(0xFFF0FAF4)], const Color(0xFF1B9E55), 3),
            const SizedBox(width: 10),
            _stat(Icons.assignment_rounded, '${v[2]}', 'Tasks', const [Color(0xFFEAE4FC), Color(0xFFF6F3FE)], const Color(0xFF6B4FD8), 4),
          ]);
        },
      );

  // Vertical layout => no horizontal overflow on narrow phones.
  Widget _stat(IconData icon, String n, String label, List<Color> bg, Color fg, int tab) => Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => tab == 1 ? widget.goTab(1) : widget.onMaintenance(tab == 3 ? 2 : 0),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: bg),
              borderRadius: BorderRadius.circular(18),
              boxShadow: _shadow(0.05),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(radius: 16, backgroundColor: Colors.white, child: Icon(icon, size: 18, color: fg)),
              const SizedBox(height: 10),
              Text(n, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: kNavy, height: 1)),
              const SizedBox(height: 2),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFF5A6785))),
            ]),
          ),
        ),
      );

  Widget _banner() => InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => widget.goTab(1),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0B6BE6), Color(0xFF4C9BFF)]),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: kBlue.withValues(alpha: 0.30), blurRadius: 18, offset: const Offset(0, 8))],
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.view_in_ar, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Your Digital Home', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white, fontSize: 16)),
                SizedBox(height: 2),
                Text('All your assets, documents, warranties and maintenance in one place.',
                    style: TextStyle(fontSize: 12, color: Color(0xFFE3EEFF))),
              ]),
            ),
            const SizedBox(width: 8),
            const CircleAvatar(radius: 16, backgroundColor: Colors.white, child: Icon(Icons.arrow_forward_rounded, size: 18, color: kBlue)),
          ]),
        ),
      );

  Widget _quickActions() => Row(children: [
        _qa(Icons.add_rounded, 'Add\nAsset', const Color(0xFF0B6BE6), () => widget.goTab(1)),
        _qa(Icons.qr_code_scanner_rounded, 'Scan &\nTrack', const Color(0xFF6B4FD8), () => widget.goTab(2)),
        _qa(Icons.description_rounded, 'View\nDocuments', const Color(0xFF1B9E55), () => widget.goTab(3)),
        _qa(Icons.weekend_outlined, 'Room\nDesigner', const Color(0xFFF08A24), widget.onAr),
      ]);

  Widget _qa(IconData icon, String label, Color color, VoidCallback onTap) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Container(
              height: 104,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: _shadow(0.06)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                CircleAvatar(radius: 20, backgroundColor: color.withValues(alpha: 0.12), child: Icon(icon, color: color, size: 22)),
                const SizedBox(height: 8),
                Text(label, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 11, height: 1.2, color: kNavy, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ),
      );

  Widget _reminders() => FutureBuilder<List<dynamic>>(
        future: _rem,
        builder: (c, s) {
          if (!s.hasData) return const SizedBox(height: 60, child: Center(child: CircularProgressIndicator()));
          final items = s.data!.take(3).toList();
          if (items.isEmpty) {
            return _reminderTile(Icons.check_circle_rounded, const Color(0xFF1B9E55), 'All good!', 'No warranties expiring soon');
          }
          return Column(children: [
            for (final r in items)
              _reminderTile(
                Icons.notifications_active_rounded,
                (r['days_left'] as int) < 0 ? Colors.red : const Color(0xFFF08A24),
                '${r['asset'] ?? 'Asset'} warranty',
                (r['days_left'] as int) < 0 ? 'Expired ${-(r['days_left'] as int)} days ago' : 'Expires in ${r['days_left']} days',
              ),
          ]);
        },
      );

  Widget _reminderTile(IconData icon, Color color, String title, String sub) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: _shadow(0.05)),
        child: Row(children: [
          CircleAvatar(radius: 20, backgroundColor: color.withValues(alpha: 0.12), child: Icon(icon, color: color, size: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: kNavy)),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFF5A6785))),
            ]),
          ),
        ]),
      );
}