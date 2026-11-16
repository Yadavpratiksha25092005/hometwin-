import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Room captured by the native ARCore scanner (see ScanActivity.kt).
/// Pure Dart (no Flutter imports) so it can be unit-tested.
class RoomData {
  /// Floor corners in metres, [x, z], relative to corner #1, in walking order.
  final List<List<double>> corners;
  final double height, area, perimeter, width, depth;
  final List<double> walls;

  const RoomData({
    required this.corners,
    required this.height,
    required this.area,
    required this.perimeter,
    required this.width,
    required this.depth,
    required this.walls,
  });

  static double _d(dynamic v) => (v as num).toDouble();

  factory RoomData.fromJson(Map<String, dynamic> j) => RoomData(
        corners: [
          for (final c in (j['corners'] as List)) [_d((c as List)[0]), _d(c[1])]
        ],
        height: _d(j['height']),
        area: _d(j['area_m2']),
        perimeter: _d(j['perimeter_m']),
        width: _d(j['width_m']),
        depth: _d(j['depth_m']),
        walls: [for (final w in (j['walls'] as List)) _d(w)],
      );

  /// Returns null when [meta] is not a room-scan meta map (e.g. an imported model).
  static RoomData? tryParse(dynamic meta) {
    try {
      if (meta is String) meta = jsonDecode(meta);
      if (meta is Map && meta['corners'] is List) {
        return RoomData.fromJson(Map<String, dynamic>.from(meta));
      }
    } catch (_) {}
    return null;
  }

  String get summary =>
      '${width.toStringAsFixed(1)} × ${depth.toStringAsFixed(1)} m • ${area.toStringAsFixed(1)} m² • h ${height.toStringAsFixed(1)} m';
}

// ------------------------------------------------------------------ triangulation

double _cross(List<double> a, List<double> b, List<double> c) =>
    (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0]);

bool _inTri(List<double> p, List<double> a, List<double> b, List<double> c) {
  double s(List<double> p1, List<double> p2, List<double> p3) =>
      (p1[0] - p3[0]) * (p2[1] - p3[1]) - (p2[0] - p3[0]) * (p1[1] - p3[1]);
  final d1 = s(p, a, b), d2 = s(p, b, c), d3 = s(p, c, a);
  final neg = d1 < -1e-9 || d2 < -1e-9 || d3 < -1e-9;
  final pos = d1 > 1e-9 || d2 > 1e-9 || d3 > 1e-9;
  return !(neg && pos);
}

/// Ear-clipping triangulation of a simple polygon given as [x, z] points.
List<int> triangulate(List<List<double>> p) {
  var idx = List<int>.generate(p.length, (i) => i);
  var a2 = 0.0;
  for (var i = 0; i < p.length; i++) {
    final j = (i + 1) % p.length;
    a2 += p[i][0] * p[j][1] - p[j][0] * p[i][1];
  }
  if (a2 < 0) idx = idx.reversed.toList(); // make CCW
  final out = <int>[];
  while (idx.length > 3) {
    var clipped = false;
    for (var i = 0; i < idx.length; i++) {
      final a = idx[(i - 1 + idx.length) % idx.length], b = idx[i], c = idx[(i + 1) % idx.length];
      if (_cross(p[a], p[b], p[c]) <= 1e-9) continue; // reflex / degenerate
      var inside = false;
      for (final k in idx) {
        if (k == a || k == b || k == c) continue;
        if (_inTri(p[k], p[a], p[b], p[c])) {
          inside = true;
          break;
        }
      }
      if (inside) continue;
      out.addAll([a, b, c]);
      idx.removeAt(i);
      clipped = true;
      break;
    }
    if (!clipped) break; // self-intersecting input: fall back to a fan below
  }
  if (idx.length == 3) {
    out.addAll(idx);
  } else {
    for (var i = 1; i + 1 < idx.length; i++) {
      out.addAll([idx[0], idx[i], idx[i + 1]]);
    }
  }
  return out;
}

// ------------------------------------------------------------------ auto-furniture

/// Furnishes the room with simple but detailed box-built furniture, chosen from [roomName]
/// (kitchen, living room / hall / studio, office / study, bathroom, else a bedroom - the app's
/// main use case). Every big piece gets a soft shadow on the floor. Too-small or L-shaped
/// rooms are left empty.
void _addAutoFurniture(
  RoomData r,
  String? roomName,
  int Function(_Mat) addMat,
  void Function(double cx, double cy, double cz, double hx, double hy, double hz, int mat, {double rotY}) addBox,
  void Function(double x, double z, double hx, double hz, double mg) addShadow,
) {
  final xs = r.corners.map((c) => c[0]).toList(), zs = r.corners.map((c) => c[1]).toList();
  final minX = xs.reduce(math.min), maxX = xs.reduce(math.max);
  final minZ = zs.reduce(math.min), maxZ = zs.reduce(math.max);
  final w = maxX - minX, d = maxZ - minZ, cx = (minX + maxX) / 2, height = r.height;
  if (w < 2.0 || d < 2.0 || r.area < 5.5) return; // too small: leave it empty
  if (r.area < 0.95 * w * d) return; // L-shaped etc.: the furniture would stick out of the room

  final nm = (roomName ?? '').toLowerCase();
  bool has(List<String> keys) => keys.any(nm.contains);

  int mat(String name, List<double> col, [double rough = 0.8, double metal = 0.0, List<double>? emit]) =>
      addMat(_Mat(name, col, roughness: rough, metallic: metal, emissive: emit));
  final woodD = mat('WoodDark', const [0.24, 0.14, 0.08, 1.0], 0.5);
  final woodM = mat('WoodMid', const [0.55, 0.38, 0.22, 1.0], 0.5);
  final woodL = mat('WoodLight', const [0.74, 0.57, 0.37, 1.0], 0.55);
  final cream = mat('Cream', const [0.93, 0.90, 0.83, 1.0], 0.95);
  final white = mat('PillowWhite', const [0.97, 0.97, 0.95, 1.0], 0.9);
  final blue = mat('FabricBlue', const [0.20, 0.33, 0.55, 1.0], 0.85);
  final grey = mat('FabricGrey', const [0.46, 0.47, 0.51, 1.0], 0.9);
  final greyL = mat('FabricGreyLight', const [0.58, 0.59, 0.62, 1.0], 0.9);
  final metal = mat('Metal', const [0.78, 0.79, 0.80, 1.0], 0.3, 0.9);
  final black = mat('Black', const [0.06, 0.06, 0.07, 1.0], 0.3);
  final leaf = mat('Leaf', const [0.22, 0.46, 0.22, 1.0], 0.8);
  final pot = mat('Pot', const [0.70, 0.45, 0.30, 1.0], 0.7);
  final shade = mat('LampShade', const [1.0, 0.92, 0.75, 1.0], 0.9, 0.0, const [0.9, 0.7, 0.4]);
  final rugD = mat('RugDark', const [0.58, 0.47, 0.44, 1.0], 0.95);
  final rugL = mat('RugLight', const [0.74, 0.63, 0.58, 1.0], 0.95);
  final cab = mat('Cabinet', const [0.93, 0.93, 0.90, 1.0], 0.6);
  final top = mat('Countertop', const [0.16, 0.16, 0.17, 1.0], 0.4);
  final steel = mat('Steel', const [0.80, 0.82, 0.85, 1.0], 0.35, 0.8);
  final seam = mat('Seam', const [0.35, 0.35, 0.35, 1.0], 0.8);

  /// Box standing on height [by] (its bottom), centre (x, z), half-sizes (hx, hy, hz).
  void box(int m, double x, double by, double z, double hx, double hy, double hz, [double rot = 0]) =>
      addBox(x, by + hy, z, hx, hy, hz, m, rotY: rot);
  void shadow(double x, double z, double hx, double hz, [double mg = 0.16]) => addShadow(x, z, hx, hz, mg);
  void rug(double x, double z, double hx, double hz) {
    final rx = math.min(hx, (maxX - minX) / 2 - 0.1);
    final rz = math.max(math.min(z, maxZ - hz - 0.05), minZ + hz + 0.05);
    box(rugD, x, 0.001, rz, rx, 0.008, hz);
    box(rugL, x, 0.009, rz, rx - 0.08, 0.006, hz - 0.08);
  }

  void plant(double x, double z) {
    box(pot, x, 0, z, 0.14, 0.15, 0.14);
    box(leaf, x, 0.3, z, 0.22, 0.28, 0.22);
    box(leaf, x, 0.3, z, 0.22, 0.28, 0.22, 0.785);
    shadow(x, z, 0.2, 0.2, 0.1);
  }

  if (has(['kitchen'])) {
    final lk = math.min(w - 0.7, 4.2), x0 = minX + 0.1, xk = x0 + lk / 2, zk = minZ + 0.4;
    box(cab, xk, 0, zk, lk / 2, 0.44, 0.3);
    shadow(xk, zk, lk / 2, 0.3, 0.12);
    box(top, xk, 0.88, zk, lk / 2 + 0.01, 0.02, 0.32);
    final n = math.max((lk / 0.6).floor(), 1);
    for (var i = 1; i < n; i++) {
      box(seam, x0 + i * lk / n, 0.05, zk + 0.301, 0.004, 0.38, 0.002); // cabinet door gaps
    }
    for (var i = 0; i < n; i++) {
      box(metal, x0 + (i + 0.5) * lk / n + 0.18, 0.7, zk + 0.31, 0.012, 0.05, 0.006); // handles
    }
    if (height >= 2.4) {
      box(cab, xk, 1.45, minZ + 0.275, lk / 2, 0.3, 0.175); // wall cabinets
      for (var i = 1; i < n; i++) {
        box(seam, x0 + i * lk / n, 1.18, minZ + 0.452, 0.004, 0.28, 0.002);
      }
    }
    box(steel, x0 + lk * 0.30, 0.9, zk, 0.25, 0.005, 0.2); // sink
    box(metal, x0 + lk * 0.30, 0.92, zk - 0.2, 0.02, 0.1, 0.02); // tap
    box(black, x0 + lk * 0.70, 0.9, zk, 0.3, 0.005, 0.25); // hob
    for (final o in const [
      [-0.12, -0.08],
      [0.12, -0.08],
      [-0.12, 0.08],
      [0.12, 0.08]
    ]) {
      box(seam, x0 + lk * 0.70 + o[0], 0.905, zk + o[1], 0.05, 0.004, 0.05);
    }
    final fx = maxX - 0.45; // fridge
    box(steel, fx, 0, minZ + 0.45, 0.35, 0.9, 0.35);
    shadow(fx, minZ + 0.45, 0.35, 0.35, 0.12);
    box(seam, fx, 0.9, minZ + 0.805, 0.34, 0.003, 0.002);
    box(metal, fx - 0.26, 0.9, minZ + 0.82, 0.012, 0.25, 0.012);
    if (d >= 3.4 && w >= 3) {
      final tz = maxZ - 1.0; // dining table + 4 stools
      box(woodL, cx, 0.72, tz, 0.6, 0.025, 0.4);
      for (final sx in const [-1, 1]) {
        for (final sz in const [-1, 1]) {
          box(woodD, cx + sx * 0.55, 0, tz + sz * 0.35, 0.03, 0.36, 0.03);
        }
      }
      shadow(cx, tz, 0.6, 0.4, 0.14);
      for (final sx in const [-1, 1]) {
        for (final sz in const [-1, 1]) {
          final px = cx + sx * 0.3, pz = tz + sz * 0.62;
          box(woodM, px, 0.43, pz, 0.19, 0.02, 0.19);
          box(woodM, px, 0, pz, 0.02, 0.21, 0.02);
          shadow(px, pz, 0.19, 0.19, 0.08);
        }
      }
    }
    if (d >= 3) plant(maxX - 0.3, maxZ - 0.3);
  } else if (has(['living', 'hall', 'lounge', 'studio'])) {
    final sl = math.min(2.2, w * 0.55), zc = minZ + 0.6, dd = 0.45; // sofa length, centre z, half depth
    for (final sx in const [-1, 1]) {
      for (final sz in const [-1, 1]) {
        box(woodD, cx + sx * (sl / 2 - 0.08), 0, zc + sz * (dd - 0.08), 0.03, 0.08, 0.03); // legs
      }
    }
    box(grey, cx, 0.08, zc, sl / 2, 0.17, dd);
    shadow(cx, zc, sl / 2, dd, 0.16);
    box(grey, cx, 0.25, minZ + 0.22, sl / 2, 0.30, 0.12); // back
    for (final sx in const [-1, 1]) {
      box(grey, cx + sx * (sl / 2 - 0.1), 0.25, zc, 0.1, 0.2, dd); // arms
    }
    for (var i = 0; i < 3; i++) {
      final xi = cx + (i - 1) * (sl - 0.4) / 3;
      box(greyL, xi, 0.25, zc + 0.07, (sl - 0.4) / 6 - 0.01, 0.08, 0.34); // seat cushions
      box(greyL, xi, 0.43, minZ + 0.38, (sl - 0.4) / 6 - 0.02, 0.17, 0.07); // back cushions
    }
    box(blue, cx - sl / 2 + 0.35, 0.33, zc + 0.05, 0.17, 0.17, 0.07, 0.3); // scatter cushion
    final tz = math.min(zc + 1.25, maxZ - 0.7); // coffee table
    box(woodL, cx, 0.36, tz, 0.55, 0.025, 0.3);
    for (final sx in const [-1, 1]) {
      for (final sz in const [-1, 1]) {
        box(woodD, cx + sx * 0.5, 0, tz + sz * 0.25, 0.025, 0.18, 0.025);
      }
    }
    shadow(cx, tz, 0.55, 0.3, 0.12);
    rug(cx, (zc + tz) / 2 + 0.1, sl / 2 + 0.15, (tz - zc) / 2 + 0.75);
    if (d >= 3.4) {
      final uz = maxZ - 0.28, uw = math.min(1.0, w * 0.3); // TV unit + TV
      box(woodD, cx, 0, uz, uw, 0.22, 0.2);
      shadow(cx, uz, uw, 0.2, 0.12);
      box(black, cx, 0.46, uz, 0.62, 0.34, 0.02);
      box(black, cx, 0.44, uz, 0.12, 0.03, 0.1);
    }
    plant(maxX - 0.3, minZ + 0.3);
  } else if (has(['office', 'study'])) {
    final zd = minZ + 0.5;
    box(woodL, cx, 0.72, zd, 0.8, 0.025, 0.35); // desk
    for (final sx in const [-1, 1]) {
      box(woodM, cx + sx * 0.75, 0, zd, 0.025, 0.36, 0.33);
    }
    shadow(cx, zd, 0.8, 0.35, 0.14);
    box(black, cx, 0.745, zd - 0.1, 0.28, 0.17, 0.012); // monitor
    box(black, cx, 0.745, zd - 0.1, 0.03, 0.02, 0.04);
    box(black, cx, 0.745, zd + 0.12, 0.18, 0.008, 0.07); // keyboard
    final chz = zd + 0.85; // chair
    box(grey, cx, 0.45, chz, 0.22, 0.03, 0.22);
    box(grey, cx, 0.5, chz - 0.2, 0.22, 0.25, 0.03);
    box(black, cx, 0.0, chz, 0.03, 0.22, 0.03);
    box(black, cx, 0, chz, 0.22, 0.03, 0.22);
    shadow(cx, chz, 0.25, 0.25, 0.1);
    final bx = minX + 0.22, bz = (minZ + maxZ) / 2; // bookshelf
    box(woodD, bx, 0, bz, 0.2, 1.0, 0.7);
    shadow(bx, bz, 0.2, 0.7, 0.1);
    final books = [blue, leaf, woodM, cream];
    for (var k = 0; k < books.length; k++) {
      for (var j = 0; j < 4; j++) {
        box(books[k], bx + 0.205, 0.12 + k * 0.45, bz - 0.55 + j * 0.28, 0.003, 0.2, 0.1);
      }
    }
    rug(cx, chz - 0.2, 0.9, 0.7);
    plant(maxX - 0.3, maxZ - 0.3);
  } else if (has(['bath', 'wash', 'toilet', 'balcony'])) {
    rug(cx, (minZ + maxZ) / 2, math.min(0.8, w * 0.25), math.min(0.5, d * 0.2));
    plant(maxX - 0.3, maxZ - 0.3);
  } else {
    // ---- bedroom (default)
    final bedW = math.min(1.6, w * 0.6), bedL = math.min(2.0, d * 0.55);
    final headZ = minZ + 0.1, bcz = headZ + bedL / 2;
    for (final sx in const [-1, 1]) {
      for (final sz in const [-1, 1]) {
        box(woodD, cx + sx * (bedW / 2 - 0.05), 0, bcz + sz * (bedL / 2 - 0.05), 0.03, 0.08, 0.03); // legs
      }
    }
    box(woodD, cx, 0.08, bcz, bedW / 2, 0.1, bedL / 2); // frame
    shadow(cx, bcz, bedW / 2, bedL / 2, 0.2);
    box(cream, cx, 0.28, bcz, bedW / 2 - 0.03, 0.11, bedL / 2 - 0.03); // mattress
    box(blue, cx, 0.5, bcz + bedL * 0.14, bedW / 2 - 0.02, 0.05, bedL * 0.36); // duvet
    for (final sx in const [-1, 1]) {
      box(blue, cx + sx * (bedW / 2 - 0.025), 0.30, bcz + bedL * 0.14, 0.012, 0.22, bedL * 0.36); // duvet sides
    }
    box(greyL, cx, 0.55, bcz + bedL * 0.33, bedW / 2 - 0.05, 0.015, 0.17); // throw
    box(woodD, cx, 0.08, headZ + 0.04, bedW / 2 + 0.04, 0.5, 0.04); // headboard
    box(woodM, cx, 0.3, headZ + 0.085, bedW / 2 - 0.04, 0.3, 0.01);
    for (final sx in const [-1, 1]) {
      box(white, cx + sx * bedW / 4, 0.5, headZ + 0.28, bedW / 8 + 0.03, 0.07, 0.17); // pillows
    }
    final nsx = bedW / 2 + 0.28;
    for (final sx in const [-1, 1]) {
      final x = cx + sx * nsx;
      if (sx < 0 && !(x - 0.22 > minX + 0.05)) continue;
      if (sx > 0 && !(x + 0.22 < maxX - 0.05)) continue;
      box(woodM, x, 0, headZ + 0.2, 0.22, 0.26, 0.2); // nightstand
      box(woodD, x, 0.52, headZ + 0.2, 0.24, 0.015, 0.22);
      shadow(x, headZ + 0.2, 0.22, 0.2, 0.1);
      box(woodD, x, 0.30, headZ + 0.405, 0.18, 0.1, 0.004); // drawer front
      box(metal, x, 0.34, headZ + 0.41, 0.05, 0.012, 0.008);
      box(metal, x, 0.535, headZ + 0.2, 0.03, 0.07, 0.03); // lamp
      box(shade, x, 0.6, headZ + 0.2, 0.09, 0.07, 0.09);
    }
    final wl = math.min(1.6, d * 0.5), wh = math.min(2.0, height - 0.15);
    if (wl > 0.6 && w > bedW + 1.2) {
      final wz = maxZ - 0.25 - wl / 2; // wardrobe on the left wall
      box(woodM, minX + 0.3, 0, wz, 0.3, wh / 2, wl / 2);
      shadow(minX + 0.3, wz, 0.3, wl / 2, 0.12);
      box(seam, minX + 0.601, 0.05, wz, 0.002, wh / 2 - 0.05, 0.004);
      for (final sz in const [-1, 1]) {
        box(metal, minX + 0.61, wh / 2, wz + sz * 0.1, 0.01, 0.1, 0.01);
      }
    }
    rug(cx, bcz + bedL / 2 + 0.15, bedW / 2 + 0.35, 0.8);
    plant(maxX - 0.3, maxZ - 0.3);
  }
}

// ------------------------------------------------------------------ GLB

/// Floor texture (wood planks, assets/models/wood_floor.jpg). It is loaded once at app start
/// (see main.dart); without it the floor is simply a plain wood colour.
class RoomTextures {
  static Uint8List? wood;
}

/// One PBR material used by the generated room/furniture mesh.
class _Mat {
  final String name;
  final List<double> color; // rgba 0..1
  final double metallic, roughness;
  final bool doubleSided, blend, textured;
  final List<double>? emissive; // glowing colour (lamp shades)
  const _Mat(this.name, this.color, {this.metallic = 0.0, this.roughness = 0.9, this.doubleSided = true, this.blend = false, this.textured = false, this.emissive});
}

/// Vertex data of everything that uses one material.
class _Prim {
  final pos = <double>[], uv = <double>[], col = <double>[];
  final idx = <int>[];
}

/// A wall of the room: start point, length, direction (u) and inward normal (n), all in the XZ plane.
class _Wall {
  final double ax, az, len, ux, uz, nx, nz;
  const _Wall(this.ax, this.az, this.len, this.ux, this.uz, this.nx, this.nz);
}

/// Builds a binary glTF (.glb) for ONE room: wooden floor, full-height painted walls with a
/// skirting board, a door and windows, soft shadows along the walls, and optional auto-furniture.
///
/// "Dollhouse" trick: the walls are single-sided and face INWARD, so the walls between the
/// camera and the room disappear automatically while you rotate the model. Y-up, metres.
Uint8List buildRoomGlb(RoomData r, {String? roomName}) => _buildGlb([MapEntry(r, roomName)]);

/// Combines several scanned rooms into ONE model. The rooms are auto-arranged side by side
/// in rows (with a small gap), so the positions are NOT the real positions in the house.
Uint8List buildHouseGlb(List<MapEntry<RoomData, String?>> rooms) {
  const rowMax = 16.0; // start a new row after this width (metres)
  const gap = 0.6; // space between rooms (metres)
  final placed = <MapEntry<RoomData, String?>>[];
  var x = 0.0, z = 0.0, rowDepth = 0.0;
  for (final e in rooms) {
    final r = e.key;
    final xs = r.corners.map((c) => c[0]).toList(), zs = r.corners.map((c) => c[1]).toList();
    final minX = xs.reduce(math.min), maxX = xs.reduce(math.max);
    final minZ = zs.reduce(math.min), maxZ = zs.reduce(math.max);
    final w = maxX - minX, d = maxZ - minZ;
    if (x > 0 && x + w > rowMax) {
      x = 0;
      z += rowDepth + gap;
      rowDepth = 0;
    }
    final ox = x - minX, oz = z - minZ;
    placed.add(MapEntry(
      RoomData(
        corners: [
          for (final c in r.corners) [c[0] + ox, c[1] + oz]
        ],
        height: r.height,
        area: r.area,
        perimeter: r.perimeter,
        width: r.width,
        depth: r.depth,
        walls: r.walls,
      ),
      e.value,
    ));
    x += w + gap;
    rowDepth = math.max(rowDepth, d);
  }
  return _buildGlb(placed);
}

Uint8List _buildGlb(List<MapEntry<RoomData, String?>> rooms) {
  final wood = RoomTextures.wood;
  final materials = <_Mat>[];
  final prims = <_Prim>[];
  final byName = <String, int>{};

  int addMat(_Mat m) {
    final known = byName[m.name];
    if (known != null) return known;
    materials.add(m);
    prims.add(_Prim());
    byName[m.name] = materials.length - 1;
    return materials.length - 1;
  }

  /// Adds one quad (4 corners, counter-clockwise when seen from the FRONT side).
  void quad(int m, List<List<double>> v, {List<List<double>>? uv, List<List<double>>? col}) {
    final p = prims[m];
    final b = p.pos.length ~/ 3;
    for (final q in v) {
      p.pos.addAll(q);
    }
    if (uv != null) {
      for (final u in uv) {
        p.uv.addAll(u);
      }
    }
    if (col != null) {
      for (final c in col) {
        p.col.addAll(c);
      }
    }
    p.idx.addAll([b, b + 1, b + 2, b, b + 2, b + 3]);
  }

  /// Axis-aligned (optionally Y-rotated) box. Centre (cx,cy,cz), half-extents (hx,hy,hz).
  void addBox(double cx, double cy, double cz, double hx, double hy, double hz, int mat, {double rotY = 0}) {
    final cs = math.cos(rotY), sn = math.sin(rotY);
    List<double> v(int sx, int sy, int sz) {
      final x = sx * hx, z = sz * hz;
      return [cx + x * cs - z * sn, cy + sy * hy, cz + x * sn + z * cs];
    }

    void f(List<int> a, List<int> b, List<int> c, List<int> d) =>
        quad(mat, [v(a[0], a[1], a[2]), v(b[0], b[1], b[2]), v(c[0], c[1], c[2]), v(d[0], d[1], d[2])]);

    f([-1, -1, 1], [1, -1, 1], [1, 1, 1], [-1, 1, 1]); // +z
    f([1, -1, -1], [-1, -1, -1], [-1, 1, -1], [1, 1, -1]); // -z
    f([1, -1, 1], [1, -1, -1], [1, 1, -1], [1, 1, 1]); // +x
    f([-1, -1, -1], [-1, -1, 1], [-1, 1, 1], [-1, 1, -1]); // -x
    f([-1, 1, 1], [1, 1, 1], [1, 1, -1], [-1, 1, -1]); // top
    f([-1, -1, -1], [1, -1, -1], [1, -1, 1], [-1, -1, 1]); // bottom
  }

  for (final e in rooms) {
    final r = e.key;
    var c = [
      for (final p in r.corners) [p[0], p[1]]
    ];
    var s = 0.0;
    for (var i = 0; i < c.length; i++) {
      final a = c[i], b = c[(i + 1) % c.length];
      s += a[0] * b[1] - b[0] * a[1];
    }
    if (s < 0) c = c.reversed.toList(); // inside is now always on the left of each wall
    final n = c.length;
    final h = r.height;

    final floor = addMat(_Mat('Floor', wood != null ? const [1.0, 1.0, 1.0, 1.0] : const [0.50, 0.33, 0.17, 1.0], roughness: 0.6, textured: wood != null));
    final wall = addMat(const _Mat('Walls', [0.94, 0.92, 0.88, 1.0], roughness: 0.95, doubleSided: false));
    final trim = addMat(const _Mat('Baseboard', [0.97, 0.97, 0.95, 1.0], roughness: 0.6, doubleSided: false));
    final cap = addMat(const _Mat('WallTop', [0.20, 0.20, 0.23, 1.0], roughness: 0.7));
    final ao = addMat(const _Mat('AO', [0.0, 0.0, 0.0, 1.0], roughness: 1.0, blend: true));
    final glass = addMat(const _Mat('Glass', [0.72, 0.86, 0.96, 1.0], roughness: 0.05, doubleSided: false));
    final frame = addMat(const _Mat('Frame', [0.96, 0.96, 0.94, 1.0], roughness: 0.5, doubleSided: false));
    final door = addMat(const _Mat('Door', [0.52, 0.35, 0.21, 1.0], roughness: 0.55, doubleSided: false));
    final knob = addMat(const _Mat('Knob', [0.85, 0.72, 0.35, 1.0], metallic: 0.9, roughness: 0.3));

    // floor: the texture tile covers 2.4 m x 1.2 m
    final fp = prims[floor];
    final fb = fp.pos.length ~/ 3;
    for (final p in c) {
      fp.pos.addAll([p[0], 0.0, p[1]]);
      if (wood != null) fp.uv.addAll([p[0] / 2.4, p[1] / 1.2]);
    }
    for (final t in triangulate(c)) {
      fp.idx.add(fb + t);
    }

    final ws = <_Wall>[];
    for (var i = 0; i < n; i++) {
      final a = c[i], b = c[(i + 1) % n];
      final dx = b[0] - a[0], dz = b[1] - a[1];
      final len = math.sqrt(dx * dx + dz * dz);
      if (len < 1e-6) continue;
      final ux = dx / len, uz = dz / len;
      ws.add(_Wall(a[0], a[1], len, ux, uz, -uz, ux)); // inward normal = (-uz, ux)
    }

    /// Quad lying ON a wall, from t0 to t1 along it and y0 to y1 up, pushed [eps] into the room.
    void wquad(int m, _Wall w, double t0, double t1, double y0, double y1, double eps, {List<List<double>>? col}) {
      List<double> pt(double t, double y) => [w.ax + w.ux * t + w.nx * eps, y, w.az + w.uz * t + w.nz * eps];
      quad(m, [pt(t0, y0), pt(t1, y0), pt(t1, y1), pt(t0, y1)], col: col);
    }

    const g0 = [0.80, 0.78, 0.75, 1.0], g1 = [1.0, 1.0, 1.0, 1.0]; // a bit darker at the floor, lighter at the top
    for (final w in ws) {
      wquad(wall, w, 0, w.len, 0, h, 0, col: [g0, g0, g1, g1]);
      wquad(trim, w, 0, w.len, 0, 0.09, 0.012); // skirting board

      // top edge: gives the wall visible thickness when seen from above
      const t = 0.12;
      final ex = w.ax + w.ux * w.len, ez = w.az + w.uz * w.len;
      quad(cap, [
        [w.ax - w.ux * t, h, w.az - w.uz * t],
        [ex + w.ux * t, h, ez + w.uz * t],
        [ex + w.ux * t - w.nx * t, h, ez + w.uz * t - w.nz * t],
        [w.ax - w.ux * t - w.nx * t, h, w.az - w.uz * t - w.nz * t],
      ]);

      // soft contact shadow on the floor along the wall (fake ambient occlusion)
      const aoW = 0.55;
      const dark = [0.0, 0.0, 0.0, 0.40], clear = [0.0, 0.0, 0.0, 0.0];
      quad(ao, [
        [w.ax, 0.003, w.az],
        [ex, 0.003, ez],
        [ex + w.nx * aoW, 0.003, ez + w.nz * aoW],
        [w.ax + w.nx * aoW, 0.003, w.az + w.nz * aoW],
      ], col: [dark, dark, clear, clear]);
    }

    /// Soft shadow on the floor around a piece of furniture: a ring that fades out, plus a filled middle.
    void addShadow(double x, double z, double hx, double hz, double mg) {
      const dark = [0.0, 0.0, 0.0, 0.42], clear = [0.0, 0.0, 0.0, 0.0];
      const corner = [
        [-1, -1],
        [1, -1],
        [1, 1],
        [-1, 1]
      ];
      List<double> out(double px, double pz) => [px + (px > x ? mg : -mg), 0.004, pz + (pz > z ? mg : -mg)];
      for (var k = 0; k < 4; k++) {
        final a = corner[k], b = corner[(k + 1) % 4];
        final i0 = [x + a[0] * hx, 0.004, z + a[1] * hz], i1 = [x + b[0] * hx, 0.004, z + b[1] * hz];
        quad(ao, [i0, i1, out(i1[0], i1[2]), out(i0[0], i0[2])], col: [dark, dark, clear, clear]);
      }
      quad(ao, [
        [x - hx, 0.004, z - hz],
        [x + hx, 0.004, z - hz],
        [x + hx, 0.004, z + hz],
        [x - hx, 0.004, z + hz],
      ], col: [dark, dark, dark, dark]);
    }

    // door + windows painted on the walls (same rule as the 2D floor plan:
    // door on the longest wall, windows on the next longest walls)
    void opening(_Wall w, double tFrac, double length, bool isDoor) {
      if (w.len < 1.3) return;
      final ln = math.min(length, w.len * 0.6);
      final cc = (tFrac * w.len).clamp(ln / 2 + 0.08 * w.len, w.len - ln / 2 - 0.08 * w.len).toDouble();
      final t0 = cc - ln / 2, t1 = cc + ln / 2;
      const e = 0.01;
      if (isDoor) {
        final dh = math.min(2.05, h - 0.1);
        wquad(frame, w, t0 - 0.05, t1 + 0.05, 0, dh + 0.05, e);
        wquad(door, w, t0, t1, 0, dh, e * 2);
        addBox(w.ax + w.ux * (t1 - 0.1) + w.nx * 0.03, 1.0, w.az + w.uz * (t1 - 0.1) + w.nz * 0.03, 0.02, 0.02, 0.02, knob);
      } else {
        final y0 = math.min(0.9, h * 0.33), y1 = math.min(2.1, h - 0.25);
        final mid = (t0 + t1) / 2, ym = (y0 + y1) / 2;
        wquad(frame, w, t0 - 0.06, t1 + 0.06, y0 - 0.06, y1 + 0.06, e);
        wquad(glass, w, t0, t1, y0, y1, e * 2);
        wquad(frame, w, mid - 0.02, mid + 0.02, y0, y1, e * 3);
        wquad(frame, w, t0, t1, ym - 0.02, ym + 0.02, e * 3);
      }
    }

    if (ws.isNotEmpty) {
      final order = List<int>.generate(ws.length, (k) => k)..sort((a, b) => ws[b].len.compareTo(ws[a].len));
      final zmin = c.map((p) => p[1]).reduce(math.min);
      // the furniture stands along the wall with the smallest z, so the door is never put there
      bool onTop(int k) {
        final w = ws[k];
        return (w.az - zmin).abs() < 0.05 && ((w.az + w.uz * w.len) - zmin).abs() < 0.05;
      }

      final candidates = order.where((k) => !onTop(k)).toList();
      final doorK = candidates.isNotEmpty ? candidates.first : order.first;
      opening(ws[doorK], 0.12, 0.9, true);
      for (final k in order.where((k) => k != doorK).take(n >= 4 ? 2 : 1)) {
        opening(ws[k], 0.5, 1.3, false);
      }
    }

    _addAutoFurniture(r, e.value, addMat, addBox, addShadow);
  }

  // ------------------------------------------------------------ write the .glb
  final chunks = <Uint8List>[];
  final bufferViews = <Map<String, dynamic>>[];
  var pos = 0;
  int addView(Uint8List data, {int? target}) {
    final padded = (data.length + 3) & ~3;
    chunks.add(Uint8List(padded)..setAll(0, data));
    bufferViews.add({'buffer': 0, 'byteOffset': pos, 'byteLength': data.length, if (target != null) 'target': target});
    pos += padded;
    return bufferViews.length - 1;
  }

  Uint8List f32(List<double> v) {
    final b = ByteData(v.length * 4);
    for (var i = 0; i < v.length; i++) {
      b.setFloat32(i * 4, v[i], Endian.little);
    }
    return b.buffer.asUint8List();
  }

  Uint8List u32(List<int> v) {
    final b = ByteData(v.length * 4);
    for (var i = 0; i < v.length; i++) {
      b.setUint32(i * 4, v[i], Endian.little);
    }
    return b.buffer.asUint8List();
  }

  final accessors = <Map<String, dynamic>>[];
  final primitives = <Map<String, dynamic>>[];
  for (var m = 0; m < prims.length; m++) {
    final p = prims[m];
    if (p.idx.isEmpty) continue;
    final count = p.pos.length ~/ 3;
    final mn = [double.infinity, double.infinity, double.infinity];
    final mx = [-double.infinity, -double.infinity, -double.infinity];
    for (var i = 0; i < p.pos.length; i++) {
      final k = i % 3;
      mn[k] = math.min(mn[k], p.pos[i]);
      mx[k] = math.max(mx[k], p.pos[i]);
    }
    accessors.add({'bufferView': addView(f32(p.pos), target: 34962), 'componentType': 5126, 'count': count, 'type': 'VEC3', 'min': mn, 'max': mx});
    final attrs = <String, int>{'POSITION': accessors.length - 1};
    if (p.uv.isNotEmpty) {
      accessors.add({'bufferView': addView(f32(p.uv), target: 34962), 'componentType': 5126, 'count': count, 'type': 'VEC2'});
      attrs['TEXCOORD_0'] = accessors.length - 1;
    }
    if (p.col.isNotEmpty) {
      accessors.add({'bufferView': addView(f32(p.col), target: 34962), 'componentType': 5126, 'count': count, 'type': 'VEC4'});
      attrs['COLOR_0'] = accessors.length - 1;
    }
    accessors.add({'bufferView': addView(u32(p.idx), target: 34963), 'componentType': 5125, 'count': p.idx.length, 'type': 'SCALAR'});
    primitives.add({'attributes': attrs, 'indices': accessors.length - 1, 'material': m});
  }

  final materialsJson = <Map<String, dynamic>>[
    for (final mat in materials)
      {
        'name': mat.name,
        'doubleSided': mat.doubleSided,
        if (mat.blend) 'alphaMode': 'BLEND',
        if (mat.emissive != null) 'emissiveFactor': mat.emissive,
        'pbrMetallicRoughness': {
          'baseColorFactor': mat.color,
          'metallicFactor': mat.metallic,
          'roughnessFactor': mat.roughness,
          if (mat.textured) 'baseColorTexture': {'index': 0},
        },
      }
  ];

  final gltf = <String, dynamic>{
    'asset': {'version': '2.0', 'generator': 'HomeDigitalTwin room scan'},
    'scene': 0,
    'scenes': [
      {'nodes': [0]}
    ],
    'nodes': [
      {'mesh': 0, 'name': rooms.length > 1 ? 'House' : 'Room'}
    ],
    'meshes': [
      {'primitives': primitives}
    ],
    'materials': materialsJson,
  };
  if (wood != null) {
    final img = addView(wood);
    gltf['images'] = [
      {'bufferView': img, 'mimeType': 'image/jpeg'}
    ];
    gltf['samplers'] = [
      {'magFilter': 9729, 'minFilter': 9987, 'wrapS': 10497, 'wrapT': 10497}
    ];
    gltf['textures'] = [
      {'sampler': 0, 'source': 0}
    ];
  }
  gltf['accessors'] = accessors;
  gltf['bufferViews'] = bufferViews;
  gltf['buffers'] = [
    {'byteLength': pos}
  ];

  final binLen = pos;
  final bin = Uint8List(binLen);
  var off = 0;
  for (final ch in chunks) {
    bin.setAll(off, ch);
    off += ch.length;
  }

  final json = utf8.encode(jsonEncode(gltf));
  final jsonPad = ((json.length + 3) & ~3) - json.length;
  final jsonBytes = Uint8List(json.length + jsonPad)..setAll(0, json);
  for (var i = json.length; i < jsonBytes.length; i++) {
    jsonBytes[i] = 0x20; // pad JSON chunk with spaces
  }

  final total = 12 + 8 + jsonBytes.length + 8 + binLen;
  final out = ByteData(total);
  out.setUint32(0, 0x46546C67, Endian.little); // 'glTF'
  out.setUint32(4, 2, Endian.little);
  out.setUint32(8, total, Endian.little);
  out.setUint32(12, jsonBytes.length, Endian.little);
  out.setUint32(16, 0x4E4F534A, Endian.little); // 'JSON'
  final res = out.buffer.asUint8List();
  res.setAll(20, jsonBytes);
  final o = 20 + jsonBytes.length;
  out.setUint32(o, binLen, Endian.little);
  out.setUint32(o + 4, 0x004E4942, Endian.little); // 'BIN\0'
  res.setAll(o + 8, bin);
  return res;
}