import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stall/main.dart';
import 'package:stall/screens/checkout.dart';
import 'package:stall/screens/extras.dart';

import 'buy_test.dart' show order;
import 'helpers.dart';
import 'store_test.dart' show myStore;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    receiptWebView = false;
  });

  Future<void> settle(WidgetTester t) async {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pumpAndSettle();
  }

  Future<FakeApi> start(WidgetTester t, Map<String, FakeRoute> routes, {Map<String, dynamic> me = const {}}) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final f = FakeApi({
      'GET config': (_) => (200, {'creditPct': 50}),
      'GET me': (_) => (200, {'user': {...user(), ...me}}),
      'GET listings': (_) => (200, {'listings': [], 'total': 0}),
      ...routes,
    });
    await f.store.write('a' * 64);
    final s = f.session();
    await t.pumpWidget(StallApp(session: s));
    await t.runAsync(s.restore);
    await settle(t);
    return f;
  }

  Map<String, dynamic> body(FakeApi f, String path) =>
      jsonDecode(f.calls.lastWhere((c) => c.url.path == '/api/$path' && c.method == 'POST').body) as Map<String, dynamic>;

  Future<void> tap(WidgetTester t, String key) async {
    final f = find.byKey(Key(key));
    if (f.evaluate().isEmpty) await t.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
    await t.ensureVisible(f);
    await t.pumpAndSettle();
    await t.tap(f);
    await settle(t);
  }

  testWidgets('badges: a new one is celebrated once, with progress to the next', (t) async {
    final f = await start(t, {
      'GET me/milestones': (_) => (200, {
            'sell': {'count': 6, 'earned': [1, 5], 'next': 10, 'fresh': 5},
            'buy': {'count': 2, 'earned': [1], 'next': 5, 'fresh': null},
            'name': 'Ada',
            'store': null,
            'school': 'ACU',
          }),
      'POST me/milestones': (_) => (200, {'ok': true}),
    });
    await t.tap(find.text('Account'));
    await settle(t);
    await tap(t, 'badgesTile');
    expect(find.text('5th sale on Stall'), findsOneWidget);
    expect(find.text('RISING SELLER'), findsOneWidget);
    expect(body(f, 'me/milestones'), {'kind': 'sell', 'n': 5});
    expect(find.text('6 completed sales · 4 more to 10 sales'), findsOneWidget);
    expect(find.text('2 safe buys · 3 more to 5 safe buys'), findsOneWidget);
  });

  testWidgets('payments to Stall open their receipts; a completed order has one too', (t) async {
    await start(t, {
      'GET pay/mine': (_) => (200, {
            'pays': [
              {'ref': 'R9', 'kind': 'boost', 'label': 'Featured: Desk lamp', 'paid': 500, 'credit': 0, 't': DateTime(2026, 10, 10).millisecondsSinceEpoch},
            ]
          }),
      'GET pay/receipt': (r) => (200, {'html': '<b>Receipt</b>', 'text': 'Stall receipt\nFeatured: ₦500\nRef ${r.url.queryParameters['ref']}', 'title': 'Receipt: Desk lamp'}),
      'GET orders/mine': (_) => (200, {'orders': [order(40, status: 'released', extra: {'rated': 5})]}),
      'GET orders/receipt': (r) => (200, {'html': '', 'text': 'Stall receipt\nOrder #${r.url.queryParameters['id']}', 'title': 'Receipt'}),
    });
    await t.tap(find.text('Account'));
    await settle(t);
    await tap(t, 'paymentsTile');
    expect(find.text('Featured: Desk lamp'), findsOneWidget);
    await tap(t, 'pay-R9');
    expect(find.textContaining('Ref R9'), findsOneWidget);
    expect(find.byKey(const Key('shareReceipt')), findsOneWidget);

    await t.pageBack();
    await settle(t);
    await t.pageBack();
    await settle(t);
    await t.tap(find.text('Orders'));
    await settle(t);
    await t.tap(find.byKey(const Key('order-40')));
    await settle(t);
    await tap(t, 'receipt');
    expect(find.textContaining('Order #40'), findsOneWidget);
  });

  testWidgets('a partner banner shows on Home and is counted', (t) async {
    final f = await start(t, {'POST partner/seen': (_) => (200, {'ok': true})}, me: {
      'partners': [
        {'id': 3, 'name': 'ACUSA', 'label': 'Partner', 'title': 'ACUSA Week is here', 'text': 'Free stalls for members', 'url': '', 'cta': '', 'img': null},
      ]
    });
    expect(find.text('ACUSA Week is here'), findsOneWidget);
    expect(body(f, 'partner/seen'), {'id': 3});
  });

  testWidgets('store owners get a QR card, and can use credit for reach', (t) async {
    final f = await start(t, {
      'GET stores': (_) => (200, {'stores': [myStore()]}),
      'POST pay/start': (_) => (200, {'url': 'https://checkout.paystack.com/z', 'ref': 'Z1'}),
      'POST pay/confirm': (_) => (200, {'ok': true}),
    }, me: {'role': 'vendor', 'credit': 1500});
    openPaystack = (context, url) async => 'Z1';
    await t.tap(find.text('Sell'));
    await settle(t);
    await tap(t, 'qrStore');
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('Mama T Kitchen'), findsOneWidget);
    await t.pageBack();
    await settle(t);

    await tap(t, 'reach-state');
    expect(find.textContaining('You have ₦1,500 Stall credit'), findsOneWidget);
    await tap(t, 'useCredit');
    expect(body(f, 'pay/start'), {'kind': 'reach', 'target': 'S5', 'level': 'state', 'credit': true});
  });
}
