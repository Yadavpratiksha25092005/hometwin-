import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api.dart';
import '../main.dart';
import '../widgets/common.dart';
import '../widgets/resource_screen.dart';
import 'asset_detail_screen.dart';

const assetFields = [
  FieldDef('name', 'Device name (e.g. Fridge, AC, TV, Washing Machine)'), FieldDef('room', 'Room (Kitchen / Living Room ...)'),
  FieldDef('brand', 'Brand'), FieldDef('model', 'Model (optional)'), FieldDef('serial_no', 'Serial No (optional)'),
  FieldDef('purchase_date', 'Purchase date', FType.date), FieldDef('price', 'Price', FType.number),
  FieldDef('photo_url', 'Photo', FType.file), FieldDef('notes', 'Notes', FType.multiline),
];

class AssetsScreen extends StatefulWidget {
  const AssetsScreen({super.key});
  @override
  State<AssetsScreen> createState() => _AssetsScreenState();
}

class _AssetsScreenState extends State<AssetsScreen> {
  late Future<List<List<dynamic>>> _future = _load();
  final _search = TextEditingController();
  String _cat = 'All';
  String _sort = 'Newest';

  Future<List<List<dynamic>>> _load() =>
      Future.wait([Api.list('assets'), Api.list('warranties'), Api.list('documents')]);
  void _reload() => setState(() {
        _future = _load();
      });

  Future<void> _add() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const AddForm(title: 'Asset', path: 'assets', fields: assetFields),
    );
    if (ok == true) _reload();
  }

  Future<void> _seed() async {
    await Api.seedDemo();
    _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.add, size: 30)),
        body: SafeArea(
          child: FutureBuilder<List<List<dynamic>>>(
            future: _future,
            builder: (c, s) {
              if (!s.hasData) return const Center(child: CircularProgressIndicator());
              return _content(s.data![0], s.data![1], s.data![2]);
            },
          ),
        ),
      );

  Widget _content(List<dynamic> assets, List<dynamic> warranties, List<dynamic> docs) {
    // latest warranty expiry per asset
    final expiry = <int, DateTime>{};
    for (final w in warranties) {
      final id = w['asset_id'];
      final d = DateTime.tryParse('${w['expiry_date']}');
      if (id is int && d != null && (expiry[id] == null || d.isAfter(expiry[id]!))) expiry[id] = d;
    }
    final docCount = <int, int>{};
    for (final d in docs) {
      final id = d['asset_id'];
      if (id is int) docCount[id] = (docCount[id] ?? 0) + 1;
    }

    final cats = ['All', 'Kitchen', 'Living Room', 'Bedroom', 'Bathroom'];
    for (final a in assets) {
      final r = '${a['room'] ?? ''}'.trim();
      if (r.isNotEmpty && !cats.any((x) => x.toLowerCase() == r.toLowerCase())) cats.add(r);
    }

    final q = _search.text.trim().toLowerCase();
    final items = assets.where((a) {
      final inCat = _cat == 'All' || '${a['room'] ?? ''}'.toLowerCase() == _cat.toLowerCase();
      final txt = '${a['name']} ${a['brand'] ?? ''} ${a['model'] ?? ''}'.toLowerCase();
      return inCat && (q.isEmpty || txt.contains(q));
    }).toList();
    if (_sort == 'Name A-Z') {
      items.sort((a, b) => '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase()));
    } else if (_sort == 'Price: high to low') {
      double p(x) => double.tryParse('${x['price'] ?? 0}') ?? 0;
      items.sort((a, b) => p(b).compareTo(p(a)));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Text('Asset Inventory', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: kNavy)),
      ),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 2, 16, 12),
        child: Text('Manage all your home assets in one place', style: TextStyle(color: Color(0xFF5A6785))),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Expanded(
            child: SizedBox(
              height: 48,
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search assets...',
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
          const SizedBox(width: 10),
          PopupMenuButton<String>(
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => [
              for (final o in ['Newest', 'Name A-Z', 'Price: high to low'])
                PopupMenuItem(value: o, child: Text(o, style: TextStyle(fontWeight: o == _sort ? FontWeight.w800 : FontWeight.w400))),
            ],
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: kBorder)),
              child: const Icon(Icons.tune_rounded, color: kNavy),
            ),
          ),
        ]),
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
            ? _empty(assets.isEmpty)
            : RefreshIndicator(
                onRefresh: () async => _reload(),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  itemCount: items.length,
                  itemBuilder: (_, i) => _card(items[i], expiry, docCount),
                ),
              ),
      ),
    ]);
  }

  Widget _empty(bool noAssetsAtAll) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircleAvatar(radius: 36, backgroundColor: Color(0xFFE3EEFF), child: Icon(Icons.inventory_2_rounded, size: 34, color: kBlue)),
            const SizedBox(height: 14),
            Text(noAssetsAtAll ? 'No assets yet' : 'No matching assets', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kNavy)),
            const SizedBox(height: 4),
            const Text('Tap + to add your first asset', style: TextStyle(color: Color(0xFF5A6785))),
            if (noAssetsAtAll) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(onPressed: _seed, icon: const Icon(Icons.auto_awesome), label: const Text('Load sample data')),
            ],
          ]),
        ),
      );

  Widget _card(Map<String, dynamic> a, Map<int, DateTime> expiry, Map<int, int> docCount) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final exp = expiry[a['id']];
    final fmt = DateFormat('MMM yyyy');

    Widget pill;
    String infoLabel = 'Valid till', infoValue = '-';
    if (exp == null) {
      pill = StatusPill.grey('No warranty');
      final pd = DateTime.tryParse('${a['purchase_date']}');
      if (pd != null) {
        infoLabel = 'Purchased';
        infoValue = fmt.format(pd);
      }
    } else if (!exp.isBefore(today)) {
      pill = StatusPill.green('Under Warranty');
      infoValue = fmt.format(exp);
    } else {
      pill = StatusPill.blue('Warranty Expired');
      final pd = DateTime.tryParse('${a['purchase_date']}');
      infoLabel = pd != null ? 'Purchased' : 'Expired';
      infoValue = fmt.format(pd ?? exp);
    }
    final docs = docCount[a['id']] ?? 0;
    final sub = [a['brand'], a['model']].where((e) => e != null && '$e'.isNotEmpty).join(' • ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _details(a),
        onLongPress: () => _confirmDelete(a),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: softShadow()),
          child: Row(children: [
            PhotoThumb(src: a['photo_url'], w: 78, h: 96),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${a['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kNavy)),
                if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFF5A6785))),
                const SizedBox(height: 6),
                pill,
                const SizedBox(height: 8),
                Wrap(spacing: 14, runSpacing: 6, children: [
                  _info(Icons.event_outlined, infoLabel, infoValue),
                  _info(Icons.description_outlined, null, docs == 1 ? '1 document' : '$docs documents'),
                ]),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF8A94A8)),
          ]),
        ),
      ),
    );
  }

  Widget _info(IconData icon, String? label, String value) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: const Color(0xFF5A6785)),
        const SizedBox(width: 4),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (label != null) Text(label, style: const TextStyle(fontSize: 9, color: Color(0xFF8A94A8), height: 1.1)),
          Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: kNavy, height: 1.2)),
        ]),
      ]);

  Future<void> _details(Map<String, dynamic> a) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => AssetDetailScreen(asset: a)));
    if (mounted) _reload();
  }

  Future<void> _confirmDelete(Map<String, dynamic> a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete asset?'),
        content: Text('"${a['name']}" will be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) {
      await Api.remove('assets', a['id']);
      _reload();
    }
  }
}