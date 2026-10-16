import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'theme.dart';

/// The Stall wordmark (indigo on light backgrounds, cream on dark).
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.height = 30, this.light = false});
  final double height;
  final bool light;
  @override
  Widget build(BuildContext context) => SvgPicture.asset(
        light ? 'assets/brand/wordmark-cream.svg' : 'assets/brand/wordmark-indigo.svg',
        height: height,
        semanticsLabel: 'Stall',
      );
}

/// The Stall mark (the awning and dot).
class StallMark extends StatelessWidget {
  const StallMark({super.key, this.size = 56, this.light = false});
  final double size;
  final bool light;
  @override
  Widget build(BuildContext context) => SvgPicture.asset(
        light ? 'assets/brand/stall-mark-cream.svg' : 'assets/brand/stall-mark.svg',
        width: size,
        excludeFromSemantics: true,
      );
}

/// The indigo "Stall is taking a short break" card shown at the top of the app.
class BreakCard extends StatelessWidget {
  const BreakCard({super.key, required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(color: StallColors.indigo, borderRadius: BorderRadius.circular(18)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(top: 6, right: 12),
              decoration: const BoxDecoration(color: StallColors.lime, shape: BoxShape.circle)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Stall is taking a short break',
                  style: TextStyle(color: StallColors.cream, fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 2),
              Text(message, style: TextStyle(color: StallColors.cream.withValues(alpha: .85), fontSize: 14, height: 1.45)),
            ]),
          ),
        ]),
      );
}

/// A friendly empty or "coming soon" state with an icon, title and line of text.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.text, this.action});
  final IconData icon;
  final String title;
  final String text;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: StallColors.cream2, borderRadius: BorderRadius.circular(20)),
              child: Icon(icon, color: StallColors.indigo, size: 30),
            ),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: StallColors.muted), textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ]),
        ),
      );
}

void toast(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(message)));
