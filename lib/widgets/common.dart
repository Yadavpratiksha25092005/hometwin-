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