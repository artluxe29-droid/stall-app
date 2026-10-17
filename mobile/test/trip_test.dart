import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stall/main.dart';
import 'package:stall/screens/trip.dart';

import 'buy_test.dart' show order;
import 'helpers.dart';
import 'selling_test.dart' show sale;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    showMapTiles = false;
  });

  Future<void> settle(WidgetTester t) async {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pumpAndSettle();
  }

  Future<FakeApi> start(WidgetTester t, Map<String, FakeRoute> routes, {required bool selling}) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final f = FakeApi({
      'GET config': (_) => (200, {}),
      'GET me': (_) => (200, {'user': user()}),
      'GET listings': (_) => (200, {'listings': [], 'total': 0}),
      'GET orders/weekly': (_) => (200, {'n': 0}),
      ...routes,
    });
    await f.store.write('a' * 64);
    final s = f.session();
    await t.pumpWidget(StallApp(session: s));
    await t.runAsync(s.restore);
    await settle(t);
    await t.tap(find.text('Orders'));
    await settle(t);
    if (selling) {
      await t.tap(find.text('Selling'));
      await settle(t);
    }
    await t.tap(find.byKey(Key('order-${selling ? 50 : 40}')));
    await settle(t);
    await t.tap(find.byKey(const Key('liveMap')));
    await settle(t);
    return f;
  }

  Map<String, dynamic> body(FakeApi f, String path) =>
      jsonDecode(f.calls.lastWhere((c) => c.url.path == '/api/$path' && c.method == 'POST').body) as Map<String, dynamic>;

  Future<void> tap(WidgetTester t, String key) async {
    await t.tap(find.byKey(Key(key)));
    await settle(t);
  }

  testWidgets('the seller shares their location on a delivery, tells the buyer when, then stops', (t) async {
    var track = <String, dynamic>{'open': true, 'mover': 'seller', 'me': 'seller', 'pin': {'lat': 7.39, 'lng': 3.91}, 'spot': 'Hall B', 'live': null};
    final fixes = StreamController<Fix>();
    locationStream = () => fixes.stream;
    final f = await start(t, {
      'GET orders/selling': (_) => (200, {'orders': [sale({'method': 'delivery', 'stage': 'on_way', 'early': false, 'addr': 'Hall B'})]}),
      'GET orders/track': (_) => (200, track),
      'POST orders/live': (r) {
        final b = jsonDecode(r.body) as Map;
        track = {...track, 'live': {'lat': b['lat'], 'lng': b['lng']}, 'eta': 3, 'lastAt': DateTime.now().millisecondsSinceEpoch};
        return (200, {'ok': true, 'dist': 400, 'eta': 3});
      },
      'POST orders/eta': (_) => (200, {'ok': true}),
      'POST orders/live/stop': (_) => (200, {'ok': true}),
    }, selling: true);
    expect(find.text('Share your location so they can follow you'), findsOneWidget);
    expect(find.byKey(const Key('pinMarker')), findsOneWidget);
    expect(find.byKey(const Key('pinSet')), findsNothing); // on deliveries the buyer sets the spot

    await tap(t, 'shareLive');
    fixes.add((lat: 7.385, lng: 3.905, acc: 12.0));
    await settle(t);
    expect(body(f, 'orders/live'), {'id': 50, 'lat': 7.385, 'lng': 3.905, 'acc': 12.0});
    expect(find.text('You are about 3 min away'), findsOneWidget);
    expect(find.byKey(const Key('liveMarker')), findsOneWidget);

    await tap(t, 'teta-10');
    expect(body(f, 'orders/eta'), {'id': 50, 'min': 10});
    await tap(t, 'stopLive');
    expect(f.calls.where((c) => c.url.path == '/api/orders/live/stop'), hasLength(1));
    expect(find.byKey(const Key('shareLive')), findsOneWidget);
    unawaited(fixes.close());
  });

  testWidgets('the buyer follows a delivery and sets the drop-off spot on the map', (t) async {
    var track = <String, dynamic>{
      'open': true,
      'mover': 'seller',
      'me': 'buyer',
      'pin': null,
      'spot': 'Hall B',
      'live': {'lat': 7.38, 'lng': 3.9},
      'eta': 6,
      'who': 'Tolu Ade',
      'lastAt': DateTime.now().millisecondsSinceEpoch,
    };
    final f = await start(t, {
      'GET orders/mine': (_) => (200, {'orders': [order(40, status: 'verified', extra: {'method': 'delivery', 'stage': 'on_way', 'addr': 'Hall B'})]}),
      'GET orders/track': (_) => (200, track),
      'POST orders/pin': (r) {
        final b = jsonDecode(r.body) as Map;
        track = {...track, 'pin': b['clear'] == true ? null : {'lat': b['lat'], 'lng': b['lng']}};
        return (200, {'ok': true});
      },
    }, selling: false);
    expect(find.text('Tolu is about 6 min away'), findsOneWidget);
    expect(find.byKey(const Key('shareLive')), findsNothing); // the seller travels on deliveries
    await tap(t, 'pinSet');
    expect(find.text('Tap the map where you\'ll meet.'), findsOneWidget);
    await t.tap(find.byType(FlutterMap));
    await t.pump(const Duration(milliseconds: 500)); // the map waits to rule out a double tap
    await settle(t);
    await tap(t, 'pinSave');
    final b = body(f, 'orders/pin');
    expect(b['id'], 40);
    expect(b['lat'], isA<double>());
    expect(b['lng'], isA<double>());
    expect(find.byKey(const Key('pinMarker')), findsOneWidget);
    await t.pump(const Duration(seconds: 5)); // let the "saved" toast go
    await t.pumpAndSettle();
    await tap(t, 'pinClear');
    expect(body(f, 'orders/pin'), {'id': 40, 'clear': true});
    expect(find.byKey(const Key('pinMarker')), findsNothing);
  });

  testWidgets('a map for an order that isn\'t on its way says so', (t) async {
    await start(t, {
      'GET orders/mine': (_) => (200, {'orders': [order(40, status: 'verified', extra: {'method': 'pickup'})]}),
      'GET orders/track': (_) => (200, {'open': false, 'mover': 'buyer', 'me': 'buyer'}),
    }, selling: false);
    expect(find.byKey(const Key('tripClosed')), findsOneWidget);
    expect(find.byKey(const Key('shareLive')), findsNothing);
  });
}
