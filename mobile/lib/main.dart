import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'push.dart';
import 'screens/account_setup.dart';
import 'screens/closed.dart';
import 'screens/shell.dart';
import 'screens/sign_in.dart';
import 'screens/splash.dart';
import 'session.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final session = Session(Api())..restore();
  runApp(StallApp(session: session));
}

/// Gives every screen access to the session: `SessionScope.of(context)`.
class SessionScope extends InheritedNotifier<Session> {
  const SessionScope({super.key, required Session session, required super.child}) : super(notifier: session);
  static Session of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<SessionScope>()!.notifier!;
}

class StallApp extends StatelessWidget {
  const StallApp({super.key, required this.session});
  final Session session;

  @override
  Widget build(BuildContext context) => SessionScope(
        session: session,
        child: MaterialApp(
          title: 'Stall',
          navigatorKey: navKey,
          scaffoldMessengerKey: messengerKey,
          debugShowCheckedModeBanner: false,
          theme: stallTheme(),
          home: const _Gate(),
        ),
      );
}

/// Decides the first screen: loading, sign-in, the "short break" screen, or Stall itself.
class _Gate extends StatelessWidget {
  const _Gate();
  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: switch (s.state) {
        SessionState.loading => const SplashScreen(),
        SessionState.signedOut => const SignInScreen(),
        SessionState.signedIn => s.closedForMe
            ? const ClosedScreen()
            : s.verifyFirst
                ? const VerifyGateScreen()
                : const Shell(),
      },
    );
  }
}
