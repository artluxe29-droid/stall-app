import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import '../main.dart';
import '../models.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets.dart';
import 'chat.dart';
import 'checkout.dart';
import 'extras.dart';
import 'item.dart';
import 'search.dart';
import 'settings.dart' show GuideScreen;

/// Where to look: my campus (students), my area, my state, or all of Nigeria (the API's "scope").
class Scope {
  static const school = 'school', area = 'area', state = 'state', all = 'all';

  static List<(String, String)> options(StallUser? u) => [
        if (u?.school != null) (school, u!.schoolName.isEmpty ? 'My campus' : u.schoolName),
        if ((u?.area ?? '').isNotEmpty) (area, u!.area),
        if ((u?.state ?? '').isNotEmpty) (state, u!.state),
        (all, 'All Nigeria'),
      ];

  static String initial(StallUser? u) => options(u).first.$1;
}

/// A row of choice chips that scrolls sideways.
class ChipRow extends StatelessWidget {
  const ChipRow({super.key, required this.options, required this.value, required this.onPick, this.icons = const {}, this.leading = const {}});
  final List<(String, String)> options;
  final String value;
  final ValueChanged<String> onPick;
  final Map<String, IconData> icons;
  final Map<String, Widget> leading;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: options.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final (id, label) = options[i];
            final on = id == value;
            return ChoiceChip(
              key: Key('chip-$id'),
              label: Text(label),
              avatar: leading[id] ?? (icons[id] == null ? null : Icon(icons[id], size: 18, color: on ? Colors.white : StallColors.indigo)),
              showCheckmark: false,
              selected: on,
              onSelected: (_) => onPick(id),
              labelStyle: TextStyle(fontWeight: FontWeight.w600, color: on ? Colors.white : StallColors.ink),
              selectedColor: StallColors.indigo,
              backgroundColor: StallColors.card,
              side: BorderSide(color: on ? StallColors.indigo : StallColors.line),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
            );
          },
        ),
      );
}

/// Loads pages of listings from the API, like the web feed (24 at a time, "Load more" as you scroll).
class ListingPager extends ChangeNotifier {
  ListingPager(this.api);
  final Api api;
  final items = <Listing>[];
  final storeHits = <StoreHit>[];
  int? total;
  bool loading = false, soon = false;
  Object? error;
  Map<String, String> _q = const {};
  int _gen = 0;

  bool get more => total != null && items.length < total!;

  Future<void> reset(Map<String, String> query) async {
    _q = query;
    final g = ++_gen;
    items.clear();
    storeHits.clear();
    total = null;
    soon = false;
    error = null;
    loading = true;
    // Seen this feed before? Show it straight away while checking for anything new.
    final last = api.seen('listings', _page(0));
    if (last != null) _take(last, 0);
    notifyListeners();
    await _fetch(g, 0);
  }

  Map<String, String> _page(int off) => {..._q, 'n': '24', if (off > 0) 'off': '$off'};

  void _take(Map<String, dynamic> r, int off) {
    if (off == 0) {
      items.clear();
      storeHits.clear();
    }
    soon = r['soon'] == true;
    total = (r['total'] as num?)?.toInt() ?? 0;
    items.addAll((r['listings'] as List? ?? const []).map((e) => Listing(e as Map<String, dynamic>)));
    if (off == 0) storeHits.addAll((r['storeHits'] as List? ?? const []).map((e) => StoreHit(e as Map<String, dynamic>)));
  }

  Future<void> loadMore() async {
    if (loading || !more) return;
    loading = true;
    notifyListeners();
    await _fetch(_gen, items.length);
  }

  Future<void> _fetch(int g, int off) async {
    try {
      final r = await api.get('listings', _page(off));
      if (g != _gen) return;
      _take(r, off);
    } catch (e) {
      if (g != _gen) return;
      error = e;
    }
    loading = false;
    notifyListeners();
  }
}

/// The feed: a grid of listings with loading, empty, "coming soon" and error states, and "load more".
class ListingSlivers extends StatelessWidget {
  const ListingSlivers({super.key, required this.pager, this.emptyTitle = 'No items yet', this.emptyText = 'Be the first to sell something here.'});
  final ListingPager pager;
  final String emptyTitle;
  final String emptyText;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: pager,
        builder: (context, _) {
          final p = pager;
          Widget fill(Widget w) => SliverFillRemaining(hasScrollBody: false, child: w);
          if (p.items.isEmpty && p.loading) return fill(const Center(child: CircularProgressIndicator()));
          if (p.items.isEmpty && p.error != null) {
            return fill(EmptyState(
                icon: Icons.wifi_off_rounded,
                title: 'Couldn\'t load items',
                text: p.error is ApiError ? (p.error as ApiError).message : 'Pull down to try again.'));
          }
          if (p.soon) {
            return fill(const EmptyState(
                icon: Icons.school_outlined, title: 'Stall isn\'t open at your school yet', text: 'We\'ll tell you the moment it opens.'));
          }
          if (p.items.isEmpty) return fill(EmptyState(icon: Icons.inventory_2_outlined, title: emptyTitle, text: emptyText));
          return SliverMainAxisGroup(slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: .70),
                itemCount: p.items.length,
                itemBuilder: (context, i) {
                  if (i >= p.items.length - 6) WidgetsBinding.instance.addPostFrameCallback((_) => p.loadMore());
                  return ItemCard(item: p.items[i]);
                },
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                child: p.loading
                    ? const Center(child: CircularProgressIndicator())
                    : p.error != null
                        ? TextButton(onPressed: p.loadMore, child: const Text('Couldn\'t load more. Tap to try again.'))
                        : Text(
                            p.more ? '' : '${p.items.length} item${p.items.length == 1 ? '' : 's'}',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall),
              ),
            ),
          ]);
        },
      );
}

/// Home, like the website's: the hero with the changing word, why Stall, categories, where to look, search and the latest items.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  ListingPager? _pager;
  String? _scope;
  String _cat = 'all';
  final _feed = GlobalKey();

  /// "New to Stall? Show me", until it's opened or closed.
  bool _guide = false;
  static const _guideKey = 'home:guideSeen';

  @override
  void initState() {
    super.initState();
    () async {
      try {
        final seen = (await SharedPreferences.getInstance()).getBool(_guideKey) ?? false;
        if (!seen && mounted) setState(() => _guide = true);
      } catch (_) {}
    }();
  }

  Future<void> _hideGuide() async {
    setState(() => _guide = false);
    try {
      await (await SharedPreferences.getInstance()).setBool(_guideKey, true);
    } catch (_) {}
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pager == null) {
      final s = SessionScope.of(context);
      _pager = ListingPager(s.api);
      _scope = Scope.initial(s.user);
      _load();
    }
  }

  @override
  void dispose() {
    _pager?.dispose();
    super.dispose();
  }

  Future<void> _load() => _pager!.reset({'scope': _scope!, if (_cat != 'all') 'cat': _cat});

  void _toFeed() {
    final c = _feed.currentContext;
    if (c != null) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    final t = Theme.of(context).textTheme;
    final u = s.user;
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
          sliver: SliverToBoxAdapter(
            child: Row(children: [
              const Wordmark(height: 28),
              const Spacer(),
              ListenableBuilder(
                listenable: s.news,
                builder: (context, _) => IconButton(
                  key: const Key('messages'),
                  tooltip: 'Messages',
                  onPressed: () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MessagesScreen()));
                    s.news.check();
                  },
                  icon: Badge(isLabelVisible: s.news.chats > 0, label: Text('${s.news.chats}'), child: const Icon(Icons.chat_bubble_outline_rounded)),
                ),
              ),
              const BagButton(),
            ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          sliver: SliverList.list(children: [
            if (u?.pausedUntil != null) ...[PausedCard(until: u!.pausedUntil!), const SizedBox(height: 12)],
            HomeHero(onShop: _toFeed, onSell: () => shellTab.value = 2),
            for (final p in u?.partners ?? const <Map<String, dynamic>>[]) ...[const SizedBox(height: 12), PartnerBanner(p: p)],
            const SizedBox(height: 12),
            const TrustTiles(),
            if (_guide) ...[
              const SizedBox(height: 12),
              _GuideCard(
                onOpen: () {
                  _hideGuide();
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => GuideScreen(selling: u?.isVendor ?? false)));
                },
                onClose: _hideGuide,
              ),
            ],
            if (s.breakMessage != null) ...[const SizedBox(height: 12), BreakCard(message: s.breakMessage!)],
            const SizedBox(height: 22),
            Row(children: [
              Expanded(child: Text('Categories', style: t.headlineSmall)),
              TextButton(key: const Key('toStores'), onPressed: () => shellTab.value = 1, child: const Text('Browse stores →')),
            ]),
          ]),
        ),
        SliverToBoxAdapter(
          child: CatTiles(
            value: _cat,
            onPick: (v) {
              setState(() => _cat = v);
              _load();
            },
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 14)),
        SliverToBoxAdapter(
          child: ChipRow(
            options: Scope.options(u),
            icons: {
              Scope.school: Icons.school_outlined,
              Scope.area: Icons.place_outlined,
              Scope.state: Icons.place_outlined,
            },
            leading: const {Scope.all: NigeriaFlag()},
            value: _scope!,
            onPick: (v) {
              setState(() => _scope = v);
              _load();
            },
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          sliver: SliverList.list(children: [
            SearchBox(onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchScreen()))),
            const SizedBox(height: 20),
            Text('Just in', key: _feed, style: t.headlineSmall),
            const SizedBox(height: 2),
            Text(
                switch (_scope) {
                  Scope.school => 'What\'s new at ${u?.schoolName ?? 'your school'}',
                  Scope.area => 'What\'s new in ${u?.area ?? 'your area'}',
                  Scope.state => 'What\'s new in ${u?.state ?? 'your state'}',
                  _ => 'What\'s new across Nigeria',
                },
                style: t.bodyMedium?.copyWith(color: StallColors.muted)),
            const SizedBox(height: 12),
          ]),
        ),
        ListingSlivers(pager: _pager!),
      ]),
    );
  }
}

/// The website's Home banner: "Everything you need, right near you." The key word changes every few seconds, in a new colour.
class HomeHero extends StatefulWidget {
  const HomeHero({super.key, required this.onShop, required this.onSell});
  final VoidCallback onShop;
  final VoidCallback onSell;

  static const words = [
    ('need', Color(0xFFC8F03C)),
    ('love', Color(0xFFF472B6)),
    ('want', Color(0xFF38BDF8)),
    ('sell', Color(0xFF4ADE80)),
    ('crave', Color(0xFFFACC15)),
    ('study with', Color(0xFFA78BFA)),
  ];

  @override
  State<HomeHero> createState() => _HomeHeroState();
}

class _HomeHeroState extends State<HomeHero> {
  int _i = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 2600), (_) {
      // Still when the phone asks for less motion, or while another tab is showing.
      if (!mounted || MediaQuery.of(context).disableAnimations || !TickerMode.valuesOf(context).enabled) return;
      setState(() => _i = (_i + 1) % HomeHero.words.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (word, colour) = HomeHero.words[_i];
    const h1 = TextStyle(fontFamily: 'Bricolage', fontSize: 36, fontWeight: FontWeight.w800, height: 1.05, letterSpacing: -1.4, color: Colors.white);
    return Container(
      key: const Key('homeHero'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight, stops: [0, .7, 1], colors: [Color(0xFF26306E), Color(0xFF1C2457), Color(0xFF27344D)]),
        boxShadow: const [BoxShadow(color: Color(0x1F161A33), blurRadius: 24, offset: Offset(0, 10))],
      ),
      child: Stack(children: [
        // The lime glow in the top corner and the faint dots, as on the website.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(center: const Alignment(1, -1), radius: 1.1, colors: [StallColors.lime.withValues(alpha: .35), StallColors.lime.withValues(alpha: 0)]),
            ),
          ),
        ),
        const Positioned.fill(child: CustomPaint(painter: _Dots())),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: StallColors.lime.withValues(alpha: .14), borderRadius: BorderRadius.circular(8)),
              child: const Text('BORN ON CAMPUS. OPEN TO EVERYONE.',
                  style: TextStyle(color: StallColors.lime, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: .7)),
            ),
            const SizedBox(height: 14),
            Text.rich(
              TextSpan(style: h1, children: [
                const TextSpan(text: 'Everything you '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: ClipRect(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 420),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      layoutBuilder: (cur, prev) => Stack(alignment: Alignment.centerLeft, children: [...prev, ?cur]),
                      transitionBuilder: (child, a) {
                        final incoming = child.key == ValueKey(word);
                        return SlideTransition(
                          position: Tween(begin: Offset(0, incoming ? .7 : -.7), end: Offset.zero).animate(a),
                          child: FadeTransition(opacity: a, child: child),
                        );
                      },
                      child: Text(word, key: ValueKey(word), style: h1.copyWith(color: colour)),
                    ),
                  ),
                ),
                const TextSpan(text: ', right near you.'),
              ]),
              key: const Key('heroLine'),
            ),
            const SizedBox(height: 10),
            const Text('Gadgets, fashion, meals and everyday essentials from people and stores near you.',
                style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 15, height: 1.4)),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: FilledButton(
                  key: const Key('shopNow'),
                  onPressed: widget.onShop,
                  style: FilledButton.styleFrom(
                      backgroundColor: StallColors.lime, foregroundColor: StallColors.limeInk, minimumSize: const Size(0, 50), padding: EdgeInsets.zero),
                  child: const Text('Shop now'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  key: const Key('sellHero'),
                  onPressed: widget.onSell,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.white.withValues(alpha: .12),
                    side: BorderSide(color: Colors.white.withValues(alpha: .28)),
                    minimumSize: const Size(0, 50),
                    padding: EdgeInsets.zero,
                  ),
                  child: const Text('Sell something'),
                ),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// The faint dot grid on the right of the hero.
class _Dots extends CustomPainter {
  const _Dots();
  @override
  void paint(Canvas canvas, Size size) {
    for (var x = 9.0; x < size.width; x += 18) {
      final a = ((x / size.width - .3) / .7).clamp(0.0, 1.0) * .07;
      if (a == 0) continue;
      final p = Paint()..color = Colors.white.withValues(alpha: a);
      for (var y = 9.0; y < size.height; y += 18) {
        canvas.drawCircle(Offset(x, y), 1, p);
      }
    }
  }

  @override
  bool shouldRepaint(_Dots old) => false;
}

/// Why Stall: three small cards under the hero, as on the website.
class TrustTiles extends StatelessWidget {
  const TrustTiles({super.key});
  @override
  Widget build(BuildContext context) {
    Widget tile(IconData i, String text) => Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
            decoration: BoxDecoration(color: StallColors.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: StallColors.line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: const Color(0xFFF1F9DC), borderRadius: BorderRadius.circular(11)),
                child: Icon(i, size: 18, color: StallColors.ink),
              ),
              const SizedBox(height: 10),
              Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, height: 1.25)),
            ]),
          ),
        );
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        tile(Icons.school_outlined, 'Born on campus'),
        const SizedBox(width: 8),
        tile(Icons.verified_user_outlined, 'Checked payments'),
        const SizedBox(width: 8),
        tile(Icons.place_outlined, 'Collect nearby'),
      ]),
    );
  }
}

class _GuideCard extends StatelessWidget {
  const _GuideCard({required this.onOpen, required this.onClose});
  final VoidCallback onOpen;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) => Container(
        key: const Key('guideCard'),
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
        decoration: BoxDecoration(color: StallColors.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: StallColors.line)),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [StallColors.lime, Color(0xFF9BD12A)])),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('New to Stall?', style: TextStyle(fontFamily: 'Bricolage', fontWeight: FontWeight.w800, fontSize: 16)),
              Text('How buying, selling and payments work', style: TextStyle(color: StallColors.muted, fontSize: 12.5)),
            ]),
          ),
          FilledButton(
            key: const Key('guideGo'),
            onPressed: onOpen,
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 14)),
            child: const Text('Show me'),
          ),
          IconButton(key: const Key('guideX'), tooltip: 'Hide', onPressed: onClose, icon: const Icon(Icons.close_rounded, size: 20)),
        ]),
      );
}

/// Category tiles on Home: a coloured icon square over the name, like the website's.
class CatTiles extends StatelessWidget {
  const CatTiles({super.key, required this.value, required this.onPick});
  final String value;
  final ValueChanged<String> onPick;
  @override
  Widget build(BuildContext context) {
    final opts = [('all', 'All', Icons.auto_awesome_rounded, StallColors.card, const Color(0xFF9BD12A)), for (final c in Category.all) (c.id, c.name, c.icon, c.bg, c.fg)];
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: opts.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (id, name, icon, bg, fg) = opts[i];
          final on = id == value;
          return Material(
            color: StallColors.card,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18), side: BorderSide(color: on ? StallColors.ink : StallColors.line, width: on ? 2 : 1)),
            child: InkWell(
              key: Key('chip-$id'),
              borderRadius: BorderRadius.circular(18),
              onTap: () => onPick(id),
              child: Container(
                constraints: const BoxConstraints(minWidth: 76),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
                    child: Icon(icon, color: fg, size: 22),
                  ),
                  const SizedBox(height: 8),
                  Text(name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A small Nigerian flag, for "All Nigeria".
class NigeriaFlag extends StatelessWidget {
  const NigeriaFlag({super.key, this.height = 14});
  final double height;
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: SizedBox(
          width: height * 1.5,
          height: height,
          child: const Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: ColoredBox(color: Color(0xFF008751))),
            Expanded(child: ColoredBox(color: Colors.white)),
            Expanded(child: ColoredBox(color: Color(0xFF008751))),
          ]),
        ),
      );
}

/// The tappable "Search Stall" box on Home.
class SearchBox extends StatelessWidget {
  const SearchBox({super.key, required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: StallColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: StallColors.line)),
        child: InkWell(
          key: const Key('searchBox'),
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            child: Row(children: [
              Icon(Icons.search_rounded, color: StallColors.muted),
              SizedBox(width: 10),
              Expanded(
                child: Text('Search books, phones, food…',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: StallColors.muted, fontSize: 15.5)),
              ),
            ]),
          ),
        ),
      );
}

/// The coloured category tile shown when an item or store has no photo.
class CatTile extends StatelessWidget {
  const CatTile({super.key, required this.cat, this.icon, this.size = 40});
  final String cat;
  final IconData? icon;
  final double size;
  @override
  Widget build(BuildContext context) {
    final c = Category.of(cat);
    return Container(color: c.bg, alignment: Alignment.center, child: Icon(icon ?? c.icon, color: c.fg, size: size));
  }
}

/// A photo from the API, with the category tile behind it while it loads or if it fails.
class Photo extends StatelessWidget {
  const Photo({super.key, required this.path, required this.cat, this.icon, this.fit = BoxFit.cover});
  final String? path;
  final String cat;
  final IconData? icon;
  final BoxFit fit;
  @override
  Widget build(BuildContext context) {
    final api = SessionScope.of(context).api;
    return Stack(fit: StackFit.expand, children: [
      CatTile(cat: cat, icon: icon),
      if (path != null) NetImage(api.url(path!), fit: fit),
    ]);
  }
}

class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.bg = StallColors.night, this.fg = Colors.white});
  final String text;
  final Color bg;
  final Color fg;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700)),
      );
}

class ItemCard extends StatelessWidget {
  const ItemCard({super.key, required this.item});
  final Listing item;
  @override
  Widget build(BuildContext context) {
    final st = item.status;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('item-${item.id}'),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ItemScreen(item: item))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Stack(fit: StackFit.expand, children: [
              Hero(tag: 'img-${item.id}', child: Photo(path: item.imgs.firstOrNull, cat: item.cat)),
              Positioned(
                left: 8,
                top: 8,
                child: Wrap(spacing: 6, children: [
                  if (st != null) Tag(st),
                  if (st == null && item.featured) const Tag('Featured', bg: StallColors.lime, fg: StallColors.limeInk),
                ]),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(naira(item.price), style: const TextStyle(fontFamily: 'Bricolage', fontWeight: FontWeight.w800, fontSize: 17)),
              const SizedBox(height: 2),
              StarText(
                [if (item.rating.n > 0) item.rating.label, if (item.deliv.on) 'Delivers' else item.spot].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Shares an item or store link the same way the web app does, with your invite code so you earn the referral reward.
Future<void> shareThing(BuildContext context, {required String id, required String text}) async {
  final api = SessionScope.of(context).api;
  String? code;
  try {
    code = (await api.get('me/referral'))['code']?.toString();
  } catch (_) {}
  final link = '${api.base}/?${id.startsWith('S') ? 'store' : 'item'}=$id${code == null ? '' : '&r=$code'}';
  await SharePlus.instance.share(ShareParams(text: '$text $link', subject: 'Stall'));
}
