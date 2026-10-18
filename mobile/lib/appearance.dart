import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';

/// Light or dark: "auto" follows the phone, like the website's Auto / Light / Dark in Account.
class Appearance extends ChangeNotifier with WidgetsBindingObserver {
  static const _key = 'theme';
  static const modes = ['auto', 'light', 'dark'];
  String mode = 'auto';

  bool get _wantDark =>
      mode == 'dark' || (mode == 'auto' && WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark);

  /// Before the first frame, so a dark phone never flashes light.
  Future<void> load() async {
    WidgetsBinding.instance.addObserver(this);
    try {
      final m = (await SharedPreferences.getInstance()).getString(_key);
      if (modes.contains(m)) mode = m!;
    } catch (_) {}
    _apply();
  }

  Future<void> set(String m) async {
    mode = m;
    _apply();
    try {
      await (await SharedPreferences.getInstance()).setString(_key, m);
    } catch (_) {}
  }

  @override
  void didChangePlatformBrightness() => _apply();

  void _apply() {
    final d = _wantDark;
    if (d == StallColors.dark) return;
    StallColors.dark = d;
    SystemChrome.setSystemUIOverlayStyle(d ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark);
    notifyListeners();
    // Screens read the colours as they build, so build every one again in the new colours.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      void again(Element e) {
        e.markNeedsBuild();
        e.visitChildren(again);
      }

      WidgetsBinding.instance.rootElement?.visitChildren(again);
    });
  }
}

final appearance = Appearance();
