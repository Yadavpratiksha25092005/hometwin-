import 'dart:math' as math;
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

class _DashboardScreenState extends State<DashboardScreen> with SingleTickerProviderStateMixin {
  static const _grey = Color(0xFF5A6785);

  // One slow loop (8 s) drives every little animation on this screen:
  // floating house in the background, moving grid + shimmer in the hero card, orbit in the banner.
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  /// Moves [child] gently up/down (and a little sideways).
  Widget _float(Widget child, {double dy = 6, double dx = 0, double phase = 0}) => AnimatedBuilder(
        animation: _anim,
        child: child,
        builder: (_, c) {
          final a = (_anim.value + phase) * 2 * math.pi;
          return Transform.translate(offset: Offset(math.cos(a) * dx, math.sin(a) * dy), child: c);
        },
      );

  late final Future<List<dynamic>> _rem = Api.reminders();
  late Future<int> _unread = Notifications.unreadCount();
  late final Future<List<int>> _counts = Future.wait([
    Api.list('assets').then((l) => l.length),
    Api.list('warranties').then((l) => l.length),
    Api.list('tasks').then((l) => l.length),
  ]);

  String get _greeting {
    final h = DateTime.now().hour;
    return h < 12 ? 'Good Morning' : (h < 17 ? 'Good Afternoon' : 'Good Evening');
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

  List<BoxShadow> _shadow([double a = 0.10]) =>
      [BoxShadow(color: kBlue.withValues(alpha: a), blurRadius: 20, offset: const Offset(0, 8))];

  @override
  Widget build(BuildContext context) {
    final name = (Api.userName ?? '').trim();
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.center, colors: [Color(0xFFE9E1FF), kBg]),
      ),
      child: Stack(children: [
        // soft floating house + drifting glow in the background
        Positioned(
          right: 14,
          top: 92,
          child: IgnorePointer(child: _float(CustomPaint(size: const Size(124, 124), painter: _HouseArtPainter()), dy: 7, dx: 2)),
        ),
        Positioned(
          left: -80,
          top: 330,
          child: IgnorePointer(
            child: _float(
              Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [kLavender.withValues(alpha: 0.22), kLavender.withValues(alpha: 0)])),
              ),
              dy: 18,
              dx: 14,
              phase: 0.4,
            ),
          ),
        ),
        Positioned.fill(
          child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            _in(0, _header(name)),
            const SizedBox(height: 20),
            _in(1, _greetingBlock(name)),
            const SizedBox(height: 16),
            _in(2, _hero()),
            const SizedBox(height: 16),
            _in(3, _stats()),
            const SizedBox(height: 16),
            _in(4, _banner()),
            const SizedBox(height: 22),
            _in(5, Row(children: [
              Expanded(child: _section('Quick Actions')),
              TextButton.icon(
                onPressed: _seeAll,
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: const Text('See All'),
                style: TextButton.styleFrom(foregroundColor: kBlue, textStyle: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ])),
            const SizedBox(height: 6),
            _in(5, _quickActions()),
            const SizedBox(height: 22),
            _in(6, _section('Upcoming Reminders')),
            const SizedBox(height: 10),
            _in(6, _reminders()),
          ],
        ),
      ),
        ),
      ]),
    );
  }

  Widget _section(String t) => Text(t, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: kNavy));

  // ------------------------------------------------------------------ header / greeting

  Widget _header(String name) => Row(children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF5B2FD0), Color(0xFF8B5CF6)]),
            boxShadow: [BoxShadow(color: kBlue.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 6))],
          ),
          child: const Icon(Icons.view_in_ar_rounded, color: Colors.white, size: 28),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Home Digital Twin', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kNavy)),
            Text('Scan · Visualize · Experience', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: kBlue)),
          ]),
        ),
        Stack(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: _shadow(0.10)),
            child: IconButton(
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
          ),
          Positioned(
            right: 11,
            top: 10,
            child: FutureBuilder<int>(
              future: _unread,
              builder: (_, s) => (s.data ?? 0) == 0
                  ? const SizedBox.shrink()
                  : Container(width: 10, height: 10, decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5))),
            ),
          ),
        ]),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: () => widget.goTab(4),
          child: Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF5B2FD0), Color(0xFF8B5CF6)]),
              boxShadow: [BoxShadow(color: kBlue.withValues(alpha: 0.30), blurRadius: 12, offset: const Offset(0, 5))],
            ),
            child: Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
          ),
        ),
      ]);

  Widget _greetingBlock(String name) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$_greeting,', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w500, color: kNavy, height: 1.15)),
        Row(children: [
          Flexible(
            child: Text(name.isEmpty ? 'there' : name[0].toUpperCase() + name.substring(1),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w800, color: kNavy, height: 1.15)),
          ),
          const SizedBox(width: 8),
          const Text('👋', style: TextStyle(fontSize: 32)),
        ]),
        const SizedBox(height: 6),
        const Text('Your home is healthier, smarter and more beautiful!', style: TextStyle(color: _grey, height: 1.3)),
        const SizedBox(height: 10),
        Container(
          width: 92,
          height: 4,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), gradient: const LinearGradient(colors: [kLavender, Color(0x00A78BFA)])),
        ),
      ]);

  // ------------------------------------------------------------------ hero (3D house)

  Widget _hero() => Container(
        height: 232,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF2E2A74), Color(0xFF5B49C8), Color(0xFF7B63D9)]),
          boxShadow: [BoxShadow(color: const Color(0xFF3A2E7E).withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 12))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Stack(children: [
            // glowing floor grid that slowly moves towards you
            Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _GridPainter(_anim)))),
            Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _SparklePainter(_anim)))),
            Positioned(
              right: 0,
              top: 8,
              bottom: 0,
              child: _float(Image.asset(
                'assets/images/hero_house.png',
                fit: BoxFit.contain,
                alignment: Alignment.centerRight,
                // if the file is missing the card still looks fine
                errorBuilder: (_, __, ___) => Padding(
                  padding: const EdgeInsets.only(right: 22, top: 30),
                  child: Icon(Icons.home_work_rounded, size: 120, color: Colors.white.withValues(alpha: 0.18)),
                ),
              ), dy: 5),
            ),
            // light sweep over the card
            Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _ShimmerPainter(_anim)))),
            Positioned(
              left: 18,
              top: 16,
              bottom: 16,
              width: 190,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.95), borderRadius: BorderRadius.circular(20)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.favorite_rounded, color: Color(0xFF1B9E55), size: 15),
                    SizedBox(width: 6),
                    Text('Home Health ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kNavy)),
                    Text('98%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF1B9E55))),
                  ]),
                ),
                const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Smart Home.', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800, color: Colors.white, height: 1.1)),
                  Text('Smarter You.', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800, color: Color(0xFFD9CCFF), height: 1.1)),
                  SizedBox(height: 6),
                  Text('Explore your home\nin stunning 3D', style: TextStyle(fontSize: 12.5, color: Color(0xFFE6DEFF), height: 1.3)),
                ]),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  elevation: 3,
                  shadowColor: Colors.black.withValues(alpha: 0.25),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: widget.onViewHome,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.visibility_outlined, size: 19, color: kBlue),
                        SizedBox(width: 8),
                        Text('View 3D Home', style: TextStyle(fontWeight: FontWeight.w700, color: kNavy, fontSize: 13.5)),
                        SizedBox(width: 6),
                        Icon(Icons.chevron_right_rounded, size: 20, color: kBlue),
                      ]),
                    ),
                  ),
                ),
                ),
              ]),
            ),
          ]),
        ),
      );

  // ------------------------------------------------------------------ stats

  Widget _stats() => FutureBuilder<List<int>>(
        future: _counts,
        builder: (c, s) {
          final v = s.data ?? [0, 0, 0];
          return Row(children: [
            _stat(Icons.view_in_ar_rounded, const [Color(0xFF60A5FA), Color(0xFF2563EB)], '${v[0]}', 'Assets', const [Color(0xFFFFFFFF), Color(0xFFE8F0FF)], 1),
            const SizedBox(width: 10),
            _stat(Icons.verified_user_rounded, const [Color(0xFF34D399), Color(0xFF059669)], '${v[1]}', 'Warranties', const [Color(0xFFFFFFFF), Color(0xFFE5F7EC)], 3),
            const SizedBox(width: 10),
            _stat(Icons.assignment_turned_in_rounded, const [Color(0xFF8B5CF6), Color(0xFF5B2FD0)], '${v[2]}', 'Tasks', const [Color(0xFFFFFFFF), Color(0xFFEDE7FF)], 4),
          ]);
        },
      );

  // Vertical layout => no horizontal overflow on narrow phones.
  Widget _stat(IconData icon, List<Color> iconGrad, String n, String label, List<Color> bg, int tab) => Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => tab == 1 ? widget.goTab(1) : widget.onMaintenance(tab == 3 ? 2 : 0),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: bg),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white),
              boxShadow: _shadow(0.08),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: iconGrad),
                  boxShadow: [BoxShadow(color: iconGrad.last.withValues(alpha: 0.30), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: Icon(icon, size: 24, color: Colors.white),
              ),
              const SizedBox(height: 14),
              Text(n, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: kNavy, height: 1)),
              const SizedBox(height: 4),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: _grey)),
            ]),
          ),
        ),
      );

  // ------------------------------------------------------------------ banner

  Widget _banner() => InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => widget.goTab(1),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 16, 16, 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF4A25B8), Color(0xFF7B4DE8)]),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: kBlue.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 10))],
          ),
          child: Row(children: [
            SizedBox(
              width: 98,
              height: 82,
              child: Stack(clipBehavior: Clip.none, children: [
                Positioned.fill(child: CustomPaint(painter: _OrbitPainter(_anim))),
                Center(child: _float(const Icon(Icons.home_rounded, color: Colors.white, size: 62), dy: 3, phase: 0.25)),
                Positioned(
                  right: 0,
                  bottom: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: kLavender, borderRadius: BorderRadius.circular(10)),
                    child: const Text('3D', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                  ),
                ),
              ]),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Your Digital Home', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white, fontSize: 17)),
                SizedBox(height: 3),
                Text('All your assets, documents, warranties and maintenance in one place.', style: TextStyle(fontSize: 12.5, color: Color(0xFFE6DEFF), height: 1.3)),
              ]),
            ),
            const SizedBox(width: 8),
            const CircleAvatar(radius: 18, backgroundColor: Colors.white, child: Icon(Icons.arrow_forward_rounded, size: 20, color: kBlue)),
          ]),
        ),
      );

  // ------------------------------------------------------------------ quick actions

  /// (icon, label, colour, action). The first four are shown on the home screen, all of them under "See All".
  List<(IconData, String, Color, VoidCallback)> get _actions => [
        (Icons.add_rounded, 'Add Asset', kBlue, () => widget.goTab(1)),
        (Icons.qr_code_scanner_rounded, 'Scan Home', const Color(0xFF6B4FD8), () => widget.goTab(2)),
        (Icons.description_rounded, 'Documents', const Color(0xFF1B9E55), () => widget.goTab(3)),
        (Icons.build_rounded, 'Maintenance', const Color(0xFFE0457B), () => widget.onMaintenance(0)),
        (Icons.weekend_outlined, 'Room Designer', const Color(0xFFF08A24), widget.onAr),
        (Icons.notifications_none_rounded, 'Notifications', const Color(0xFF2563EB), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()))),
      ];

  Widget _quickActions() {
    final a = _actions.take(4).toList();
    return Row(children: [
      for (var i = 0; i < a.length; i++) _qa(a[i].$1, a[i].$2, a[i].$3, a[i].$4, filled: i == 0),
    ]);
  }

  void _seeAll() => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        backgroundColor: kBg,
        builder: (sheet) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 10), child: _section('All Quick Actions')),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 0,
              childAspectRatio: 1.0,
              children: [
                for (var i = 0; i < _actions.length; i++)
                  _qaTile(_actions[i].$1, _actions[i].$2, _actions[i].$3, () {
                    Navigator.pop(sheet);
                    _actions[i].$4();
                  }, filled: i == 0),
              ],
            ),
          ]),
        ),
      );

  Widget _qaIcon(IconData icon, Color color, bool filled) => Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: filled ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF7C5CF0), Color(0xFF5B2FD0)]) : null,
          color: filled ? null : color.withValues(alpha: 0.13),
        ),
        child: Icon(icon, color: filled ? Colors.white : color, size: 25),
      );

  Widget _qaTile(IconData icon, String label, Color color, VoidCallback onTap, {bool filled = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: _shadow(0.07)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              _qaIcon(icon, color, filled),
              const SizedBox(height: 10),
              Text(label, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 12, height: 1.2, color: kNavy, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );

  Widget _qa(IconData icon, String label, Color color, VoidCallback onTap, {bool filled = false}) => Expanded(
        child: SizedBox(height: 110, child: _qaTile(icon, label, color, onTap, filled: filled)),
      );

  // ------------------------------------------------------------------ reminders

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
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: _shadow(0.06)),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: kNavy)),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: _grey)),
            ]),
          ),
        ]),
      );
}


// ---------------------------------------------------------------------- little animations

/// Perspective floor grid; the horizontal lines glide towards the viewer.
class _GridPainter extends CustomPainter {
  final Animation<double> t;
  _GridPainter(this.t) : super(repaint: t);

  @override
  void paint(Canvas c, Size s) {
    final horizon = s.height * 0.60;
    final vx = s.width * 0.55;
    final p = Paint()..style = PaintingStyle.stroke..strokeWidth = 1;
    p.color = Colors.white.withValues(alpha: 0.10);
    for (var i = -9; i <= 9; i++) {
      c.drawLine(Offset(vx + i * s.width * 0.025, horizon), Offset(vx + i * s.width * 0.19, s.height), p);
    }
    final phase = (t.value * 3) % 1; // one grid step every ~2.7 s
    for (var k = 0; k < 6; k++) {
      final f = (k + phase) / 6;
      final y = horizon + (s.height - horizon) * f * f;
      p.color = Colors.white.withValues(alpha: 0.16 * f);
      c.drawLine(Offset(0, y), Offset(s.width, y), p);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => false;
}

/// A few stars that twinkle.
class _SparklePainter extends CustomPainter {
  final Animation<double> t;
  _SparklePainter(this.t) : super(repaint: t);
  static const _pts = [(0.46, 0.16, 0.0), (0.88, 0.12, 0.3), (0.70, 0.40, 0.6), (0.96, 0.58, 0.15), (0.50, 0.70, 0.8), (0.82, 0.86, 0.45)];

  @override
  void paint(Canvas c, Size s) {
    for (final q in _pts) {
      final a = 0.5 + 0.5 * math.sin((t.value * 2 + q.$3) * 2 * math.pi);
      final o = Offset(q.$1 * s.width, q.$2 * s.height);
      c.drawCircle(o, 5, Paint()..color = Colors.white.withValues(alpha: 0.10 * a)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
      c.drawCircle(o, 1.6, Paint()..color = Colors.white.withValues(alpha: 0.35 + 0.5 * a));
    }
  }

  @override
  bool shouldRepaint(_SparklePainter old) => false;
}

/// Soft light band that sweeps across the hero card now and then.
class _ShimmerPainter extends CustomPainter {
  final Animation<double> t;
  _ShimmerPainter(this.t) : super(repaint: t);

  @override
  void paint(Canvas c, Size s) {
    final f = (t.value * 1.0) % 1; // 0..1 per 8 s: the band is visible in the first part only
    if (f > 0.55) return;
    final x = (f / 0.55) * (s.width * 1.6) - s.width * 0.4;
    final r = Rect.fromLTWH(x, 0, s.width * 0.35, s.height);
    c.save();
    c.translate(r.center.dx, r.center.dy);
    c.transform(Matrix4.skewX(-0.35).storage);
    c.translate(-r.center.dx, -r.center.dy);
    c.drawRect(
      r,
      Paint()..shader = LinearGradient(colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: 0.13), Colors.white.withValues(alpha: 0)]).createShader(r),
    );
    c.restore();
  }

  @override
  bool shouldRepaint(_ShimmerPainter old) => false;
}

/// Orbit ring with a small light travelling around it, plus twinkling plus-signs.
class _OrbitPainter extends CustomPainter {
  final Animation<double> t;
  _OrbitPainter(this.t) : super(repaint: t);

  @override
  void paint(Canvas c, Size s) {
    final centre = Offset(s.width / 2, s.height * 0.70);
    final rx = s.width * 0.48, ry = s.height * 0.17;
    c.drawOval(Rect.fromCenter(center: centre, width: rx * 2, height: ry * 2), Paint()..style = PaintingStyle.stroke..strokeWidth = 1.3..color = Colors.white.withValues(alpha: 0.35));
    final a = t.value * 2 * math.pi * 2; // two laps per loop
    final d = centre + Offset(math.cos(a) * rx, math.sin(a) * ry);
    c.drawCircle(d, 7, Paint()..color = Colors.white.withValues(alpha: 0.25)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    c.drawCircle(d, 3, Paint()..color = Colors.white);
    for (final q in const [(0.10, 0.10, 0.0), (0.92, 0.22, 0.5)]) {
      final al = 0.35 + 0.5 * (0.5 + 0.5 * math.sin((t.value * 3 + q.$3) * 2 * math.pi));
      final o = Offset(q.$1 * s.width, q.$2 * s.height);
      final p = Paint()..color = Colors.white.withValues(alpha: al)..strokeWidth = 1.4..strokeCap = StrokeCap.round;
      c.drawLine(o - const Offset(4, 0), o + const Offset(4, 0), p);
      c.drawLine(o - const Offset(0, 4), o + const Offset(0, 4), p);
    }
  }

  @override
  bool shouldRepaint(_OrbitPainter old) => false;
}

/// Soft, filled house (roof, chimney, door, windows) used as a faint background decoration.
class _HouseArtPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final u = s.width / 100; // draw on a 100 x 100 grid
    final shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [kLavender.withValues(alpha: 0.30), kBlue.withValues(alpha: 0.11)],
    ).createShader(Offset.zero & s);
    final fill = Paint()..shader = shader;

    // chimney + body
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(68 * u, 14 * u, 80 * u, 38 * u), Radius.circular(2.5 * u)), fill);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(16 * u, 44 * u, 84 * u, 93 * u), Radius.circular(7 * u)), fill);

    // roof: triangle with soft rounded corners
    final roof = Path()
      ..moveTo(50 * u, 9 * u)
      ..lineTo(96 * u, 50 * u)
      ..lineTo(4 * u, 50 * u)
      ..close();
    c.drawPath(roof, fill);
    c.drawPath(roof, Paint()..shader = shader..style = PaintingStyle.stroke..strokeWidth = 6 * u..strokeJoin = StrokeJoin.round);

    // door, windows, round attic window (lighter than the house)
    final light = Paint()..color = Colors.white.withValues(alpha: 0.40);
    c.drawRRect(RRect.fromRectAndCorners(Rect.fromLTRB(42 * u, 63 * u, 58 * u, 93 * u), topLeft: Radius.circular(8 * u), topRight: Radius.circular(8 * u)), light);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(23 * u, 57 * u, 36 * u, 71 * u), Radius.circular(3 * u)), light);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(64 * u, 57 * u, 77 * u, 71 * u), Radius.circular(3 * u)), light);
    c.drawCircle(Offset(50 * u, 34 * u), 6.5 * u, light);
    c.drawCircle(Offset(54.5 * u, 79 * u), 1.4 * u, Paint()..color = kBlue.withValues(alpha: 0.30));
  }

  @override
  bool shouldRepaint(_HouseArtPainter old) => false;
}