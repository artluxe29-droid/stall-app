import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One thing in the bag: a listing ("L12") or a store item ("I5"), with what's needed to show it offline.
class BagLine {
  BagLine({required this.id, required this.title, required this.price, required this.cat, this.img, required this.seller, this.max, this.multi = false, this.q = 1});
  final String id;
  final String title;
  final int price;
  final String cat;
  final String? img;
  final String seller;
  /// Most you can buy (stock left), or null for no limit.
  final int? max;
  /// Whether more than one can be bought (store items, or listings with several in stock).
  final bool multi;
  int q;

  int get total => price * q;
  bool get canAdd => multi && (max == null || q < max!);

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'price': price, 'cat': cat, 'img': img, 'seller': seller, 'max': max, 'multi': multi, 'q': q};
  factory BagLine.fromJson(Map<String, dynamic> j) => BagLine(
        id: j['id'] as String,
        title: (j['title'] ?? '') as String,
        price: (j['price'] as num).toInt(),
        cat: (j['cat'] ?? '') as String,
        img: j['img'] as String?,
        seller: (j['seller'] ?? '') as String,
        max: (j['max'] as num?)?.toInt(),
        multi: j['multi'] == true,
        q: (j['q'] as num? ?? 1).toInt(),
      );
}

/// The bag, kept on the phone like the web app's (so it survives closing the app).
class Bag extends ChangeNotifier {
  static const _key = 'bag';
  final lines = <BagLine>[];

  int get count => lines.fold(0, (s, l) => s + l.q);
  int get total => lines.fold(0, (s, l) => s + l.total);
  int qtyOf(String id) => lines.where((l) => l.id == id).fold(0, (s, l) => s + l.q);

  /// The item ids as the API wants them: one entry per unit ("L1","L1","I4").
  List<String> get apiItems => [for (final l in lines) for (var i = 0; i < l.q; i++) l.id];

  Future<void> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      lines
        ..clear()
        ..addAll(raw == null ? const [] : (jsonDecode(raw) as List).map((e) => BagLine.fromJson(e as Map<String, dynamic>)).where((l) => RegExp(r'^[LI]\d+$').hasMatch(l.id)));
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _save() async {
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setString(_key, jsonEncode(lines.map((l) => l.toJson()).toList()));
    } catch (_) {}
  }

  /// Adds one. Returns false when there's no more stock to add (or a one-off item is already in the bag).
  bool add(BagLine line) {
    final cur = lines.where((l) => l.id == line.id).firstOrNull;
    if (cur == null) {
      if (line.max != null && line.max! < 1) return false;
      lines.add(line..q = 1);
    } else {
      if (!cur.canAdd) return false;
      cur.q++;
    }
    _save();
    return true;
  }

  void dec(String id) {
    final cur = lines.where((l) => l.id == id).firstOrNull;
    if (cur == null) return;
    if (cur.q > 1) {
      cur.q--;
    } else {
      lines.remove(cur);
    }
    _save();
  }

  void remove(String id) {
    lines.removeWhere((l) => l.id == id);
    _save();
  }

  void clear() {
    lines.clear();
    _save();
  }
}
