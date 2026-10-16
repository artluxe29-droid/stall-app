import 'package:flutter/material.dart';

/// Stall brand colours, the same as the web app (index.html :root).
class StallColors {
  static const indigo = Color(0xFF26306E); // brand
  static const night = Color(0xFF141A3D);
  static const lime = Color(0xFFC8F03C); // accent
  static const limeInk = Color(0xFF1C2457); // text on lime
  static const cream = Color(0xFFF6F2EA); // page background
  static const cream2 = Color(0xFFEDE7DA); // inputs, chips
  static const card = Color(0xFFFFFFFF);
  static const ink = Color(0xFF161A33); // text
  static const muted = Color(0xFF5B6077);
  static const line = Color(0xFFE2DCCD);
  static const green = Color(0xFF16A34A);
  static const red = Color(0xFFE5484D);
  static const amber = Color(0xFFB45309);
}

/// Display type (headings) is Bricolage Grotesque; everything else is Figtree.
const _display = 'Bricolage';
const _body = 'Figtree';

ThemeData stallTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: StallColors.indigo,
    onPrimary: Colors.white,
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
      titleMedium: const TextStyle(fontFamily: _body, fontSize: 16, fontWeight: FontWeight.w700, color: StallColors.ink),
      bodyLarge: const TextStyle(fontFamily: _body, fontSize: 16, height: 1.45, color: StallColors.ink),
      bodyMedium: const TextStyle(fontFamily: _body, fontSize: 14.5, height: 1.45, color: StallColors.ink),
      bodySmall: const TextStyle(fontFamily: _body, fontSize: 13, height: 1.4, color: StallColors.muted),
      labelLarge: const TextStyle(fontFamily: _body, fontSize: 16, fontWeight: FontWeight.w700),
    ),
    appBarTheme: const AppBarTheme(
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
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontFamily: _body, fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: StallColors.ink,
        minimumSize: const Size.fromHeight(54),
        side: const BorderSide(color: StallColors.line, width: 1.5),
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
      labelStyle: const TextStyle(color: StallColors.muted),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: StallColors.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: StallColors.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: StallColors.indigo, width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: StallColors.red)),
    ),
    cardTheme: CardThemeData(
      color: StallColors.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: StallColors.line)),
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
    snackBarTheme: SnackBarThemeData(
      backgroundColor: StallColors.night,
      contentTextStyle: const TextStyle(fontFamily: _body, color: Colors.white, fontSize: 14.5),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
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
