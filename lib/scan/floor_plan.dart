import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../main.dart';
import 'room_model.dart';

/// 2D top-down floor plan with wall lengths and area.
class FloorPlanPainter extends CustomPainter {
  final RoomData room;
  FloorPlanPainter(this.room);

  void _label(Canvas c, String t, Offset at, {double size = 12, Color color = kNavy, FontWeight w = FontWeight.w700}) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: TextStyle(fontSize: size, color: color, fontWeight: w)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, at - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final pts = room.corners;
    if (pts.length < 3) return;
    final minX = pts.map((p) => p[0]).reduce(math.min), maxX = pts.map((p) => p[0]).reduce(math.max);
    final minZ = pts.map((p) => p[1]).reduce(math.min), maxZ = pts.map((p) => p[1]).reduce(math.max);
    const pad = 52.0;
    final w = math.max(maxX - minX, 0.01), h = math.max(maxZ - minZ, 0.01);
    final scale = math.min((size.width - 2 * pad) / w, (size.height - 2 * pad) / h);
    final ox = (size.width - w * scale) / 2, oy = (size.height - h * scale) / 2;
    Offset map(List<double> p) => Offset(ox + (p[0] - minX) * scale, oy + (p[1] - minZ) * scale);

    final path = Path()..moveTo(map(pts[0]).dx, map(pts[0]).dy);
    for (final p in pts.skip(1)) {
      final o = map(p);
      path.lineTo(o.dx, o.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFE3EEFF));
    canvas.drawPath(path, Paint()..color = kBlue..style = PaintingStyle.stroke..strokeWidth = 3..strokeJoin = StrokeJoin.round);

    final centroid = pts.map(map).reduce((a, b) => a + b) / pts.length.toDouble();
    for (var i = 0; i < pts.length; i++) {
      final a = map(pts[i]), b = map(pts[(i + 1) % pts.length]);
      canvas.drawCircle(a, 5, Paint()..color = kBlue);
      final mid = (a + b) / 2;
      final dir = mid - centroid;
      final out = dir.distance == 0 ? Offset.zero : dir / dir.distance * 18;
      _label(canvas, '${room.walls[i].toStringAsFixed(2)} m', mid + out);
    }
    _label(canvas, '${room.area.toStringAsFixed(1)} m²', centroid, size: 18, w: FontWeight.w800);
  }

  @override
  bool shouldRepaint(covariant FloorPlanPainter old) => old.room != room;
}