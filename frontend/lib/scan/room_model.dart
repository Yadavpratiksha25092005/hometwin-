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

/// One PBR material used by the generated room/furniture mesh.
class _Mat {
  final String name;
  final List<double> color; // rgba 0..1
  final double metallic, roughness;
  const _Mat(this.name, this.color, {this.metallic = 0.0, this.roughness = 0.9});
}

/// Builds a binary glTF (.glb) for ONE room: floor + low dark walls + optional auto-furniture,
/// double-sided, Y-up, metres.
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
  final verts = <double>[];

  // ---- materials: 0=floor 1=walls 2=trim, then furniture materials appended below
  final materials = <_Mat>[
    const _Mat('Floor', [0.50, 0.33, 0.17, 1.0], roughness: 0.75), // warm wood
    const _Mat('Walls', [0.15, 0.15, 0.17, 1.0], roughness: 0.7), // dark low walls
    const _Mat('Trim', [0.14, 0.14, 0.16, 1.0], roughness: 0.6),
  ];
  // index lists per material (parallel to `materials`)
  final idxByMat = <List<int>>[<int>[], <int>[], <int>[]];

  int addMat(_Mat m) {
    materials.add(m);
    idxByMat.add(<int>[]);
    return materials.length - 1;
  }

  /// Adds an axis-aligned (optionally Y-rotated) box, each face with its own 4 verts
  /// so auto-computed normals come out flat/correct. Centre (cx,cy,cz), half-extents (hx,hy,hz).
  void addBox(double cx, double cy, double cz, double hx, double hy, double hz, int mat, {double rotY = 0}) {
    final cos = math.cos(rotY), sin = math.sin(rotY);
    List<double> rot(double x, double z) => [cx + x * cos - z * sin, cz + x * sin + z * cos];
    // local corners (x,y,z) of the 8 box vertices
    final c = <List<double>>[
      for (final sy in [-1, 1])
        for (final sx in [-1, 1])
          for (final sz in [-1, 1]) [sx * hx, cy + sy * hy, sz * hz]
    ];
    List<double> v(int sx, int sy, int sz) {
      final i = ((sy + 1) ~/ 2) * 4 + ((sx + 1) ~/ 2) * 2 + ((sz + 1) ~/ 2);
      final p = c[i];
      final xz = rot(p[0], p[2]);
      return [xz[0], p[1], xz[1]];
    }

    void face(List<double> a, List<double> b, List<double> cc, List<double> d) {
      final base = verts.length ~/ 3;
      verts.addAll([...a, ...b, ...cc, ...d]);
      idxByMat[mat].addAll([base, base + 1, base + 2, base, base + 2, base + 3]);
    }

    face(v(-1, -1, 1), v(1, -1, 1), v(1, 1, 1), v(-1, 1, 1)); // +z
    face(v(1, -1, -1), v(-1, -1, -1), v(-1, 1, -1), v(1, 1, -1)); // -z
    face(v(1, -1, 1), v(1, -1, -1), v(1, 1, -1), v(1, 1, 1)); // +x
    face(v(-1, -1, -1), v(-1, -1, 1), v(-1, 1, 1), v(-1, 1, -1)); // -x
    face(v(-1, 1, 1), v(1, 1, 1), v(1, 1, -1), v(-1, 1, -1)); // +y (top)
    face(v(-1, -1, -1), v(1, -1, -1), v(1, -1, 1), v(-1, -1, 1)); // -y (bottom)
  }

  // ---- every room: floor + walls + trim + furniture
  for (final e in rooms) {
    final r = e.key;
    final n = r.corners.length;

    final floorBase = verts.length ~/ 3;
    for (final c in r.corners) {
      verts.addAll([c[0], 0, c[1]]);
    }
    for (final t in triangulate(r.corners)) {
      idxByMat[0].add(floorBase + t);
    }

    // Low, thick, dark walls (cut-away look) so the inside of the room stays visible.
    const wallT = 0.12; // thickness (m)
    final wallH = math.min(0.35, r.height);
    var sa = 0.0; // sign tells which side of a wall is the inside
    for (var i = 0; i < n; i++) {
      final a = r.corners[i], b = r.corners[(i + 1) % n];
      sa += a[0] * b[1] - b[0] * a[1];
    }
    for (var i = 0; i < n; i++) {
      final a = r.corners[i], b = r.corners[(i + 1) % n];
      final dx = b[0] - a[0], dz = b[1] - a[1];
      final len = math.sqrt(dx * dx + dz * dz);
      if (len < 1e-6) continue;
      final nx = (sa > 0 ? dz : -dz) / len, nz = (sa > 0 ? -dx : dx) / len; // outward normal
      final wx = (a[0] + b[0]) / 2 + nx * wallT / 2, wz = (a[1] + b[1]) / 2 + nz * wallT / 2;
      addBox(wx, wallH / 2, wz, len / 2 + wallT / 2, wallH / 2, wallT / 2, 1, rotY: math.atan2(dz, dx));
    }

    _addAutoFurniture(r, e.value, addMat, addBox);
  }

  final mn = [double.infinity, double.infinity, double.infinity];
  final mx = [-double.infinity, -double.infinity, -double.infinity];
  for (var i = 0; i < verts.length; i++) {
    final k = i % 3;
    mn[k] = math.min(mn[k], verts[i]);
    mx[k] = math.max(mx[k], verts[i]);
  }

  int pad4(int v) => (v + 3) & ~3;
  final posBytes = verts.length * 4;

  // Lay out one index bufferView per non-empty material group, after the position buffer.
  final idxOff = <int>[];
  var cursor = posBytes;
  for (final idx in idxByMat) {
    idxOff.add(cursor);
    cursor += pad4(idx.length * 4); // Uint32 indices
  }
  final binLen = cursor;

  final bin = ByteData(binLen);
  for (var i = 0; i < verts.length; i++) {
    bin.setFloat32(i * 4, verts[i], Endian.little);
  }
  for (var m = 0; m < idxByMat.length; m++) {
    final idx = idxByMat[m];
    for (var i = 0; i < idx.length; i++) {
      bin.setUint32(idxOff[m] + i * 4, idx[i], Endian.little);
    }
  }

  // accessor 0 = positions; accessors 1..N = indices, one per material group (empty groups skipped)
  final accessors = <Map<String, dynamic>>[
    {'bufferView': 0, 'componentType': 5126, 'count': verts.length ~/ 3, 'type': 'VEC3', 'min': mn, 'max': mx},
  ];
  final bufferViews = <Map<String, dynamic>>[
    {'buffer': 0, 'byteOffset': 0, 'byteLength': posBytes, 'target': 34962},
  ];
  final primitives = <Map<String, dynamic>>[];
  final materialsJson = <Map<String, dynamic>>[];
  for (var m = 0; m < materials.length; m++) {
    final mat = materials[m];
    materialsJson.add({
      'name': mat.name,
      'doubleSided': true,
      'pbrMetallicRoughness': {
        'baseColorFactor': mat.color,
        'metallicFactor': mat.metallic,
        'roughnessFactor': mat.roughness,
      },
    });
    final idx = idxByMat[m];
    if (idx.isEmpty) continue;
    bufferViews.add({'buffer': 0, 'byteOffset': idxOff[m], 'byteLength': idx.length * 4, 'target': 34963});
    accessors.add({'bufferView': bufferViews.length - 1, 'componentType': 5125, 'count': idx.length, 'type': 'SCALAR'});
    primitives.add({
      'attributes': {'POSITION': 0},
      'indices': accessors.length - 1,
      'material': m,
    });
  }

  final gltf = {
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
    'accessors': accessors,
    'bufferViews': bufferViews,
    'buffers': [
      {'byteLength': binLen}
    ],
  };

  var json = utf8.encode(jsonEncode(gltf));
  final jsonPad = pad4(json.length) - json.length;
  final jsonBytes = Uint8List(json.length + jsonPad)..setAll(0, json);
  for (var i = json.length; i < jsonBytes.length; i++) {
    jsonBytes[i] = 0x20; // pad JSON chunk with spaces
  }

  final total = 12 + 8 + jsonBytes.length + 8 + binLen;
  final out = ByteData(total);
  var o = 0;
  out.setUint32(o, 0x46546C67, Endian.little); // 'glTF'
  out.setUint32(o + 4, 2, Endian.little);
  out.setUint32(o + 8, total, Endian.little);
  o = 12;
  out.setUint32(o, jsonBytes.length, Endian.little);
  out.setUint32(o + 4, 0x4E4F534A, Endian.little); // 'JSON'
  o += 8;
  final res = out.buffer.asUint8List();
  res.setAll(o, jsonBytes);
  o += jsonBytes.length;
  out.setUint32(o, binLen, Endian.little);
  out.setUint32(o + 4, 0x004E4942, Endian.little); // 'BIN\0'
  o += 8;
  res.setAll(o, bin.buffer.asUint8List());
  return res;
}