import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stall/bag.dart';
import 'package:stall/main.dart';
import 'package:stall/models.dart';
import 'package:stall/screens/checkout.dart';

import 'browse_test.dart' show listing;
import 'helpers.dart';

Map<String, dynamic> order(int id, {String status = 'pending', Map<String, dynamic> extra = const {}}) => {
      'id': id,
      'title': 'Calculus textbook',
      'amount': 4500,
      'sub': 4500,
      'fee': 225,
      'status': status,
      'deadline': DateTime.now().millisecondsSinceEpoch + 15 * 60000,
      'code': status == 'verified' ? 'STALL-AB12CD' : null,
      'note': '',
      'sellerName': 'Tolu A.',
      'sellerPhone': '08031234567',
      'card': true,
      'paidVia': status == 'pending' ? null : 'paystack',
      'deliv': {'on': true, 'fee': 500, 'note': 'Hostels only'},
      'pickup': 'Library',
      'method': status == 'pending' ? null : 'pickup',
      'early': true,
      ...extra,
    };

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> settle(WidgetTester t) async {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
  }

  Future<FakeApi> signedIn(WidgetTester t, Map<String, FakeRoute> routes) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final f = FakeApi({'GET config': (_) => (200, {}), 'GET me': (_) => (200, {'user': user()}), ...routes});
    await f.store.write('a' * 64);
    final s = f.session();
    await t.pumpWidget(StallApp(session: s));
    await t.runAsync(s.restore);
    await settle(t);
    return f;
  }

  Map<String, dynamic> body(FakeApi f, String path) =>
      jsonDecode(f.calls.lastWhere((c) => c.url.path == '/api/$path').body) as Map<String, dynamic>;

  Future<void> tap(WidgetTester t, Finder f) async {
    if (f.evaluate().isEmpty) await t.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).last);
    await t.ensureVisible(f);
    await t.pump();
    await t.tap(f);
    await settle(t);
  }

  testWidgets('buy now: agree, place the order, choose delivery, pay on Paystack, get the release code', (t) async {
    var paid = false;
    final f = await signedIn(t, {
      'GET listings': (_) => (200, {'listings': [listing(1)], 'total': 1}),
      'POST orders/create': (_) => (200, {'orders': [order(31)]}),
      'POST pay/start': (_) => (200, {'url': 'https://checkout.paystack.com/abc', 'ref': 'ref_123456'}),
      'POST pay/confirm': (_) {
        paid = true;
        return (200, {'ok': true});
      },
      'GET orders/mine': (_) => (200, {'orders': [paid ? order(31, status: 'verified', extra: {'method': 'delivery', 'addr': 'Hall B, Room 214'}) : order(31)]}),
    });
    String? opened;
    openPaystack = (context, url) async {
      opened = url;
      return 'ref_123456';
    };

    await tap(t, find.byKey(const Key('item-L1')));
    await tap(t, find.byKey(const Key('buyNow')));
    expect(find.text('Check out'), findsWidgets);

    // Must agree first.
    await tap(t, find.byKey(const Key('placeOrder')));
    expect(find.text('Tick the box to agree to how Stall holds your payment.'), findsOneWidget);
    expect(f.calls.where((c) => c.url.path == '/api/orders/create'), isEmpty);
    await tap(t, find.byKey(const Key('agree')));
    await tap(t, find.byKey(const Key('placeOrder')));
    expect(body(f, 'orders/create'), {'items': ['L1'], 'consent': true});

    // Pay screen: delivery adds the seller's fee and needs an address.
    expect(find.text('Pay Tolu A.'), findsOneWidget);
    expect(find.text('₦4,500'), findsWidgets);
    await tap(t, find.byKey(const Key('delivery-31')));
    expect(find.byKey(const Key('payTotal')), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const Key('payTotal'))).data, '₦5,000');
    await tap(t, find.byKey(const Key('pay')));
    expect(find.byKey(const Key('payError')), findsOneWidget);
    await t.enterText(find.byKey(const Key('addr')), 'Hall B, Room 214');
    await tap(t, find.byKey(const Key('pay')));
    await settle(t);

    expect(body(f, 'pay/start'), {
      'kind': 'cart',
      'orders': [
        {'id': 31, 'method': 'delivery'}
      ],
      'addr': 'Hall B, Room 214',
      'dphone': '08031234567',
    });
    expect(opened, 'https://checkout.paystack.com/abc');
    expect(body(f, 'pay/confirm'), {'reference': 'ref_123456'});
    expect(find.text('Payment verified'), findsOneWidget);
    expect(find.text('STALL-AB12CD'), findsOneWidget);
    expect(find.text('Give this code to Tolu A. when your order arrives at Hall B, Room 214.'), findsOneWidget);
    expect(SessionScope.of(t.element(find.byType(PaidScreen))).bag.count, 0);
  });

  testWidgets('closing Paystack without paying keeps the order waiting', (t) async {
    final f = await signedIn(t, {
      'GET listings': (_) => (200, {'listings': [listing(1)], 'total': 1}),
      'POST orders/create': (_) => (200, {'orders': [order(32)]}),
      'POST pay/start': (_) => (200, {'url': 'https://checkout.paystack.com/x', 'ref': 'ref_999999'}),
      'POST pay/confirm': (_) => (402, {'error': 'Payment could not be confirmed.', 'notPaid': true}),
    });
    openPaystack = (context, url) async => null;
    await tap(t, find.byKey(const Key('item-L1')));
    await tap(t, find.byKey(const Key('buyNow')));
    await tap(t, find.byKey(const Key('agree')));
    await tap(t, find.byKey(const Key('placeOrder')));
    await tap(t, find.byKey(const Key('pay')));
    await settle(t);
    expect(body(f, 'pay/confirm'), {'reference': 'ref_999999'});
    expect(find.textContaining('Payment not finished'), findsOneWidget);
    expect(find.text('Pay Tolu A.'), findsOneWidget);
  });

  testWidgets('the bag keeps items, counts stock and remembers them', (t) async {
    await signedIn(t, {
      'GET listings': (_) => (200, {'listings': [listing(1, extra: {'qty': 3, 'qtyLeft': 2})], 'total': 1}),
    });
    await tap(t, find.byKey(const Key('item-L1')));
    await tap(t, find.byKey(const Key('addToBag')));
    await tap(t, find.byKey(const Key('addToBag')));
    await tap(t, find.byKey(const Key('addToBag')));
    expect(find.text('No more in stock'), findsOneWidget);
    await tap(t, find.byKey(const Key('bagButton')));
    expect(find.text('₦9,000'), findsWidgets);
    await tap(t, find.byKey(const Key('dec-L1')));
    expect(t.widget<Text>(find.byKey(const Key('bagTotal'))).data, '₦4,500');

    final saved = (await SharedPreferences.getInstance()).getString('bag')!;
    final again = Bag();
    SharedPreferences.setMockInitialValues({'bag': saved});
    await again.load();
    expect(again.apiItems, ['L1']);
  });

  testWidgets('orders: see the release code, confirm you got it, then rate the seller', (t) async {
    var status = 'verified';
    final f = await signedIn(t, {
      'GET listings': (_) => (200, {'listings': [], 'total': 0}),
      'GET orders/mine': (_) => (200, {'orders': [order(40, status: status, extra: {'holdUntil': DateTime(2026, 10, 20).millisecondsSinceEpoch})]}),
      'POST orders/received': (_) {
        status = 'released';
        return (200, {'ok': true});
      },
      'POST orders/rate': (_) => (200, {'ok': true}),
    });
    await t.tap(find.text('Orders'));
    await settle(t);
    expect(find.text('Paid'), findsOneWidget);
    await tap(t, find.byKey(const Key('order-40')));
    expect(find.text('STALL-AB12CD'), findsOneWidget);
    expect(find.textContaining('the seller is paid on Tue, 20 Oct'), findsOneWidget);

    await tap(t, find.byKey(const Key('gotIt')));
    await tap(t, find.byKey(const Key('confirmYes')));
    expect(body(f, 'orders/received'), {'id': 40});
    expect(find.text('Completed'), findsOneWidget);

    await tap(t, find.byKey(const Key('star-4')));
    await tap(t, find.byKey(const Key('sendRating')));
    expect(body(f, 'orders/rate'), {'id': 40, 'stars': 4, 'text': ''});
  });

  testWidgets('an unpaid order can be paid or cancelled from Orders', (t) async {
    final f = await signedIn(t, {
      'GET listings': (_) => (200, {'listings': [], 'total': 0}),
      'GET orders/mine': (_) => (200, {'orders': [order(41)]}),
      'POST orders/cancel': (_) => (200, {'ok': true}),
    });
    await t.tap(find.text('Orders'));
    await settle(t);
    expect(find.text('Awaiting payment'), findsOneWidget);
    await tap(t, find.byKey(const Key('order-41')));
    expect(find.byKey(const Key('payNow')), findsOneWidget);
    await tap(t, find.byKey(const Key('cancelPending')));
    await tap(t, find.byKey(const Key('confirmYes')));
    expect(body(f, 'orders/cancel'), {'id': 41});
  });

  test('order badges and steps read like the web app', () {
    expect(Order(order(1)).badge, 'Awaiting payment');
    expect(Order(order(1, status: 'verified', extra: {'handedAt': 1})).badge, 'Handed over');
    expect(Order(order(1, status: 'expired', extra: {'note': 'You cancelled this order before paying.'})).badge, 'Cancelled');
    expect(Order(order(1, status: 'verified', extra: {'method': 'delivery', 'stage': 'packed'})).steps,
        [('Paid', true), ('Packed', true), ('On the way', false), ('Delivered', false)]);
    expect(Order(order(1, status: 'released')).steps.every((s) => s.$2), isTrue);
    expect(clock(61000), '1:01');
  });
}
