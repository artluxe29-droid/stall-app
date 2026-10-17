import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Where the Stall API lives. Override for testing with --dart-define=STALL_API=http://10.0.2.2:8789
const apiBase = String.fromEnvironment('STALL_API', defaultValue: 'https://stall.com.ng');

/// An error the server explained in words people can read (it's shown as-is).
class ApiError implements Exception {
  ApiError(this.message, {this.status = 0, this.data = const {}});
  final String message;
  final int status;
  final Map<String, dynamic> data;
  @override
  String toString() => message;
}

/// Keeps the sign-in token. Production uses the phone's secure storage (Android Keystore / iOS Keychain).
abstract class TokenStore {
  Future<String?> read();
  Future<void> write(String? token);
}

class SecureTokenStore implements TokenStore {
  static const _key = 'stall_session';
  final _s = const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));
  @override
  Future<String?> read() => _s.read(key: _key);
  @override
  Future<void> write(String? token) => token == null ? _s.delete(key: _key) : _s.write(key: _key, value: token);
}

class MemoryTokenStore implements TokenStore {
  String? token;
  @override
  Future<String?> read() async => token;
  @override
  Future<void> write(String? t) async => token = t;
}

/// Talks to the same API as the web app. The app signs in with a token
/// ("Authorization: Bearer …") instead of the web app's cookie.
class Api {
  Api({http.Client? client, TokenStore? store, this.base = apiBase})
      : _http = client ?? http.Client(),
        _store = store ?? SecureTokenStore();

  final http.Client _http;
  final TokenStore _store;
  final String base;
  String? _token;
  bool _loaded = false;

  Future<String?> token() async {
    if (!_loaded) {
      _token = await _store.read();
      _loaded = true;
    }
    return _token;
  }

  Future<void> setToken(String? t) async {
    _token = t;
    _seen.clear(); // a different person (or nobody) from here on
    _loaded = true;
    await _store.write(t);
  }

  /// Photos and other paths from the API ("/api/photo/12/0") as full addresses.
  String url(String path) => path.startsWith('http') ? path : '$base$path';

  /// The last answer to each GET, so a screen can show it at once while it asks again.
  final _seen = <String, Map<String, dynamic>>{};
  static String _key(String path, Map<String, String>? query) => query == null || query.isEmpty ? path : '$path?${Uri(queryParameters: query).query}';

  /// What this GET returned last time, if it was asked before since sign-in.
  Map<String, dynamic>? seen(String path, [Map<String, String>? query]) => _seen[_key(path, query)];

  Future<Map<String, dynamic>> get(String path, [Map<String, String>? query]) async {
    final r = await _send('GET', path, query: query);
    if (_seen.length > 200) _seen.clear();
    return _seen[_key(path, query)] = r;
  }

  Future<Map<String, dynamic>> post(String path, [Map<String, dynamic>? body]) => _send('POST', path, body: body ?? const {});

  Future<Map<String, dynamic>> _send(String method, String path, {Map<String, String>? query, Map<String, dynamic>? body}) async {
    final uri = Uri.parse('$base/api/$path').replace(queryParameters: query);
    final t = await token();
    final headers = {
      'accept': 'application/json',
      'x-stall-app': '1',
      if (body != null) 'content-type': 'application/json',
      if (t != null) 'authorization': 'Bearer $t',
    };
    http.Response r;
    try {
      r = method == 'GET'
          ? await _http.get(uri, headers: headers).timeout(const Duration(seconds: 20))
          : await _http.post(uri, headers: headers, body: jsonEncode(body)).timeout(const Duration(seconds: 20));
    } catch (_) {
      throw ApiError('No connection. Check your data or Wi-Fi and try again.');
    }
    Map<String, dynamic> data;
    try {
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      data = d is Map<String, dynamic> ? d : {'data': d};
    } catch (_) {
      throw ApiError('Stall is having a problem right now. Please try again.', status: r.statusCode);
    }
    if (r.statusCode >= 400 || data['error'] != null) {
      throw ApiError((data['error'] ?? 'Something went wrong. Please try again.').toString(), status: r.statusCode, data: data);
    }
    return data;
  }
}
