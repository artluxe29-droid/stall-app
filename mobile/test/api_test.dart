import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stall/api.dart';

import 'helpers.dart';

void main() {
  test('sends the app header, and the token once signed in', () async {
    final f = FakeApi({'GET me': (_) => (200, {'user': user()})});
    await f.api.get('me');
    expect(f.calls.last.headers['x-stall-app'], '1');
    expect(f.calls.last.headers.containsKey('authorization'), isFalse);
    await f.api.setToken('a' * 64);
    await f.api.get('me');
    expect(f.calls.last.headers['authorization'], 'Bearer ${'a' * 64}');
    expect(f.store.token, 'a' * 64);
  });

  test('server error messages come through as ApiError, as written', () async {
    final f = FakeApi({'POST login': (_) => (401, {'error': 'Wrong phone number or password.'})});
    await expectLater(
      f.api.post('login', {'id': 'x', 'password': 'y'}),
      throwsA(isA<ApiError>().having((e) => e.message, 'message', 'Wrong phone number or password.').having((e) => e.status, 'status', 401)),
    );
  });

  test('no connection gives a friendly message', () async {
    final api = Api(base: 'https://stall.test', store: MemoryTokenStore(), client: MockClient((_) async => throw http.ClientException('offline')));
    await expectLater(api.get('config'), throwsA(isA<ApiError>().having((e) => e.message, 'message', contains('No connection'))));
  });

  test('photo paths become full addresses', () {
    final f = FakeApi({});
    expect(f.api.url('/api/photo/3/0'), 'https://stall.test/api/photo/3/0');
    expect(f.api.url('https://x.test/a.png'), 'https://x.test/a.png');
  });
}
