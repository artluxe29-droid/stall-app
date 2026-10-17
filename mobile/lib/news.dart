import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// What's new since you last looked: order updates (buying and selling) and unread chats, for the dots on
/// Orders and Messages. Checked every minute while Stall is open, like the website's news dots.
class News extends ChangeNotifier {
  News(this.api);
  final Api api;
  int buy = 0, sell = 0, chats = 0;
  int _sb = 0, _ss = 0;
  Timer? _timer;

  int get orders => buy + sell;

  Future<void> start() async {
    if (_timer != null) return;
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => check());
    try {
      final p = await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;
      // On a new phone, start from now rather than flagging every past order.
      _sb = p.getInt('news:sb') ?? now;
      _ss = p.getInt('news:ss') ?? now;
    } catch (_) {}
    await check();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    buy = sell = chats = 0;
  }

  Future<void> check() async {
    try {
      final r = await api.get('orders/news', {'sb': '$_sb', 'ss': '$_ss'});
      final n = (r['news'] as List? ?? const []).whereType<Map>();
      buy = n.where((x) => x['side'] == 'buy').length;
      sell = n.where((x) => x['side'] == 'sell').length;
      chats = (r['chats'] as num?)?.toInt() ?? 0;
      notifyListeners();
    } catch (_) {}
  }

  /// You've looked at your buying (or selling) orders: clear that dot.
  Future<void> seen({required bool selling}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (selling) {
      _ss = now;
      sell = 0;
    } else {
      _sb = now;
      buy = 0;
    }
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setInt(selling ? 'news:ss' : 'news:sb', now);
    } catch (_) {}
  }
}
