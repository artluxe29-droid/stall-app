import 'package:flutter/foundation.dart';

import 'api.dart';
import 'bag.dart';
import 'theme.dart';

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
  String get state => (school?['state'] ?? '').toString();
  bool get isVendor => role == 'vendor';
  String get email => (raw['email'] ?? '').toString();
  bool get emailVerified => raw['emailVerified'] == true;
  /// 0 = not verified, 1 = confirmed a school email, 2 = Stall checked a school document.
  int get vlevel => (raw['vlevel'] as num?)?.toInt() ?? 0;
  /// The latest school document check: null, 'pending', 'approved' or 'rejected' (with [idReason]).
  String? get idCheck => raw['idCheck'] as String?;
  String get idReason => (raw['idReason'] ?? '').toString();
  bool get mustVerify => raw['mustVerify'] == true;
  /// Admin → "Students must be verified to use Stall" (on unless turned off).
  bool get verifyGate => raw['verifyGate'] == true;
  /// Has a payout bank account saved (it's added with the first listing).
  bool get acctSet => raw['acctSet'] == true;
  /// Sales left with no Stall fee (launch offer).
  int get freeLeft => (raw['freeLeft'] as num?)?.toInt() ?? 0;
  Map<String, dynamic> get deliv => raw['deliv'] is Map<String, dynamic> ? raw['deliv'] as Map<String, dynamic> : const {};
}

enum SessionState { loading, signedOut, signedIn }

/// Who is signed in, plus the server settings the whole app depends on
/// (closed for a break, short break message, store links…).
class Session extends ChangeNotifier {
  Session(this.api);
  final Api api;
  final bag = Bag();

  SessionState state = SessionState.loading;
  StallUser? user;
  Map<String, dynamic> config = const {};

  /// Stall is closed to the public (Admin → Close the app): only staff may use it.
  /// Students must show a school document before they can buy, sell or chat (when Admin has that on).
  bool get verifyFirst {
    final u = user;
    return u != null && u.verifyGate && !u.isVendor && !u.isAdmin && u.vlevel < 1;
  }

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
    await Future.wait([_loadConfig(), bag.load()]);
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

  /// Creates an account (the same fields as the web sign-up form).
  Future<void> signUp(Map<String, dynamic> body) async {
    final r = await api.post('register', body);
    final token = r['token'];
    if (token is! String) throw ApiError('Could not create your account. Please update the app and try again.');
    await api.setToken(token);
    user = StallUser(r['user'] as Map<String, dynamic>);
    await refresh();
    await _loadConfig();
    _set(SessionState.signedIn);
  }

  /// Reloads who you are (verification level, email, school…) after something changed it.
  Future<void> refresh() async {
    try {
      final m = await api.get('me');
      user = StallUser(m['user'] as Map<String, dynamic>);
      notifyListeners();
    } catch (_) {}
  }

  bool get emailOn => config['emailOn'] == true;

  /// Stall's sale fee on a price, set in Admin → Settings → Sale fee (the server works it out the same way).
  int feeOf(int amount) {
    final c = config['fee'] is Map ? config['fee'] as Map : const {'rate': 5, 'min': 150, 'cap': 2000};
    final rate = (c['rate'] as num? ?? 5).toDouble(), min = (c['min'] as num? ?? 150).toInt(), cap = (c['cap'] as num? ?? 2000).toInt();
    final f = (amount * rate / 100).round();
    return [f < min ? min : f, cap, amount ~/ 2].reduce((a, b) => a < b ? a : b);
  }

  String get feeDesc {
    final c = config['fee'] is Map ? config['fee'] as Map : const {'rate': 5, 'min': 150, 'cap': 2000};
    final min = (c['min'] as num? ?? 150).toInt();
    return '${c['rate'] ?? 5}% (${min > 0 ? 'at least ${naira(min)}, ' : ''}never more than ${naira((c['cap'] as num? ?? 2000).toInt())})';
  }

  Future<void> signOut() async {
    try {
      await api.post('logout');
    } catch (_) {}
    await api.setToken(null);
    user = null;
    bag.clear();
    _set(SessionState.signedOut);
  }

  void _set(SessionState s) {
    state = s;
    notifyListeners();
  }
}
