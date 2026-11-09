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

/// Adds a simple, box-based furniture set sized to fit inside the room's bounding
/// box, picked from [roomName] (falls back to a bedroom set, the app's main use case).
/// Too-small rooms (e.g. a scanned closet or bathroom) are left empty.
void _addAutoFurniture(
  RoomData r,
  String? roomName,
  int Function(_Mat) addMat,
  void Function(double cx, double cy, double cz, double hx, double hy, double hz, int mat, {double rotY}) addBox,
) {
  final xs = r.corners.map((c) => c[0]).toList(), zs = r.corners.map((c) => c[1]).toList();
  final minX = xs.reduce(math.min), maxX = xs.reduce(math.max);
  final minZ = zs.reduce(math.min), maxZ = zs.reduce(math.max);
  final w = maxX - minX, d = maxZ - minZ;
  if (w < 2.0 || d < 2.0 || r.area < 5.5) return; // too small/odd-shaped: leave it empty
  if (r.area < 0.95 * w * d) return; // L-shaped etc.: the furniture would stick out of the room

  void bAt(double cx, double baseY, double cz, double hx, double hy, double hz, int mat, {double rotY = 0}) =>
      addBox(cx, baseY + hy, cz, hx, hy, hz, mat, rotY: rotY);

  final name = (roomName ?? '').toLowerCase();
  final nonBedroom =
      ['kitchen', 'living', 'hall', 'lounge', 'office', 'study', 'studio', 'bath', 'wash', 'toilet', 'balcony'].any(name.contains);

  // Rug (every room type gets this small touch).
  final rug = addMat(const _Mat('Rug', [0.74, 0.47, 0.44, 1.0], roughness: 0.95));

  if (nonBedroom) {
    bAt((minX + maxX) / 2, 0.001, (minZ + maxZ) / 2, math.min(1.4, w * 0.3), 0.01, math.min(1.0, d * 0.25), rug);
    return;
  }

  // ---- bedroom set -------------------------------------------------------
  final bedFrame = addMat(const _Mat('BedFrame', [0.24, 0.14, 0.08, 1.0], roughness: 0.5));
  final mattress = addMat(const _Mat('Mattress', [0.93, 0.90, 0.82, 1.0], roughness: 0.95));
  final blanket = addMat(const _Mat('Blanket', [0.20, 0.33, 0.55, 1.0], roughness: 0.85));
  final pillow = addMat(const _Mat('Pillow', [0.97, 0.97, 0.95, 1.0], roughness: 0.9));
  final nightstandWood = addMat(const _Mat('NightstandWood', [0.42, 0.28, 0.16, 1.0], roughness: 0.55));
  final wardrobeWood = addMat(const _Mat('WardrobeWood', [0.55, 0.38, 0.22, 1.0], roughness: 0.5));

  final cx = (minX + maxX) / 2;
  final bedW = math.min(1.6, w * 0.6); // along x
  final bedL = math.min(2.0, d * 0.55); // along z
  final gap = 0.10;
  final headZ = minZ + gap; // wall-side edge of the bed
  final bedCenterZ = headZ + bedL / 2;

  bAt(cx, 0, bedCenterZ, bedW / 2, 0.125, bedL / 2, bedFrame); // frame/base
  bAt(cx, 0.25, bedCenterZ, bedW / 2 - 0.03, 0.125, bedL / 2 - 0.03, mattress); // mattress
  bAt(cx, 0, headZ + 0.04, bedW / 2 + 0.03, 0.5, 0.04, bedFrame); // headboard
  bAt(cx, 0.5, bedCenterZ + bedL * 0.12, bedW / 2 - 0.02, 0.05, bedL * 0.33, blanket); // blanket (foot half)
  bAt(cx - bedW / 4, 0.5, headZ + 0.26, bedW / 8, 0.08, 0.18, pillow);
  bAt(cx + bedW / 4, 0.5, headZ + 0.26, bedW / 8, 0.08, 0.18, pillow);

  // Nightstands either side of the headboard, if there's room.
  final nsX = bedW / 2 + 0.25;
  if (cx - nsX - 0.2 > minX + 0.1) bAt(cx - nsX, 0, headZ + 0.2, 0.2, 0.25, 0.2, nightstandWood);
  if (cx + nsX + 0.2 < maxX - 0.1) bAt(cx + nsX, 0, headZ + 0.2, 0.2, 0.25, 0.2, nightstandWood);

  // Wardrobe along a side wall, opposite the bed's foot end.
  final wardrobeLen = math.min(1.6, d * 0.5);
  final wardrobeH = math.min(2.0, r.height - 0.15);
  if (wardrobeLen > 0.6 && (maxX - minX) > bedW + 1.2) {
    bAt(minX + 0.3, 0, maxZ - 0.25 - wardrobeLen / 2, 0.3, wardrobeH / 2, wardrobeLen / 2, wardrobeWood);
  }

  // Rug in front of the bed.
  bAt(cx, 0.001, bedCenterZ + bedL / 2 + 0.35, bedW / 2 + 0.15, 0.01, 0.45, rug);
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
  const _Mat(this.name, this.color, {this.metallic = 0.0, this.roughness = 0.9, this.doubleSided = true, this.blend = false, this.textured = false});
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
      opening(ws[order.first], 0.28, 0.9, true);
      for (final k in order.skip(1).take(n >= 4 ? 2 : 1)) {
        opening(ws[k], 0.5, 1.3, false);
      }
    }

    _addAutoFurniture(r, e.value, addMat, addBox);
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