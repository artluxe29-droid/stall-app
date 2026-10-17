import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stall/main.dart';
import 'package:stall/screens/browse.dart' show SearchBox;
import 'package:stall/screens/sell.dart';
import 'package:stall/voice.dart';

import 'helpers.dart';
import 'sell_test.dart' show photo;
import 'store_test.dart' show myStore;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> settle(WidgetTester t) async {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pumpAndSettle();
  }

  Future<FakeApi> start(WidgetTester t, Map<String, FakeRoute> routes, {Map<String, dynamic> me = const {}}) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final f = FakeApi({
      'GET config': (_) => (200, {'fee': {'rate': 5, 'min': 150, 'cap': 2000}}),
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

  Iterable<Map<String, dynamic>> posts(FakeApi f, String path) =>
      f.calls.where((c) => c.url.path == '/api/$path' && c.method == 'POST').map((c) => jsonDecode(c.body) as Map<String, dynamic>);

  Future<void> tap(WidgetTester t, String key) async {
    final f = find.byKey(Key(key));
    if (f.evaluate().isEmpty) await t.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
    await t.ensureVisible(f);
    await t.pumpAndSettle();
    await t.tap(f);
    await settle(t);
  }

  testWidgets('dots show new order updates and unread chats, and clear when you look', (t) async {
    await start(t, {
      'GET orders/news': (_) => (200, {
            'chats': 2,
            'news': [
              {'id': 1, 'side': 'buy'},
              {'id': 2, 'side': 'sell'},
            ]
          }),
      'GET orders/mine': (_) => (200, {'orders': []}),
    });
    await settle(t);
    Finder badge(String label) => find.descendant(of: find.byType(Badge), matching: find.text(label));
    expect(badge('2'), findsNWidgets(2)); // Orders tab and Messages
    await t.tap(find.text('Orders'));
    await settle(t);
    expect(badge('1'), findsOneWidget); // buying seen; one sale still new
  });

  testWidgets('voice search fills the search and runs it', (t) async {
    final f = await start(t, {});
    listenOnce = (_) async => 'rice cooker';
    await reveal(t, find.byType(SearchBox));
    await t.tap(find.byType(SearchBox));
    await settle(t);
    await tap(t, 'voice');
    expect(find.text('rice cooker'), findsOneWidget);
    expect(f.calls.lastWhere((c) => c.url.path == '/api/listings').url.queryParameters['q'], 'rice cooker');
  });

  testWidgets('add several listings at once; a refused one stays to fix', (t) async {
    final f = await start(t, {
      'POST listings': (r) {
        final b = jsonDecode(r.body) as Map;
        return b['title'] == 'Broken thing' ? (400, {'error': 'That photo doesn\'t look like the item.'}) : (200, {'ok': true, 'id': 'L1'});
      },
    }, me: {'acctSet': true, 'seller_ok': true});
    pickListingPhotos = (context, max) async => [photo];
    await t.tap(find.text('Sell'));
    await settle(t);
    await tap(t, 'bulkAdd');
    await tap(t, 'bkPost');
    expect(find.text('Fill in at least one item.'), findsOneWidget);
    for (final (i, title) in [(0, 'Desk lamp'), (1, 'Broken thing')]) {
      await tap(t, 'bkPhoto-$i');
      await t.enterText(find.byKey(Key('bkTitle-$i')), title);
      await t.enterText(find.byKey(Key('bkPrice-$i')), '3000');
    }
    await t.enterText(find.byKey(const Key('bkSpot')), 'Library steps');
    await tap(t, 'bkPost');
    final sent = posts(f, 'listings').toList();
    expect(sent.map((b) => b['title']), ['Desk lamp', 'Broken thing']);
    expect(sent.first, allOf(containsPair('price', 3000), containsPair('spot', 'Library steps'), containsPair('qty', 1), containsPair('imgs', [photo])));
    expect(find.text('1 posted, 1 need fixing (see below).'), findsOneWidget);
    expect(find.text('That photo doesn\'t look like the item.'), findsOneWidget);
    // Posting again only sends the one that failed.
    await tap(t, 'bkPost');
    expect(posts(f, 'listings').map((b) => b['title']).toList(), ['Desk lamp', 'Broken thing', 'Broken thing']);
  });

  testWidgets('add several items to a store', (t) async {
    final f = await start(t, {
      'GET stores': (_) => (200, {'stores': [myStore()]}),
      'POST stores/item': (_) => (200, {'ok': true}),
    }, me: {'role': 'vendor'});
    pickListingPhotos = (context, max) async => [photo];
    await t.tap(find.text('Sell'));
    await settle(t);
    await tap(t, 'bulkStore');
    expect(find.text('Add up to 10 items to Mama T Kitchen.'), findsOneWidget);
    expect(find.byKey(const Key('bkSpot')), findsNothing);
    await tap(t, 'bkPhoto-0');
    await t.enterText(find.byKey(const Key('bkTitle-0')), 'Fried rice');
    await t.enterText(find.byKey(const Key('bkPrice-0')), '2000');
    await tap(t, 'bkPost');
    expect(posts(f, 'stores/item').single, {'title': 'Fried rice', 'price': 2000, 'qty': 1, 'desc': '', 'imgs': [photo]});
  });

  testWidgets('a badge opens as a picture to share', (t) async {
    await start(t, {
      'GET me/milestones': (_) => (200, {
            'sell': {'count': 6, 'earned': [1, 5], 'next': 10, 'fresh': null},
            'buy': {'count': 0, 'earned': [], 'next': 1, 'fresh': null},
            'name': 'Ada',
            'store': 'Mama T Kitchen',
          }),
    });
    await t.tap(find.text('Account'));
    await settle(t);
    await tap(t, 'badgesTile');
    await t.tap(find.text('5 sales'));
    await settle(t);
    expect(find.text('5th sale on Stall'), findsOneWidget);
    expect(find.text('Mama T Kitchen'), findsOneWidget);
    expect(find.byKey(const Key('shareBadge')), findsOneWidget);
  });
}
