import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stall/main.dart';

import 'helpers.dart';

void main() {
  Future<FakeApi> pump(WidgetTester t, Map<String, FakeRoute> routes) async {
    final f = FakeApi({'GET config': (_) => (200, {}), ...routes});
    final s = f.session();
    await t.pumpWidget(StallApp(session: s));
    await t.runAsync(s.restore);
    await t.pumpAndSettle();
    return f;
  }

  testWidgets('sign-in checks the form, then shows the server\'s message', (t) async {
    await pump(t, {'POST login': (_) => (401, {'error': 'Wrong phone number or password.'})});
    expect(find.text('Welcome back'), findsOneWidget);
    await t.tap(find.byKey(const Key('signIn')));
    await t.pump();
    expect(find.text('Enter your phone number.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('phone')), '08031234567');
    await t.enterText(find.byKey(const Key('password')), 'nope');
    await t.runAsync(() async {
      await t.tap(find.byKey(const Key('signIn')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await t.pumpAndSettle();
    expect(find.byKey(const Key('error')), findsOneWidget);
    expect(find.text('Wrong phone number or password.'), findsOneWidget);
  });

  testWidgets('signing in opens Stall with the tab bar; sign out returns', (t) async {
    await pump(t, {
      'POST login': (_) => (200, {'user': user(), 'token': 'f' * 64}),
      'GET me': (_) => (200, {'user': user()}),
      'GET listings': (_) => (200, {'listings': [], 'total': 0}),
      'POST logout': (_) => (200, {'ok': true}),
    });
    await t.enterText(find.byKey(const Key('phone')), '08031234567');
    await t.enterText(find.byKey(const Key('password')), 'password123');
    await t.runAsync(() async {
      await t.tap(find.byKey(const Key('signIn')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await t.pumpAndSettle();
    expect(find.text('Hi Ada'), findsOneWidget);
    expect(find.text('No items yet'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    await t.tap(find.text('Account'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.byKey(const Key('signOut')), 200, scrollable: find.byType(Scrollable).first);
    await t.runAsync(() async {
      await t.tap(find.byKey(const Key('signOut')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await t.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets('when Stall is closed, a student sees the break screen', (t) async {
    await pump(t, {
      'GET config': (_) => (200, {'closed': true, 'brk': {'msg': 'Back after exams.'}}),
      'POST login': (_) => (200, {'user': user(), 'token': 'g' * 64}),
      'GET me': (_) => (200, {'user': user()}),
    });
    await t.enterText(find.byKey(const Key('phone')), '08031234567');
    await t.enterText(find.byKey(const Key('password')), 'password123');
    await t.runAsync(() async {
      await t.tap(find.byKey(const Key('signIn')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await t.pumpAndSettle();
    expect(find.text('Stall is taking a short break'), findsOneWidget);
    expect(find.text('Back after exams.'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });
}
