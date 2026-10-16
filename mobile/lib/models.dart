import 'package:flutter/material.dart';

/// Item categories, the same as the web app's CATS (id, name, tile colours, icon).
class Category {
  const Category(this.id, this.name, this.icon, this.bg, this.fg);
  final String id;
  final String name;
  final IconData icon;
  final Color bg;
  final Color fg;

  static const all = [
    Category('books', 'Books', Icons.menu_book_rounded, Color(0xFFEEF8C8), Color(0xFF4E6106)),
    Category('tech', 'Electronics', Icons.headphones_rounded, Color(0xFFDDEBFF), Color(0xFF2563EB)),
    Category('fashion', 'Fashion', Icons.checkroom_rounded, Color(0xFFFCE4F1), Color(0xFFDB2777)),
    Category('hostel', 'Hostel gear', Icons.bed_rounded, Color(0xFFDCF7E6), Color(0xFF16A34A)),
    Category('food', 'Food', Icons.ramen_dining_rounded, Color(0xFFFDE2E4), Color(0xFFC2253D)),
    Category('services', 'Services', Icons.content_cut_rounded, Color(0xFFEDE9FE), Color(0xFF7C3AED)),
  ];

  static Category of(String? id) => all.firstWhere((c) => c.id == id, orElse: () => all.first);
}

/// Store icons saved by the web app (a key, or an emoji on older stores).
IconData storeIcon(String? key, String? cat) {
  const keys = {
    'bowl': Icons.ramen_dining_rounded,
    'bread': Icons.bakery_dining_rounded,
    'cup': Icons.local_cafe_rounded,
    'book': Icons.menu_book_rounded,
    'shirt': Icons.checkroom_rounded,
    'laptop': Icons.laptop_rounded,
    'scissors': Icons.content_cut_rounded,
    'bag': Icons.shopping_bag_rounded,
    'headphones': Icons.headphones_rounded,
    'bed': Icons.bed_rounded,
  };
  const emoji = {'🍲': 'bowl', '🍚': 'bowl', '🍞': 'bread', '🥤': 'cup', '📚': 'book', '👗': 'shirt', '💻': 'laptop', '✂️': 'scissors', '🛍️': 'bag'};
  final k = (key ?? '').trim();
  return keys[k] ?? keys[emoji[k] ?? emoji[k.replaceAll('️', '')] ?? ''] ?? Category.of(cat).icon;
}

int _int(Object? v, [int d = 0]) => v is num ? v.toInt() : (v is bool ? (v ? 1 : 0) : d);
String _str(Object? v) => (v ?? '').toString();
List<String> _imgs(Object? v) => (v as List? ?? const []).map((e) => e.toString()).toList();

class Rating {
  const Rating(this.avg, this.n);
  final double avg;
  final int n;
  factory Rating.from(Object? v) => v is Map ? Rating((v['avg'] as num? ?? 0).toDouble(), _int(v['n'])) : const Rating(0, 0);
  String get label => '★ ${avg.toStringAsFixed(1)} ($n)';
}

class Delivery {
  const Delivery(this.on, this.fee, this.note);
  final bool on;
  final int fee;
  final String note;
  factory Delivery.from(Object? v) => v is Map ? Delivery(v['on'] == true, _int(v['fee']), _str(v['note'])) : const Delivery(false, 0, '');
}

/// A student's marketplace listing (id "L12").
class Listing {
  Listing(this.raw);
  final Map<String, dynamic> raw;
  String get id => _str(raw['id']);
  int get sellerId => _int(raw['sid']);
  String get title => _str(raw['title']);
  int get price => _int(raw['price']);
  String get cat => _str(raw['cat']);
  String get cond => _str(raw['cond']);
  String get spot => _str(raw['spot']);
  String get desc => _str(raw['desc']);
  String get seller => _str(raw['seller']);
  String get school => _str(raw['school']);
  List<String> get imgs => _imgs(raw['imgs']);
  int get time => _int(raw['t']);
  bool get sold => _int(raw['sold']) == 1;
  bool get featured => raw['featured'] == true;
  bool get verified => raw['verified'] == true;
  int get vlevel => _int(raw['vlevel']);
  int get qty => _int(raw['qty'], 1);
  int? get qtyLeft => raw['qtyLeft'] == null ? null : _int(raw['qtyLeft']);
  bool get mine => raw['mine'] == true;
  Rating get rating => Rating.from(raw['rating']);
  Delivery get deliv => Delivery.from(raw['deliv']);

  /// "Sold", "Reserved" (paid for but not handed over yet), or null when it can be bought.
  String? get status => sold ? 'Sold' : (qtyLeft == 0 ? 'Reserved' : null);

  /// The web app's stock line: nothing for a single item, otherwise "Only 3 left" / "8 available" / "Sold out".
  String? get stockLine {
    final l = qtyLeft;
    if (l == null || (qty <= 1 && l > 0)) return null;
    if (l <= 0) return 'Sold out';
    return l <= 5 ? 'Only $l left' : '$l available';
  }
}

/// A store search hit: an item from an open store that matched a search.
class StoreHit {
  StoreHit(this.raw);
  final Map<String, dynamic> raw;
  String get title => _str(raw['title']);
  int get price => _int(raw['price']);
  String get storeId => _str(raw['store']);
  String get storeName => _str(raw['storeName']);
  String get cat => _str(raw['cat']);
  String get emoji => _str(raw['emoji']);
}

class StoreItem {
  StoreItem(this.raw);
  final Map<String, dynamic> raw;
  String get id => _str(raw['id']);
  String get title => _str(raw['title']);
  int get price => _int(raw['price']);
  String get desc => _str(raw['desc']);
  bool get avail => raw['avail'] == true;
  int? get qtyLeft => raw['qtyLeft'] == null ? null : _int(raw['qtyLeft']);
  List<String> get imgs => _imgs(raw['imgs']);
}

/// A campus store or food stall (id "S4").
class Store {
  Store(this.raw);
  final Map<String, dynamic> raw;
  String get id => _str(raw['id']);
  int get ownerId => _int(raw['uid']);
  String get name => _str(raw['name']);
  String? get logo => raw['logo'] == null ? null : _str(raw['logo']);
  String get emoji => _str(raw['emoji']);
  String get cat => _str(raw['cat']);
  String get desc => _str(raw['desc']);
  String get spot => _str(raw['spot']);
  bool get open => raw['open'] == true;
  bool get vendor => raw['vendor'] == true;
  bool get featured => raw['featured'] == true;
  bool get verified => raw['verified'] == true;
  int get vlevel => _int(raw['vlevel']);
  int get founding => _int(raw['founding']);
  String get school => _str(raw['school']);
  String get state => _str(raw['state']);
  String get reach => _str(raw['reach']);
  Rating get rating => Rating.from(raw['rating']);
  Delivery get deliv => Delivery.from(raw['deliv']);
  List<StoreItem> get items => (raw['items'] as List? ?? const []).map((e) => StoreItem(e as Map<String, dynamic>)).toList();
  int get availableCount => items.where((i) => i.avail).length;
}

/// "5m ago", "3h ago", "2d ago", like the web app.
String ago(int t, [DateTime? now]) {
  if (t <= 0) return '';
  final s = ((now ?? DateTime.now()).millisecondsSinceEpoch - t) ~/ 1000;
  if (s < 60) return 'just now';
  if (s < 3600) return '${s ~/ 60}m ago';
  if (s < 86400) return '${s ~/ 3600}h ago';
  if (s < 86400 * 30) return '${s ~/ 86400}d ago';
  return '${s ~/ (86400 * 30)}mo ago';
}

/// Search filters, sent to the API exactly as the web app does (min, max, cond, dl, vf, r4, sort).
class Filters {
  const Filters({this.min, this.max, this.cond, this.delivers = false, this.verified = false, this.topRated = false, this.sort = 'new'});
  final int? min;
  final int? max;
  final String? cond;
  final bool delivers;
  final bool verified;
  final bool topRated;
  final String sort;

  static const sorts = {'new': 'Newest', 'lo': 'Price: low to high', 'hi': 'Price: high to low', 'top': 'Top rated sellers'};

  int get count => [min != null, max != null, cond != null, delivers, verified, topRated].where((x) => x).length;

  Map<String, String> get query => {
        if (min != null) 'min': '$min',
        if (max != null) 'max': '$max',
        'cond': ?cond,
        if (delivers) 'dl': '1',
        if (verified) 'vf': '1',
        if (topRated) 'r4': '1',
        if (sort != 'new') 'sort': sort,
      };

  Filters copyWith({String? sort}) =>
      Filters(min: min, max: max, cond: cond, delivers: delivers, verified: verified, topRated: topRated, sort: sort ?? this.sort);
}
