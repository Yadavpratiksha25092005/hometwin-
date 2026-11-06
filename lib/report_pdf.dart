import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'api.dart';

/// Builds the "Home Report" PDF from the app data (works in demo and server mode).
class ReportPdf {
  static const _blue = PdfColor.fromInt(0xFF0B6BE6);
  static const _navy = PdfColor.fromInt(0xFF0F1F4B);

  static String _date(dynamic v) {
    final d = DateTime.tryParse('${v ?? ''}');
    return d == null ? '-' : DateFormat('d MMM yyyy').format(d);
  }

  static String _money(dynamic v) {
    final n = num.tryParse('${v ?? ''}');
    return n == null ? '-' : 'Rs. ${NumberFormat('#,##0').format(n)}';
  }

  static String _text(dynamic v) => (v == null || '$v'.trim().isEmpty) ? '-' : '$v';

  static String _warrantyStatus(dynamic expiry) {
    final d = DateTime.tryParse('${expiry ?? ''}');
    if (d == null) return '-';
    final n = DateTime.now();
    final days = d.difference(DateTime(n.year, n.month, n.day)).inDays;
    if (days < 0) return 'Expired';
    if (days <= 30) return 'Expiring soon';
    return 'Active';
  }

  static pw.Widget _heading(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 18, bottom: 6),
        child: pw.Text(t, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _navy)),
      );

  static pw.Widget _table(List<String> headers, List<List<String>> rows) {
    if (rows.isEmpty) {
      return pw.Text('No records.', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700));
    }
    pw.Widget cell(String t, {bool head = false}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: pw.Text(
            t,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: head ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: head ? PdfColors.white : PdfColors.black,
            ),
          ),
        );
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _blue),
          children: [for (final h in headers) cell(h, head: true)],
        ),
        for (final r in rows) pw.TableRow(children: [for (final c in r) cell(c)]),
      ],
    );
  }

  static pw.Widget _stat(String label, String value) => pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.only(right: 6),
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400, width: 0.5), borderRadius: pw.BorderRadius.circular(4)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(value, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _blue)),
            pw.SizedBox(height: 2),
            pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
          ]),
        ),
      );

  /// Creates home_report.pdf in the temp folder and returns it.
  static Future<File> build() async {
    final data = jsonDecode(await Api.report()) as Map<String, dynamic>;
    List<Map<String, dynamic>> rows(String k) =>
        ((data[k] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

    final assets = rows('assets');
    final warranties = rows('warranties');
    final repairs = rows('repairs');
    final tasks = rows('tasks');
    final docs = rows('documents');
    final assetName = {for (final a in assets) a['id']: '${a['name']}'};
    String an(dynamic id) => assetName[id] ?? '-';

    num totalValue = 0;
    for (final a in assets) {
      totalValue += num.tryParse('${a['price'] ?? ''}') ?? 0;
    }
    num totalRepairs = 0;
    for (final r in repairs) {
      totalRepairs += num.tryParse('${r['cost'] ?? ''}') ?? 0;
    }

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(pageFormat: PdfPageFormat.a4, margin: pw.EdgeInsets.all(32)),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        ),
        build: (ctx) => [
          pw.Text('Home Digital Twin', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: _blue)),
          pw.Text('Home Report', style: pw.TextStyle(fontSize: 14, color: _navy)),
          pw.SizedBox(height: 2),
          pw.Text(
            'Prepared for ${Api.userName ?? ''}  |  Generated ${DateFormat('d MMM yyyy, h:mm a').format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 14),
          pw.Row(children: [
            _stat('Assets', '${assets.length}'),
            _stat('Total asset value', _money(totalValue)),
            _stat('Active warranties', '${warranties.where((w) => _warrantyStatus(w['expiry_date']) != 'Expired').length}'),
            _stat('Repair spend', _money(totalRepairs)),
          ]),
          _heading('Assets'),
          _table(
            ['Name', 'Category', 'Room', 'Brand / Model', 'Purchased', 'Price'],
            [
              for (final a in assets)
                [
                  _text(a['name']),
                  _text(a['category']),
                  _text(a['room']),
                  [a['brand'], a['model']].where((e) => e != null && '$e'.isNotEmpty).join(' ').isEmpty
                      ? '-'
                      : [a['brand'], a['model']].where((e) => e != null && '$e'.isNotEmpty).join(' '),
                  _date(a['purchase_date']),
                  _money(a['price']),
                ],
            ],
          ),
          _heading('Warranties'),
          _table(
            ['Asset', 'Provider', 'Start', 'Expiry', 'Status'],
            [
              for (final w in warranties)
                [an(w['asset_id']), _text(w['provider']), _date(w['start_date']), _date(w['expiry_date']), _warrantyStatus(w['expiry_date'])],
            ],
          ),
          _heading('Service history'),
          _table(
            ['Date', 'Work done', 'Asset', 'Provider', 'Cost'],
            [
              for (final r in repairs)
                [_date(r['repair_date']), _text(r['title']), an(r['asset_id']), _text(r['service_provider']), _money(r['cost'])],
            ],
          ),
          _heading('Maintenance tasks'),
          _table(
            ['Task', 'Asset', 'Start', 'Due'],
            [
              for (final t in tasks) [_text(t['title']), an(t['asset_id']), _date(t['start_date']), _date(t['due_date'])],
            ],
          ),
          _heading('Documents'),
          _table(
            ['Title', 'Category', 'Linked asset'],
            [
              for (final d in docs) [_text(d['title']), _text(d['category']), an(d['asset_id'])],
            ],
          ),
        ],
      ),
    );

    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/home_report.pdf');
    await f.writeAsBytes(await doc.save());
    return f;
  }
}