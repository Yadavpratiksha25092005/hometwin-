import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../main.dart';
import 'room_model.dart';

/// 2D top-down floor plan: wooden floor, thick walls with soft shadows, door and windows,
/// wall lengths, area and a 1 m scale bar.
///
/// Doors and windows are only drawn for looks (the scan does not know where they are):
/// the door goes on the longest wall and windows on the next longest walls.
class FloorPlanPainter extends CustomPainter {
  final RoomData room;
  final bool showOpenings;
  FloorPlanPainter(this.room, {this.showOpenings = true});

  static const _wall = Color(0xFF262626);
  static const _floorTints = [Color(0xFFE9D2AA), Color(0xFFE3C99E), Color(0xFFEDD8B3), Color(0xFFE6CDA2)];

  void _pill(Canvas c, String t, Offset at, {double size = 12, FontWeight w = FontWeight.w700, Color color = kNavy}) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: TextStyle(fontSize: size, color: color, fontWeight: w)),
      textDirection: TextDirection.ltr,
    )..layout();
    final r = RRect.fromRectAndRadius(
      Rect.fromCenter(center: at, width: tp.width + 14, height: tp.height + 8),
      const Radius.circular(12),
    );
    c.drawRRect(r.shift(const Offset(0, 1.5)), Paint()..color = Colors.black.withValues(alpha: 0.12)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    c.drawRRect(r, Paint()..color = Colors.white.withValues(alpha: 0.94));
    tp.paint(c, at - Offset(tp.width / 2, tp.height / 2));
  }

  /// Wood planks, staggered joints, light and soft shading, clipped to [clip].
  void _floor(Canvas canvas, Path clip, Rect box, double scale) {
    canvas.save();
    canvas.clipPath(clip);
    final plank = math.max(scale * 0.14, 5.0);
    final seam = scale * 1.1;
    final line = Paint()..color = const Color(0x26000000)..strokeWidth = 0.8;
    final rows = (box.height / plank).ceil() + 1;
    for (var r = 0; r < rows; r++) {
      final y = box.top + r * plank;
      canvas.drawRect(Rect.fromLTWH(box.left, y, box.width, plank), Paint()..color = _floorTints[(r * 7 + 3) % _floorTints.length]);
      canvas.drawLine(Offset(box.left, y), Offset(box.right, y), line);
      var x = box.left - ((r * 0.37) % 1.0) * seam;
      while (x < box.right) {
        canvas.drawLine(Offset(x, y), Offset(x, y + plank), line);
        x += seam;
      }
    }
    // gentle light from the top left
    canvas.drawRect(
      box,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white.withValues(alpha: 0.20), Colors.transparent, Colors.black.withValues(alpha: 0.08)],
        ).createShader(box),
    );
    // soft shadow along the inside of the walls
    canvas.drawPath(
      clip,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(scale * 0.35, 14)
        ..color = Colors.black.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final pts = room.corners;
    if (pts.length < 3) return;
    final n = pts.length;
    final minX = pts.map((p) => p[0]).reduce(math.min), maxX = pts.map((p) => p[0]).reduce(math.max);
    final minZ = pts.map((p) => p[1]).reduce(math.min), maxZ = pts.map((p) => p[1]).reduce(math.max);
    const pad = 64.0;
    final w = math.max(maxX - minX, 0.01), h = math.max(maxZ - minZ, 0.01);
    final scale = math.min((size.width - 2 * pad) / w, (size.height - 2 * pad) / h);
    final ox = (size.width - w * scale) / 2, oy = (size.height - h * scale) / 2;
    Offset map(List<double> p) => Offset(ox + (p[0] - minX) * scale, oy + (p[1] - minZ) * scale);

    final m = [for (final p in pts) map(p)];
    final path = Path()..moveTo(m[0].dx, m[0].dy);
    for (final o in m.skip(1)) {
      path.lineTo(o.dx, o.dy);
    }
    path.close();
    final box = path.getBounds();
    final wt = (scale * 0.14).clamp(6.0, 14.0).toDouble(); // wall thickness on screen

    // which side is "inside" (shoelace sign)
    var s = 0.0;
    for (var i = 0; i < n; i++) {
      final a = m[i], b = m[(i + 1) % n];
      s += a.dx * b.dy - b.dx * a.dy;
    }
    Offset inward(Offset a, Offset b) {
      final d = b - a;
      final l = d.distance == 0 ? 1.0 : d.distance;
      final v = s > 0 ? Offset(-d.dy, d.dx) : Offset(d.dy, -d.dx);
      return v / l;
    }

    // 1) drop shadow of the whole house
    canvas.drawPath(path.shift(const Offset(5, 9)), Paint()..color = Colors.black.withValues(alpha: 0.28)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12));

    // 2) floor
    _floor(canvas, path, box, scale);

    // 3) openings: longest wall = door, next longest walls = windows
    final order = List<int>.generate(n, (i) => i)..sort((a, b) => room.walls[b].compareTo(room.walls[a]));
    final doorWall = order.first;
    final windowWalls = <int>[
      if (showOpenings) ...order.skip(1).take(n >= 4 ? 2 : 1),
    ];
    // (start, end) of an opening on wall i, centred at [t] (0..1) and [len] metres long
    (Offset, Offset)? gap(int i, double t, double len) {
      final a = m[i], b = m[(i + 1) % n];
      final wl = room.walls[i];
      if (wl < 1.3) return null;
      final l = math.min(len, wl * 0.6) / wl; // fraction of the wall
      final c = t.clamp(l / 2 + 0.08, 1 - l / 2 - 0.08).toDouble();
      return (Offset.lerp(a, b, c - l / 2)!, Offset.lerp(a, b, c + l / 2)!);
    }

    final door = showOpenings ? gap(doorWall, 0.28, 0.9) : null;
    final windows = <(Offset, Offset, int)>[
      for (final i in windowWalls)
        if (gap(i, 0.5, 1.3) case final g?) (g.$1, g.$2, i),
    ];

    // 4) walls (openings are cut out of them)
    canvas.saveLayer(box.inflate(wt * 2), Paint());
    canvas.drawPath(
      path,
      Paint()..color = _wall..style = PaintingStyle.stroke..strokeWidth = wt..strokeJoin = StrokeJoin.miter..strokeMiterLimit = 10,
    );
    final cut = Paint()..blendMode = BlendMode.clear..strokeWidth = wt + 4..strokeCap = StrokeCap.butt;
    if (door != null) canvas.drawLine(door.$1, door.$2, cut);
    for (final g in windows) {
      canvas.drawLine(g.$1, g.$2, cut);
    }
    canvas.restore();

    // 5) door leaf and swing, window glass
    if (door != null) {
      final a = door.$1, b = door.$2;
      final nrm = inward(m[doorWall], m[(doorWall + 1) % n]);
      final len = (b - a).distance;
      final leafEnd = a + nrm * len;
      canvas.drawLine(a, leafEnd, Paint()..color = const Color(0xFF3A3A3A)..strokeWidth = 2.6..strokeCap = StrokeCap.round);
      final a0 = math.atan2((b - a).dy, (b - a).dx), a1 = math.atan2(nrm.dy, nrm.dx);
      var sweep = a1 - a0;
      while (sweep > math.pi) {
        sweep -= 2 * math.pi;
      }
      while (sweep < -math.pi) {
        sweep += 2 * math.pi;
      }
      canvas.drawArc(Rect.fromCircle(center: a, radius: len), a0, sweep, false, Paint()..color = const Color(0x99333333)..style = PaintingStyle.stroke..strokeWidth = 1.3);
    }
    for (final g in windows) {
      final nrm = inward(m[g.$3], m[(g.$3 + 1) % n]);
      canvas.drawLine(g.$1, g.$2, Paint()..color = const Color(0xFFD3E8F7)..strokeWidth = wt * 0.7);
      for (final k in [-wt * 0.3, 0.0, wt * 0.3]) {
        canvas.drawLine(g.$1 + nrm * k, g.$2 + nrm * k, Paint()..color = const Color(0xFF7FA9C9)..strokeWidth = 1.2);
      }
      canvas.drawLine(g.$1 - nrm * wt * 0.4, g.$1 + nrm * wt * 0.4, Paint()..color = _wall..strokeWidth = 2);
      canvas.drawLine(g.$2 - nrm * wt * 0.4, g.$2 + nrm * wt * 0.4, Paint()..color = _wall..strokeWidth = 2);
    }

    // 6) wall lengths (outside), area (centre)
    final centroid = m.reduce((a, b) => a + b) / n.toDouble();
    for (var i = 0; i < n; i++) {
      final a = m[i], b = m[(i + 1) % n];
      final out = -inward(a, b) * (wt / 2 + 16);
      _pill(canvas, '${room.walls[i].toStringAsFixed(2)} m', (a + b) / 2 + out, size: 11.5);
    }
    _pill(canvas, '${room.area.toStringAsFixed(1)} m²', centroid, size: 18, w: FontWeight.w800);

    // 7) scale bar
    final bar = scale.clamp(20.0, 160.0).toDouble();
    final y = size.height - 22;
    final p = Paint()..color = kNavy..strokeWidth = 2;
    canvas.drawLine(Offset(16, y), Offset(16 + bar, y), p);
    canvas.drawLine(Offset(16, y - 5), Offset(16, y + 5), p);
    canvas.drawLine(Offset(16 + bar, y - 5), Offset(16 + bar, y + 5), p);
    final tp = TextPainter(
      text: const TextSpan(text: '1 m', style: TextStyle(fontSize: 11, color: kNavy, fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(16 + bar + 8, y - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant FloorPlanPainter old) => old.room != room || old.showOpenings != showOpenings;
}