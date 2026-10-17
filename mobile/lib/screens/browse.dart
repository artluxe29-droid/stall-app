import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../api.dart';
import '../main.dart';
import '../models.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets.dart';
import 'chat.dart';
import 'checkout.dart';
import 'item.dart';
import 'search.dart';

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
  const ChipRow({super.key, required this.options, required this.value, required this.onPick, this.icons = const {}});
  final List<(String, String)> options;
  final String value;
  final ValueChanged<String> onPick;
  final Map<String, IconData> icons;
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
              avatar: icons[id] == null ? null : Icon(icons[id], size: 18, color: on ? Colors.white : StallColors.indigo),
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
    notifyListeners();
    await _fetch(g, 0);
  }

  Future<void> loadMore() async {
    if (loading || !more) return;
    loading = true;
    notifyListeners();
    await _fetch(_gen, items.length);
  }

  Future<void> _fetch(int g, int off) async {
    try {
      final r = await api.get('listings', {..._q, 'n': '24', if (off > 0) 'off': '$off'});
      if (g != _gen) return;
      soon = r['soon'] == true;
      total = (r['total'] as num?)?.toInt() ?? 0;
      items.addAll((r['listings'] as List? ?? const []).map((e) => Listing(e as Map<String, dynamic>)));
      if (off == 0) storeHits.addAll((r['storeHits'] as List? ?? const []).map((e) => StoreHit(e as Map<String, dynamic>)));
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

/// Home: search, the break message, where to look, categories and the latest items.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  ListingPager? _pager;
  String? _scope;
  String _cat = 'all';

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

  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    final t = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          sliver: SliverList.list(children: [
            Row(children: [
              const Wordmark(height: 28),
              const Spacer(),
              IconButton(
                key: const Key('messages'),
                tooltip: 'Messages',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MessagesScreen())),
                icon: const Icon(Icons.chat_bubble_outline_rounded),
              ),
              const BagButton(),
            ]),
            if (s.user?.pausedUntil != null) ...[const SizedBox(height: 12), PausedCard(until: s.user!.pausedUntil!)],
            const SizedBox(height: 16),
            SearchBox(onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchScreen()))),
            const SizedBox(height: 16),
            if (s.breakMessage != null) ...[BreakCard(message: s.breakMessage!), const SizedBox(height: 16)],
            Text('Hi ${s.user?.firstName ?? ''}', style: t.headlineMedium),
            const SizedBox(height: 4),
            Text(
                switch (_scope) {
                  Scope.school => 'What\'s new at ${s.user?.schoolName ?? 'your school'}',
                  Scope.area => 'What\'s new in ${s.user?.area ?? 'your area'}',
                  Scope.state => 'What\'s new in ${s.user?.state ?? 'your state'}',
                  _ => 'What\'s new across Nigeria',
                },
                style: t.bodyLarge?.copyWith(color: StallColors.muted)),
            const SizedBox(height: 14),
          ]),
        ),
        SliverToBoxAdapter(
          child: ChipRow(
            options: Scope.options(s.user),
            value: _scope!,
            onPick: (v) {
              setState(() => _scope = v);
              _load();
            },
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
        SliverToBoxAdapter(
          child: ChipRow(
            options: [('all', 'All'), for (final c in Category.all) (c.id, c.name)],
            icons: {for (final c in Category.all) c.id: c.icon},
            value: _cat,
            onPick: (v) {
              setState(() => _cat = v);
              _load();
            },
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ListingSlivers(pager: _pager!),
      ]),
    );
  }
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
      if (path != null) Image.network(api.url(path!), fit: fit, errorBuilder: (_, _, _) => const SizedBox()),
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
