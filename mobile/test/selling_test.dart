import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stall/main.dart';

import 'buy_test.dart' show order;
import 'helpers.dart';

/// An order someone placed with you (the seller's view of it).
Map<String, dynamic> sale(Map<String, dynamic> extra) => order(50, status: 'verified', extra: {
      'code': null,
      'buyerName': 'Tunde Bello',
      'buyerPhone': '08091234567',
      'buyerRating': {'avg': 4.5, 'n': 2},
      ...extra,
    });

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> settle(WidgetTester t) async {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pumpAndSettle();
  }

  /// Signed in, on Orders → Selling, with the server's orders/selling answered by [sales].
  Future<FakeApi> selling(WidgetTester t, Map<String, dynamic> Function() sales, Map<String, FakeRoute> routes,
      {Map<String, dynamic>? week}) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final f = FakeApi({
      'GET config': (_) => (200, {'timers': {'hand': 30}}),
      'GET me': (_) => (200, {'user': user()}),
      'GET listings': (_) => (200, {'listings': [], 'total': 0}),
      'GET orders/mine': (_) => (200, {'orders': []}),
      'GET orders/selling': (_) => (200, {'orders': [sales()]}),
      'GET orders/weekly': (_) => (200, week ?? {'n': 0}),
      ...routes,
    });
    await f.store.write('a' * 64);
    final s = f.session();
    await t.pumpWidget(StallApp(session: s));
    await t.runAsync(s.restore);
    await settle(t);
    await t.tap(find.text('Orders'));
    await settle(t);
    await t.tap(find.text('Selling'));
    await settle(t);
    return f;
  }

  Map<String, dynamic> body(FakeApi f, String path) =>
      jsonDecode(f.calls.lastWhere((c) => c.url.path == '/api/$path' && c.method == 'POST').body) as Map<String, dynamic>;

  Future<void> tap(WidgetTester t, String key) async {
    final f = find.byKey(Key(key));
    // The order screen is a lazy list: scroll it (not a text field's own scrollable) until the button is built.
    if (f.evaluate().isEmpty) {
      await t.scrollUntilVisible(f, 200, scrollable: find.descendant(of: find.byType(ListView).last, matching: find.byType(Scrollable)).first);
    }
    await t.ensureVisible(f);
    await t.pumpAndSettle();
    await t.tap(f);
    await settle(t);
  }

  testWidgets('a delivery: packed, out for delivery, tell the buyer when, hand over, then release with the code', (t) async {
    var o = sale({'method': 'delivery', 'addr': 'Hall B, Room 214', 'dphone': '08051234567', 'stage': null});
    final f = await selling(t, () => o, {
      'POST orders/stage': (r) {
        final st = (jsonDecode(r.body) as Map)['stage'];
        o = {...o, 'stage': st, 'early': false};
        return (200, {'ok': true, 'stage': st});
      },
      'POST orders/eta': (_) => (200, {'ok': true}),
      'POST orders/handed': (_) {
        o = {...o, 'handedAt': DateTime.now().millisecondsSinceEpoch, 'handUntil': DateTime.now().millisecondsSinceEpoch + 1800000};
        return (200, {'ok': true});
      },
      'POST orders/code': (r) {
        final c = (jsonDecode(r.body) as Map)['code'];
        if (c != 'STALL-AB12CD') return (400, {'error': 'That code doesn\'t match this order.'});
        o = {...o, 'status': 'released', 'payout': 'paid'};
        return (200, {'ok': true});
      },
    });
    expect(find.textContaining('Tunde Bello'), findsOneWidget);
    await t.tap(find.byKey(const Key('order-50')));
    await settle(t);
    expect(find.textContaining('Deliver to: Hall B, Room 214'), findsOneWidget);
    expect(find.textContaining('Stall is holding ₦4,275 for you'), findsOneWidget);
    expect(find.byKey(const Key('handed')), findsNothing); // must move it on first
    expect(find.byKey(const Key('eta-10')), findsNothing);

    await tap(t, 'nextStage');
    expect(body(f, 'orders/stage'), {'id': 50, 'stage': 'packed'});
    expect(find.text('Out for delivery'), findsOneWidget);
    await tap(t, 'nextStage');
    expect(body(f, 'orders/stage'), {'id': 50, 'stage': 'on_way'});

    await tap(t, 'eta-10');
    expect(body(f, 'orders/eta'), {'id': 50, 'min': 10});
    await tap(t, 'eta-here');
    expect(body(f, 'orders/eta'), {'id': 50, 'here': true});

    await tap(t, 'handed');
    expect(find.textContaining('within 30 minutes'), findsOneWidget);
    await t.enterText(find.byKey(const Key('noteText')), 'Gave it to them at the gate');
    await tap(t, 'noteSend');
    expect(body(f, 'orders/handed'), containsPair('note', 'Gave it to them at the gate'));
    expect(find.textContaining('You marked this as handed over'), findsOneWidget);
    expect(find.byKey(const Key('eta-10')), findsNothing);

    await t.enterText(find.byKey(const Key('releaseCode')), 'stall-zz9999');
    await tap(t, 'release');
    expect(find.text('That code doesn\'t match this order.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('releaseCode')), 'STALL-AB12CD');
    await tap(t, 'release');
    expect(body(f, 'orders/code'), {'id': 50, 'code': 'STALL-AB12CD'});
    expect(find.text('₦4,275 sent to your bank ✓'), findsOneWidget);
  });

  testWidgets('a pickup: ready, then the buyer doesn\'t show up', (t) async {
    var o = sale({'method': 'pickup', 'pickup': 'Library'});
    final f = await selling(t, () => o, {
      'POST orders/stage': (_) {
        o = {...o, 'stage': 'ready', 'early': false};
        return (200, {'ok': true, 'stage': 'ready'});
      },
      'POST orders/cancel': (_) {
        o = {...o, 'status': 'refunded', 'note': 'The buyer didn\'t show up.'};
        return (200, {'ok': true});
      },
    });
    await t.tap(find.byKey(const Key('order-50')));
    await settle(t);
    expect(find.textContaining('The buyer collects at Library'), findsOneWidget);
    expect(find.byKey(const Key('noShow')), findsNothing);
    await tap(t, 'nextStage');
    expect(body(f, 'orders/stage'), {'id': 50, 'stage': 'ready'});
    expect(find.byKey(const Key('eta-10')), findsNothing); // on pickups the buyer is the one travelling
    await tap(t, 'noShow');
    await t.tap(find.text('Cancel order'));
    await settle(t);
    expect(body(f, 'orders/cancel'), {'id': 50, 'noshow': true});
    expect(find.textContaining('the buyer refunded'), findsOneWidget);
  });

  testWidgets('a problem report: give your side with a note, or accept and refund', (t) async {
    var o = sale({
      'status': 'disputed',
      'method': 'pickup',
      'stage': 'ready',
      'note': 'The buyer reported: the screen is cracked',
      'dispBy': 'buyer',
      'dispDue': DateTime(2026, 10, 18, 14).millisecondsSinceEpoch,
    });
    final f = await selling(t, () => o, {
      'POST orders/evidence': (_) {
        o = {...o, 'dispReply': 1};
        return (200, {'ok': true});
      },
      'POST orders/settle': (_) {
        o = {...o, 'status': 'refunded', 'note': 'You accepted the report.'};
        return (200, {'ok': true});
      },
    });
    await t.tap(find.byKey(const Key('order-50')));
    await settle(t);
    expect(find.textContaining('The buyer reported: the screen is cracked'), findsOneWidget);
    expect(find.textContaining('or it\'s decided for the buyer'), findsOneWidget);
    expect(find.byKey(const Key('releaseCode')), findsNothing);

    await tap(t, 'giveSide');
    await tap(t, 'noteSend');
    expect(find.text('Write what happened (a sentence or two) or add a photo.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('noteText')), 'It was fine when they checked it at pickup.');
    await tap(t, 'noteSend');
    expect(body(f, 'orders/evidence'), containsPair('text', 'It was fine when they checked it at pickup.'));
    expect(find.textContaining('the Stall team will decide'), findsOneWidget);
    expect(find.text('Add more'), findsOneWidget);

    await tap(t, 'settleAccept');
    await t.tap(find.text('Accept and refund').last);
    await settle(t);
    expect(body(f, 'orders/settle'), {'id': 50, 'how': 'accept'});
    expect(find.textContaining('Refunded'), findsWidgets);
  });

  testWidgets('this week\'s sales show above the orders and open the statement; completed orders ask to rate the buyer', (t) async {
    var o = sale({'status': 'released', 'payout': 'paid', 'method': 'pickup', 'stage': 'ready'});
    final f = await selling(t, () => o, {
      'POST orders/rate-buyer': (_) {
        o = {...o, 'brate': 4};
        return (200, {'ok': true});
      },
    }, week: {'n': 3, 'total': 12500, 'label': '13 – 19 Oct', 'text': 'Desk lamp ₦3,000\nCalculus textbook ₦4,500'});
    expect(find.text('₦12,500 · 3 orders delivered'), findsOneWidget);
    await t.tap(find.byKey(const Key('weekCard')));
    await settle(t);
    expect(find.text('Weekly statement'), findsOneWidget);
    expect(find.textContaining('Desk lamp ₦3,000'), findsOneWidget);
    await t.pageBack();
    await settle(t);

    await t.tap(find.byKey(const Key('order-50')));
    await settle(t);
    await tap(t, 'bstar-4');
    await tap(t, 'rateBuyer');
    expect(body(f, 'orders/rate-buyer'), {'id': 50, 'stars': 4});
    expect(find.text('You rated this buyer ★★★★'), findsOneWidget);
  });
}
