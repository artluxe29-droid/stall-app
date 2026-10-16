import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stall/main.dart';
import 'package:stall/models.dart';

import 'helpers.dart';

Map<String, dynamic> listing(int id, {String title = 'Calculus textbook', int price = 4500, Map<String, dynamic> extra = const {}}) => {
      'id': 'L$id',
      'sid': 9,
      'title': title,
      'price': price,
      'cat': 'books',
      'cond': 'Like new',
      'spot': 'Library',
      'desc': 'Barely used, no marks.',
      'seller': 'Tolu A.',
      'school': 'ACU',
      'imgs': <String>[],
      't': DateTime.now().millisecondsSinceEpoch - 3 * 3600000,
      'sold': 0,
      'rating': {'avg': 4.5, 'n': 2},
      'deliv': {'on': true, 'fee': 500, 'note': 'Hostels only'},
      'qty': 1,
      'qtyLeft': 1,
      ...extra,
    };

Map<String, dynamic> store() => {
      'id': 'S4',
      'uid': 12,
      'name': 'Mama T Kitchen',
      'emoji': 'bowl',
      'cat': 'food',
      'desc': 'Hot jollof every afternoon.',
      'spot': 'Behind the chapel',
      'open': true,
      'vendor': true,
      'founding': 3,
      'school': 'ACU',
      'state': 'Oyo',
      'rating': {'avg': 4.8, 'n': 10},
      'deliv': {'on': false},
      'items': [
        {'id': 'I1', 'title': 'Jollof and chicken', 'price': 2500, 'desc': 'With plantain', 'avail': true, 'qtyLeft': 3, 'imgs': <String>[]},
        {'id': 'I2', 'title': 'Fried rice', 'price': 2200, 'desc': '', 'avail': false, 'imgs': <String>[]},
      ],
    };

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> settle(WidgetTester t) async {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pumpAndSettle();
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

  Map<String, String> lastQuery(FakeApi f, String path) => f.calls.lastWhere((c) => c.url.path == '/api/$path').url.queryParameters;

  testWidgets('home shows school items; scope and category chips change the feed', (t) async {
    final f = await signedIn(t, {
      'GET listings': (r) => (200, {
            'listings': [listing(1), listing(2, title: 'Desk lamp', price: 3000)],
            'total': 2,
          }),
    });
    expect(find.text('What\'s new at ACU'), findsOneWidget);
    expect(find.text('Calculus textbook'), findsOneWidget);
    expect(find.text('₦4,500'), findsOneWidget);
    expect(lastQuery(f, 'listings')['scope'], 'school');

    await t.tap(find.byKey(const Key('chip-state')));
    await settle(t);
    expect(lastQuery(f, 'listings')['scope'], 'state');
    expect(find.text('What\'s new in Oyo'), findsOneWidget);

    await t.tap(find.byKey(const Key('chip-all')).first);
    await settle(t);
    expect(lastQuery(f, 'listings')['scope'], 'all');

    await t.tap(find.byKey(const Key('chip-books')));
    await settle(t);
    expect(lastQuery(f, 'listings'), containsPair('cat', 'books'));
  });

  testWidgets('an item opens with its details, and the seller\'s reviews', (t) async {
    await signedIn(t, {
      'GET listings': (_) => (200, {'listings': [listing(1)], 'total': 1}),
      'GET reviews': (_) => (200, {
            'rating': {'avg': 4.5, 'n': 2},
            'cancels': {'n': 0, 'of': 3},
            'reviews': [
              {'id': 1, 'who': 'Bisi O.', 'stars': 5, 'title': 'Calculus textbook', 'text': 'Fast and friendly', 't': 0, 'reply': 'Thank you!'},
            ],
          }),
    });
    await t.tap(find.byKey(const Key('item-L1')));
    await settle(t);
    expect(find.text('Barely used, no marks.'), findsOneWidget);
    expect(find.textContaining('Meet at Library'), findsOneWidget);
    expect(find.text('Delivers for ₦500 · Hostels only'), findsOneWidget);
    expect(find.text('Sold by Tolu A. · ACU'), findsOneWidget);

    await t.tap(find.byKey(const Key('seller')));
    await settle(t);
    expect(find.text('Sent all 3 orders in the last 90 days ✓'), findsOneWidget);
    expect(find.text('Fast and friendly'), findsOneWidget);
    expect(find.textContaining('Thank you!'), findsOneWidget);
  });

  testWidgets('search sends words and filters, shows store hits and remembers the search', (t) async {
    final f = await signedIn(t, {
      'GET listings': (r) => (200, {
            'listings': r.url.queryParameters['q'] == null ? [] : [listing(5, title: 'Jollof cooler')],
            'total': r.url.queryParameters['q'] == null ? 0 : 1,
            'storeHits': [
              {'id': 'I1', 'title': 'Jollof and chicken', 'price': 2500, 'store': 'S4', 'storeName': 'Mama T Kitchen', 'cat': 'food', 'emoji': 'bowl'},
            ],
          }),
      'GET stores': (_) => (200, {'stores': [store()]}),
    });
    await t.tap(find.byKey(const Key('searchBox')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('searchField')), 'jollof');
    await t.testTextInput.receiveAction(TextInputAction.search);
    await settle(t);
    expect(lastQuery(f, 'listings'), containsPair('q', 'jollof'));
    expect(find.text('From stores'), findsOneWidget);
    expect(find.text('Jollof cooler'), findsOneWidget);

    await t.tap(find.byKey(const Key('filters')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('fMax')), '5000');
    await t.tap(find.text('Seller delivers'));
    await t.pump();
    await t.tap(find.byKey(const Key('fApply')));
    await settle(t);
    final q = lastQuery(f, 'listings');
    expect(q['max'], '5000');
    expect(q['dl'], '1');
    expect(q['q'], 'jollof');

    expect((await SharedPreferences.getInstance()).getStringList('recent_searches'), ['jollof']);

    await t.tap(find.text('Jollof and chicken'));
    await settle(t);
    expect(find.text('Mama T Kitchen'), findsOneWidget);
    expect(find.text('Founding Seller #3 · ACU'), findsOneWidget);
  });

  testWidgets('the Stores tab lists stores and opens a store with its items', (t) async {
    final f = await signedIn(t, {
      'GET listings': (_) => (200, {'listings': [], 'total': 0}),
      'GET stores': (_) => (200, {'stores': [store()]}),
    });
    await t.tap(find.text('Stores'));
    await settle(t);
    expect(lastQuery(f, 'stores')['scope'], 'school');
    expect(find.text('Mama T Kitchen'), findsOneWidget);
    expect(find.textContaining('1 available now · '), findsOneWidget);
    expect(find.textContaining('4.8 (10)'), findsWidgets);

    await t.tap(find.byKey(const Key('store-S4')));
    await t.pumpAndSettle();
    expect(find.text('Hot jollof every afternoon.'), findsOneWidget);
    expect(find.text('Jollof and chicken'), findsOneWidget);
    expect(find.text('Only 3 left'), findsOneWidget);
    expect(find.text('Sold out'), findsOneWidget);
  });

  test('listing stock and status match the web app', () {
    expect(Listing(listing(1)).stockLine, isNull);
    expect(Listing(listing(1, extra: {'qty': 10, 'qtyLeft': 4})).stockLine, 'Only 4 left');
    expect(Listing(listing(1, extra: {'qty': 10, 'qtyLeft': 8})).stockLine, '8 available');
    expect(Listing(listing(1, extra: {'qty': 10, 'qtyLeft': 0})).stockLine, 'Sold out');
    expect(Listing(listing(1, extra: {'sold': 1})).status, 'Sold');
    expect(Listing(listing(1, extra: {'qtyLeft': 0})).status, 'Reserved');
    expect(Listing(listing(1)).status, isNull);
  });

  test('filters become the same query the web app sends', () {
    const f = Filters(min: 1000, cond: 'Used', verified: true, topRated: true, sort: 'lo');
    expect(f.query, {'min': '1000', 'cond': 'Used', 'vf': '1', 'r4': '1', 'sort': 'lo'});
    expect(f.count, 4);
    expect(const Filters().query, isEmpty);
  });

  test('ago reads like the web app', () {
    final now = DateTime(2026, 10, 16, 12);
    int before(Duration d) => now.subtract(d).millisecondsSinceEpoch;
    expect(ago(before(const Duration(seconds: 20)), now), 'just now');
    expect(ago(before(const Duration(minutes: 5)), now), '5m ago');
    expect(ago(before(const Duration(hours: 3)), now), '3h ago');
    expect(ago(before(const Duration(days: 2)), now), '2d ago');
  });

  test('old emoji store icons map to the same icons as new ones', () {
    expect(storeIcon('🍲', 'food'), storeIcon('bowl', 'food'));
    expect(storeIcon('', 'books'), Category.of('books').icon);
  });
}
