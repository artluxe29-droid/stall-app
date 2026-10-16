import 'package:flutter_test/flutter_test.dart';
import 'package:stall/api.dart';
import 'package:stall/session.dart';

import 'helpers.dart';

void main() {
  test('sign in saves the token and loads the user', () async {
    final f = FakeApi({
      'GET config': (_) => (200, {'closed': false}),
      'POST login': (r) => (200, {'user': user(), 'token': 'b' * 64}),
      'GET me': (_) => (200, {'user': user()}),
    });
    final s = f.session();
    await s.restore();
    expect(s.state, SessionState.signedOut);
    await s.signIn('0803 123 4567', 'password123');
    expect(s.state, SessionState.signedIn);
    expect(s.user!.firstName, 'Ada');
    expect(s.user!.schoolName, 'ACU');
    expect(f.store.token, 'b' * 64);
  });

  test('a rejected token signs you out; a bad connection does not', () async {
    var status = 401;
    final f = FakeApi({
      'GET config': (_) => (200, {}),
      'GET me': (_) => (status, {'error': status == 401 ? 'Not signed in' : 'Server busy'}),
    });
    await f.store.write('c' * 64);
    final s = f.session();
    await s.restore();
    expect(s.state, SessionState.signedOut);
    expect(f.store.token, isNull);

    status = 503;
    await f.store.write('c' * 64);
    final s2 = FakeApi(f.routes).session();
    await (s2.api..setToken('c' * 64)).token();
    await s2.restore();
    expect(s2.state, SessionState.signedIn);
  });

  test('closed to the public: only staff get in', () async {
    final f = FakeApi({
      'GET config': (_) => (200, {'closed': true, 'brk': {'msg': ''}}),
      'POST login': (_) => (200, {'user': user(), 'token': 'd' * 64}),
      'GET me': (_) => (200, {'user': user()}),
    });
    final s = f.session();
    await s.restore();
    await s.signIn('08031234567', 'password123');
    expect(s.closedForMe, isTrue);
    expect(s.breakMessage, Session.defaultBreakMessage);
    s.user = StallUser(user(admin: true));
    expect(s.closedForMe, isFalse);
  });

  test('sign out forgets the token', () async {
    final f = FakeApi({'POST logout': (_) => (200, {'ok': true})});
    await f.api.setToken('e' * 64);
    final s = f.session()..user = StallUser(user());
    await s.signOut();
    expect(s.state, SessionState.signedOut);
    expect(await f.api.token(), isNull);
    expect(f.calls.single.headers['authorization'], 'Bearer ${'e' * 64}');
  });

  test('a login reply without a token is an error, not a half sign-in', () async {
    final f = FakeApi({'POST login': (_) => (200, {'user': user()})});
    await expectLater(f.session().signIn('08031234567', 'x'), throwsA(isA<ApiError>()));
  });
}
