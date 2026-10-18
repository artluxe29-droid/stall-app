import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stall/main.dart';

import 'helpers.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> settle(WidgetTester t) async {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pumpAndSettle();
  }

  Future<FakeApi> account(WidgetTester t, Map<String, FakeRoute> routes, {Map<String, dynamic> me = const {}}) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    var u = {...user(), 'email': 'ada@gmail.com', 'emailVerified': true, 'emailNotify': true, ...me};
    final f = FakeApi({
      'GET config': (_) => (200, {'emailOn': true, 'phone': '08012345678', 'email': 'help@stall.com.ng'}),
      'GET me': (_) => (200, {'user': u}),
      'GET listings': (_) => (200, {'listings': [], 'total': 0}),
      'POST me/notify': (r) {
        u = {...u, 'emailNotify': (jsonDecode(r.body) as Map)['on']};
        return (200, {'ok': true});
      },
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

  testWidgets('email updates switch off and on', (t) async {
    final f = await account(t, {});
    await tap(t, 'emailNotify');
    expect(body(f, 'me/notify'), {'on': false});
    expect(t.widget<SwitchListTile>(find.byKey(const Key('emailNotify'))).value, isFalse);
  });

  testWidgets('invite friends shows your code, who joined and your credit', (t) async {
    await account(t, {
      'GET me/referral': (_) => (200, {'code': 'ADA42', 'link': 'https://stall.com.ng/?r=ADA42', 'invited': 3, 'rewarded': 2, 'credit': 1000, 'reward': 500, 'minOrder': 2000, 'pct': 50}),
    }, me: {'credit': 1000});
    await t.scrollUntilVisible(find.text('₦1,000 credit'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('₦1,000 credit'), findsOneWidget);
    await tap(t, 'inviteTile');
    expect(find.text('ADA42'), findsOneWidget);
    expect(find.text('Get ₦500 credit for each friend'), findsOneWidget);
    expect(find.textContaining('first order of ₦2,000 or more'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('how Stall works and help', (t) async {
    await account(t, {});
    await tap(t, 'guideTile');
    expect(find.text('1. Find what you need'), findsOneWidget);
    await t.tap(find.text('Selling'));
    await t.pumpAndSettle();
    expect(find.text('1. Post an item'), findsOneWidget);
    await t.pageBack();
    await settle(t);
    await tap(t, 'helpTile');
    expect(find.byKey(const Key('helpWa')), findsOneWidget);
    expect(find.text('Email help@stall.com.ng'), findsOneWidget);
  });

  testWidgets('delete account: a wrong password is refused, the right one signs you out', (t) async {
    final f = await account(t, {
      'POST me/delete': (r) =>
          (jsonDecode(r.body) as Map)['password'] == 'password123' ? (200, {'ok': true}) : (400, {'error': 'That password is wrong.'}),
      'POST logout': (_) => (200, {'ok': true}),
    });
    await tap(t, 'manageAccount'); // help and a break come first
    expect(find.text('Problem with an order or payment?'), findsOneWidget);
    await tap(t, 'deleteAccount');
    await tap(t, 'delGo');
    expect(find.text('Choose why you\'re leaving.'), findsOneWidget);
    await t.tap(find.byKey(const Key('delWhy')));
    await t.pumpAndSettle();
    await t.tap(find.text('Privacy concerns').last);
    await t.pumpAndSettle();
    await tap(t, 'delGo');
    expect(find.text('Type your password to confirm.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('delPw')), 'nope');
    await tap(t, 'delGo');
    expect(find.text('That password is wrong.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('delPw')), 'password123');
    await tap(t, 'delGo');
    expect(body(f, 'me/delete'), {'password': 'password123', 'why': 'privacy'});
    expect(find.text('Welcome back'), findsOneWidget);
    expect(await f.store.read(), isNull);
  });
}
