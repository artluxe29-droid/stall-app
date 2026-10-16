import 'package:flutter/material.dart';

import '../main.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets.dart';

/// While Stall is closed to the public (Admin → Close the app), everyone except staff sees this.
class ClosedScreen extends StatelessWidget {
  const ClosedScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    return Scaffold(
      backgroundColor: StallColors.indigo,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const StallMark(size: 64, light: true),
              const SizedBox(height: 24),
              Text('Stall is taking a short break',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: StallColors.cream)),
              const SizedBox(height: 12),
              Text(s.breakMessage ?? Session.defaultBreakMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: StallColors.cream.withValues(alpha: .85), fontSize: 16, height: 1.5)),
              const SizedBox(height: 14),
              Text("You're signed in as ${s.user?.name ?? 'you'}, so you're on the list. We'll let you know as soon as Stall is back.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: StallColors.cream.withValues(alpha: .65), fontSize: 14, height: 1.45)),
              const SizedBox(height: 24),
              SizedBox(
                width: 160,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: StallColors.cream, foregroundColor: StallColors.ink),
                  onPressed: s.signOut,
                  child: const Text('Sign out'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
