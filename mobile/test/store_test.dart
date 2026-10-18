import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stall/main.dart';
import 'package:stall/screens/checkout.dart';
import 'package:stall/screens/my_store.dart';
import 'package:stall/screens/sell.dart';

import 'helpers.dart';
import 'sell_test.dart' show photo;

Map<String, dynamic> myStore({Map<String, dynamic> extra = const {}, List<Map<String, dynamic>> items = const []}) => {
      'id': 'S5',
      'uid': 7,
      'name': 'Mama T Kitchen',
      'emoji': 'bowl',
      'cat': 'food',
      'desc': 'Hot meals from 11am',
      'spot': 'Cafeteria, Stall 4',
      'open': true,
      'deliv': {'on': false, 'fee': 0, 'note': ''},
      'rating': null,
      'school': 'ACU',
      'state': 'Oyo',
      'reach': 'school',
      'reachUntil': 0,
      'featured': false,
      'featuredUntil': 0,
      'founding': 0,
      'items': items,
      ...extra,
    };

Map<String, dynamic> storeItem(int id, {Map<String, dynamic> extra = const {}}) =>
    {'id': 'I$id', 'title': 'Jollof rice', 'price': 1500, 'desc': '', 'avail': true, 'qtyLeft': null, 'review': 'live', 'imgs': [], ...extra};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> settle(WidgetTester t) async {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pumpAndSettle();
  }

  /// A business, signed in, on the Sell tab (which is their store).
  Future<FakeApi> start(WidgetTester t, Map<String, FakeRoute> routes) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final f = FakeApi({
      'GET config': (_) => (200, {'fee': {'rate': 5, 'min': 150, 'cap': 2000}}),
      'GET me': (_) => (200, {'user': {...user(), 'role': 'vendor', 'vlevel': 0}}),
      'GET listings': (_) => (200, {'listings': [], 'total': 0}),
      'GET banks': (_) => (200, {'banks': [{'code': '058', 'name': 'GTBank'}]}),
      'POST bank/resolve': (_) => (200, {'name': 'TITI ADE'}),
      ...routes,
    });
    await f.store.write('a' * 64);
    final s = f.session();
    await t.pumpWidget(StallApp(session: s));
    await t.runAsync(s.restore);
    await settle(t);
    await t.tap(find.text('Sell'));
    await settle(t);
    return f;
  }

  Map<String, dynamic> body(FakeApi f, String path) =>
      jsonDecode(f.calls.lastWhere((c) => c.url.path == '/api/$path' && c.method == 'POST').body) as Map<String, dynamic>;

  Finder page() => find.byType(Scrollable).first;

  Future<void> tap(WidgetTester t, Finder f) async {
    if (f.evaluate().isEmpty) await t.scrollUntilVisible(f, 200, scrollable: page());
    await t.ensureVisible(f);
    await t.pumpAndSettle();
    await t.tap(f);
    await settle(t);
  }

  Future<void> tapKey(WidgetTester t, String k) => tap(t, find.byKey(Key(k)));

  /// Scrolls the screen until [f] is built, then checks it's there once.
  Future<void> see(WidgetTester t, Finder f) async {
    await settle(t); // let a reload that follows a save finish
    // Down first, then back up (a failed search ends with a failed check, so catch anything).
    for (final d in const [300.0, -300.0]) {
      if (f.evaluate().isNotEmpty) break;
      try {
        await t.scrollUntilVisible(f, d, scrollable: page(), maxScrolls: 15);
      } catch (_) {}
    }
    expect(f, findsWidgets);
  }

  Future<void> type(WidgetTester t, String k, String text) async {
    final f = find.byKey(Key(k));
    if (f.evaluate().isEmpty) await t.scrollUntilVisible(f, 200, scrollable: page());
    await t.ensureVisible(f);
    await t.enterText(f, text);
    await t.pump();
  }

  Future<void> fillStore(WidgetTester t) async {
    await type(t, 'st-name', 'Mama T Kitchen');
    await type(t, 'st-spot', 'Cafeteria, Stall 4');
    await tapKey(t, 'st-bank');
    await t.tap(find.text('GTBank').last);
    await t.pumpAndSettle();
    await type(t, 'st-acct', '0123456789');
    await tapKey(t, 'verifyBank');
    expect(find.text('✓ TITI ADE'), findsOneWidget);
  }

  testWidgets('open a store free with a store code, with a logo and icon', (t) async {
    Map<String, dynamic>? st;
    final f = await start(t, {
      'GET stores': (_) => (200, {'stores': [?st]}),
      'POST pay/start': (r) {
        st = myStore();
        return (200, {'ok': true, 'free': true, 'id': 'S5'});
      },
    });
    pickLogo = (_) async => photo;
    await tapKey(t, 'openStore');
    await see(t, find.text('Pay ₦5,000 and open store'));

    await tapKey(t, 'st-open');
    await see(t, find.text('Where can buyers find you?'));
    await see(t, find.text('Enter a store name.'));
    expect(f.calls.where((c) => c.url.path == '/api/pay/start'), isEmpty);

    await fillStore(t);
    await tapKey(t, 'icon-cup');
    await tapKey(t, 'st-logo');
    await tap(t, find.text('Have a free store code?'));
    await type(t, 'st-code', 'free-ab12cd');
    await see(t, find.text('Open my store free'));
    await tapKey(t, 'st-open');

    final b = body(f, 'pay/start');
    expect(b['kind'], 'store');
    expect(b['code'], 'FREE-AB12CD');
    expect(b['d'], {
      'name': 'Mama T Kitchen',
      'emoji': 'cup',
      'cat': 'books',
      'desc': '',
      'spot': 'Cafeteria, Stall 4',
      'phone': '08031234567',
      'bank_code': '058',
      'acct': '0123456789',
      'acctName': 'TITI ADE',
      'bank_manual': '',
      'logo': photo,
    });
    // A new store gets its "Now on Stall" kit straight away.
    expect(find.text('Your store is live'), findsOneWidget);
    expect(find.byKey(const Key('kit-post')), findsOneWidget);
    await t.pageBack();
    await settle(t);
    expect(find.text('Mama T Kitchen'), findsOneWidget);
    expect(find.text('Open: taking orders'), findsOneWidget);
  });

  testWidgets('open a store by paying the fee on Paystack', (t) async {
    Map<String, dynamic>? st;
    final f = await start(t, {
      'GET stores': (_) => (200, {'stores': [?st]}),
      'POST pay/start': (_) => (200, {'url': 'https://checkout.paystack.com/x', 'ref': 'R1'}),
      'POST pay/confirm': (_) {
        st = myStore();
        return (200, {'ok': true});
      },
    });
    String? opened;
    openPaystack = (context, url) async {
      opened = url;
      return 'R1';
    };
    await tapKey(t, 'openStore');
    await fillStore(t);
    await tapKey(t, 'st-open');
    expect(body(f, 'pay/start').containsKey('code'), isFalse);
    expect(opened, 'https://checkout.paystack.com/x');
    expect(body(f, 'pay/confirm'), {'reference': 'R1'});
    expect(find.text('Your store is live'), findsOneWidget);
    await t.pageBack();
    await settle(t);
    expect(find.text('Mama T Kitchen'), findsOneWidget);
  });

  testWidgets('run the store: open and closed, add and manage items, look, delivery', (t) async {
    var st = myStore(items: [storeItem(1, extra: {'qtyLeft': 3})]);
    final f = await start(t, {
      'GET stores': (_) => (200, {'stores': [st]}),
      'POST stores/toggle': (_) {
        st = {...st, 'open': !(st['open'] as bool)};
        return (200, {'ok': true});
      },
      'POST stores/item': (r) {
        st = {
          ...st,
          'items': [...st['items'] as List, storeItem(2, extra: {'title': 'Fried rice', 'price': 2000, 'review': 'checking'})]
        };
        return (200, {'ok': true});
      },
      'POST stores/item/avail': (_) => (200, {'ok': true}),
      'POST stores/item/stock': (_) => (200, {'ok': true}),
      'POST stores/item/delete': (_) => (200, {'ok': true}),
      'POST stores/look': (_) => (200, {'ok': true}),
      'POST stores/delivery': (r) {
        st = {...st, 'deliv': {'on': true, 'fee': 300, 'note': ''}};
        return (200, {'ok': true});
      },
    });
    expect(find.text('₦1,500 · 3 left'), findsOneWidget);

    await tapKey(t, 'storeOpen');
    expect(f.calls.where((c) => c.url.path == '/api/stores/toggle'), hasLength(1));
    expect(find.text('Closed: buyers can look but not order'), findsOneWidget);

    pickListingPhotos = (context, max) async => [photo];
    await tapKey(t, 'addStoreItem');
    await tapKey(t, 'it-save');
    expect(find.text('Add at least one photo.'), findsOneWidget);
    await tapKey(t, 'it-photos');
    await type(t, 'it-title', 'Fried rice');
    await type(t, 'it-price', '2000');
    expect(find.text('You get ₦1,900 per sale (Stall\'s fee ₦100).'), findsNothing); // fee is at least ₦150
    expect(find.text('You get ₦1,850 per sale (Stall\'s fee ₦150).'), findsOneWidget);
    await tapKey(t, 'it-save');
    expect(body(f, 'stores/item'), {'title': 'Fried rice', 'price': 2000, 'desc': '', 'qty': '', 'imgs': [photo]});
    await see(t, find.text('Checking the photo…'));

    await tapKey(t, 'avail-I1');
    expect(body(f, 'stores/item/avail'), {'id': 'I1'});
    await tapKey(t, 'stock-I1');
    await t.enterText(find.byKey(const Key('itemStock')), '10');
    await tapKey(t, 'itemStockSave');
    expect(body(f, 'stores/item/stock'), {'id': 'I1', 'qty': 10});
    await tapKey(t, 'del-I1');
    await t.tap(find.text('Delete').last);
    await settle(t);
    expect(body(f, 'stores/item/delete'), {'id': 'I1'});

    await tapKey(t, 'storeLook');
    await tapKey(t, 'icon-book');
    await tapKey(t, 'lookIcon');
    expect(body(f, 'stores/look'), {'emoji': 'book'});

    await tapKey(t, 'storeDelivery');
    await tapKey(t, 'deliverOn');
    await t.enterText(find.byKey(const Key('deliverFee')), '300');
    await tapKey(t, 'deliverSave');
    expect(body(f, 'stores/delivery'), {'on': true, 'fee': 300, 'note': ''});
    await see(t, find.text('You deliver for ₦300'));
  });

  testWidgets('reach, featuring and deleting the store', (t) async {
    Map<String, dynamic>? st = myStore();
    final f = await start(t, {
      'GET stores': (_) => (200, {'stores': [?st]}),
      'POST pay/start': (r) {
        final b = jsonDecode(r.body) as Map;
        if (b['kind'] == 'reach') st = {...?st, 'reach': 'national', 'reachUntil': DateTime(2026, 11, 16).millisecondsSinceEpoch};
        return (200, {'url': 'https://checkout.paystack.com/y', 'ref': 'R2'});
      },
      'POST pay/confirm': (_) => (200, {'ok': true}),
      'POST stores/delete': (_) {
        st = null;
        return (200, {'ok': true});
      },
    });
    openPaystack = (context, url) async => 'R2';
    await see(t, find.textContaining('Your store shows to people in Ibadan North and ACU'));
    await tapKey(t, 'reach-national');
    expect(body(f, 'pay/start'), {'kind': 'reach', 'target': 'S5', 'level': 'national'});
    await see(t, find.text('Nationwide until Mon, 16 Nov'));

    await tapKey(t, 'feature-7');
    expect(body(f, 'pay/start'), {'kind': 'boost', 'target': 'S5', 'days': 7});

    await t.pump(const Duration(seconds: 5)); // let the "featured" toast go, so it doesn't cover the button
    await t.pumpAndSettle();
    await tapKey(t, 'deleteStore');
    await t.tap(find.text('Delete store').last); // greyed out until the name is typed
    await t.pumpAndSettle();
    expect(f.calls.where((c) => c.url.path == '/api/stores/delete'), isEmpty);
    await t.enterText(find.byKey(const Key('delStoreName')), 'mama t kitchen');
    await t.pump();
    await t.tap(find.byKey(const Key('delStoreGo')));
    await settle(t);
    expect(f.calls.where((c) => c.url.path == '/api/stores/delete'), hasLength(1));
    expect(find.byKey(const Key('openStore')), findsOneWidget);
  });

  testWidgets('anyone can open a store from the Sell tab', (t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final f = FakeApi({
      'GET config': (_) => (200, {}),
      'GET me': (_) => (200, {'user': user()}),
      'GET listings': (_) => (200, {'listings': [], 'total': 0}),
      'GET stores': (_) => (200, {'stores': []}),
    });
    await f.store.write('a' * 64);
    final s = f.session();
    await t.pumpWidget(StallApp(session: s));
    await t.runAsync(s.restore);
    await settle(t);
    await t.tap(find.text('Sell'));
    await settle(t);
    expect(find.byType(SellTab), findsOneWidget);
    await tapKey(t, 'storeTile');
    expect(find.byKey(const Key('openStore')), findsOneWidget);
  });
}
