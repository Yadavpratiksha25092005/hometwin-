import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api.dart';

enum FType { text, number, date, asset, file, multiline }

class FieldDef {
  final String key, label;
  final FType type;
  const FieldDef(this.key, this.label, [this.type = FType.text]);
}

/// Generic list + add + delete screen (documents, scans ...).
class ResourceScreen extends StatefulWidget {
  final String title, path, titleKey;
  final String? subtitleKey;
  final IconData icon;
  final List<FieldDef> fields;
  final bool embedded; // true = inside bottom-nav (no back button)
  const ResourceScreen({
    super.key,
    required this.title,
    required this.path,
    required this.fields,
    required this.titleKey,
    this.subtitleKey,
    this.icon = Icons.inventory_2,
    this.embedded = false,
  });
  @override
  State<ResourceScreen> createState() => _ResourceScreenState();
}

class _ResourceScreenState extends State<ResourceScreen> {
  late Future<List<dynamic>> _future = Api.list(widget.path);
  void _reload() => setState(() {
        _future = Api.list(widget.path);
      });

  Future<void> _add() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddForm(title: widget.title, path: widget.path, fields: widget.fields),
    );
    if (saved == true) _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.title), automaticallyImplyLeading: !widget.embedded),
        floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.add)),
        body: FutureBuilder<List<dynamic>>(
          future: _future,
          builder: (c, s) {
            if (s.hasError) return Center(child: Text('${s.error}'));
            if (!s.hasData) return const Center(child: CircularProgressIndicator());
            final items = s.data!;
            if (items.isEmpty) return Center(child: Text('No ${widget.title.toLowerCase()} yet. Tap + to add.'));
            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 80),
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final it = items[i] as Map<String, dynamic>;
                  return Dismissible(
                    key: ValueKey(it['id']),
                    direction: DismissDirection.endToStart,
                    background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: Colors.white)),
                    onDismissed: (_) async {
                      await Api.remove(widget.path, it['id']);
                      _reload();
                    },
                    child: Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(child: Icon(widget.icon)),
                        title: Text('${it[widget.titleKey] ?? '-'}'),
                        subtitle: widget.subtitleKey == null ? null : Text('${it[widget.subtitleKey] ?? ''}'),
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

/// Bottom-sheet form. Pops `true` after saving.
class AddForm extends StatefulWidget {
  final String title, path;
  final List<FieldDef> fields;
  final Map<String, dynamic>? initial; // pre-filled hidden values
  const AddForm({super.key, required this.title, required this.path, required this.fields, this.initial});
  @override
  State<AddForm> createState() => _AddFormState();
}

class _AddFormState extends State<AddForm> {
  final Map<String, dynamic> _data = {};
  final Map<String, TextEditingController> _ctl = {};
  List<dynamic> _assets = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _data.addAll(widget.initial ?? {});
    for (final f in widget.fields) {
      _ctl[f.key] = TextEditingController();
    }
    if (widget.fields.any((f) => f.type == FType.asset)) {
      Api.list('assets').then((a) => mounted ? setState(() => _assets = a) : null);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      for (final f in widget.fields) {
        if (f.type == FType.text || f.type == FType.number || f.type == FType.multiline) {
          final v = _ctl[f.key]!.text.trim();
          if (v.isNotEmpty) _data[f.key] = v;
        }
      }
      await Api.create(widget.path, _data);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(FieldDef f) {
    switch (f.type) {
      case FType.date:
        return TextField(
          controller: _ctl[f.key],
          readOnly: true,
          decoration: InputDecoration(labelText: f.label, suffixIcon: const Icon(Icons.calendar_today), border: const OutlineInputBorder()),
          onTap: () async {
            final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
            if (d != null) {
              final s = DateFormat('yyyy-MM-dd').format(d);
              _ctl[f.key]!.text = s;
              _data[f.key] = s;
            }
          },
        );
      case FType.asset:
        return DropdownButtonFormField<int>(
          decoration: InputDecoration(labelText: f.label, border: const OutlineInputBorder()),
          items: [for (final a in _assets) DropdownMenuItem(value: a['id'] as int, child: Text('${a['name']}'))],
          onChanged: (v) => _data[f.key] = v,
        );
      case FType.file:
        return OutlinedButton.icon(
          icon: const Icon(Icons.attach_file),
          label: Text(_ctl[f.key]!.text.isEmpty ? f.label : _ctl[f.key]!.text),
          onPressed: () async {
            final file = await FilePicker.pickFile();
            final p = file?.path;
            if (p == null) return;
            setState(() => _busy = true);
            try {
              _data[f.key] = await Api.upload(p);
              _ctl[f.key]!.text = file!.name;
            } catch (e) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
            }
            if (mounted) setState(() => _busy = false);
          },
        );
      default:
        return TextField(
          controller: _ctl[f.key],
          keyboardType: f.type == FType.number ? TextInputType.number : TextInputType.text,
          maxLines: f.type == FType.multiline ? 3 : 1,
          decoration: InputDecoration(labelText: f.label, border: const OutlineInputBorder()),
        );
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Add ${widget.title}', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            for (final f in widget.fields) ...[_field(f), const SizedBox(height: 12)],
            FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Please wait...' : 'Save')),
          ]),
        ),
      );
}