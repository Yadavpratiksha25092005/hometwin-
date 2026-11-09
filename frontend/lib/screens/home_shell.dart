import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../api.dart';
import '../main.dart';
import '../notifications.dart';
import '../report_pdf.dart';
import 'assets_screen.dart';
import 'auth_screen.dart';
import 'dashboard_screen.dart';
import 'maintenance_screen.dart';
import 'notifications_screen.dart';
import 'room_designer_screen.dart';
import 'scan_screens.dart';
import 'vault_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _i = 0;

  @override
  void initState() {
    super.initState();
    _setupNotifications();
  }

  Future<void> _setupNotifications() async {
    await Notifications.init();
    if (await Notifications.enabled) {
      await Notifications.requestPermission();
      await Notifications.sync();
    }
  }

  void _push(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardScreen(
        goTab: (t) => setState(() => _i = t),
        onMaintenance: (t) => _push(MaintenanceScreen(initialTab: t)),
        onViewHome: () => _push(const ScanScreen()),
        onAr: () => _push(const RoomDesignerScreen()),
      ),
      const AssetsScreen(),
      const ScanScreen(embedded: true),
      const VaultScreen(),
      const ProfileScreen(),
    ];
    return PopScope(
      // Home tab par back = app band; baaki tabs par back = Home tab par wapas.
      canPop: _i == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _i = 0);
      },
      child: Scaffold(
      body: pages[_i],
      bottomNavigationBar: _NavBar(index: _i, onTap: (v) => setState(() => _i = v)),
    ));
  }
}

/// Floating white bottom bar; the selected tab is a lavender pill with icon + label.
class _NavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const _NavBar({required this.index, required this.onTap});

  static const _items = [
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.grid_view_outlined, Icons.grid_view_rounded, 'Assets'),
    (Icons.crop_free_rounded, Icons.crop_free_rounded, 'Scan'),
    (Icons.shield_outlined, Icons.shield_rounded, 'Vault'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: Container(
            height: 68,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(34),
              boxShadow: [BoxShadow(color: kBlue.withValues(alpha: 0.14), blurRadius: 22, offset: const Offset(0, 8))],
            ),
            child: Row(children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onTap(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 7),
                      decoration: BoxDecoration(color: i == index ? kLilac : Colors.transparent, borderRadius: BorderRadius.circular(27)),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(i == index ? _items[i].$2 : _items[i].$1, size: 25, color: i == index ? kBlue : const Color(0xFF5A6785)),
                        const SizedBox(height: 2),
                        Text(
                          _items[i].$3,
                          maxLines: 1,
                          style: TextStyle(fontSize: 11.5, fontWeight: i == index ? FontWeight.w700 : FontWeight.w500, color: i == index ? kBlue : const Color(0xFF5A6785)),
                        ),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      );
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  void _push(BuildContext c, Widget w) => Navigator.push(c, MaterialPageRoute(builder: (_) => w));

  String get _name {
    final n = (Api.userName ?? '').trim();
    return n.isEmpty ? '' : n[0].toUpperCase() + n.substring(1);
  }

  Future<void> _editName() async {
    final c = TextEditingController(text: Api.userName ?? '');
    final v = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Your name'),
        content: TextField(controller: c, autofocus: true, maxLength: 60, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (v == null || v.isEmpty || v == Api.userName) return;
    try {
      final synced = await Api.updateName(v);
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(synced ? 'Name updated' : 'Name changed on this phone. Restart the updated backend to save it on the server too.'),
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))));
    }
  }

  Widget _profileCard() => ValueListenableBuilder<String?>(valueListenable: Api.nameN, builder: (_, __, ___) => _profileCardBody());

  Widget _profileCardBody() => InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: _editName,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF3EFFF), Color(0xFFE6DEFF)]),
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: [BoxShadow(color: kBlue.withValues(alpha: 0.16), blurRadius: 22, offset: const Offset(0, 10))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(children: [
              // faint house in the corner
              Positioned(
                right: 18,
                bottom: -6,
                child: Icon(Icons.home_rounded, size: 96, color: kBlue.withValues(alpha: 0.07)),
              ),
              Row(children: [
                SizedBox(
                  width: 84,
                  height: 84,
                  child: Stack(clipBehavior: Clip.none, children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white, boxShadow: [BoxShadow(color: kBlue.withValues(alpha: 0.25), blurRadius: 14, offset: const Offset(0, 6))]),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF7C5CF0), Color(0xFF5B2FD0)])),
                        child: Text(_name.isEmpty ? '?' : _name[0], style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 6, offset: const Offset(0, 2))]),
                        child: const Icon(Icons.edit_rounded, size: 16, color: kBlue),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kNavy)),
                    const SizedBox(height: 6),
                    Row(children: [
                      const Icon(Icons.home_rounded, size: 17, color: kBlue),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          Api.remote ? 'Home Digital Twin  •  Server mode' : 'Home Digital Twin  •  Demo mode',
                          maxLines: 2,
                          style: const TextStyle(fontSize: 12.5, color: kNavy, height: 1.25),
                        ),
                      ),
                    ]),
                  ]),
                ),
                const Icon(Icons.chevron_right_rounded, color: kNavy, size: 26),
              ]),
            ]),
          ),
        ),
      );

  // ------------------------------------------------------------------ header + menu

  Widget _header() => SizedBox(
        height: 96,
        child: Stack(children: [
          Positioned(right: 0, top: 0, child: IgnorePointer(child: CustomPaint(size: const Size(150, 88), painter: _SkylinePainter()))),
          const Align(
            alignment: Alignment.centerLeft,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Profile', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: kNavy)),
              SizedBox(height: 4),
              SizedBox(width: 230, child: Text('Manage your account & preferences', style: TextStyle(fontSize: 13.5, color: Color(0xFF5A6785), height: 1.25))),
            ]),
          ),
        ]),
      );

  Widget _group(String title, List<Widget> items) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 18, 0, 8),
          child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF5A6785), letterSpacing: 0.4)),
        ),
        ...items,
      ]);

  Widget _item(IconData icon, Color color, String title, String sub, VoidCallback onTap) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: kBlue.withValues(alpha: 0.07), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
                  child: Icon(icon, color: color, size: 23),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kNavy)),
                    const SizedBox(height: 2),
                    Text(sub, style: const TextStyle(fontSize: 12, color: Color(0xFF5A6785), height: 1.25)),
                  ]),
                ),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFF9AA3BD)),
              ]),
            ),
          ),
        ),
      );

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<bool> _confirm(String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: Text(action, style: const TextStyle(color: Colors.red))),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.center, colors: [Color(0xFFF1EEFB), kBg])),
          child: SafeArea(
            bottom: false,
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 28), children: [
              _header(),
              const SizedBox(height: 8),
              _profileCard(),
              _group('Home', [
                _item(Icons.build_circle_outlined, kBlue, 'Maintenance & Warranty', 'Upcoming tasks and expiring warranties', () => _push(context, const MaintenanceScreen())),
                _item(Icons.history_rounded, const Color(0xFF2563EB), 'Service History', 'Everything that was serviced or repaired', () => _push(context, const MaintenanceScreen(initialTab: 1))),
                _item(Icons.verified_user_outlined, const Color(0xFF1B9E55), 'Warranties', 'Track warranty dates of your assets', () => _push(context, const MaintenanceScreen(initialTab: 2))),
                _item(Icons.notifications_none_rounded, const Color(0xFFF08A24), 'Notifications', 'Reminders and alerts', () => _push(context, const NotificationsScreen())),
              ]),
              _group('Tools', [
                _item(Icons.weekend_outlined, const Color(0xFFE0457B), 'Room Designer', 'Drag furniture into a photo of your room', () => _push(context, const RoomDesignerScreen())),
                _item(Icons.ios_share_rounded, const Color(0xFF6B4FD8), 'Export / Share Home Report', 'Create a PDF of your home and share it', () async {
                  try {
                    final f = await ReportPdf.build();
                    await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], text: 'My Home Digital Twin report'));
                  } catch (e) {
                    _snack('Could not create report: $e');
                  }
                }),
              ]),
              _group('Data & account', [
                _item(Icons.auto_awesome_outlined, kLavender, 'Load sample data', 'Fill the app with example assets and tasks', () async {
                  await Api.seedDemo();
                  _snack('Sample data added. Check the Assets / Maintenance tabs.');
                }),
                _item(Icons.delete_sweep_outlined, Colors.red, 'Clear all data', 'Remove assets, warranties, documents and tasks', () async {
                  if (await _confirm('Clear all data?', 'All assets, warranties, documents and tasks will be removed.', 'Clear')) await Api.clearData();
                }),
                _item(Icons.logout_rounded, Colors.red, 'Logout', 'Sign out of this device', () async {
                  if (!await _confirm('Log out?', 'You can log in again any time.', 'Log out')) return;
                  await Api.logout();
                  if (mounted) {
                    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const AuthScreen()), (_) => false);
                  }
                }),
              ]),
            ]),
          ),
        ),
      );
}

/// Small lavender city skyline for the top right of the Profile screen.
class _SkylinePainter extends CustomPainter {
  // x, width, height (all as a fraction of the drawing area)
  static const _b = [(0.02, 0.16, 0.42), (0.20, 0.18, 0.68), (0.40, 0.20, 1.0), (0.62, 0.16, 0.58), (0.80, 0.18, 0.80)];

  @override
  void paint(Canvas c, Size s) {
    final shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [kLavender.withValues(alpha: 0.50), kLavender.withValues(alpha: 0.12)],
    ).createShader(Offset.zero & s);
    final win = Paint()..color = Colors.white.withValues(alpha: 0.55);
    for (final b in _b) {
      final x = b.$1 * s.width, w = b.$2 * s.width, h = b.$3 * s.height;
      final top = s.height - h;
      c.drawRRect(RRect.fromRectAndCorners(Rect.fromLTWH(x, top, w, h), topLeft: const Radius.circular(5), topRight: const Radius.circular(5)), Paint()..shader = shader);
      // windows: 2 columns
      for (var row = 0; row < (h - 14) ~/ 11; row++) {
        for (var col = 0; col < 2; col++) {
          c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x + w * (0.2 + col * 0.42), top + 9 + row * 11, w * 0.2, 5), const Radius.circular(1.5)), win);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_SkylinePainter old) => false;
}