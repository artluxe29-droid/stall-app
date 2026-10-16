import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stall/main.dart';
import 'package:stall/screens/account_setup.dart';

import 'helpers.dart';

final schools = {
  'schools': [
    {'id': 1, 'name': 'Ajayi Crowther University', 'short': 'ACU', 'state': 'Oyo', 'launch': 'live'},
    {'id': 2, 'name': 'University of Lagos', 'short': 'UNILAG', 'state': 'Lagos', 'launch': 'soon'},
  ],
  'states': ['Lagos', 'Oyo'],
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> settle(WidgetTester t) async {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pumpAndSettle();
  }

  Future<FakeApi> start(WidgetTester t, Map<String, FakeRoute> routes, {bool signedIn = false}) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final f = FakeApi({
      'GET config': (_) => (200, {'emailOn': true}),
      'GET schools': (_) => (200, schools),
      'GET listings': (_) => (200, {'listings': [], 'total': 0}),
      ...routes,
    });
    if (signedIn) await f.store.write('a' * 64);
    final s = f.session();
    await t.pumpWidget(StallApp(session: s));
    await t.runAsync(s.restore);
    await settle(t);
    return f;
  }

  Map<String, dynamic> body(FakeApi f, String path) =>
      jsonDecode(f.calls.lastWhere((c) => c.url.path == '/api/$path').body) as Map<String, dynamic>;

  Future<void> type(WidgetTester t, String key, String text) async {
    await t.ensureVisible(find.byKey(Key(key)));
    await t.enterText(find.byKey(Key(key)), text);
  }

  Future<void> tap(WidgetTester t, String key) async {
    await t.ensureVisible(find.byKey(Key(key)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(Key(key)));
    await settle(t);
  }

  testWidgets('a student signs up, then confirms their email with a code', (t) async {
    var me = {...user(), 'email': 'ada@gmail.com', 'emailVerified': false};
    final f = await start(t, {
      'POST register': (_) => (200, {'user': me, 'token': 'b' * 64}),
      'GET me': (_) => (200, {'user': me}),
      'POST verify/email/start': (_) => (200, {'ok': true, 'school': null}),
      'POST verify/email/confirm': (_) {
        me = {...me, 'emailVerified': true};
        return (200, {'ok': true, 'vlevel': 0});
      },
    });
    await tap(t, 'toSignUp');
    expect(find.text('Create your account'), findsOneWidget);

    // Nothing filled in: every field explains what it needs.
    await tap(t, 'su-submit');
    expect(find.text('Choose your school.'), findsOneWidget);
    expect(find.text('Enter your full name.'), findsOneWidget);
    expect(find.text('Please confirm to continue.'), findsOneWidget);
    expect(f.calls.where((c) => c.url.path == '/api/register'), isEmpty);

    await tap(t, 'school');
    await t.enterText(find.byKey(const Key('schoolSearch')), 'acu');
    await t.pumpAndSettle();
    expect(find.text('University of Lagos (UNILAG)'), findsNothing);
    await t.tap(find.text('Ajayi Crowther University (ACU)'));
    await t.pumpAndSettle();

    await type(t, 'su-name', 'Ada Obi');
    await type(t, 'su-matric', 'ac20201234');
    await type(t, 'su-email', 'ada@gmail.com');
    await type(t, 'su-phone', '0803 123 4567');
    await type(t, 'su-pw', 'password123');
    await type(t, 'su-where', 'Hall B');
    await tap(t, 'su-ok');
    await tap(t, 'su-submit');

    expect(body(f, 'register'), {
      'school_id': 1,
      'role': 'student',
      'name': 'Ada Obi',
      'phone': '0803 123 4567',
      'where': 'Hall B',
      'password': 'password123',
      'matric': 'ac20201234',
      'email': 'ada@gmail.com',
    });
    expect(f.calls.last.headers['x-stall-app'], '1');
    expect(await f.store.read(), 'b' * 64);

    // Straight to "Confirm your email", with the code already sent.
    expect(find.text('Confirm your email'), findsOneWidget);
    expect(body(f, 'verify/email/start'), {'email': 'ada@gmail.com'});
    await t.enterText(find.byKey(const Key('em-code')), '123456');
    await tap(t, 'em-confirm');
    expect(body(f, 'verify/email/confirm'), {'code': '123456'});
    expect(find.text('Hi Ada'), findsOneWidget);
  });

  testWidgets('a server error lands on the right field; an unlisted school sends its name and state', (t) async {
    final f = await start(t, {
      'POST register': (_) => (409, {'error': 'An account with this matric number or phone number already exists. Try signing in.', 'field': 'matric'}),
    });
    await tap(t, 'toSignUp');
    await tap(t, 'school');
    await t.enterText(find.byKey(const Key('schoolSearch')), 'Kings College');
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('notListed')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('newSchoolState')));
    await t.pumpAndSettle();
    await t.tap(find.text('Lagos').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('newSchoolSave')));
    await t.pumpAndSettle();
    expect(find.text('Kings College — Lagos'), findsOneWidget);

    await type(t, 'su-name', 'Ada Obi');
    await type(t, 'su-matric', 'AC20201234');
    await type(t, 'su-email', 'ada@gmail.com');
    await type(t, 'su-phone', '08031234567');
    await type(t, 'su-pw', 'password123');
    await type(t, 'su-where', 'Hall B');
    await tap(t, 'su-ok');
    await tap(t, 'su-submit');
    expect(body(f, 'register'), containsPair('school_name', 'Kings College'));
    expect(body(f, 'register'), containsPair('school_state', 'Lagos'));
    expect(find.text('An account with this matric number or phone number already exists. Try signing in.'), findsOneWidget);
    expect(find.text('Create your account'), findsOneWidget);
  });

  testWidgets('a campus vendor signs up with business details', (t) async {
    final f = await start(t, {
      'POST register': (_) => (200, {'user': {...user(), 'role': 'vendor'}, 'token': 'c' * 64}),
      'GET me': (_) => (200, {'user': {...user(), 'role': 'vendor'}}),
    });
    await tap(t, 'toSignUp');
    await t.tap(find.text('Campus vendor'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('su-matric')), findsNothing);
    await tap(t, 'school');
    await t.tap(find.text('Ajayi Crowther University (ACU)'));
    await t.pumpAndSettle();
    await type(t, 'su-biz', 'Mama T Kitchen');
    await type(t, 'su-name', 'Titi Ade');
    await type(t, 'su-phone', '08091234567');
    await type(t, 'su-pw', 'password123');
    await type(t, 'su-where', 'Cafeteria, Stall 4');
    await tap(t, 'su-ok');
    await tap(t, 'su-submit');
    expect(body(f, 'register'), allOf(containsPair('role', 'vendor'), containsPair('biz', 'Mama T Kitchen'), containsPair('cat', 'books')));
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('forgot password: email a code, then set a new password', (t) async {
    final f = await start(t, {
      'POST auth/forgot': (_) => (200, {'ok': true, 'message': 'If that account has a confirmed email, we have sent it a code.'}),
      'POST auth/reset': (_) => (200, {'ok': true}),
    });
    await t.enterText(find.byKey(const Key('phone')), '08031234567');
    await tap(t, 'forgot');
    await tap(t, 'fg-go');
    expect(body(f, 'auth/forgot'), {'id': '08031234567'});
    expect(find.text('Check your email'), findsOneWidget);
    await t.enterText(find.byKey(const Key('fg-code')), '654321');
    await t.enterText(find.byKey(const Key('fg-pw')), 'short');
    await tap(t, 'fg-go');
    expect(find.text('Use at least 8 characters.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('fg-pw')), 'newpassword1');
    await tap(t, 'fg-go');
    expect(body(f, 'auth/reset'), {'id': '08031234567', 'code': '654321', 'password': 'newpassword1'});
    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets('verification shows a pending check, and asks for a photo before sending', (t) async {
    var me = {...user(), 'vlevel': 0, 'idCheck': null};
    await start(t, {'GET me': (_) => (200, {'user': me})}, signedIn: true);
    await t.tap(find.text('Account'));
    await t.pumpAndSettle();
    expect(find.text('Not verified yet'), findsOneWidget);
    await tap(t, 'verify');
    await tap(t, 'vf-send');
    expect(find.text('Add a clear photo of your school document.'), findsOneWidget);
    expect(find.text('Or: a school email address'), findsOneWidget);

    me = {...me, 'idCheck': 'pending'};
    await t.pageBack();
    await t.pumpAndSettle();
    final s = SessionScope.of(t.element(find.byType(NavigationBar)));
    await t.runAsync(s.refresh);
    await t.pumpAndSettle();
    expect(find.text('Being checked'), findsOneWidget);
    await tap(t, 'verify');
    expect(find.byKey(const Key('vf-pending')), findsOneWidget);
  });

  testWidgets('when Admin requires it, unverified students verify before using Stall', (t) async {
    var me = {...user(), 'verifyGate': true, 'vlevel': 0, 'idCheck': 'pending'};
    await start(t, {'GET me': (_) => (200, {'user': me})}, signedIn: true);
    expect(find.text('We\'re checking your student ID'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    me = {...me, 'vlevel': 2, 'idCheck': 'approved'};
    await tap(t, 'checkAgain');
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('admins and vendors skip the verify-first screen', (t) async {
    await start(t, {'GET me': (_) => (200, {'user': {...user(admin: true), 'verifyGate': true, 'vlevel': 0}})}, signedIn: true);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  test('phone numbers are checked like the server does', () {
    expect(phoneError('0803 123 4567'), isNull);
    expect(phoneError('+234 803 123 4567'), isNull);
    expect(phoneError('0603 123 4567'), isNotNull);
    expect(phoneError('0801 111 1111'), isNotNull);
    expect(phoneError('08012345678'), isNotNull);
  });
}
