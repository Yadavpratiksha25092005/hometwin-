import 'dart:io';
import 'package:flutter/material.dart';
import '../api.dart';
import '../main.dart';

List<BoxShadow> softShadow([double a = 0.06]) =>
    [BoxShadow(color: kNavy.withValues(alpha: a), blurRadius: 14, offset: const Offset(0, 6))];

/// Photo from assets ('asset:...'), a local file path, or an icon placeholder.
class PhotoThumb extends StatelessWidget {
  final String? src;
  final double w, h;
  final IconData fallback;
  final double radius;
  const PhotoThumb({super.key, this.src, this.w = 76, this.h = 76, this.fallback = Icons.inventory_2_rounded, this.radius = 12});

  Widget _placeholder() => Container(
        color: const Color(0xFFEAF2FF),
        child: Icon(fallback, color: kBlue.withValues(alpha: 0.7), size: h * 0.4),
      );

  Widget _img() {
    final s = src;
    if (s == null || s.isEmpty) return _placeholder();
    if (s.startsWith('asset:')) {
      return Image.asset(s.substring(6), fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder());
    }
    if (Api.isServerPath(s)) {
      return Image.network(Api.fileUrl(s), fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder());
    }
    final f = File(s);
    if (f.existsSync()) return Image.file(f, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder());
    return _placeholder();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(width: w, height: h, child: _img()),
      );
}

class StatusPill extends StatelessWidget {
  final String text;
  final Color bg, fg;
  final IconData? icon;
  const StatusPill(this.text, {super.key, required this.bg, required this.fg, this.icon});

  factory StatusPill.green(String t, {Key? key}) =>
      StatusPill(t, key: key, bg: const Color(0xFFDDF4E7), fg: const Color(0xFF1B9E55), icon: Icons.check_rounded);
  factory StatusPill.blue(String t, {Key? key}) =>
      StatusPill(t, key: key, bg: const Color(0xFFE3EEFF), fg: kBlue);
  factory StatusPill.grey(String t, {Key? key}) =>
      StatusPill(t, key: key, bg: const Color(0xFFEEF1F6), fg: const Color(0xFF5A6785));

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: 3)],
          Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg))),
        ]),
      );
}
/// Turns an error into text a person can read (no "Exception:" prefix, no database internals).
String friendlyError(Object e) {
  final s = '$e'.replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
  if (s.contains('SQLSTATE') || s.contains('ERROR:')) {
    if (s.contains('22P02') || s.contains('numeric') || s.contains('integer')) return 'Please enter a valid number.';
    if (s.contains('22007') || s.contains('22008') || s.contains('date')) return 'Please enter a valid date.';
    if (s.contains('23502')) return 'Please fill in all required fields.';
    return 'Something went wrong. Please try again.';
  }
  return s.isEmpty ? 'Something went wrong. Please try again.' : s;
}

/// Short message shown above everything, including an open bottom sheet.
/// (A normal SnackBar is drawn by the screen *behind* the sheet, so people never see it.)
void showToast(BuildContext context, String message, {bool error = true}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => Positioned(
      left: 16,
      right: 16,
      top: MediaQuery.of(ctx).padding.top + 12,
      child: IgnorePointer(
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: error ? const Color(0xFFB3261E) : const Color(0xFF1E8E3E),
              borderRadius: BorderRadius.circular(14),
              boxShadow: softShadow(0.25),
            ),
            child: Row(children: [
              Icon(error ? Icons.error_outline : Icons.check_circle_outline, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500))),
            ]),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  Future.delayed(const Duration(seconds: 3), () {
    if (entry.mounted) entry.remove();
  });
}
