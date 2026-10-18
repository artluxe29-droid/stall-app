import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stall/appearance.dart';
import 'package:stall/main.dart';
import 'package:stall/theme.dart';

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
}
