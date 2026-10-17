import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stall/main.dart';
import 'package:stall/screens/sell.dart';

import 'browse_test.dart' show listing;
import 'helpers.dart';

const photo = 'data:image/jpeg;base64,/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQH/wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAACv/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AN//Z';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> settle(WidgetTester t) async {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
  }

  Future<FakeApi> sellTab(WidgetTester t, Map<String, FakeRoute> routes, {Map<String, dynamic> me = const {}}) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final f = FakeApi({
      'GET config': (_) => (200, {'fee': {'rate': 5, 'min': 150, 'cap': 2000}}),
      'GET me': (_) => (200, {'user': {...user(), 'vlevel': 2, ...me}}),
      'GET listings': (_) => (200, {'listings': [], 'total': 0}),
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

  // The screen's own list, not a text field's scrollable.
  Finder page() => find.byType(Scrollable).first;

  Future<void> tap(WidgetTester t, Finder f) async {
    if (f.evaluate().isEmpty) await t.scrollUntilVisible(f, 200, scrollable: page());
    await t.ensureVisible(f);
    await t.pump();
    await t.tap(f);
    await settle(t);
  }

  Future<void> type(WidgetTester t, String key, String text) async {
    final f = find.byKey(Key(key));
    if (f.evaluate().isEmpty) await t.scrollUntilVisible(f, 200, scrollable: page());
    await t.ensureVisible(f);
    await t.enterText(f, text);
    await t.pump();
  }

  testWidgets('first sale: photos, price hint, what you get, bank check, seller rules, then posted', (t) async {
    var agreed = false;
    final f = await sellTab(t, {
      'GET banks': (_) => (200, {'banks': [{'code': '058', 'name': 'GTBank'}, {'code': '999992', 'name': 'OPay'}]}),
      'GET price-hint': (_) => (200, {'n': 5, 'low': 3000, 'high': 6000, 'mid': 4500}),
      'POST bank/resolve': (_) => (200, {'name': 'ADA OBI'}),
      'POST me/seller-ok': (_) {
        agreed = true;
        return (200, {'ok': true});
      },
      'POST listings': (_) => agreed ? (200, {'ok': true, 'id': 'L9', 'checking': true}) : (400, {'error': 'Please agree to how selling on Stall works.', 'need': 'seller_ok'}),
    }, me: {'acctSet': false, 'freeLeft': 0});
    pickListingPhotos = (context, max) async => [photo, photo];

    await tap(t, find.byKey(const Key('sellItem')));
    await tap(t, find.byKey(const Key('postListing')));
    expect(find.text('Add at least one photo.'), findsOneWidget);
    expect(f.calls.where((c) => c.url.path == '/api/listings' && c.method == 'POST'), isEmpty);

    await tap(t, find.byKey(const Key('addPhotos')));
    await type(t, 's-title', 'Calculus textbook');
    await t.pump(const Duration(milliseconds: 700));
    await settle(t);
    expect(find.byKey(const Key('priceHint')), findsOneWidget);
    await tap(t, find.text('Use ₦4,500'));
    expect(find.text('You get ₦4,275'), findsOneWidget);

    await t.pump(const Duration(seconds: 5)); // let the "Price set" toast go
    await t.pumpAndSettle();
    await type(t, 's-spot', 'Library steps');
    await tap(t, find.byKey(const Key('postListing')));
    expect(find.text('Enter your 10-digit account number, then tap "Verify account".'), findsOneWidget);

    await tap(t, find.byKey(const Key('s-bank')));
    await t.tap(find.text('GTBank').last);
    await t.pumpAndSettle();
    await type(t, 's-acct', '0123456789');
    await tap(t, find.byKey(const Key('verifyBank')));
    expect(find.text('✓ ADA OBI'), findsOneWidget);

    await tap(t, find.byKey(const Key('postListing')));
    // The server asks for the seller rules; both ticks are needed.
    expect(find.text('Before you sell'), findsOneWidget);
    await tap(t, find.byKey(const Key('rulesSchool')));
    await tap(t, find.byKey(const Key('rulesAgree')));
    await tap(t, find.byKey(const Key('rulesOk')));
    await settle(t);

    final b = body(f, 'listings');
    expect(b, containsPair('title', 'Calculus textbook'));
    expect(b, containsPair('price', 4500));
    expect(b, containsPair('bank_code', '058'));
    expect(b, containsPair('acct_no', '0123456789'));
    expect(b, containsPair('acct_name', 'ADA OBI'));
    expect(b.containsKey('bank_manual'), isFalse);
    expect((b['imgs'] as List).length, 2);
    expect(find.text('Sell an item'), findsOneWidget); // back on the Sell tab
  });

  testWidgets('your listings: review status, stock, sold and delete', (t) async {
    final f = await sellTab(t, {
      'GET listings': (r) => (200, {
            'listings': r.url.queryParameters['mine'] == '1'
                ? [
                    listing(1, extra: {'mine': true, 'review': 'live', 'qty': 5, 'qtyLeft': 3}),
                    listing(2, title: 'Blurry lamp', extra: {'mine': true, 'review': 'rejected', 'reviewNote': 'Photo doesn\'t show the item'}),
                  ]
                : [],
            'total': 0,
          }),
      'POST listings/stock': (_) => (200, {'ok': true}),
      'POST listings/sold': (_) => (200, {'ok': true}),
      'POST listings/delete': (_) => (200, {'ok': true}),
    }, me: {'acctSet': true});
    await t.scrollUntilVisible(find.textContaining('Photo doesn\'t show the item'), 200, scrollable: page());
    expect(find.text('Live'), findsOneWidget);
    expect(find.text('Not approved'), findsOneWidget);
    expect(find.textContaining('Photo doesn\'t show the item'), findsOneWidget);

    await tap(t, find.byKey(const Key('stock-L1')));
    await t.enterText(find.byKey(const Key('stockField')), '7');
    await tap(t, find.byKey(const Key('stockSave')));
    expect(body(f, 'listings/stock'), {'id': 'L1', 'qty': 7});

    await tap(t, find.byKey(const Key('sold-L1')));
    expect(body(f, 'listings/sold'), {'id': 'L1', 'sold': true});

    await tap(t, find.byKey(const Key('del-L2')));
    await tap(t, find.byKey(const Key('confirmYes')));
    expect(body(f, 'listings/delete'), {'id': 'L2'});
  });

  testWidgets('delivery settings save the fee and note', (t) async {
    final f = await sellTab(t, {'POST me/delivery': (_) => (200, {'ok': true})}, me: {'deliv': {'on': false, 'fee': 0}});
    expect(find.text('Off: buyers collect from you'), findsOneWidget);
    await tap(t, find.byKey(const Key('deliveryTile')));
    await tap(t, find.byKey(const Key('deliverOn')));
    await t.enterText(find.byKey(const Key('deliverFee')), '400');
    await tap(t, find.byKey(const Key('deliverSave')));
    expect(body(f, 'me/delivery'), {'on': true, 'fee': 400, 'note': ''});
  });

  testWidgets('for a business, the Sell tab is their store', (t) async {
    await sellTab(t, {'GET stores': (_) => (200, {'stores': []})}, me: {'role': 'vendor'});
    expect(find.text('Your store'), findsOneWidget);
    expect(find.byKey(const Key('openStore')), findsOneWidget);
    expect(find.byKey(const Key('sellItem')), findsNothing);
  });
}
