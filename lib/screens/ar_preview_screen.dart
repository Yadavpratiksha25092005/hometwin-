import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../api.dart';
import '../main.dart';

/// Furniture preview on a PHOTO: take or pick a photo of your room, add furniture on top of it,
/// move / resize / rotate it anywhere, then save or share the result.
/// Furniture comes from assets/furniture/catalog.json (add a PNG with a transparent background
/// + one entry in that file to add a new item).
class _Item {
  final String id, name, category, image;
  final double widthM, aspect; // real width in metres, image height / width
  _Item(this.id, this.name, this.category, this.image, this.widthM, this.aspect);

  /// Server images (real photos) are downloaded the first time they are shown, then kept on the phone.
  bool get isRemote => image.startsWith('/files/') || image.startsWith('http');
  late final Future<File?> file = Api.cachedFile(image);
  factory _Item.fromJson(Map<String, dynamic> j) =>
      _Item('${j['id']}', '${j['name']}', '${j['category']}', '${j['image']}', (j['width_m'] as num).toDouble(), (j['aspect'] as num).toDouble());
}

/// One piece of furniture placed on the photo. Position and size are fractions of the photo.
class _Placed {
  final _Item item;
  double cx, cy, wf, rot;
  bool flip;
  _Placed(this.item, this.wf, {this.cx = 0.5, this.cy = 0.6, this.rot = 0, this.flip = false});
}

/// Furniture picture: bundled asset, or a server image downloaded once and cached.
class _ItemImage extends StatelessWidget {
  final _Item item;
  final BoxFit fit;
  final int? cacheWidth;
  const _ItemImage(this.item, {this.fit = BoxFit.fill, this.cacheWidth});

  @override
  Widget build(BuildContext context) {
    if (!item.isRemote) return Image.asset(item.image, fit: fit, cacheWidth: cacheWidth, gaplessPlayback: true);
    return FutureBuilder<File?>(
      future: item.file,
      builder: (_, s) {
        final f = s.data;
        if (f == null) {
          return Center(
            child: s.connectionState == ConnectionState.done
                ? const Icon(Icons.broken_image_outlined, color: Color(0xFF9AA6C0))
                : const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        return Image.file(f, fit: fit, cacheWidth: cacheWidth, gaplessPlayback: true);
      },
    );
  }
}

class ArPreviewScreen extends StatefulWidget {
  const ArPreviewScreen({super.key});
  @override
  State<ArPreviewScreen> createState() => _ArPreviewScreenState();
}

class _ArPreviewScreenState extends State<ArPreviewScreen> {
  static const _roomWidthM = 4.5; // assumed width of the photographed wall -> default object size
  final _boundaryKey = GlobalKey();
  final _picker = ImagePicker();

  List<_Item> _items = [];
  String _cat = '';
  ImageProvider? _photo;
  double _aspect = 0.75; // photo width / height
  final _objs = <_Placed>[];
  _Placed? _sel;
  bool _capturing = false;
  double _startWf = 0.3, _startRot = 0;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _loadCatalog() async {
    try {
      final list = jsonDecode(await rootBundle.loadString('assets/furniture/catalog.json')) as List;
      final items = [for (final e in list) _Item.fromJson(Map<String, dynamic>.from(e as Map))];
      // Any other PNG dropped into assets/furniture/ shows up automatically under "My items".
      try {
        final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
        final known = items.map((e) => e.image).toSet();
        final extra = manifest.listAssets().where((p) => p.startsWith('assets/furniture/') && p.toLowerCase().endsWith('.png') && !known.contains(p)).toList()..sort();
        for (final p in extra) {
          final im = await decodeImageFromList((await rootBundle.load(p)).buffer.asUint8List());
          final aspect = im.height / im.width;
          im.dispose();
          final base = p.split('/').last.replaceAll(RegExp(r'\.png$', caseSensitive: false), '').replaceAll(RegExp(r'[_-]+'), ' ').trim();
          final name = base.isEmpty ? 'Item' : base[0].toUpperCase() + base.substring(1);
          items.add(_Item(p, name, 'My items', p, 1.2, aspect));
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _items = items;
        _cat = items.isEmpty ? '' : items.first.category;
      });
      // Real furniture photos hosted on the server (uploads/furniture/<Category>/<name>.png).
      try {
        final remote = await Api.furnitureCatalog();
        if (mounted && remote.isNotEmpty) {
          setState(() => _items.addAll([for (final e in remote) _Item.fromJson(Map<String, dynamic>.from(e as Map))]));
        }
      } catch (_) {}
    } catch (e) {
      _snack('Could not load the furniture list: $e');
    }
  }

  List<String> get _cats => _items.map((e) => e.category).toSet().toList();

  // ------------------------------------------------------------------ photo

  Future<void> _pick(ImageSource src) async {
    try {
      final x = await _picker.pickImage(source: src, maxWidth: 1800, imageQuality: 90);
      if (x == null) return;
      await _setPhoto(await x.readAsBytes());
    } catch (e) {
      _snack('Could not open the photo: $e');
    }
  }

  Future<void> _useSample() async {
    final data = await rootBundle.load('assets/images/demo/room.jpg');
    await _setPhoto(data.buffer.asUint8List());
  }

  Future<void> _setPhoto(Uint8List bytes) async {
    final img = await decodeImageFromList(bytes);
    final a = img.width / img.height;
    img.dispose();
    if (!mounted) return;
    setState(() {
      _photo = MemoryImage(bytes);
      _aspect = a;
      _objs.clear();
      _sel = null;
    });
  }

  void _photoSheet() => showModalBottomSheet(
        context: context,
        builder: (_) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(context);
                _pick(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(context);
                _pick(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.weekend_outlined),
              title: const Text('Use the sample room'),
              onTap: () {
                Navigator.pop(context);
                _useSample();
              },
            ),
          ]),
        ),
      );

  // ------------------------------------------------------------------ objects

  void _add(_Item it) {
    final wf = (it.widthM / _roomWidthM).clamp(0.12, 0.8).toDouble();
    final hf = wf * it.aspect * _aspect; // object height as a fraction of the photo height
    final cy = (0.82 - hf / 2).clamp(0.2, 0.85).toDouble();
    final cx = (0.5 + 0.05 * (_objs.length % 5 - 2)).clamp(0.2, 0.8).toDouble();
    final o = _Placed(it, wf, cx: cx, cy: cy);
    setState(() {
      _objs.add(o);
      _sel = o;
    });
  }

  void _resize(double k) {
    final o = _sel;
    if (o == null) return;
    setState(() => o.wf = (o.wf * k).clamp(0.04, 1.6).toDouble());
  }

  void _duplicate() {
    final o = _sel;
    if (o == null) return;
    final c = _Placed(o.item, o.wf, cx: (o.cx + 0.05).clamp(0.0, 1.0).toDouble(), cy: (o.cy + 0.04).clamp(0.0, 1.0).toDouble(), rot: o.rot, flip: o.flip);
    setState(() {
      _objs.add(c);
      _sel = c;
    });
  }

  void _delete() {
    final o = _sel;
    if (o == null) return;
    setState(() {
      _objs.remove(o);
      _sel = null;
    });
  }

  void _toFront() {
    final o = _sel;
    if (o == null) return;
    setState(() {
      _objs.remove(o);
      _objs.add(o);
    });
  }

  Future<void> _clearAll() async {
    if (_objs.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove all furniture?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true && mounted) {
      setState(() {
        _objs.clear();
        _sel = null;
      });
    }
  }

  // ------------------------------------------------------------------ save / share

  Future<void> _share() async {
    if (_photo == null) return;
    setState(() => _capturing = true); // hides the selection border for the picture
    await WidgetsBinding.instance.endOfFrame;
    try {
      final b = _boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 2.5);
      final bd = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/room_design_${DateTime.now().millisecondsSinceEpoch}.png')..writeAsBytesSync(bd!.buffer.asUint8List());
      await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], text: 'My room design'));
    } catch (e) {
      _snack('Could not save the image: $e');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('Room Design'),
          actions: [
            if (_photo != null) ...[
              IconButton(tooltip: 'Change photo', onPressed: _photoSheet, icon: const Icon(Icons.add_a_photo_outlined)),
              IconButton(tooltip: 'Remove all', onPressed: _clearAll, icon: const Icon(Icons.layers_clear_outlined)),
              IconButton(tooltip: 'Save / share', onPressed: _share, icon: const Icon(Icons.ios_share_rounded)),
            ],
          ],
        ),
        body: _photo == null ? _start() : Column(children: [Expanded(child: _canvas()), _toolbar(), _panel()]),
      );

  Widget _start() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.weekend_outlined, size: 56, color: kBlue),
            const SizedBox(height: 14),
            const Text('Design your room', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kNavy)),
            const SizedBox(height: 8),
            const Text(
              'Take a photo of your room, then add furniture on top of it. Move, resize and rotate it anywhere you like.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF5A6785)),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(onPressed: () => _pick(ImageSource.camera), icon: const Icon(Icons.photo_camera_outlined), label: const Text('Take a photo')),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(onPressed: () => _pick(ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined), label: const Text('Choose from gallery')),
            ),
            const SizedBox(height: 6),
            TextButton(onPressed: _useSample, child: const Text('Try with a sample room')),
          ]),
        ),
      );

  Widget _canvas() => LayoutBuilder(builder: (context, c) {
        var w = c.maxWidth, h = c.maxWidth / _aspect;
        if (h > c.maxHeight) {
          h = c.maxHeight;
          w = h * _aspect;
        }
        return Center(
          child: SizedBox(
            width: w,
            height: h,
            child: Stack(children: [
              RepaintBoundary(
                key: _boundaryKey,
                child: ClipRect(
                  child: Stack(children: [
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: () => setState(() => _sel = null),
                        child: Image(image: _photo!, fit: BoxFit.fill, gaplessPlayback: true),
                      ),
                    ),
                    for (final o in _objs) _object(o, w, h),
                  ]),
                ),
              ),
              if (_objs.isEmpty && !_capturing)
                Positioned(
                  left: 12,
                  right: 12,
                  top: 12,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(14)),
                      child: const Text(
                        'Pick furniture below to add it.\nDrag to move  •  Pinch to resize  •  Twist to rotate',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        );
      });

  Widget _object(_Placed o, double w, double h) {
    final pw = o.wf * w, ph = pw * o.item.aspect;
    final selected = identical(o, _sel) && !_capturing;
    return Positioned(
      key: ObjectKey(o),
      left: o.cx * w - pw / 2,
      top: o.cy * h - ph / 2,
      width: pw,
      height: ph,
      child: Transform.rotate(
        angle: o.rot,
        child: GestureDetector(
          onTap: () => setState(() => _sel = o),
          onScaleStart: (d) {
            _startWf = o.wf;
            _startRot = o.rot;
            setState(() => _sel = o);
          },
          onScaleUpdate: (d) => setState(() {
            o.cx = (o.cx + d.focalPointDelta.dx / w).clamp(-0.1, 1.1).toDouble();
            o.cy = (o.cy + d.focalPointDelta.dy / h).clamp(-0.1, 1.1).toDouble();
            if (d.pointerCount > 1) {
              o.wf = (_startWf * d.scale).clamp(0.04, 1.6).toDouble();
              o.rot = _startRot + d.rotation;
            }
          }),
          child: Container(
            decoration: selected ? BoxDecoration(border: Border.all(color: kBlue, width: 2), borderRadius: BorderRadius.circular(4)) : null,
            child: Transform.flip(flipX: o.flip, child: _ItemImage(o.item)),
          ),
        ),
      ),
    );
  }

  Widget _toolbar() {
    final on = _sel != null;
    Widget b(IconData i, String tip, VoidCallback f) => Expanded(
          child: IconButton(
            onPressed: on ? f : null,
            tooltip: tip,
            icon: Icon(i, size: 22),
            color: kNavy,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            visualDensity: VisualDensity.compact,
          ),
        );
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFE3E8F2)))),
      child: Row(children: [
        b(Icons.remove_circle_outline, 'Smaller', () => _resize(0.9)),
        b(Icons.add_circle_outline, 'Bigger', () => _resize(1.1)),
        b(Icons.rotate_left, 'Rotate left', () => setState(() => _sel!.rot -= 0.1745)),
        b(Icons.rotate_right, 'Rotate right', () => setState(() => _sel!.rot += 0.1745)),
        b(Icons.flip, 'Flip', () => setState(() => _sel!.flip = !_sel!.flip)),
        b(Icons.flip_to_front, 'Bring to front', _toFront),
        b(Icons.copy_rounded, 'Duplicate', _duplicate),
        b(Icons.delete_outline, 'Delete', _delete),
      ]),
    );
  }

  Widget _panel() {
    final shown = _items.where((e) => e.category == _cat).toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: kNavy.withValues(alpha: 0.08), blurRadius: 14, offset: const Offset(0, -3))]),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _cats.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final c = _cats[i];
              return ChoiceChip(label: Text(c), selected: c == _cat, onSelected: (_) => setState(() => _cat = c), visualDensity: VisualDensity.compact);
            },
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: shown.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final it = shown[i];
              return GestureDetector(
                onTap: () => _add(it),
                child: SizedBox(
                  width: 92,
                  child: Column(children: [
                    Container(
                      height: 66,
                      width: double.infinity,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: const Color(0xFFF4F6FA), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE3E8F2))),
                      child: _ItemImage(it, fit: BoxFit.contain, cacheWidth: 240),
                    ),
                    const SizedBox(height: 4),
                    Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: kNavy)),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}