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
      await Api.updateName(v);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))));
    }
  }

  Widget _profileCard() => InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: _editName,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFEDE7FF), Color(0xFFDCD0FF)]),
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

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          _profileCard(),
          const SizedBox(height: 8),
          _tile(Icons.build_circle_outlined, 'Maintenance & Warranty', () => _push(context, const MaintenanceScreen())),
          _tile(Icons.history_rounded, 'Service History', () => _push(context, const MaintenanceScreen(initialTab: 1))),
          _tile(Icons.verified_user_outlined, 'Warranties', () => _push(context, const MaintenanceScreen(initialTab: 2))),
          _tile(Icons.notifications_outlined, 'Notifications', () => _push(context, const NotificationsScreen())),
          _tile(Icons.weekend_outlined, 'Room Designer', () => _push(context, const RoomDesignerScreen())),
          _tile(Icons.ios_share_rounded, 'Export / Share Home Report (PDF)', () async {
            try {
              final f = await ReportPdf.build();
              await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], text: 'My Home Digital Twin report'));
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not create report: $e')));
              }
            }
          }),
          _tile(Icons.auto_awesome_outlined, 'Load sample data', () async {
            await Api.seedDemo();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sample data added. Check the Assets / Maintenance tabs.')));
            }
          }),
          _tile(Icons.delete_sweep_outlined, 'Clear all data', () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Clear all data?'),
                content: const Text('All assets, warranties, documents and tasks will be removed.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                  TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear', style: TextStyle(color: Colors.red))),
                ],
              ),
            );
            if (ok == true) await Api.clearData();
          }),
          _tile(Icons.logout, 'Logout', () async {
            await Api.logout();
            if (context.mounted) {
              Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const AuthScreen()), (_) => false);
            }
          }),
        ]),
      );

  Widget _tile(IconData i, String t, VoidCallback onTap) => Card(
        child: ListTile(leading: Icon(i, color: kBlue), title: Text(t), trailing: const Icon(Icons.chevron_right), onTap: onTap),
      );
}