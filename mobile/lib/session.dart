import 'package:flutter/foundation.dart';

import 'api.dart';

/// The signed-in person, from the API's user object.
class StallUser {
  StallUser(this.raw);
  final Map<String, dynamic> raw;
  int get uid => (raw['uid'] as num?)?.toInt() ?? 0;
  String get name => (raw['name'] ?? '').toString();
  String get firstName => name.split(' ').first;
  String get phone => (raw['phone'] ?? '').toString();
  String get role => (raw['role'] ?? 'student').toString();
  bool get isAdmin => raw['admin'] == true;
  bool get isReviewer => raw['reviewer'] == true;
  bool get isStaff => isAdmin || isReviewer;
  Map<String, dynamic>? get school => raw['schoolInfo'] is Map<String, dynamic> ? raw['schoolInfo'] as Map<String, dynamic> : null;
  String get schoolName => (school?['short'] ?? school?['name'] ?? '').toString();
}

enum SessionState { loading, signedOut, signedIn }

/// Who is signed in, plus the server settings the whole app depends on
/// (closed for a break, short break message, store links…).
class Session extends ChangeNotifier {
  Session(this.api);
  final Api api;

  SessionState state = SessionState.loading;
  StallUser? user;
  Map<String, dynamic> config = const {};

  /// Stall is closed to the public (Admin → Close the app): only staff may use it.
  bool get closedForMe => config['closed'] == true && !(user?.isStaff ?? false);
  String? get breakMessage {
    final b = config['brk'];
    if (b is! Map) return null;
    final m = (b['msg'] ?? '').toString().trim();
    return m.isEmpty ? defaultBreakMessage : m;
  }

  static const defaultBreakMessage =
      "We're building something better, and we'll be back soon. Thank you for your patience. We can't wait to show you what's next.";

  /// On launch: load server settings, and sign back in with the saved token if there is one.
  Future<void> restore() async {
    await _loadConfig();
    if (await api.token() == null) {
      _set(SessionState.signedOut);
      return;
    }
    try {
      final r = await api.get('me');
      user = StallUser(r['user'] as Map<String, dynamic>);
      _set(SessionState.signedIn);
    } on ApiError catch (e) {
      // Only a rejected token signs you out; a bad connection keeps you signed in for the next try.
      if (e.status == 401) await api.setToken(null);
      _set(e.status == 401 ? SessionState.signedOut : SessionState.signedIn);
    }
  }

  Future<void> _loadConfig() async {
    try {
      config = await api.get('config');
    } catch (_) {}
  }

  /// Signs in with phone number and password. Throws ApiError with the server's message.
  Future<void> signIn(String phone, String password) async {
    final r = await api.post('login', {'id': phone.trim(), 'password': password});
    final token = r['token'];
    if (token is! String) throw ApiError('Could not sign in. Please update the app and try again.');
    await api.setToken(token);
    try {
      final m = await api.get('me');
      user = StallUser(m['user'] as Map<String, dynamic>);
    } catch (_) {
      user = StallUser(r['user'] as Map<String, dynamic>);
    }
    await _loadConfig();
    _set(SessionState.signedIn);
  }

  Future<void> signOut() async {
    try {
      await api.post('logout');
    } catch (_) {}
    await api.setToken(null);
    user = null;
    _set(SessionState.signedOut);
  }

  void _set(SessionState s) {
    state = s;
    notifyListeners();
  }
}
