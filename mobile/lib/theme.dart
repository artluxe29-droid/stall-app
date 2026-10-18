import 'package:flutter/material.dart';

/// Stall brand colours, the same as the web app (index.html :root), with the web app's dark set for dark mode.
/// The ones that change with dark mode are getters; [StallTheme] sets [dark] and rebuilds the app when it changes.
class StallColors {
  static bool dark = false;
  static Color get indigo => dark ? const Color(0xFFC8F03C) : const Color(0xFF26306E); // brand (lime in the dark, as on the website)
  static Color get onBrand => dark ? const Color(0xFF1C2457) : Colors.white; // text and icons on [indigo]
  static const night = Color(0xFF141A3D);
  static const lime = Color(0xFFC8F03C); // accent
  static const limeInk = Color(0xFF1C2457); // text on lime
  static Color get cream => dark ? const Color(0xFF0F1330) : const Color(0xFFF6F2EA); // page background
  static Color get cream2 => dark ? const Color(0xFF1C2250) : const Color(0xFFEDE7DA); // inputs, chips
  static Color get card => dark ? const Color(0xFF161B42) : const Color(0xFFFFFFFF);
  static Color get ink => dark ? const Color(0xFFF6F1E7) : const Color(0xFF161A33); // text
  static Color get muted => dark ? const Color(0xFF9AA1C9) : const Color(0xFF5B6077);
  static Color get line => dark ? const Color(0xFF2B3268) : const Color(0xFFE2DCCD);
  // Soft backgrounds for statuses (problem, done, waiting, paid); deep versions in the dark.
  static Color get redTint => dark ? const Color(0xFF4A1D2C) : const Color(0xFFFDE2E4);
  static Color get greenTint => dark ? const Color(0xFF123D33) : const Color(0xFFDCF7E6);
  static Color get amberTint => dark ? const Color(0xFF43361A) : const Color(0xFFFEF3C7);
  static Color get limeTint => dark ? const Color(0xFF2E3A1C) : const Color(0xFFEEF8C8);
  static Color get olive => dark ? const Color(0xFFC8F03C) : const Color(0xFF4E6106); // text on [limeTint]
  static const green = Color(0xFF16A34A);
  static const red = Color(0xFFE5484D);
  static const amber = Color(0xFFB45309);
}

/// Display type (headings) is Bricolage Grotesque; everything else is Figtree.
const _display = 'Bricolage';
const _body = 'Figtree';

ThemeData stallTheme() {
  final scheme = ColorScheme(
    brightness: StallColors.dark ? Brightness.dark : Brightness.light,
    primary: StallColors.indigo,
    onPrimary: StallColors.onBrand,
    secondary: StallColors.lime,
    onSecondary: StallColors.limeInk,
    error: StallColors.red,
    onError: Colors.white,
    surface: StallColors.cream,
    onSurface: StallColors.ink,
    surfaceContainerHighest: StallColors.cream2,
    outline: StallColors.line,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: _body);
  TextStyle d(double size, FontWeight w, {double ls = -0.02}) =>
      TextStyle(fontFamily: _display, fontSize: size, fontWeight: w, letterSpacing: size * ls, height: 1.08, color: StallColors.ink);
  return base.copyWith(
    scaffoldBackgroundColor: StallColors.cream,
    textTheme: base.textTheme.copyWith(
      displaySmall: d(34, FontWeight.w800, ls: -0.035),
      headlineMedium: d(28, FontWeight.w800, ls: -0.03),
      headlineSmall: d(22, FontWeight.w700),
      titleLarge: d(19, FontWeight.w700, ls: -0.01),
      titleMedium: TextStyle(fontFamily: _body, fontSize: 16, fontWeight: FontWeight.w700, color: StallColors.ink),
      bodyLarge: TextStyle(fontFamily: _body, fontSize: 16, height: 1.45, color: StallColors.ink),
      bodyMedium: TextStyle(fontFamily: _body, fontSize: 14.5, height: 1.45, color: StallColors.ink),
      bodySmall: TextStyle(fontFamily: _body, fontSize: 13, height: 1.4, color: StallColors.muted),
      labelLarge: const TextStyle(fontFamily: _body, fontSize: 16, fontWeight: FontWeight.w700),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: StallColors.cream,
      foregroundColor: StallColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: _display, fontSize: 20, fontWeight: FontWeight.w800, color: StallColors.ink),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: StallColors.indigo,
        foregroundColor: StallColors.onBrand,
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontFamily: _body, fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: StallColors.ink,
        minimumSize: const Size.fromHeight(54),
        side: BorderSide(color: StallColors.line, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontFamily: _body, fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: StallColors.indigo, textStyle: const TextStyle(fontFamily: _body, fontWeight: FontWeight.w700)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      errorMaxLines: 3,
      fillColor: StallColors.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: TextStyle(color: StallColors.muted),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: StallColors.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: StallColors.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: StallColors.indigo, width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: StallColors.red)),
    ),
    cardTheme: CardThemeData(
      color: StallColors.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: StallColors.line)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: StallColors.card,
      indicatorColor: StallColors.lime,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontFamily: _body,
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? StallColors.ink : StallColors.muted,
          )),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: QuickPageTransition(),
      TargetPlatform.linux: QuickPageTransition(),
    }),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: StallColors.night,
      contentTextStyle: const TextStyle(fontFamily: _body, color: Colors.white, fontSize: 14.5),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

/// Opening a page: a short slide and fade (200 ms) instead of Android's default zoom (300 ms),
/// which also redraws the page underneath and drags on cheaper phones.
class QuickPageTransition extends PageTransitionsBuilder {
  const QuickPageTransition();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 200);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 160);

  static final _slide = Tween(begin: const Offset(0.06, 0), end: Offset.zero).chain(CurveTween(curve: Curves.easeOutCubic));

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) =>
      FadeTransition(opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut), child: SlideTransition(position: animation.drive(_slide), child: child));
}

/// Formats naira like the web app: ₦12,500.
String naira(num n) {
  final s = n.round().abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '${n < 0 ? '-' : ''}₦$b';
}
