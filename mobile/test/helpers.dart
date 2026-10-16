import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stall/api.dart';
import 'package:stall/session.dart';

/// A fake Stall API: routes are 'GET me', 'POST login'…; each returns (status, json).
typedef FakeRoute = (int, Map<String, dynamic>) Function(http.Request r);

class FakeApi {
  FakeApi(this.routes);
  final Map<String, FakeRoute> routes;
  final calls = <http.Request>[];
  final store = MemoryTokenStore();

  late final api = Api(
    base: 'https://stall.test',
    store: store,
    client: MockClient((r) async {
      calls.add(r);
      final key = '${r.method} ${r.url.path.replaceFirst('/api/', '')}';
      final h = routes[key];
      if (h == null) return http.Response(jsonEncode({'error': 'Not found'}), 404);
      final (status, body) = h(r);
      return http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});
    }),
  );

  Session session() => Session(api);
}

Map<String, dynamic> user({bool admin = false, String name = 'Ada Obi'}) => {
      'uid': 7,
      'name': name,
      'phone': '08031234567',
      'role': 'student',
      'admin': admin,
      'reviewer': false,
      'schoolInfo': {'id': 1, 'name': 'Ajayi Crowther University', 'short': 'ACU'},
    };
