import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'session.dart';

/// Firebase settings for push, passed in at build time from the GOOGLE_SERVICES_JSON secret (see .github/workflows/mobile.yml).
/// Without them, the app works the same, just without push notifications.
const _fcm = (
  apiKey: String.fromEnvironment('FCM_API_KEY'),
  appId: String.fromEnvironment('FCM_APP_ID'),
  sender: String.fromEnvironment('FCM_SENDER_ID'),
  project: String.fromEnvironment('FCM_PROJECT_ID'),
);

/// The app's navigator and snack bars, so a notification can open a screen from anywhere.
final navKey = GlobalKey<NavigatorState>();
final messengerKey = GlobalKey<ScaffoldMessengerState>();

/// Where a notification wants to go, from its link ("/app?go=orders", "/?go=messages&t=9").
/// The signed-in app listens and opens it.
final pushTarget = ValueNotifier<Uri?>(null);

/// Native push notifications (Firebase Cloud Messaging). The server sends them; this registers the phone,
/// shows ones that arrive while the app is open, and opens the right screen when one is tapped.
class Push {
  static String? _token;
  static bool _started = false;
  static final _subs = <StreamSubscription<Object?>>[];

  static bool get configured => !kIsWeb && _fcm.apiKey.isNotEmpty && _fcm.appId.isNotEmpty && !Platform.environment.containsKey('FLUTTER_TEST');

  /// After sign-in: ask permission (Android 13+), send this phone's token to Stall, and listen.
  static Future<void> start(Session s) async {
    if (!configured || _started) return;
    _started = true;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
            options: FirebaseOptions(apiKey: _fcm.apiKey, appId: _fcm.appId, messagingSenderId: _fcm.sender, projectId: _fcm.project));
      }
      final m = FirebaseMessaging.instance;
      await m.requestPermission();
      final t = await m.getToken();
      if (t != null) await _register(s, t);
      _subs.add(m.onTokenRefresh.listen((t) => _register(s, t)));
      _subs.add(FirebaseMessaging.onMessage.listen(_foreground));
      _subs.add(FirebaseMessaging.onMessageOpenedApp.listen((r) => _open(r.data['url'])));
      final first = await m.getInitialMessage();
      if (first != null) _open(first.data['url']);
    } catch (_) {
      _started = false; // no Google Play services, or permission refused: Stall works without push
    }
  }

  static Future<void> _register(Session s, String t) async {
    _token = t;
    try {
      await s.api.post('push/fcm', {'token': t, 'platform': 'android'});
    } catch (_) {}
  }

  /// Before sign-out: stop this phone getting the account's notifications.
  static Future<void> stop(Session s) async {
    final t = _token;
    for (final x in _subs) {
      await x.cancel();
    }
    _subs.clear();
    _started = false;
    _token = null;
    if (t == null) return;
    try {
      await s.api.post('push/fcm/remove', {'token': t});
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }

  /// While the app is open, Android doesn't show the notification, so show it as a bar with "Open".
  static void _foreground(RemoteMessage r) {
    final n = r.notification;
    if (n == null) return;
    messengerKey.currentState?.showSnackBar(SnackBar(
      content: Text([n.title, n.body].where((x) => (x ?? '').isNotEmpty).join('\n')),
      duration: const Duration(seconds: 6),
      action: (r.data['url'] ?? '').toString().isEmpty ? null : SnackBarAction(label: 'Open', onPressed: () => _open(r.data['url'])),
    ));
  }

  static void _open(Object? url) {
    final u = Uri.tryParse((url ?? '').toString());
    if (u != null) pushTarget.value = u;
  }
}
