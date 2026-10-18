import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'theme.dart';

// The class rep's "who has paid" list, A to Z, as a branded PDF (more pages for long lists) or a spreadsheet (CSV).

String _date(int ms) {
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.day} ${m[d.month - 1]} ${d.year}';
}

String _time(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '${_date(ms)}, $h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'am' : 'pm'}';
}

List<Map<String, dynamic>> _sorted(List<Map<String, dynamic>> paid) =>
    [...paid]..sort((a, b) => (a['name'] ?? '').toString().toLowerCase().compareTo((b['name'] ?? '').toString().toLowerCase()));

String collectionFileName(Map<String, dynamic> c) {
  final s = (c['title'] ?? 'collection').toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
  return 'stall-${s.length > 40 ? s.substring(0, 40) : s}-paid';
}

/// Spreadsheet: one row per person who paid.
Uint8List paidCsv(List<Map<String, dynamic>> paid) {
  String q(Object? v) => '"${(v ?? '').toString().replaceAll('"', '""')}"';
  final rows = [
    ['#', 'Name', 'Paid', 'Amount', 'Reference', 'Collected'].map(q).join(','),
    for (final (i, p) in _sorted(paid).indexed)
      [i + 1, p['name'], _time((p['t'] as num?)?.toInt() ?? 0), p['amount'] ?? '', p['ref'] ?? '', p['ticked'] == true ? 'Yes' : 'No'].map(q).join(','),
  ];
  return Uint8List.fromList(utf8.encode('﻿${rows.join('\r\n')}\r\n'));
}

final _fonts = <String, ByteData>{};

/// PDF: the Stall header with the totals, then the list A to Z with page numbers.
Future<Uint8List> paidPdf(Map<String, dynamic> c, List<Map<String, dynamic>> paid, {required String host}) async {
  const indigo = PdfColor.fromInt(0xFF26306E), deep = PdfColor.fromInt(0xFF1C2457), lime = PdfColor.fromInt(0xFFC8F03C);
  const cream = PdfColor.fromInt(0xFFF6F1E7), grey = PdfColor.fromInt(0xFFCCCACF), muted = PdfColor.fromInt(0xFF5B6077);
  final rows = _sorted(paid);
  final amount = (c['amount'] as num?) ?? 0;
  final total = rows.fold<num>(0, (a, r) => a + ((r['amount'] as num?) ?? amount));
  final expected = c['expected'];
  // Figtree like the app; Bricolage fills in the ₦ sign, which Figtree doesn't have.
  pw.Font font(String f) => pw.Font.ttf(_fonts[f]!);
  for (final f in ['Figtree_400Regular', 'Figtree_700Bold', 'BricolageGrotesque_700Bold']) {
    _fonts[f] ??= await rootBundle.load('assets/fonts/$f.ttf');
  }
  final wordmark = pw.MemoryImage((await rootBundle.load('assets/receipt/wm-cream.png')).buffer.asUint8List());
  final doc = pw.Document(
    title: '${c['title']} - paid list',
    theme: pw.ThemeData.withFont(
        base: font('Figtree_400Regular'), bold: font('Figtree_700Bold'), fontFallback: [font('BricolageGrotesque_700Bold')]),
  );
  pw.Widget stat(String v, String l, {bool hot = false}) => pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.only(right: 6),
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: pw.BoxDecoration(color: deep, borderRadius: pw.BorderRadius.circular(8)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(v, style: pw.TextStyle(color: hot ? lime : cream, fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.Text(l, style: const pw.TextStyle(color: grey, fontSize: 8)),
          ]),
        ),
      );
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(32, 24, 32, 28),
    header: (ctx) => ctx.pageNumber == 1
        ? pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 14),
            padding: const pw.EdgeInsets.fromLTRB(18, 16, 18, 16),
            decoration: pw.BoxDecoration(color: indigo, borderRadius: pw.BorderRadius.circular(10)),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Image(wordmark, width: 58, height: 24),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: pw.BoxDecoration(color: lime, borderRadius: pw.BorderRadius.circular(8)),
                  child: pw.Text('PAID LIST', style: pw.TextStyle(color: deep, fontSize: 8, fontWeight: pw.FontWeight.bold, letterSpacing: 1.2)),
                ),
              ]),
              pw.SizedBox(height: 10),
              pw.Text((c['title'] ?? '').toString(), style: pw.TextStyle(color: cream, fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.Text([c['cls'], c['school'], if (c['rep'] != null) 'Collected by ${c['rep']}'].where((x) => (x ?? '').toString().isNotEmpty).join(' · '),
                  style: const pw.TextStyle(color: grey, fontSize: 9)),
              pw.SizedBox(height: 10),
              pw.Row(children: [
                stat(naira(amount), 'per person'),
                stat('${rows.length}${expected != null ? ' of $expected' : ''}', 'paid', hot: true),
                stat(naira(total), 'collected'),
                stat(_date(DateTime.now().millisecondsSinceEpoch), 'as of'),
              ]),
            ]),
          )
        : pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 10),
            child: pw.Text('${c['title']} · paid list, continued', style: pw.TextStyle(color: deep, fontSize: 11, fontWeight: pw.FontWeight.bold)),
          ),
    footer: (ctx) => pw.Container(
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: PdfColor.fromInt(0xFFE3DED2), width: 1))),
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('Paid through Stall · $host/c/${c['code']}', style: const pw.TextStyle(color: muted, fontSize: 8)),
        pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: const pw.TextStyle(color: muted, fontSize: 8)),
      ]),
    ),
    build: (ctx) => [
      if (rows.isEmpty)
        pw.Text('No one has paid yet.', style: const pw.TextStyle(color: muted, fontSize: 11))
      else
        pw.TableHelper.fromTextArray(
          headers: ['#', 'NAME', 'PAID', 'COLLECTED'],
          data: [
            for (final (i, r) in rows.indexed)
              ['${i + 1}', (r['name'] ?? '').toString(), _time((r['t'] as num?)?.toInt() ?? 0), r['ticked'] == true ? 'Given' : ''],
          ],
          headerStyle: pw.TextStyle(color: muted, fontSize: 8, fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(color: deep, fontSize: 10),
          headerDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColor.fromInt(0xFFE3DED2), width: 1.5))),
          oddRowDecoration: const pw.BoxDecoration(color: cream),
          border: null,
          columnWidths: {0: const pw.FixedColumnWidth(28), 1: const pw.FlexColumnWidth(), 2: const pw.FixedColumnWidth(130), 3: const pw.FixedColumnWidth(66)},
          headerAlignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerLeft, 2: pw.Alignment.centerLeft, 3: pw.Alignment.center},
          cellAlignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerLeft, 2: pw.Alignment.centerLeft, 3: pw.Alignment.center},
          cellHeight: 22,
        ),
    ],
  ));
  return doc.save();
}
