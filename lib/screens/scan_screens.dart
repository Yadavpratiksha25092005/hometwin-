import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../api.dart';
import '../config.dart';
import '../main.dart';
import '../scan/floor_plan.dart';
import '../scan/room_model.dart';
import '../scan/room_scanner.dart';
import '../widgets/common.dart';

Future<Directory> _scanDir() async {
  final base = await getApplicationDocumentsDirectory();
  final d = Directory('${base.path}/scans');
  if (!d.existsSync()) d.createSync(recursive: true);
  return d;
}

/// 3D Scans tab: AR room scan (Android / ARCore) + import of .glb models (fallback).
class ScanScreen extends StatefulWidget {
  final bool embedded;
  const ScanScreen({super.key, this.embedded = false});
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  late Future<List<dynamic>> _future = Api.list('scans');
  bool _busy = false;

  void _reload() => setState(() {
        _future = Api.list('scans');
      });

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _info(String title, String body) => showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );

  /// Save dialog. Returns the chosen name, or null if the user discards.
  Future<String?> _askName(String initial, String subtitle) async {
    final c = TextEditingController(text: initial);
    final r = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Save scan'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(subtitle, style: const TextStyle(color: Color(0xFF5A6785))),
          const SizedBox(height: 12),
          TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'Room / scan name', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Discard')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text.trim().isEmpty ? initial : c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    return r; // controller is not disposed: the dialog's closing animation is still running
  }

  Future<void> _scanRoom() async {
    if (!RoomScanner.platformOk) {
      _snack('Room scan currently works only on Android. Use "Import 3D model" instead.');
      return;
    }
    setState(() => _busy = true);
    try {
      final avail = await RoomScanner.availability();
      if (avail == 'unsupported') {
        await _info('This phone does not support ARCore',
            'Room scan needs a phone with ARCore support.\n\nYou can scan with an app like Polycam / Scaniverse, export as .glb, and add it here using "Import 3D model".');
        return;
      }
      final res = await RoomScanner.scan();
      if (res == null || !mounted) return; // user cancelled the scan
      final room = RoomData.fromJson(res);
      final n = (await Api.list('scans')).length + 1;
      final name = await _askName('Room $n', '${room.summary}  •  ${room.corners.length} corners');
      if (name == null) return;

      final dir = await _scanDir();
      final f = File('${dir.path}/room_${DateTime.now().millisecondsSinceEpoch}.glb')..writeAsBytesSync(buildRoomGlb(room, roomName: name));
      final url = await Api.upload(f.path);
      await Api.create('scans', {
        'name': name,
        'notes': room.summary,
        'model_url': url,
        'source': 'arcore_room',
        'meta': res,
      });
      _reload();
      _snack('"$name" saved');
    } on PlatformException catch (e) {
      _snack(e.message ?? 'Scan failed');
    } catch (e) {
      _snack('Could not save scan: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importModel() async {
    setState(() => _busy = true);
    try {
      final picked = await FilePicker.pickFile();
      final path = picked?.path;
      if (picked == null || path == null) return;
      final lower = picked.name.toLowerCase();
      if (lower.endsWith('.usdz')) {
        await _info('.usdz is not supported on Android', 'The 3D viewer on Android only shows .glb files. Export as .glb from your scanner app.');
        return;
      }
      if (!lower.endsWith('.glb')) {
        await _info('Only .glb is supported', 'Export as "GLB" from your scanner app (Polycam, Scaniverse...) and try again.');
        return;
      }
      final raf = await File(path).open();
      final head = await raf.read(4);
      await raf.close();
      if (head.length < 4 || String.fromCharCodes(head) != 'glTF') {
        _snack('This does not look like a valid .glb file');
        return;
      }
      if (!mounted) return;
      final base = picked.name.replaceAll(RegExp(r'\.glb$', caseSensitive: false), '');
      final name = await _askName(base, picked.name);
      if (name == null) return;

      final dir = await _scanDir();
      final copy = await File(path).copy('${dir.path}/import_${DateTime.now().millisecondsSinceEpoch}.glb');
      final url = await Api.upload(copy.path);
      await Api.create('scans', {
        'name': name,
        'notes': 'Imported 3D model (${(copy.lengthSync() / 1048576).toStringAsFixed(1)} MB)',
        'model_url': url,
        'source': 'import',
      });
      _reload();
      _snack('"$name" imported');
    } catch (e) {
      _snack('Import failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _numField(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        ),
      );

  /// No camera needed: enter length x width x height to get an instant 3D room.
  Future<void> _quickRoom() async {
    final n = (await Api.list('scans')).length + 1;
    if (!mounted) return;
    final nameC = TextEditingController(text: 'Room $n');
    final lC = TextEditingController(), wC = TextEditingController(), hC = TextEditingController(text: '2.7');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Enter room size'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameC, decoration: const InputDecoration(labelText: 'Room name', border: OutlineInputBorder())),
            _numField(lC, 'Length (meters)'),
            _numField(wC, 'Width (meters)'),
            _numField(hC, 'Height (meters)'),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create')),
        ],
      ),
    );
    double? p(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));
    final l = p(lC), w = p(wC), h = p(hC);
    final name = nameC.text.trim().isEmpty ? 'Room $n' : nameC.text.trim();
    if (ok != true) return;
    if (l == null || w == null || h == null || l < 0.5 || w < 0.5 || l > 50 || w > 50 || h < 1.8 || h > 6) {
      _snack('Enter valid sizes (length/width 0.5 to 50 m, height 1.8 to 6 m)');
      return;
    }
    setState(() => _busy = true);
    try {
      final meta = {
        'version': 1,
        'unit': 'm',
        'corners': [
          [0.0, 0.0],
          [l, 0.0],
          [l, w],
          [0.0, w]
        ],
        'height': h,
        'area_m2': l * w,
        'perimeter_m': 2 * (l + w),
        'width_m': l,
        'depth_m': w,
        'walls': [l, w, l, w],
        'manual': true,
      };
      final room = RoomData.fromJson(meta);
      final dir = await _scanDir();
      final f = File('${dir.path}/room_${DateTime.now().millisecondsSinceEpoch}.glb')..writeAsBytesSync(buildRoomGlb(room, roomName: name));
      final url = await Api.upload(f.path);
      await Api.create('scans', {
        'name': name,
        'notes': room.summary,
        'model_url': url,
        'source': 'manual_room',
        'meta': meta,
      });
      _reload();
      _snack('"$name" created');
    } catch (e) {
      _snack('Could not create room: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Pick a video -> "processing" -> add a sample 3D room (DEMO, kMockVideoScan).
  Future<void> _videoScan() async {
    if (!kMockVideoScan) {
      _snack('3D from video is not available yet.');
      return;
    }
    setState(() => _busy = true);
    try {
      final picked = await FilePicker.pickFile();
      if (picked == null) return;
      final n = picked.name.toLowerCase();
      const ok = ['.mp4', '.mov', '.avi', '.mkv', '.webm', '.3gp', '.m4v'];
      if (!ok.any(n.endsWith)) {
        _snack('Choose a video file (mp4, mov, avi...)');
        return;
      }
      if (!mounted) return;
      await showDialog(context: context, barrierDismissible: false, builder: (_) => const _FakeProcessing());
      final catalog = List<dynamic>.from(jsonDecode(await rootBundle.loadString('assets/models/catalog.json')));
      final used = (await Api.list('scans')).where((s) => s['source'] == 'demo_video').length;
      final m = catalog[used % catalog.length] as Map<String, dynamic>;
      final round = used ~/ catalog.length;
      final name = round == 0 ? '${m['name']}' : '${m['name']} (${round + 1})';
      final room = RoomData.fromJson(Map<String, dynamic>.from(m['meta']));
      await Api.create('scans', {
        'name': name,
        'notes': '${room.summary}  •  Demo (${picked.name})',
        'model_url': 'asset:${m['file']}',
        'source': 'demo_video',
        'meta': m['meta'],
      });
      _reload();
      _snack('"$name" created');
    } catch (e) {
      _snack('Video scan failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Combines every saved room-scan (that has scan geometry, i.e. not an imported .glb)
  /// into ONE model, auto-arranged side by side, and saves it as a new "Full House" scan.
  Future<void> _combineAll() async {
    setState(() => _busy = true);
    try {
      final all = await Api.list('scans');
      final rooms = <MapEntry<RoomData, String?>>[];
      for (final s in all) {
        final room = RoomData.tryParse(s['meta']);
        if (room != null) rooms.add(MapEntry(room, '${s['name']}'));
      }
      if (rooms.length < 2) {
        _snack('Scan at least 2 rooms first (imported .glb files cannot be combined).');
        return;
      }
      final glb = buildHouseGlb(rooms);
      final dir = await _scanDir();
      final f = File('${dir.path}/house_${DateTime.now().millisecondsSinceEpoch}.glb')..writeAsBytesSync(glb);
      final url = await Api.upload(f.path);
      final n = (await Api.list('scans')).where((s) => '${s['name']}'.startsWith('Full House')).length + 1;
      final name = n == 1 ? 'Full House' : 'Full House ($n)';
      await Api.create('scans', {
        'name': name,
        'notes': '${rooms.length} rooms combined • auto-arranged (not real positions)',
        'model_url': url,
        'source': 'combined',
      });
      _reload();
      _snack('"$name" created — see it in the list below');
    } catch (e) {
      _snack('Combine failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _actions() => Card(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Digitize your home', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kNavy)),
            const SizedBox(height: 4),
            const Text(
              'Scan your room with AR and the app will build a 3D model — move your phone around and tap each corner.',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF5A6785)),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(onPressed: _busy ? null : _scanRoom, icon: const Icon(Icons.view_in_ar), label: const Text('AR Scan')),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _combineAll,
                icon: const Icon(Icons.home_work_outlined),
                label: const Text('View whole house (combine)'),
              ),
            ),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: const Text('More options (advanced)', style: TextStyle(fontSize: 13, color: Color(0xFF5A6785))),
                children: [
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _videoScan,
                        icon: const Icon(Icons.videocam),
                        label: const Text('3D scan from video (demo)'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : _quickRoom, icon: const Icon(Icons.straighten), label: const Text('Enter size'))),
                  ]),
                  // NOTE: Gallery/manual image upload is intentionally not here yet — planned for a future phase.
                ],
              ),
            ),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('3D Scans'), automaticallyImplyLeading: !widget.embedded),
        body: FutureBuilder<List<dynamic>>(
          future: _future,
          builder: (c, s) {
            if (s.hasError) return Center(child: Text('${s.error}'));
            if (!s.hasData) return const Center(child: CircularProgressIndicator());
            final items = s.data!;
            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: items.length + 1 + (items.isEmpty ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i == 0) return _actions();
                  if (items.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('No scans yet.', style: TextStyle(color: Color(0xFF5A6785)))),
                    );
                  }
                  final it = items[i - 1] as Map<String, dynamic>;
                  final isRoom = ['arcore_room', 'manual_room', 'demo_video'].contains(it['source']);
                  return Dismissible(
                    key: ValueKey(it['id']),
                    direction: DismissDirection.endToStart,
                    background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: Colors.white)),
                    onDismissed: (_) async {
                      await deleteScan(it);
                      _reload();
                    },
                    child: Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFFEAF2FF),
                          child: Icon(isRoom ? Icons.meeting_room_outlined : Icons.view_in_ar, color: kBlue),
                        ),
                        title: Text('${it['name'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w700, color: kNavy)),
                        subtitle: Text('${it['notes'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: switch (it['source']) {
                          'manual_room' => StatusPill.green('Quick room'),
                          'demo_video' => StatusPill.blue('Video scan'),
                          'arcore_room' => StatusPill.blue('AR scan'),
                          _ => StatusPill.grey('Imported'),
                        },
                        onTap: () async {
                          await Navigator.push(context, MaterialPageRoute(builder: (_) => ScanDetailScreen(scan: it)));
                          _reload();
                        },
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      );
}

/// Removes the scan record and (best effort) its model file from app storage.
Future<void> deleteScan(Map<String, dynamic> scan) async {
  await Api.remove('scans', scan['id']);
  final p = '${scan['model_url'] ?? ''}';
  if (p.contains('/scans/')) {
    try {
      final f = File(p);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }
}

class ScanDetailScreen extends StatelessWidget {
  final Map<String, dynamic> scan;
  const ScanDetailScreen({super.key, required this.scan});

  String get _raw => '${scan['model_url'] ?? ''}';
  bool get _isRemote => Api.isServerPath(_raw);
  // full http URL for server files, otherwise the phone's local path
  String get _url => _isRemote ? Api.fileUrl(_raw) : _raw;
  bool get _hasFile => _raw.isNotEmpty && !_isRemote && File(_raw).existsSync();

  Widget _viewer() {
    if (_raw.startsWith('asset:')) {
      return ModelViewer(src: _raw.substring(6), alt: '${scan['name']}', ar: false, autoRotate: false, cameraControls: true, backgroundColor: const Color(0xFFEFF3FA), shadowIntensity: 1, shadowSoftness: 1, exposure: 1.05, environmentImage: 'neutral');
    }
    if (_url.toLowerCase().endsWith('.usdz')) {
      return const _Msg(Icons.info_outline, '.usdz cannot be shown on Android. Import a .glb instead.');
    }
    if (_isRemote) {
      return ModelViewer(src: _url, alt: '${scan['name']}', ar: false, autoRotate: false, cameraControls: true, backgroundColor: const Color(0xFFEFF3FA), shadowIntensity: 1, shadowSoftness: 1, exposure: 1.05, environmentImage: 'neutral');
    }
    if (!_hasFile) return const _Msg(Icons.broken_image_outlined, '3D model file not found.');
    return ModelViewer(src: 'file://$_url', alt: '${scan['name']}', ar: false, autoRotate: false, cameraControls: true, backgroundColor: const Color(0xFFEFF3FA), shadowIntensity: 1, shadowSoftness: 1, exposure: 1.05, environmentImage: 'neutral');
  }

  Widget _stat(String label, String value) => Expanded(
        child: Column(children: [
          Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kNavy)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11.5, color: Color(0xFF5A6785))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final room = RoomData.tryParse(scan['meta']);
    final body = Column(children: [
      Expanded(
        child: room == null
            ? _viewer()
            : TabBarView(physics: const NeverScrollableScrollPhysics(), children: [
                _viewer(),
                Container(color: Colors.white, child: CustomPaint(painter: FloorPlanPainter(room), size: Size.infinite)),
              ]),
      ),
      if (room != null)
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 18),
          child: Row(children: [
            _stat('Area', '${room.area.toStringAsFixed(1)} m²'),
            _stat('Size', '${room.width.toStringAsFixed(1)}×${room.depth.toStringAsFixed(1)} m'),
            _stat('Height', '${room.height.toStringAsFixed(1)} m'),
            _stat('Perimeter', '${room.perimeter.toStringAsFixed(1)} m'),
          ]),
        )
      else if ('${scan['notes'] ?? ''}'.isNotEmpty)
        Container(
          width: double.infinity,
          color: Colors.white,
          padding: const EdgeInsets.all(16),
          child: Text('${scan['notes']}', style: const TextStyle(color: Color(0xFF5A6785))),
        ),
    ]);

    final actions = [
      if (_hasFile)
        IconButton(
          tooltip: 'Share .glb',
          icon: const Icon(Icons.ios_share_rounded),
          onPressed: () => SharePlus.instance.share(ShareParams(files: [XFile(_url)], text: '${scan['name']}')),
        ),
      IconButton(
        tooltip: 'Delete',
        icon: const Icon(Icons.delete_outline),
        onPressed: () async {
          final nav = Navigator.of(context);
          final ok = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Delete scan?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
              ],
            ),
          );
          if (ok == true) {
            await deleteScan(scan);
            nav.pop();
          }
        },
      ),
    ];

    final title = Text('${scan['name'] ?? '3D Scan'}');
    if (room == null) {
      return Scaffold(appBar: AppBar(title: title, actions: actions), body: body);
    }
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: title,
          actions: actions,
          bottom: const TabBar(tabs: [Tab(text: '3D'), Tab(text: 'Floor plan')]),
        ),
        body: body,
      ),
    );
  }
}

class _Msg extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Msg(this.icon, this.text);
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 40, color: const Color(0xFF9AA6C0)),
            const SizedBox(height: 10),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF5A6785))),
          ]),
        ),
      );
}

/// Demo "processing" dialog: shows a few steps and closes itself.
class _FakeProcessing extends StatefulWidget {
  const _FakeProcessing();
  @override
  State<_FakeProcessing> createState() => _FakeProcessingState();
}

class _FakeProcessingState extends State<_FakeProcessing> {
  static const _steps = [
    'Uploading video…',
    'Extracting frames…',
    'Estimating camera positions…',
    'Building 3D model…',
    'Applying textures…',
  ];
  int _i = 0;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(milliseconds: 1300), (t) {
      if (!mounted) return;
      if (_i >= _steps.length - 1) {
        t.cancel();
        Navigator.pop(context);
      } else {
        setState(() => _i++);
      }
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Building 3D model'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            LinearProgressIndicator(value: (_i + 1) / _steps.length),
            const SizedBox(height: 16),
            Text(_steps[_i]),
          ]),
        ),
      );
}