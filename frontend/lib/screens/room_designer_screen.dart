import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api.dart';
import '../main.dart';
import '../widgets/common.dart';

/// Room Designer
///  1. Take / pick a photo of your room.
///  2. Add any furniture you like as a photo (camera or gallery) - the server turns it into a 3D model.
///  3. Press & hold a piece in the tray and drag it onto the room photo (or just tap it).
///  4. Drag to move, pinch to resize, twist with two fingers to turn it.
/// Without a server (demo mode) the furniture photo itself is placed, and a few sample 3D pieces are included.

const _maxPlaced = 5; // every 3D piece is its own WebView, so keep it reasonable

class Furniture {
  final String id;
  String name;
  final String photo; // 'asset:...' or a local file path
  String status; // processing | ready | flat | failed
  String? jobId;
  String? model; // 'asset:...' | '/files/x.glb' (server) | local path
  int progress;
  final bool sample;

  Furniture({
    required this.id,
    required this.name,
    required this.photo,
    this.status = 'flat',
    this.jobId,
    this.model,
    this.progress = 0,
    this.sample = false,
  });

  bool get ready => status == 'ready' && model != null && model!.isNotEmpty;

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'photo': photo, 'status': status, 'jobId': jobId, 'model': model, 'progress': progress};

  factory Furniture.fromJson(Map<String, dynamic> j) => Furniture(
        id: '${j['id']}',
        name: '${j['name'] ?? 'Furniture'}',
        photo: '${j['photo'] ?? ''}',
        status: '${j['status'] ?? 'flat'}',
        jobId: j['jobId'] as String?,
        model: j['model'] as String?,
        progress: (j['progress'] as num?)?.toInt() ?? 0,
      );
}

/// Ready-made 3D pieces so the screen can be tried without any server.
final _samples = <Furniture>[
  Furniture(id: 's1', name: 'Modern Sofa', photo: 'asset:assets/images/demo/sofa1.jpg', status: 'ready', model: 'asset:assets/ar/modern_sofa.glb', sample: true),
  Furniture(id: 's2', name: 'L-Shaped Sofa', photo: 'asset:assets/images/demo/sofa2.jpg', status: 'ready', model: 'asset:assets/ar/l_sofa.glb', sample: true),
  Furniture(id: 's3', name: 'Leather Sofa', photo: 'asset:assets/images/demo/sofa3.jpg', status: 'ready', model: 'asset:assets/ar/leather_sofa.glb', sample: true),
  Furniture(id: 's4', name: 'Armchair', photo: 'asset:assets/ar/armchair.png', status: 'ready', model: 'asset:assets/ar/armchair.glb', sample: true),
  Furniture(id: 's5', name: 'Day Bed', photo: '', status: 'ready', model: 'asset:assets/ar/vintage_day_bed_1k-v1.glb', sample: true),
];

class _Placed {
  final String uid, fid;
  Offset c; // centre, as a fraction of the room photo (0..1)
  double w; // width, as a fraction of the room photo width
  double yaw; // degrees
  _Placed(this.uid, this.fid, this.c, this.w, [this.yaw = 0]);
}

double _clamp(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

class RoomDesignerScreen extends StatefulWidget {
  const RoomDesignerScreen({super.key});
  @override
  State<RoomDesignerScreen> createState() => _RoomDesignerScreenState();
}

class _RoomDesignerScreenState extends State<RoomDesignerScreen> {
  final _picker = ImagePicker();
  final _canvasKey = GlobalKey();
  final _mine = <Furniture>[];
  final _placed = <_Placed>[];
  final _web = <String, dynamic>{}; // uid -> WebViewController of that piece
  String? _room;
  String? _sel;
  Timer? _timer;
  bool _polling = false;
  double _gW = 0.3, _gYaw = 0; // values at the start of a pinch / twist

  String get _prefKey => 'designer_items_${Api.userName ?? ''}';

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------------ storage

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    try {
      final list = jsonDecode(p.getString(_prefKey) ?? '[]') as List;
      _mine
        ..clear()
        ..addAll(list.map((e) => Furniture.fromJson(Map<String, dynamic>.from(e as Map))));
    } catch (_) {}
    if (mounted) setState(() {});
    _poll();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_prefKey, jsonEncode(_mine.map((e) => e.toJson()).toList()));
  }

  Furniture? _find(String id) {
    for (final f in _mine) {
      if (f.id == id) return f;
    }
    for (final f in _samples) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// Asks the server how far the 3D jobs are.
  Future<void> _poll() async {
    if (_polling || !Api.remote) return;
    _polling = true;
    try {
      var changed = false;
      for (final f in _mine.where((e) => e.status == 'processing' && e.jobId != null).toList()) {
        try {
          final s = await Api.furnitureStatus(f.jobId!);
          final st = '${s['status']}';
          if (st == 'ready') {
            f.status = 'ready';
            f.model = '${s['model_url']}';
            f.progress = 100;
            changed = true;
            if (mounted) _snack('${f.name} is ready in 3D');
          } else if (st == 'failed') {
            f.status = 'failed';
            changed = true;
            if (mounted) _snack('${f.name}: ${s['error'] ?? '3D could not be made. Try a clearer photo.'}');
          } else {
            final pr = (s['progress'] as num?)?.toInt() ?? 0;
            if (pr != f.progress) {
              f.progress = pr;
              changed = true;
            }
          }
        } catch (_) {
          // network hiccup: try again on the next tick
        }
      }
      if (changed) {
        await _save();
        if (mounted) setState(() {});
      }
    } finally {
      _polling = false;
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  // ------------------------------------------------------------------ photos

  Future<ImageSource?> _sourceSheet(String title, String tip) => showModalBottomSheet<ImageSource>(
        context: context,
        showDragHandle: true,
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kNavy)),
              const SizedBox(height: 4),
              Text(tip, style: const TextStyle(fontSize: 13, color: Color(0xFF5A6785))),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined, color: kBlue),
                title: const Text('Take a photo'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined, color: kBlue),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ]),
          ),
        ),
      );

  Future<String?> _pick(ImageSource s, {required int maxSide}) async {
    try {
      final x = await _picker.pickImage(source: s, maxWidth: maxSide.toDouble(), maxHeight: maxSide.toDouble(), imageQuality: 88);
      return x?.path;
    } on PlatformException catch (e) {
      _snack('Could not open the ${s == ImageSource.camera ? 'camera' : 'gallery'}: ${e.message ?? e.code}');
      return null;
    }
  }

  Future<void> _pickRoom() async {
    final s = await _sourceSheet('Photo of your room', 'Stand back so the floor and walls are visible.');
    if (s == null) return;
    final path = await _pick(s, maxSide: 2000);
    if (path != null && mounted) setState(() => _room = path);
  }

  Future<String?> _askName() {
    final c = TextEditingController(text: 'Furniture ${_mine.length + 1}');
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Name this piece'),
        content: TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(hintText: 'e.g. Grey sofa')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text.trim().isEmpty ? 'Furniture' : c.text.trim()), child: const Text('Add')),
        ],
      ),
    );
  }

  /// Photo of any furniture the user likes -> tray item (+ 3D model from the server).
  Future<void> _addFurniture() async {
    final s = await _sourceSheet('Add furniture', 'Photograph or pick ONE piece (sofa, bed, chair...) with the whole item visible, on a plain background.');
    if (s == null) return;
    final path = await _pick(s, maxSide: 1280);
    if (path == null || !mounted) return;
    final name = await _askName();
    if (name == null) return;

    final dir = await getApplicationDocumentsDirectory(); // the picker's temp copy can be deleted by the system
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final saved = await File(path).copy('${dir.path}/furn_$id.jpg');
    final f = Furniture(id: id, name: name, photo: saved.path);
    setState(() => _mine.insert(0, f));

    String? note;
    try {
      final job = await Api.furnitureStart(saved.path);
      if (job != null) {
        f.jobId = job;
        f.status = 'processing';
        note = 'Making the 3D model... you can drop the photo into the room meanwhile.';
      } else {
        note = Api.remote
            ? 'Added. The server has no 3D service set up yet, so the photo is used.'
            : 'Added. 3D needs the server (demo mode), so the photo is used.';
      }
    } catch (e) {
      note = 'Added as a photo. 3D failed: ${'$e'.replaceFirst('Exception: ', '')}';
    }
    await _save();
    if (mounted) {
      setState(() {});
      _snack(note);
    }
  }

  Future<void> _deleteFurniture(Furniture f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Remove ${f.name}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _mine.remove(f);
      for (final p in _placed.where((p) => p.fid == f.id)) {
        _web.remove(p.uid);
      }
      _placed.removeWhere((p) => p.fid == f.id);
      if (_selected == null) _sel = null;
    });
    await _save();
  }

  // ------------------------------------------------------------------ placing / editing

  _Placed? get _selected {
    for (final p in _placed) {
      if (p.uid == _sel) return p;
    }
    return null;
  }

  /// Puts a piece on the room photo. [global] = where it was dropped (null = tap, goes to the middle).
  void _place(Furniture f, {Offset? global}) {
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (_room == null || box == null) {
      _snack('Add a photo of your room first');
      return;
    }
    if (_placed.length >= _maxPlaced) {
      _snack('You can place up to $_maxPlaced pieces. Remove one first.');
      return;
    }
    var c = const Offset(0.5, 0.68);
    if (global != null) {
      final l = box.globalToLocal(global);
      c = Offset(_clamp(l.dx / box.size.width, 0.05, 0.95), _clamp(l.dy / box.size.height, 0.05, 0.95));
    }
    final uid = '${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      _placed.add(_Placed(uid, f.id, c, 0.34));
      _sel = uid;
    });
    if (!f.ready) _snack('${f.name} is shown as a photo until its 3D model is ready.');
  }

  void _removePlaced(_Placed p) {
    setState(() {
      _placed.remove(p);
      _web.remove(p.uid);
      _sel = null;
    });
  }

  void _applyYaw(_Placed p) {
    final c = _web[p.uid];
    if (c == null) return;
    final js = "var m=document.querySelector('model-viewer'); if(m){m.orientation='0deg 0deg ${p.yaw.toStringAsFixed(0)}deg';}";
    Future<void>.sync(() => c.runJavaScript(js)).catchError((_) {});
  }

  void _turn(_Placed p, double deg) {
    setState(() => p.yaw = (p.yaw + deg) % 360);
    _applyYaw(p);
  }

  void _resize(_Placed p, double factor) => setState(() => p.w = _clamp(p.w * factor, 0.12, 0.9));

  String? _src(Furniture f) {
    final m = f.model;
    if (m == null || m.isEmpty) return null;
    if (m.startsWith('asset:')) return m.substring(6);
    if (Api.isServerPath(m)) return Api.fileUrl(m);
    return 'file://$m';
  }

  void _view3d(Furniture f) {
    final src = f.ready ? _src(f) : null;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SizedBox(
        height: 380,
        child: Column(children: [
          Text(f.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kNavy)),
          const SizedBox(height: 8),
          Expanded(
            child: src != null
                ? ModelViewer(src: src, alt: f.name, ar: false, autoRotate: true, cameraControls: true, backgroundColor: const Color(0xFFEFF3FA), shadowIntensity: 1, exposure: 1.05, environmentImage: 'neutral')
                : Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        f.status == 'processing' ? 'The 3D model is still being made (${f.progress}%).' : 'No 3D model for this piece.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFF5A6785)),
                      ),
                    ),
                  ),
          ),
        ]),
      ),
    );
  }

  void _help() => showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Room Designer'),
          content: const Text(
            '1. Add a photo of your room.\n'
            '2. Tap "Add photo" and take or pick a photo of any furniture you like. The app turns it into a 3D model.\n'
            '3. Press and hold a piece in the tray, then drag it onto your room (or just tap it).\n\n'
            'Drag to move  •  pinch to resize  •  twist with two fingers to turn  •  tap a piece for more options.',
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(children: [
            _header(),
            Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 8), child: _room == null ? _emptyRoom() : _canvas())),
            _selBar(),
            _tray(),
          ]),
        ),
      );

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
        child: Row(children: [
          IconButton(onPressed: () => Navigator.maybePop(context), icon: const Icon(Icons.arrow_back_rounded, color: kNavy)),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Room Designer', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kNavy)),
              Text('Drag furniture into your room photo', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Color(0xFF5A6785))),
            ]),
          ),
          if (_room != null) IconButton(tooltip: 'Change room photo', onPressed: _pickRoom, icon: const Icon(Icons.add_photo_alternate_outlined, color: kNavy)),
          IconButton(onPressed: _help, icon: const Icon(Icons.help_outline_rounded, color: kNavy)),
        ]),
      );

  Widget _emptyRoom() => Container(
        width: double.infinity,
        decoration: BoxDecoration(color: const Color(0xFFF4F6FA), borderRadius: BorderRadius.circular(16), border: Border.all(color: kBorder)),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.chair_outlined, size: 46, color: kBlue),
              const SizedBox(height: 12),
              const Text('Start with a photo of your room', textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kNavy)),
              const SizedBox(height: 6),
              const Text('Then drag sofas, beds and more into it to see how they look.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Color(0xFF5A6785))),
              const SizedBox(height: 16),
              FilledButton.icon(onPressed: _pickRoom, icon: const Icon(Icons.photo_camera_outlined), label: const Text('Add room photo')),
            ]),
          ),
        ),
      );

  Widget _canvas() => DragTarget<Furniture>(
        onAcceptWithDetails: (d) => _place(d.data, global: d.offset + const Offset(45, 45)), // 45 = half of the 90px drag preview
        builder: (context, over, _) => ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            key: _canvasKey,
            foregroundDecoration: over.isEmpty ? null : BoxDecoration(border: Border.all(color: kBlue, width: 3), borderRadius: BorderRadius.circular(16)),
            color: Colors.black12,
            child: LayoutBuilder(builder: (context, box) {
              final cs = box.biggest;
              return Stack(children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => setState(() => _sel = null),
                    child: Image.file(File(_room!), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined, size: 40))),
                  ),
                ),
                for (final p in _placed) _item(p, cs),
                if (_placed.isEmpty)
                  Positioned(
                    left: 12,
                    right: 12,
                    top: 12,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(14)),
                        child: const Text('Press & hold a piece below and drag it here', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
              ]);
            }),
          ),
        ),
      );

  Widget _item(_Placed p, Size cs) {
    final f = _find(p.fid);
    if (f == null) return const SizedBox.shrink();
    final w = p.w * cs.width, h = w * 0.85;
    final sel = _sel == p.uid;
    return Positioned(
      left: p.c.dx * cs.width - w / 2,
      top: p.c.dy * cs.height - h / 2,
      width: w,
      height: h,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _sel = p.uid),
        onScaleStart: (_) {
          _gW = p.w;
          _gYaw = p.yaw;
          setState(() => _sel = p.uid);
        },
        onScaleUpdate: (d) {
          setState(() {
            p.c = Offset(_clamp(p.c.dx + d.focalPointDelta.dx / cs.width, 0, 1), _clamp(p.c.dy + d.focalPointDelta.dy / cs.height, 0, 1));
            if (d.pointerCount > 1) {
              p.w = _clamp(_gW * d.scale, 0.12, 0.9);
              p.yaw = (_gYaw + d.rotation * 180 / math.pi) % 360;
            }
          });
          if (d.pointerCount > 1) _applyYaw(p);
        },
        child: Stack(fit: StackFit.expand, children: [
          _visual(p, f, w, h),
          if (sel) IgnorePointer(child: Container(decoration: BoxDecoration(border: Border.all(color: kBlue, width: 1.5), borderRadius: BorderRadius.circular(10)))),
        ]),
      ),
    );
  }

  Widget _visual(_Placed p, Furniture f, double w, double h) {
    final src = f.ready ? _src(f) : null;
    if (src != null) {
      return IgnorePointer(
        child: ModelViewer(
          key: ValueKey('${p.uid}|$src'),
          src: src,
          alt: f.name,
          id: 'mv',
          ar: false,
          autoRotate: false,
          cameraControls: false,
          disableZoom: true,
          backgroundColor: Colors.transparent,
          shadowIntensity: 1,
          shadowSoftness: 1,
          exposure: 1.05,
          environmentImage: 'neutral',
          onWebViewCreated: (c) {
            _web[p.uid] = c;
            Future.delayed(const Duration(milliseconds: 1500), () => _applyYaw(p));
          },
        ),
      );
    }
    // no 3D (yet): show the furniture photo
    return Stack(fit: StackFit.expand, children: [
      PhotoThumb(src: f.photo, w: w, h: h, radius: 10, fallback: Icons.chair_outlined),
      if (f.status == 'processing')
        Positioned(
          right: 4,
          top: 4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
              const SizedBox(width: 5),
              Text('3D ${f.progress}%', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
    ]);
  }

  Widget _selBar() {
    final p = _selected;
    final f = p == null ? null : _find(p.fid);
    if (p == null || f == null) return const SizedBox.shrink();
    Widget b(IconData i, String tip, VoidCallback onTap, {Color color = kNavy}) => IconButton(
          tooltip: tip,
          onPressed: onTap,
          icon: Icon(i, color: color),
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.all(6),
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        );
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
      decoration: BoxDecoration(color: const Color(0xFFF4F6FA), borderRadius: BorderRadius.circular(14), border: Border.all(color: kBorder)),
      child: Row(children: [
        Expanded(child: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: kNavy))),
        b(Icons.rotate_left_rounded, 'Turn left', () => _turn(p, -20)),
        b(Icons.rotate_right_rounded, 'Turn right', () => _turn(p, 20)),
        b(Icons.remove_circle_outline_rounded, 'Smaller', () => _resize(p, 0.9)),
        b(Icons.add_circle_outline_rounded, 'Bigger', () => _resize(p, 1.12)),
        b(Icons.view_in_ar_rounded, 'View in 3D', () => _view3d(f), color: kBlue),
        b(Icons.delete_outline_rounded, 'Remove from room', () => _removePlaced(p), color: Colors.red),
      ]),
    );
  }

  Widget _tray() {
    final all = [..._mine, ..._samples];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: kNavy.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, -4))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('Furniture', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kNavy))),
          FilledButton.tonalIcon(
            onPressed: _addFurniture,
            icon: const Icon(Icons.add_a_photo_outlined, size: 18),
            label: const Text('Add photo'),
          ),
        ]),
        const SizedBox(height: 2),
        const Text('Press & hold, then drag onto your room  •  or tap to place', style: TextStyle(fontSize: 11.5, color: Color(0xFF5A6785))),
        const SizedBox(height: 8),
        SizedBox(
          height: 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: all.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => _card(all[i]),
          ),
        ),
      ]),
    );
  }

  Widget _badge(Furniture f) {
    final (text, bg, fg) = switch (f.status) {
      'ready' => ('3D', const Color(0xFFDDF4E7), const Color(0xFF1B9E55)),
      'processing' => ('3D ${f.progress}%', const Color(0xFFE3EEFF), kBlue),
      'failed' => ('Photo', const Color(0xFFFDE8E8), const Color(0xFFC62828)),
      _ => ('Photo', const Color(0xFFEEF1F6), const Color(0xFF5A6785)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: fg)),
    );
  }

  Widget _card(Furniture f) {
    Widget body({double opacity = 1}) => Opacity(
          opacity: opacity,
          child: SizedBox(
            width: 92,
            child: Column(children: [
              Stack(children: [
                Container(
                  height: 80,
                  width: 92,
                  decoration: BoxDecoration(color: const Color(0xFFF4F6FA), borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder)),
                  child: PhotoThumb(src: f.photo, w: 92, h: 80, fallback: Icons.chair_outlined),
                ),
                Positioned(right: 4, bottom: 4, child: _badge(f)),
                if (!f.sample)
                  Positioned(
                    left: 2,
                    top: 2,
                    child: GestureDetector(
                      onTap: () => _deleteFurniture(f),
                      child: CircleAvatar(radius: 10, backgroundColor: Colors.black.withValues(alpha: 0.55), child: const Icon(Icons.close, size: 12, color: Colors.white)),
                    ),
                  ),
              ]),
              const SizedBox(height: 4),
              Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: kNavy)),
            ]),
          ),
        );

    return LongPressDraggable<Furniture>(
      data: f,
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(opacity: 0.9, child: PhotoThumb(src: f.photo, w: 90, h: 90, radius: 14, fallback: Icons.chair_outlined)),
      ),
      childWhenDragging: body(opacity: 0.35),
      child: GestureDetector(onTap: () => _place(f), child: body()),
    );
  }
}