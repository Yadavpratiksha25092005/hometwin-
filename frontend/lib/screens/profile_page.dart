import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../api.dart';
import '../main.dart';
import '../report_pdf.dart';
import 'auth_screen.dart';
import 'maintenance_screen.dart';
import 'notifications_screen.dart';
import 'room_designer_screen.dart';

/// New Profile screen design (wave header, white profile card, lavender icon tiles).
/// Same features as the old ProfileScreen in home_shell.dart.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  static const _soft = Color(0xFF5A6785);

  void _push(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));

  String get _name {
    final n = (Api.userName ?? '').trim();
    return n.isEmpty ? '' : n[0].toUpperCase() + n.substring(1);
  }

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
      _snack(synced ? 'Name updated' : 'Name changed on this phone. Restart the updated backend to save it on the server too.');
    } catch (e) {
      _snack('$e'.replaceFirst('Exception: ', ''));
    }
  }

  // ---------------------------------------------------------------- header

  Widget _header() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Profile', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: kNavy, letterSpacing: -0.5)),
        const SizedBox(height: 6),
        const SizedBox(width: 215, child: Text('Manage your account & preferences', style: TextStyle(fontSize: 15.5, color: _soft, height: 1.25))),
        const SizedBox(height: 12),
        Container(
          width: 60,
          height: 5,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(5), gradient: const LinearGradient(colors: [kBlue, kLavender])),
        ),
      ]);

  // ---------------------------------------------------------------- profile card

  Widget _profileCard() => ValueListenableBuilder<String?>(valueListenable: Api.nameN, builder: (_, __, ___) => _profileCardBody());

  Widget _profileCardBody() => InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: _editName,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [BoxShadow(color: kBlue.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, 10))],
          ),
          child: Row(children: [
            SizedBox(
              width: 88,
              height: 88,
              child: Stack(clipBehavior: Clip.none, children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white, boxShadow: [BoxShadow(color: kBlue.withValues(alpha: 0.25), blurRadius: 14, offset: const Offset(0, 6))]),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF7C5CF0), Color(0xFF5B2FD0)])),
                    child: Text(_name.isEmpty ? '?' : _name[0], style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w600)),
                  ),
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
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
                Text(_name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: kNavy)),
                const SizedBox(height: 6),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.home_rounded, size: 19, color: kBlue),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      Api.remote ? 'Home Digital Twin  •  Server mode' : 'Home Digital Twin  •  Demo mode',
                      maxLines: 2,
                      style: const TextStyle(fontSize: 13.5, color: kNavy, height: 1.25),
                    ),
                  ),
                ]),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: kNavy, size: 28),
          ]),
        ),
      );

  // ---------------------------------------------------------------- menu

  Widget _group(String title, List<Widget> items) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 24, 0, 12),
          child: Row(children: [
            Container(width: 4, height: 24, decoration: BoxDecoration(color: kBlue, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 10),
            Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: kNavy)),
          ]),
        ),
        ...items,
      ]);

  /// [tint] is only used for the red "danger" items; the others use the purple tile.
  Widget _item(IconData icon, String title, String sub, VoidCallback onTap, {Color? tint}) {
    final iconColor = tint ?? kBlue;
    final tileColor = tint == null ? kLilac : tint.withValues(alpha: 0.12);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: kBlue.withValues(alpha: 0.08), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: tileColor, borderRadius: BorderRadius.circular(15)),
                child: Icon(icon, color: iconColor, size: 25),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, color: kNavy)),
                  const SizedBox(height: 2),
                  Text(sub, style: const TextStyle(fontSize: 13, color: _soft, height: 1.25)),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: kBlue, size: 26),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final w = MediaQuery.of(context).size.width;
    return Scaffold(
      body: Stack(fit: StackFit.expand, children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.center, colors: [Color(0xFFF1EEFB), kBg])),
          ),
        ),
        // purple wave in the top right corner
        Positioned(top: 0, right: 0, child: IgnorePointer(child: CustomPaint(size: Size(w, top + 150), painter: _WavePainter()))),
        ListView(
          padding: EdgeInsets.fromLTRB(16, top + 20, 16, 28),
          children: [
            _header(),
            const SizedBox(height: 22),
            _profileCard(),
            _group('Home', [
              _item(Icons.shield_rounded, 'Maintenance & Warranty', 'Upcoming tasks and expiring warranties', () => _push(const MaintenanceScreen())),
              _item(Icons.history_rounded, 'Service History', 'Everything that was serviced or repaired', () => _push(const MaintenanceScreen(initialTab: 1))),
              _item(Icons.verified_user_outlined, 'Warranties', 'Track warranty dates of your assets', () => _push(const MaintenanceScreen(initialTab: 2))),
              _item(Icons.notifications_none_rounded, 'Notifications', 'Reminders and alerts', () => _push(const NotificationsScreen())),
            ]),
            _group('Tools', [
              _item(Icons.weekend_outlined, 'Room Designer', 'Drag furniture into a photo of your room', () => _push(const RoomDesignerScreen())),
              _item(Icons.ios_share_rounded, 'Export / Share Home Report', 'Create a PDF of your home and share it', () async {
                try {
                  final f = await ReportPdf.build();
                  await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], text: 'My Home Digital Twin report'));
                } catch (e) {
                  _snack('Could not create report: $e');
                }
              }),
            ]),
            _group('Data & account', [
              _item(Icons.auto_awesome_outlined, 'Load sample data', 'Fill the app with example assets and tasks', () async {
                await Api.seedDemo();
                _snack('Sample data added. Check the Assets / Maintenance tabs.');
              }),
              _item(Icons.delete_sweep_outlined, 'Clear all data', 'Remove assets, warranties, documents and tasks', () async {
                if (await _confirm('Clear all data?', 'All assets, warranties, documents and tasks will be removed.', 'Clear')) await Api.clearData();
              }, tint: Colors.red),
              _item(Icons.logout_rounded, 'Logout', 'Sign out of this device', () async {
                if (!await _confirm('Log out?', 'You can log in again any time.', 'Log out')) return;
                await Api.logout();
                if (mounted) {
                  Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const AuthScreen()), (_) => false);
                }
              }, tint: Colors.red),
            ]),
          ],
        ),
      ]),
    );
  }
}

/// Two soft purple waves for the top right corner.
class _WavePainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    final outer = Path()
      ..moveTo(w * 0.50, 0)
      ..cubicTo(w * 0.46, h * 0.52, w * 0.70, h * 0.70, w, h * 0.92)
      ..lineTo(w, 0)
      ..close();
    c.drawPath(
      outer,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kLavender.withValues(alpha: 0.10), kLavender.withValues(alpha: 0.30)],
        ).createShader(Offset.zero & s),
    );
    final inner = Path()
      ..moveTo(w * 0.70, 0)
      ..cubicTo(w * 0.62, h * 0.40, w * 0.86, h * 0.55, w, h * 0.70)
      ..lineTo(w, 0)
      ..close();
    c.drawPath(inner, Paint()..color = kLavender.withValues(alpha: 0.18));
  }

  @override
  bool shouldRepaint(_WavePainter old) => false;
}