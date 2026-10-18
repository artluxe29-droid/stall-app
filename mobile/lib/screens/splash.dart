import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';

/// Shown for a moment while Stall checks whether you're signed in.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: StallColors.cream,
        body: Center(child: StallMark(size: 72)),
      );
}
