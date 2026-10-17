import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stall/main.dart';
import 'package:stall/push.dart';
import 'package:stall/screens/checkout.dart';

import 'helpers.dart';

Map<String, dynamic> view({required bool owner, bool open = true, List<Map<String, dynamic>> paid = const [], Map<String, dynamic>? mine}) => {
      'c': {
        'code': 'AB12CD',
        'title': 'CSC 301 handout',
        'cls': '300L CS',
        'descr': '',
        'publicList': false,
        'amount': 1500,
        'charge': 50,
        'total': 1550,
        'expected': 60,
        'deadline': null,
        'open': open,
        'status': open ? 'open' : 'closed',
        'rep': 'Ada Obi',
        'repVerified': true,
        'school': 'ACU',
      },
      'owner': owner,
      'mine': mine,
      'n': paid.length,
      'total': paid.length * 1500,
      'paid': owner ? paid : null,
    };

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> settle(WidgetTester t) async {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pumpAndSettle();
  }

  Future<FakeApi> start(WidgetTester t, Map<String, FakeRoute> routes) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final f = FakeApi({
      'GET config': (_) => (200, {}),
      'GET me': (_) => (200, {'user': {...user(), 'vlevel': 1}}),
      'GET listings': (_) => (200, {'listings': [], 'total': 0}),
      ...routes,
    });
    await f.store.write('a' * 64);
    final s = f.session();
    await t.pumpWidget(StallApp(session: s));
    await t.runAsync(s.restore);
    await settle(t);
    await t.tap(find.text('Account'));
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

  testWidgets('a class rep starts a collection, ticks off who collected, and closes it', (t) async {
    var paid = [
      {'id': 1, 'name': 'Kemi Ola', 't': DateTime(2026, 10, 17, 10).millisecondsSinceEpoch, 'ref': 'R1', 'ticked': false},
    ];
    var open = true;
    final f = await start(t, {
      'GET collect/mine': (_) => (200, {'items': [], 'bank': {'bank': 'GTBank', 'acct': '••••6789', 'name': 'ADA OBI'}}),
      'POST collect/create': (_) => (200, {'ok': true, 'code': 'AB12CD', 'link': 'https://stall.com.ng/?collect=AB12CD'}),
      'GET collect/view': (_) => (200, view(owner: true, open: open, paid: paid)),
      'POST collect/tick': (r) {
        paid = [{...paid.first, 'ticked': (jsonDecode(r.body) as Map)['on']}];
        return (200, {'ok': true});
      },
      'POST collect/status': (r) {
        open = (jsonDecode(r.body) as Map)['open'] as bool;
        return (200, {'ok': true});
      },
    });
    await tap(t, 'collectTile');
    await tap(t, 'coNew');
    expect(find.byKey(const Key('co-bank')), findsNothing); // their payout account is already set
    await t.enterText(find.byKey(const Key('coTitle')), 'CSC 301 handout');
    await t.enterText(find.byKey(const Key('coAmount')), '1500');
    await tap(t, 'coCreate');
    expect(body(f, 'collect/create'), {'title': 'CSC 301 handout', 'cls': '', 'descr': '', 'amount': 1500, 'public_list': false});
    expect(find.text('1 of 60'), findsOneWidget);
    expect(find.text('Kemi Ola'), findsOneWidget);

    await tap(t, 'coTick-1');
    expect(body(f, 'collect/tick'), {'code': 'AB12CD', 'id': 1, 'on': true});
    await tap(t, 'coOpen');
    expect(body(f, 'collect/status'), {'code': 'AB12CD', 'open': false});
    expect(find.text('Closed: no more payments.'), findsOneWidget);
  });

  testWidgets('a classmate pays into a collection with its code', (t) async {
    var mine = false;
    final f = await start(t, {
      'GET collect/mine': (_) => (200, {'items': [], 'bank': null}),
      'GET collect/view': (r) {
        expect(r.url.queryParameters['code'], 'AB12CD');
        return (200, view(owner: false, mine: mine ? {'t': DateTime(2026, 10, 17, 11).millisecondsSinceEpoch} : null));
      },
      'POST pay/start': (_) => (200, {'url': 'https://checkout.paystack.com/c', 'ref': 'C1'}),
      'POST pay/confirm': (_) {
        mine = true;
        return (200, {'ok': true});
      },
    });
    openPaystack = (context, url) async => 'C1';
    await tap(t, 'collectTile');
    await tap(t, 'coPay');
    await t.enterText(find.byKey(const Key('coCode')), 'https://stall.com.ng/?collect=ab12cd');
    await tap(t, 'coCodeGo');
    expect(find.text('Pay ₦1,550'), findsOneWidget);
    expect(find.textContaining('plus a ₦50 payment charge'), findsOneWidget);
    await tap(t, 'coPayNow');
    expect(body(f, 'pay/start'), {'kind': 'collect', 'target': 'AB12CD'});
    expect(find.byKey(const Key('coPaid')), findsOneWidget);
  });

  testWidgets('a collection link opens it', (t) async {
    await start(t, {'GET collect/view': (_) => (200, view(owner: false))});
    pushTarget.value = Uri.parse('https://stall.com.ng/?collect=ab12cd');
    await settle(t);
    expect(find.text('CSC 301 handout'), findsOneWidget);
  });
}
