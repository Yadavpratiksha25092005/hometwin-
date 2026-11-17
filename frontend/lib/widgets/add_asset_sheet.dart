import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api.dart';
import '../main.dart';

/// New "Add Asset" bottom sheet (only used by the Assets screen; other forms still use AddForm).
class AddAssetSheet extends StatefulWidget {
  const AddAssetSheet({super.key});

  /// Opens the sheet. Returns true after the asset was saved.
  static Future<bool?> show(BuildContext context) => showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const AddAssetSheet(),
      );

  @override
  State<AddAssetSheet> createState() => _AddAssetSheetState();
}

class _AddAssetSheetState extends State<AddAssetSheet> {
  static const _ink = Color(0xFF1A1240);
  static const _soft = Color(0xFF6B7690);
  static const _rooms = ['Living Room', 'Kitchen', 'Bedroom', 'Bathroom', 'Dining Room', 'Balcony', 'Study', 'Garage', 'Other'];

  final _name = TextEditingController();
  final _brand = TextEditingController();
  final _model = TextEditingController();
  final _serial = TextEditingController();
  final _date = TextEditingController();
  final _price = TextEditingController();
  String? _room;
  String? _dateIso; // yyyy-MM-dd, what the server stores
  String? _photoUrl, _photoName, _photoPath;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _brand, _model, _serial, _date, _price]) {
      c.dispose();
    }
    super.dispose();
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  InputDecoration _dec(String? hint, IconData icon, {Widget? suffix}) => InputDecoration(
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
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: Color(0xFFDCD2FA))),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: Color(0xFFDCD2FA))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: kBlue, width: 1.4)),
      );

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (d == null) return;
    setState(() {
      _dateIso = DateFormat('yyyy-MM-dd').format(d);
      _date.text = DateFormat('dd MMM yyyy').format(d);
    });
  }

  Future<void> _pickPhoto() async {
    final file = await FilePicker.pickFile();
    final p = file?.path;
    if (p == null) return;
    setState(() => _busy = true);
    try {
      _photoUrl = await Api.upload(p);
      _photoName = file!.name;
      _photoPath = p;
    } catch (e) {
      _snack('$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _save() async {
    String? problem;
    if (_name.text.trim().isEmpty) {
      problem = 'Device name is required';
    } else if (_room == null) {
      problem = 'Please choose a room';
    } else if (_brand.text.trim().isEmpty) {
      problem = 'Brand is required';
    }
    if (problem != null) {
      _snack(problem);
      return;
    }
    final data = <String, dynamic>{'name': _name.text.trim(), 'room': _room, 'brand': _brand.text.trim()};
    void put(String key, String? v) {
      if (v != null && v.trim().isNotEmpty) data[key] = v.trim();
    }

    put('model', _model.text);
    put('serial_no', _serial.text);
    put('purchase_date', _dateIso);
    put('price', _price.text);
    put('photo_url', _photoUrl);
    setState(() => _busy = true);
    try {
      await Api.create('assets', data);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _snack('$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
            child: const Icon(Icons.view_in_ar_rounded, color: Colors.white, size: 32),
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Add Asset', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: _ink, letterSpacing: -0.4)),
            SizedBox(height: 2),
            Text('Enter the details of your asset', style: TextStyle(fontSize: 14.5, color: _soft)),
          ]),
        ),
        InkWell(
          customBorder: const CircleBorder(),
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: kBlue.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 4))]),
            child: const Icon(Icons.close_rounded, color: _ink),
          ),
        ),
      ]);

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
                    TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: _dec('Device name (e.g. Fridge, AC, TV...) *', Icons.desktop_windows_outlined)),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      value: _room,
                      isExpanded: true,
                      borderRadius: BorderRadius.circular(20),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: kBlue, size: 28),
                      hint: const Text('Room (Kitchen / Living Room ...) *', style: TextStyle(color: _soft, fontSize: 16)),
                      decoration: _dec(null, Icons.weekend_outlined),
                      items: [for (final r in _rooms) DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontSize: 16, color: _ink)))],
                      onChanged: (v) => setState(() => _room = v),
                    ),
                    const SizedBox(height: 14),
                    TextField(controller: _brand, textCapitalization: TextCapitalization.words, decoration: _dec('Brand *', Icons.sell_outlined)),
                    const SizedBox(height: 14),
                    TextField(controller: _model, decoration: _dec('Model (optional)', Icons.view_in_ar_outlined)),
                    const SizedBox(height: 14),
                    TextField(controller: _serial, decoration: _dec('Serial No (optional)', Icons.qr_code_2_rounded)),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _date,
                      readOnly: true,
                      onTap: _pickDate,
                      decoration: _dec('Purchase date', Icons.calendar_month_outlined, suffix: const Padding(padding: EdgeInsets.only(right: 14), child: Icon(Icons.calendar_today_outlined, color: _ink))),
                    ),
                    const SizedBox(height: 14),
                    TextField(controller: _price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: _dec('Price', Icons.currency_rupee_rounded)),
                    const SizedBox(height: 14),
                    if (_photoPath != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.file(File(_photoPath!), height: 130, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
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
                        onPressed: _busy ? null : _pickPhoto,
                        icon: Icon(_photoPath == null ? Icons.photo_camera_outlined : Icons.check_circle_rounded, size: 26),
                        label: Text(_photoName ?? 'Add Photo', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      ),
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
                                    Icon(Icons.save_outlined, color: Colors.white, size: 26),
                                    SizedBox(width: 10),
                                    Text('Save', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700)),
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