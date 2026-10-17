import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stall/main.dart';

import 'buy_test.dart' show order;
import 'helpers.dart';

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
      'GET config': (_) => (200, {'timers': {'answer': 4}}),
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

  Finder page() => find.byType(Scrollable).first;

  Future<void> tap(WidgetTester t, String key) async {
    final f = find.byKey(Key(key));
    if (f.evaluate().isEmpty) await t.scrollUntilVisible(f, 200, scrollable: page());
    await t.ensureVisible(f);
    await t.pumpAndSettle();
    await t.tap(f);
    await settle(t);
  }

  Future<void> openOrder(WidgetTester t) async {
    await t.tap(find.text('Orders'));
    await settle(t);
    await t.tap(find.byKey(const Key('order-40')));
    await settle(t);
  }

  testWidgets('message the seller from an order: send, see a safety warning, report and block', (t) async {
    var blocked = false;
    final msgs = <Map<String, dynamic>>[
      {'id': 1, 'mine': false, 'body': 'Hi, it\'s ready', 't': DateTime.now().millisecondsSinceEpoch},
    ];
    final f = await start(t, {
      'GET orders/mine': (_) => (200, {'orders': [order(40, status: 'verified')]}),
      'POST chat/open': (_) => (200, {'id': 9}),
      'GET chat/msgs': (r) {
        final after = int.tryParse(r.url.queryParameters['after'] ?? '') ?? 0;
        return (200, {
          'thread': {'id': 9, 'ref': 'O40', 'title': 'Order #40 · Calculus textbook', 'with': 'Tolu A.', 'iBlock': blocked},
          'msgs': msgs.where((m) => (m['id'] as int) > after).toList(),
        });
      },
      'POST chat/send': (r) {
        final b = (jsonDecode(r.body) as Map)['body'] as String;
        msgs.add({'id': msgs.length + 1, 'mine': true, 'body': b, 't': DateTime.now().millisecondsSinceEpoch});
        return (200, {'ok': true, 'id': msgs.length, 'warn': b.contains('0123456789')});
      },
      'POST chat/report': (_) => (200, {'ok': true}),
      'POST chat/block': (_) {
        blocked = true;
        return (200, {'ok': true, 'iBlock': true});
      },
    });
    await openOrder(t);
    await tap(t, 'msg-O40');
    expect(body(f, 'chat/open'), {'ref': 'O40'});
    expect(find.text('Tolu A.'), findsOneWidget);
    expect(find.text('Hi, it\'s ready'), findsOneWidget);

    await t.enterText(find.byKey(const Key('chatText')), 'Can I pay to 0123456789?');
    await tap(t, 'chatSend');
    expect(body(f, 'chat/send'), {'tid': 9, 'body': 'Can I pay to 0123456789?'});
    expect(find.text('Can I pay to 0123456789?'), findsOneWidget);
    expect(find.textContaining('Money sent straight to someone\'s account isn\'t protected'), findsOneWidget);

    await tap(t, 'chatMenu');
    await t.tap(find.text('Report'));
    await settle(t);
    await t.enterText(find.byKey(const Key('reportWhy')), 'Asking me to pay outside');
    await tap(t, 'reportSend');
    expect(body(f, 'chat/report'), {'tid': 9, 'reason': 'Asking me to pay outside'});

    await tap(t, 'chatMenu');
    await t.tap(find.text('Block'));
    await settle(t);
    expect(body(f, 'chat/block'), {'tid': 9, 'on': true});
    expect(find.byKey(const Key('chatText')), findsNothing);
  });

  testWidgets('Messages lists chats, unread first', (t) async {
    await start(t, {
      'GET chat/list': (_) => (200, {
            'threads': [
              {'id': 3, 'ref': 'L5', 'title': 'Desk lamp', 'with': 'Kemi', 'role': 'buyer', 'last': 'Still available?', 'lastAt': 1, 'unread': true},
            ]
          }),
      'GET chat/msgs': (_) => (200, {'thread': {'id': 3, 'with': 'Kemi', 'title': 'Desk lamp'}, 'msgs': []}),
    });
    await tap(t, 'messages');
    expect(find.text('Kemi'), findsOneWidget);
    expect(find.text('Still available?'), findsOneWidget);
    await tap(t, 'thread-3');
    expect(find.text('Say hello'), findsOneWidget);
  });

  testWidgets('report a problem with a note, then the seller answers and the buyer accepts or sees both sides', (t) async {
    var o = order(40, status: 'verified');
    final f = await start(t, {
      'GET orders/mine': (_) => (200, {'orders': [o]}),
      'POST orders/report': (r) {
        o = {...o, 'status': 'disputed', 'dispBy': 'buyer', 'note': 'The buyer reported: the cover is torn'};
        return (200, {'ok': true});
      },
      'POST orders/settle': (_) {
        o = {...o, 'status': 'verified', 'dispBy': null, 'note': ''};
        return (200, {'ok': true});
      },
      'GET orders/evidence': (_) => (200, {
            'items': [
              {'side': 'buyer', 'who': 'Ada Obi', 'text': 'The cover is torn', 'photo': null, 't': 1},
              {'side': 'seller', 'who': 'Tolu A.', 'text': 'It was fine at pickup', 'photo': null, 't': 2},
            ]
          }),
    });
    await openOrder(t);
    await tap(t, 'reportProblem');
    expect(find.textContaining('has 4 hours to accept'), findsOneWidget);
    await tap(t, 'noteSend');
    expect(find.text('Write what happened (a sentence or two) or add a photo.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('noteText')), 'the cover is torn');
    await tap(t, 'noteSend');
    expect(body(f, 'orders/report'), containsPair('reason', 'the cover is torn'));
    expect(find.textContaining('The buyer reported: the cover is torn'), findsOneWidget);

    await tap(t, 'bothSides');
    expect(find.text('It was fine at pickup'), findsOneWidget);
    await t.pageBack();
    await settle(t);

    await tap(t, 'settleWithdraw');
    await t.tap(find.text('Withdraw report').last);
    await settle(t);
    expect(body(f, 'orders/settle'), {'id': 40, 'how': 'withdraw'});
    await t.scrollUntilVisible(find.byKey(const Key('gotIt')), 200, scrollable: page());
    expect(find.byKey(const Key('gotIt')), findsOneWidget);
  });

  testWidgets('a buyer marked as a no-show can say it isn\'t true', (t) async {
    final f = await start(t, {
      'GET orders/mine': (_) => (200, {'orders': [order(40, status: 'refunded', extra: {'noShow': true})]}),
      'POST orders/object': (_) => (200, {'ok': true}),
    });
    await openOrder(t);
    expect(find.textContaining('counts as a strike on your account'), findsOneWidget);
    await tap(t, 'objectNoShow');
    await t.tap(find.text('It isn\'t true'));
    await settle(t);
    expect(body(f, 'orders/object'), {'id': 40});
  });

  testWidgets('a seller replies to a review from Account; a paused account sees why', (t) async {
    var replied = false;
    final f = await start(t, {
      'GET reviews': (_) => (200, {
            'rating': {'avg': 4, 'n': 1},
            'reviews': [
              {'id': 12, 'who': 'Kemi A.', 'title': 'Desk lamp', 'stars': 4, 'text': 'Good lamp', 't': 1, 'reply': replied ? 'Thanks Kemi!' : ''},
            ],
          }),
      'POST reviews/reply': (_) {
        replied = true;
        return (200, {'ok': true});
      },
    }, me: {'pausedUntil': DateTime(2026, 10, 30).millisecondsSinceEpoch});
    expect(find.byKey(const Key('paused')), findsOneWidget);
    await t.tap(find.text('Account'));
    await settle(t);
    expect(find.byKey(const Key('paused')), findsOneWidget);
    await tap(t, 'myReviews');
    await tap(t, 'reply-12');
    await t.enterText(find.byKey(const Key('replyText')), 'Thanks Kemi!');
    await tap(t, 'replySend');
    expect(body(f, 'reviews/reply'), {'id': 12, 'text': 'Thanks Kemi!'});
    expect(find.textContaining('Thanks Kemi!'), findsOneWidget);
    expect(find.byKey(const Key('reply-12')), findsNothing);
  });
}
