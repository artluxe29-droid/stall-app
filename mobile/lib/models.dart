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

/// An order, as the API returns it (one per seller). Status: pending (waiting for payment), under_review,
/// verified (paid, Stall holds the money), disputed, released (complete), refunded, rejected or expired.
class Order {
  Order(this.raw);
  final Map<String, dynamic> raw;
  int get id => _int(raw['id']);
  String get title => _str(raw['title']);
  int get amount => _int(raw['amount']);
  int get sub => _int(raw['sub'] ?? raw['amount']);
  int get fee => _int(raw['fee']);
  String get status => _str(raw['status']);
  int get deadline => _int(raw['deadline']);
  String? get code => raw['code'] as String?;
  String get note => _str(raw['note']);
  String get sellerName => _str(raw['sellerName']);
  String get sellerPhone => _str(raw['sellerPhone']);
  bool get card => raw['card'] == true;
  String? get paidVia => raw['paidVia'] as String?;
  Delivery get deliv => Delivery.from(raw['deliv']);
  String get pickup => _str(raw['pickup']);
  String? get method => raw['method'] as String?;
  String get addr => _str(raw['addr']);
  String? get stage => raw['stage'] as String?;
  int? get rated => raw['rated'] == null ? null : _int(raw['rated']);
  int? get holdUntil => raw['holdUntil'] == null ? null : _int(raw['holdUntil']);
  int? get refundAt => raw['refundAt'] == null ? null : _int(raw['refundAt']);
  int? get handedAt => raw['handedAt'] == null ? null : _int(raw['handedAt']);
  int? get handUntil => raw['handUntil'] == null ? null : _int(raw['handUntil']);
  bool get early => raw['early'] == true;
  bool get noShow => raw['noShow'] == true;
  String? get dispBy => raw['dispBy'] as String?;

  bool get verified => status == 'verified';
  bool get payable => card && status == 'pending' && deadline > DateTime.now().millisecondsSinceEpoch;

  /// The status chip, worded like the web app.
  String get badge => switch (status) {
        'refunding' => 'Refunding…',
        'pending' => 'Awaiting payment',
        'under_review' => 'Under review',
        'verified' => handedAt != null ? 'Handed over' : 'Paid',
        'released' => 'Completed',
        'rejected' => 'Rejected',
        'disputed' => 'Problem reported',
        'refunded' => 'Refunded',
        _ => note.startsWith('You cancelled') ? 'Cancelled' : 'Expired',
      };

  /// Delivery/pickup progress: (label, done) steps, like the web app's tracker.
  List<(String, bool)> get steps {
    final l = method == 'delivery'
        ? const [('paid', 'Paid'), ('packed', 'Packed'), ('on_way', 'On the way'), ('done', 'Delivered')]
        : const [('paid', 'Paid'), ('ready', 'Ready'), ('done', 'Collected')];
    final cur = status == 'released' ? 'done' : (stage ?? 'paid');
    final k = l.indexWhere((x) => x.$1 == cur);
    return [for (var i = 0; i < l.length; i++) (l[i].$2, i <= k)];
  }
}

/// "Tue, 21 Oct, 3:05 pm" and "Tue, 21 Oct", for order deadlines.
String when(int t) {
  final d = DateTime.fromMillisecondsSinceEpoch(t);
  const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '${wd[d.weekday - 1]}, ${d.day} ${mo[d.month - 1]}, $h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'am' : 'pm'}';
}

String dayOf(int t) => when(t).split(', ').take(2).join(', ');

/// "14:59" left to pay.
String clock(int ms) {
  if (ms <= 0) return '0:00';
  final s = ms ~/ 1000;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}
