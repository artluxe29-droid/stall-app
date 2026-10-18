import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stall/collect_export.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final c = {'title': 'GST 101 handout', 'cls': '200L Accounting', 'school': 'ACU', 'rep': 'Ada Obi', 'amount': 1500, 'expected': 60, 'code': 'AB12CD'};
  final paid = [
    for (var i = 0; i < 45; i++) {'id': i, 'name': 'Student ${String.fromCharCode(90 - i % 26)} $i', 't': 1760000000000 + i * 60000, 'ref': 'R$i', 'ticked': i.isEven},
  ];

  test('the paid list as a PDF, several pages for a long list', () async {
    final bytes = await paidPdf(c, paid, host: 'stall.com.ng');
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    final out = Platform.environment['PDF_OUT'];
    if (out != null) File(out).writeAsBytesSync(bytes);
  });

  test('the paid list as a spreadsheet, A to Z', () {
    final bytes = paidCsv(paid);
    expect(bytes.take(3), [0xEF, 0xBB, 0xBF]); // so Excel reads it as UTF-8
    final lines = utf8.decode(bytes.skip(3).toList()).trim().split('\r\n');
    expect(lines.first, '"#","Name","Paid","Amount","Reference","Collected"');
    expect(lines, hasLength(46));
    expect(lines[1], startsWith('"1","Student A '));
  });
}
