import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stall/appearance.dart';
import 'package:stall/main.dart';
import 'package:stall/screens/sell.dart' show pickListingPhotos;
import 'package:stall/theme.dart';

import 'browse_test.dart' show listing;
import 'helpers.dart';
import 'store_test.dart' show myStore;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => StallColors.dark = false);

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
      'GET me': (_) => (200, {'user': user()}),
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

  Future<void> tap(WidgetTester t, String key) async {
    await reveal(t, find.byKey(Key(key)));
    await t.ensureVisible(find.byKey(Key(key)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(Key(key)));
    await settle(t);
  }

  testWidgets('Account switches the app to dark and back, and remembers it', (t) async {
    await start(t, {});
    await t.tap(find.text('Account'));
    await settle(t);
    await reveal(t, find.byKey(const Key('themeMode')));
    await t.tap(find.text('Dark'));
    await settle(t);
    expect(StallColors.dark, isTrue);
    expect(appearance.mode, 'dark');
    expect(Theme.of(t.element(find.byKey(const Key('themeMode')))).brightness, Brightness.dark);
    expect((await SharedPreferences.getInstance()).getString('theme'), 'dark');

    await t.tap(find.text('Light'));
    await settle(t);
    expect(StallColors.dark, isFalse);
    expect(Theme.of(t.element(find.byKey(const Key('themeMode')))).brightness, Brightness.light);
  });

  testWidgets('a store owner adds items and manages the store from its own page, or from Account', (t) async {
    await start(t, {
      'GET stores': (_) => (200, {
            'stores': [myStore()]
          }),
    });
    await t.tap(find.text('Account'));
    await settle(t);
    await tap(t, 'accStore');
    expect(find.text('Mama T Kitchen'), findsWidgets);
    await tap(t, 'seeStore');
    expect(find.byKey(const Key('ownerAddItem')), findsOneWidget);
    expect(find.byKey(const Key('ownerManage')), findsOneWidget);
    expect(find.byKey(const Key('logoNudge')), findsOneWidget); // no logo yet
    await tap(t, 'ownerAddItem');
    expect(find.byType(TextField), findsWidgets); // the add-item form
  });

  Map<String, dynamic> body(FakeApi f, String path) =>
      jsonDecode(f.calls.lastWhere((c) => c.url.path == '/api/$path' && c.method == 'POST').body) as Map<String, dynamic>;

  testWidgets('change password from Account; a wrong current password is explained', (t) async {
    var ok = false;
    final f = await start(t, {
      'POST password': (r) {
        final b = jsonDecode(r.body) as Map<String, dynamic>;
        if (b['old'] != 'password123') return (400, {'error': 'Your current password is wrong.'});
        ok = true;
        return (200, {'ok': true});
      },
    });
    await t.tap(find.text('Account'));
    await settle(t);
    await tap(t, 'accPw');
    await t.enterText(find.byKey(const Key('pwOld')), 'nope');
    await t.enterText(find.byKey(const Key('pwNew')), 'newpass99');
    await tap(t, 'pwSave');
    expect(find.text('Your current password is wrong.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('pwOld')), 'password123');
    await tap(t, 'pwSave');
    expect(ok, isTrue);
    expect(body(f, 'password'), {'old': 'password123', 'password': 'newpass99'});
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('Account shows whether this phone gets notifications', (t) async {
    await start(t, {});
    await t.tap(find.text('Account'));
    await settle(t);
    await reveal(t, find.byKey(const Key('accPush')));
    expect(find.text('Not available in this version'), findsOneWidget); // tests have no Firebase
    await tap(t, 'accPush');
    expect(find.byKey(const Key('pushStatus')), findsOneWidget);
  });

  testWidgets('a listing can be reported to the Stall team', (t) async {
    final f = await start(t, {
      'GET listings': (_) => (200, {'listings': [listing(1)], 'total': 1}),
      'GET reviews': (_) => (200, {'rating': {'avg': 0, 'n': 0}, 'reviews': []}),
      'POST report': (_) => (200, {'ok': true}),
    });
    await reveal(t, find.byKey(const Key('item-L1')));
    await t.tap(find.byKey(const Key('item-L1')));
    await settle(t);
    await tap(t, 'report-listing');
    await t.enterText(find.byKey(const Key('noteText')), 'Looks like a scam');
    await t.tap(find.text('Send report'));
    await settle(t);
    expect(body(f, 'report'), {'kind': 'listing', 'target': 'L1', 'reason': 'Looks like a scam'});
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('apply for the verified seller badge, then pay once approved', (t) async {
    var me = {...user(), 'verify': null};
    final f = await start(t, {
      'GET me': (_) => (200, {'user': me}),
      'POST verify/apply': (_) {
        me = {...me, 'verify': 'pending'};
        return (200, {'ok': true});
      },
    });
    pickListingPhotos = (_, _) async => ['data:image/jpeg;base64,AAAA'];
    await t.tap(find.text('Account'));
    await settle(t);
    await tap(t, 'accVerify');
    await t.enterText(find.byKey(const Key('verNote')), '300L student, I sell perfumes');
    await tap(t, 'verPhoto');
    await tap(t, 'verSend');
    expect(body(f, 'verify/apply'), {'note': '300L student, I sell perfumes', 'photo': 'data:image/jpeg;base64,AAAA'});
    expect(find.byKey(const Key('verPending')), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('a seller features their own listing for 3 days', (t) async {
    final f = await start(t, {
      'GET listings': (_) => (200, {'listings': [listing(1, extra: {'mine': true})], 'total': 1}),
      'GET reviews': (_) => (200, {'rating': {'avg': 0, 'n': 0}, 'reviews': []}),
      'POST pay/start': (_) => (200, {'ok': true}),
    });
    await reveal(t, find.byKey(const Key('item-L1')));
    await t.tap(find.byKey(const Key('item-L1')));
    await settle(t);
    await tap(t, 'feat-3');
    expect(body(f, 'pay/start'), {'kind': 'boost', 'target': 'L1', 'days': 3});
    expect(find.text('Featured for 3 days'), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('Home shows a Featured row for promoted items, and refreshes when listings change', (t) async {
    var v = 1;
    var items = [listing(1, extra: {'featured': true}), listing(2, title: 'Desk lamp')];
    final f = await start(t, {
      'GET listings/ver': (_) => (200, {'v': v}),
      'GET listings': (_) => (200, {'listings': items, 'total': items.length}),
    });
    await reveal(t, find.byKey(const Key('featRow')));
    expect(find.text('Promoted'), findsOneWidget);
    final before = f.calls.where((c) => c.url.path == '/api/listings').length;
    v = 2; // someone posted something
    items = [listing(3, title: 'New kettle'), ...items];
    await t.pump(const Duration(minutes: 1));
    await settle(t);
    expect(f.calls.where((c) => c.url.path == '/api/listings').length, greaterThan(before));
  });

  testWidgets('when students can\'t sell at their school, Sell says so instead of opening the form', (t) async {
    await start(t, {
      'GET me': (_) => (200, {
            'user': {
              ...user(),
              'schoolInfo': {'id': 1, 'name': 'Ajayi Crowther University', 'short': 'ACU', 'state': 'Oyo', 'stu_sell': 0}
            }
          }),
    });
    await t.tap(find.text('Sell'));
    await settle(t);
    expect(find.byKey(const Key('stuOff')), findsOneWidget);
    await tap(t, 'sellItem');
    expect(find.textContaining('Students can\'t sell on Stall at ACU right now'), findsWidgets);
    await t.pump(const Duration(seconds: 5));
  });
}
