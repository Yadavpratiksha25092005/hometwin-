import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../api.dart';
import '../main.dart';
import '../widgets/common.dart';

const _cats = ['Invoice', 'Warranty', 'Insurance', 'Receipt', 'Property', 'Other'];

(IconData, Color) _meta(String c) => switch (c.toLowerCase()) {
      'invoice' => (Icons.receipt_long_rounded, kBlue),
      'warranty' => (Icons.verified_user_rounded, const Color(0xFF1B9E55)),
      'insurance' => (Icons.shield_rounded, const Color(0xFF6B4FD8)),
      'receipt' => (Icons.request_quote_rounded, const Color(0xFFF08A24)),
      'property' => (Icons.home_work_rounded, const Color(0xFF0E9AA7)),
      _ => (Icons.description_rounded, const Color(0xFF5A6785)),
    };

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});
  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  late Future<List<List<dynamic>>> _future = _load();
  final _search = TextEditingController();
  String _cat = 'All';

  Future<List<List<dynamic>>> _load() => Future.wait([Api.list('documents'), Api.list('assets')]);
  void _reload() => setState(() {
        _future = _load();
      });

  Future<void> _add() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddDocSheet(),
    );
    if (ok == true) _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.upload_file_rounded)),
        body: SafeArea(
          child: FutureBuilder<List<List<dynamic>>>(
            future: _future,
            builder: (c, s) {
              if (!s.hasData) return const Center(child: CircularProgressIndicator());
              return _content(s.data![0], s.data![1]);
            },
          ),
        ),
      );

  Widget _content(List<dynamic> docs, List<dynamic> assets) {
    final cats = ['All', ..._cats];
    for (final d in docs) {
      final c = '${d['category'] ?? ''}'.trim();
      if (c.isNotEmpty && !cats.any((x) => x.toLowerCase() == c.toLowerCase())) cats.add(c);
    }
    final q = _search.text.trim().toLowerCase();
    final items = docs.where((d) {
      final inCat = _cat == 'All' || '${d['category'] ?? ''}'.toLowerCase() == _cat.toLowerCase();
      return inCat && (q.isEmpty || '${d['title']} ${d['category'] ?? ''}'.toLowerCase().contains(q));
    }).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Text('Document Vault', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: kNavy)),
      ),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 2, 16, 12),
        child: Text('Store property, insurance, bills & receipts securely', style: TextStyle(color: Color(0xFF5A6785))),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF172554), Color(0xFF6338D6)]),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.lock_rounded, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${docs.length} ${docs.length == 1 ? 'document' : 'documents'} secured',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                const Text('Invoices, warranties & receipts in one safe place', style: TextStyle(color: Color(0xFFD6E6FF), fontSize: 12)),
              ]),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SizedBox(
          height: 48,
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search documents...',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: Colors.white,
              contentPadding: EdgeInsets.zero,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: kBorder)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: kBorder)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: kBlue)),
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 38,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: cats.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final sel = cats[i] == _cat;
            return GestureDetector(
              onTap: () => setState(() => _cat = cats[i]),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: sel ? kBlue : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: sel ? kBlue : kBorder),
                ),
                child: Text(cats[i], style: TextStyle(fontWeight: FontWeight.w600, color: sel ? Colors.white : kNavy)),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 8),
      Expanded(
        child: items.isEmpty
            ? _empty(docs.isEmpty)
            : RefreshIndicator(
                onRefresh: () async => _reload(),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  itemCount: items.length,
                  itemBuilder: (_, i) => _card(Map<String, dynamic>.from(items[i]), assets),
                ),
              ),
      ),
    ]);
  }

  Widget _empty(bool none) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircleAvatar(radius: 36, backgroundColor: Color(0xFFE3EEFF), child: Icon(Icons.folder_open_rounded, size: 34, color: kBlue)),
            const SizedBox(height: 14),
            Text(none ? 'Vault is empty' : 'No matching documents', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kNavy)),
            const SizedBox(height: 4),
            const Text('Tap the upload button to add a document', style: TextStyle(color: Color(0xFF5A6785))),
          ]),
        ),
      );

  Widget _card(Map<String, dynamic> d, List<dynamic> assets) {
    final cat = '${d['category'] ?? 'Other'}';
    final (icon, color) = _meta(cat);
    final path = d['file_url'] as String?;
    final hasFile = path != null && path.isNotEmpty;
    final ext = hasFile && path.contains('.') ? path.split('.').last.toUpperCase() : null;
    final created = DateTime.tryParse('${d['created_at']}');
    String? assetName;
    for (final a in assets) {
      if (a['id'] == d['asset_id']) assetName = '${a['name']}';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _open(d),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: softShadow()),
          child: Row(children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${d['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, color: kNavy, fontSize: 15)),
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  StatusPill(cat, bg: color.withValues(alpha: 0.12), fg: color),
                  if (ext != null && ext.length <= 4) StatusPill.grey(ext),
                  if (!hasFile) StatusPill.grey('No file'),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  if (assetName != null) ...[
                    const Icon(Icons.link_rounded, size: 14, color: Color(0xFF5A6785)),
                    const SizedBox(width: 3),
                    Flexible(child: Text(assetName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFF5A6785)))),
                    const SizedBox(width: 10),
                  ],
                  if (created != null) Text(DateFormat('d MMM yyyy').format(created), style: const TextStyle(fontSize: 12, color: Color(0xFF8A94A8))),
                ]),
              ]),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF8A94A8)),
              onSelected: (v) {
                if (v == 'open') _open(d);
                if (v == 'share') _share(d);
                if (v == 'delete') _delete(d);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'open', child: Text('Open')),
                PopupMenuItem(value: 'share', child: Text('Share')),
                PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  /// Local file, ya server wali file download (cache) karke.
  Future<File?> _file(Map<String, dynamic> d) async {
    try {
      return await Api.localFile(d['file_url'] as String?);
    } catch (_) {
      return null;
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _open(Map<String, dynamic> d) async {
    final f = await _file(d);
    if (!mounted) return;
    if (f == null) {
      _snack('No file is attached to this document.');
      return;
    }
    final ext = f.path.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(ext)) {
      showDialog(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(12),
          child: Stack(children: [
            InteractiveViewer(child: Image.file(f, fit: BoxFit.contain)),
            Positioned(right: 4, top: 4, child: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context))),
          ]),
        ),
      );
    } else {
      await _share(d); // PDF / baaki files: "open with" chooser
    }
  }

  Future<void> _share(Map<String, dynamic> d) async {
    final f = await _file(d);
    if (!mounted) return;
    if (f == null) {
      _snack('No file is attached to this document.');
      return;
    }
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], text: '${d['title']}'));
  }

  Future<void> _delete(Map<String, dynamic> d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete document?'),
        content: Text('"${d['title']}" will be removed from the vault.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) {
      final f = await _file(d);
      if (f != null && f.existsSync()) f.deleteSync();
      await Api.remove('documents', d['id']);
      _reload();
    }
  }
}

class _AddDocSheet extends StatefulWidget {
  const _AddDocSheet();
  @override
  State<_AddDocSheet> createState() => _AddDocSheetState();
}

class _AddDocSheetState extends State<_AddDocSheet> {
  static const _soft = Color(0xFF6B7690);
  final _title = TextEditingController();
  String _cat = 'Invoice';
  int? _asset;
  String? _path, _name;
  List<dynamic> _assets = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Api.list('assets').then((a) => mounted ? setState(() => _assets = a) : null);
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  bool get _isImage => _name != null && RegExp(r'\.(png|jpe?g|webp|gif|heic)$', caseSensitive: false).hasMatch(_name!);

  Future<void> _pick() async {
    final f = await FilePicker.pickFile();
    if (f?.path == null) return;
    setState(() {
      _path = f!.path;
      _name = f.name;
    });
  }

  Future<void> _save() async {
    var title = _title.text.trim();
    if (title.isEmpty && _name != null) title = _name!;
    if (title.isEmpty) {
      _snack('Enter a document title or choose a file.');
      return;
    }
    setState(() => _busy = true);
    try {
      String? saved;
      if (_path != null) {
        // copy the file into the app's permanent folder (so it survives cache clearing)
        final dir = await getApplicationDocumentsDirectory();
        final vault = Directory('${dir.path}/vault');
        if (!vault.existsSync()) vault.createSync(recursive: true);
        saved = '${vault.path}/${DateTime.now().millisecondsSinceEpoch}_$_name';
        await File(_path!).copy(saved);
      }
      await Api.create('documents', {
        'title': title,
        'category': _cat,
        'asset_id': _asset,
        'file_url': saved == null ? null : await Api.upload(saved),
        'file_name': _name,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _dec(String? hint, IconData icon) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _soft, fontSize: 16),
        prefixIcon: Padding(
          padding: const EdgeInsets.all(8),
          child: Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(color: kLilac, shape: BoxShape.circle),
            child: Icon(icon, color: kBlue, size: 22),
          ),
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: Color(0xFFDCD2FA))),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: Color(0xFFDCD2FA))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: kBlue, width: 1.4)),
      );

  Widget _circle(double size, double alpha) =>
      Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, color: kLavender.withValues(alpha: alpha)));

  Widget _header() => Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(26),
            boxShadow: [BoxShadow(color: kBlue.withValues(alpha: 0.15), blurRadius: 18, offset: const Offset(0, 8))],
          ),
          child: Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF8B5CF6), Color(0xFF4C1D95)]),
            ),
            child: const Icon(Icons.folder_special_rounded, color: Colors.white, size: 32),
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Add Document', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: kNavy, letterSpacing: -0.4)),
            SizedBox(height: 2),
            Text('Keep it safe in your vault', style: TextStyle(fontSize: 14.5, color: _soft)),
          ]),
        ),
        InkWell(
          customBorder: const CircleBorder(),
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: kBlue.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 4))]),
            child: const Icon(Icons.close_rounded, color: kNavy),
          ),
        ),
      ]);

  Widget _chip(String c) {
    final sel = _cat == c;
    final (icon, color) = _meta(c);
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => setState(() => _cat = c),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: sel ? kBlue : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: sel ? kBlue : const Color(0xFFDCD2FA)),
          boxShadow: sel ? [BoxShadow(color: kBlue.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))] : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18, color: sel ? Colors.white : color),
          const SizedBox(width: 6),
          Text(c, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: sel ? Colors.white : kNavy)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final kb = MediaQuery.of(context).viewInsets.bottom;
    final bottomSafe = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFF1ECFF), Color(0xFFFBFAFF)]),
        ),
        child: Stack(children: [
          Positioned(top: -50, right: -40, child: _circle(170, 0.16)),
          Positioned(top: 40, right: 60, child: _circle(70, 0.08)),
          Padding(
            padding: EdgeInsets.only(bottom: kb),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(margin: const EdgeInsets.only(top: 10, bottom: 14), width: 48, height: 5, decoration: BoxDecoration(color: const Color(0xFFB9AEDC), borderRadius: BorderRadius.circular(3))),
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(18, 0, 18, 18 + bottomSafe),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    _header(),
                    const SizedBox(height: 22),
                    if (_isImage && _path != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.file(File(_path!), height: 130, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                      ),
                      const SizedBox(height: 10),
                    ],
                    SizedBox(
                      height: 56,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: const Color(0xFFF3EEFF),
                          foregroundColor: kBlue,
                          side: const BorderSide(color: Color(0xFFB9A4F5), width: 1.2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                        onPressed: _busy ? null : _pick,
                        icon: Icon(_name == null ? Icons.attach_file_rounded : Icons.check_circle_rounded, color: _name == null ? kBlue : const Color(0xFF1B9E55), size: 26),
                        label: Text(_name ?? 'Choose file (PDF / photo)', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(controller: _title, textCapitalization: TextCapitalization.sentences, decoration: _dec('Title', Icons.edit_note_rounded)),
                    const SizedBox(height: 22),
                    Row(children: [
                      Container(width: 4, height: 20, decoration: BoxDecoration(color: kBlue, borderRadius: BorderRadius.circular(3))),
                      const SizedBox(width: 10),
                      const Text('Category', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: kNavy)),
                    ]),
                    const SizedBox(height: 12),
                    Wrap(spacing: 10, runSpacing: 10, children: [for (final c in _cats) _chip(c)]),
                    const SizedBox(height: 22),
                    DropdownButtonFormField<int>(
                      isExpanded: true,
                      borderRadius: BorderRadius.circular(20),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: kBlue, size: 28),
                      hint: const Text('Link to asset (optional)', style: TextStyle(color: _soft, fontSize: 16)),
                      decoration: _dec(null, Icons.link_rounded),
                      items: [for (final a in _assets) DropdownMenuItem(value: a['id'] as int, child: Text('${a['name']}', maxLines: 1, overflow: TextOverflow.ellipsis))],
                      onChanged: (v) => _asset = v,
                    ),
                    const SizedBox(height: 22),
                    Container(
                      height: 58,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        gradient: const LinearGradient(colors: [Color(0xFF7C4DF0), Color(0xFF4C1D95)]),
                        boxShadow: [BoxShadow(color: kBlue.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 8))],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(30),
                          onTap: _busy ? null : _save,
                          child: Center(
                            child: _busy
                                ? const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white))
                                : const Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(Icons.lock_rounded, color: Colors.white, size: 24),
                                    SizedBox(width: 10),
                                    Text('Save to Vault', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700)),
                                  ]),
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}