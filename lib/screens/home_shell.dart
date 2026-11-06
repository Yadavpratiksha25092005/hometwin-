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
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i,
        onDestinationSelected: (v) => setState(() => _i = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home, color: kBlue), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2, color: kBlue), label: 'Assets'),
          NavigationDestination(icon: Icon(Icons.crop_free_rounded), selectedIcon: Icon(Icons.crop_free_rounded, color: kBlue), label: 'Scan'),
          NavigationDestination(icon: Icon(Icons.shield_outlined), selectedIcon: Icon(Icons.shield, color: kBlue), label: 'Vault'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person, color: kBlue), label: 'Profile'),
        ],
      ),
    ));
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  void _push(BuildContext c, Widget w) => Navigator.push(c, MaterialPageRoute(builder: (_) => w));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: kBlue,
                child: Text((Api.userName ?? '').isEmpty ? '?' : Api.userName![0].toUpperCase(), style: const TextStyle(color: Colors.white)),
              ),
              title: Text(Api.userName ?? ''),
              subtitle: Text(Api.remote ? 'Home Digital Twin  •  Server mode' : 'Home Digital Twin  •  Demo mode (phone only)'),
            ),
          ),
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