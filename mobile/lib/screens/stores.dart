import 'package:flutter/material.dart';

import '../api.dart';
import '../bag.dart';
import '../main.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'browse.dart';
import 'checkout.dart';
import 'item.dart';

Future<List<Store>> loadStores(Api api, String scope) async {
  final r = await api.get('stores', {'scope': scope});
  if (r['soon'] == true) throw const _Soon();
  return (r['stores'] as List? ?? const []).map((e) => Store(e as Map<String, dynamic>)).toList();
}

class _Soon implements Exception {
  const _Soon();
}

/// Stores: campus shops and food stalls, at your school, in your state, or nationwide.
class StoresTab extends StatefulWidget {
  const StoresTab({super.key});
  @override
  State<StoresTab> createState() => _StoresTabState();
}

class _StoresTabState extends State<StoresTab> {
  String? _scope;
  Future<List<Store>>? _f;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scope == null) {
      _scope = Scope.initial(SessionScope.of(context).user);
      _load();
    }
  }

  void _load() {
    final f = loadStores(SessionScope.of(context).api, _scope!);
    setState(() {
      _f = f;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    final t = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: () async {
        _load();
        await _f!.catchError((_) => <Store>[]);
      },
      child: CustomScrollView(slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          sliver: SliverList.list(children: [
            Text('Stores', style: t.headlineMedium),
            const SizedBox(height: 4),
            Text('Campus shops, food stalls and student brands.', style: t.bodyLarge?.copyWith(color: StallColors.muted)),
          ]),
        ),
        SliverToBoxAdapter(
          child: ChipRow(
              options: Scope.options(s.user),
              value: _scope!,
              onPick: (v) {
                _scope = v;
                _load();
              }),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        FutureBuilder<List<Store>>(
          future: _f,
          builder: (context, snap) {
            Widget fill(Widget w) => SliverFillRemaining(hasScrollBody: false, child: w);
            if (snap.connectionState != ConnectionState.done) return fill(const Center(child: CircularProgressIndicator()));
            if (snap.error is _Soon) {
              return fill(const EmptyState(
                  icon: Icons.school_outlined, title: 'Stall isn\'t open at your school yet', text: 'We\'ll tell you the moment it opens.'));
            }
            if (snap.hasError) {
              return fill(EmptyState(
                  icon: Icons.wifi_off_rounded,
                  title: 'Couldn\'t load stores',
                  text: snap.error is ApiError ? (snap.error as ApiError).message : 'Pull down to try again.'));
            }
            final ss = snap.data!;
            if (ss.isEmpty) {
              return fill(const EmptyState(
                  icon: Icons.storefront_outlined, title: 'No stores yet', text: 'Campus shops and students can open a store on Stall.'));
            }
            return SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: SliverList.separated(
                itemCount: ss.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) => StoreCard(store: ss[i], mySchool: s.user?.schoolName ?? ''),
              ),
            );
          },
        ),
      ]),
    );
  }
}

/// A store's logo, or its icon on its category colour.
class StoreAvatar extends StatelessWidget {
  const StoreAvatar({super.key, required this.store, this.size = 64});
  final Store store;
  final double size;
  @override
  Widget build(BuildContext context) {
    final c = Category.of(store.cat);
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * .28),
      child: SizedBox.square(
        dimension: size,
        child: store.logo != null
            ? Image.network(SessionScope.of(context).api.url(store.logo!),
                fit: BoxFit.cover, errorBuilder: (_, _, _) => CatTile(cat: store.cat, icon: storeIcon(store.emoji, store.cat)))
            : Container(color: c.bg, child: Icon(storeIcon(store.emoji, store.cat), color: c.fg, size: size * .48)),
      ),
    );
  }
}

class StoreCard extends StatelessWidget {
  const StoreCard({super.key, required this.store, this.mySchool = ''});
  final Store store;
  final String mySchool;
  @override
  Widget build(BuildContext context) {
    final s = store;
    final t = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('store-${s.id}'),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StoreScreen(store: s))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            StoreAvatar(store: s),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium)),
                  _OpenDot(open: s.open),
                ]),
                if (s.founding > 0 || s.featured)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(spacing: 6, children: [
                      if (s.featured) const Tag('Featured', bg: StallColors.lime, fg: StallColors.limeInk),
                      if (s.founding > 0) const Tag('Founding Seller', bg: StallColors.indigo),
                    ]),
                  ),
                const SizedBox(height: 4),
                Text(
                  [
                    Category.of(s.cat).name,
                    if (s.spot.isNotEmpty) s.spot,
                    if (s.vendor) 'Business',
                    if (s.school.isNotEmpty && s.school != mySchool) s.school,
                    if (s.reach == 'national') 'Ships nationwide',
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySmall,
                ),
                const SizedBox(height: 2),
                StarText([
                  '${s.availableCount} available now',
                  if (s.rating.n > 0) s.rating.label,
                ].join(' · '), style: t.bodySmall?.copyWith(color: StallColors.ink, fontWeight: FontWeight.w600)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _OpenDot extends StatelessWidget {
  const _OpenDot({required this.open});
  final bool open;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 8, height: 8, decoration: BoxDecoration(color: open ? StallColors.green : StallColors.muted, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(open ? 'Open' : 'Closed', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: open ? StallColors.green : StallColors.muted)),
      ]);
}

/// A store's page. Pass the store, or just its id (from a search hit or a shared link) to look it up.
class StoreScreen extends StatefulWidget {
  const StoreScreen({super.key, this.store, this.storeId}) : assert(store != null || storeId != null);
  final Store? store;
  final String? storeId;
  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  Future<Store?>? _f;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.store == null) {
      _f ??= loadStores(SessionScope.of(context).api, Scope.all)
          .then((l) => l.where((s) => s.id == widget.storeId).firstOrNull);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.store != null) return _StoreBody(store: widget.store!);
    return FutureBuilder<Store?>(
      future: _f,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
        }
        if (snap.data == null) {
          return Scaffold(
            appBar: AppBar(),
            body: EmptyState(
                icon: Icons.storefront_outlined,
                title: 'Store not found',
                text: snap.error is ApiError ? (snap.error as ApiError).message : 'It may have closed, or isn\'t open to your school.'),
          );
        }
        return _StoreBody(store: snap.data!);
      },
    );
  }
}

class _StoreBody extends StatelessWidget {
  const _StoreBody({required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) {
    final s = store;
    final t = Theme.of(context).textTheme;
    final c = Category.of(s.cat);
    final mine = SessionScope.of(context).user?.uid == s.ownerId;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: c.bg,
        actions: [
          const BagButton(),
          IconButton(
            key: const Key('share'),
            tooltip: 'Share store',
            onPressed: () => shareThing(context, id: s.id, text: 'Check out ${s.name} on Stall'),
            icon: const Icon(Icons.ios_share_rounded),
          ),
        ],
      ),
      body: ListView(padding: EdgeInsets.zero, children: [
        Container(
          color: c.bg,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(children: [
            StoreAvatar(store: s, size: 88),
            const SizedBox(height: 12),
            Text(s.name, style: t.headlineMedium, textAlign: TextAlign.center),
            if (s.founding > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Tag('Founding Seller #${s.founding}${s.school.isEmpty ? '' : ' · ${s.school}'}', bg: StallColors.indigo),
              ),
            const SizedBox(height: 6),
            VerifyBadge(verified: s.verified, vlevel: s.vlevel),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _OpenDot(open: s.open),
              if (s.vendor) Text(' · Business', style: t.bodySmall),
            ]),
            if (s.rating.n > 0)
              TextButton(onPressed: () => showReviews(context, uid: s.ownerId, name: s.name), child: StarText('${s.rating.label} · reviews')),
            const SizedBox(height: 8),
            Row(children: [
              _Stat('${s.availableCount}', 'Available'),
              _Stat('${s.items.length}', 'Items'),
              _Stat(s.school.isEmpty ? c.name : s.school, s.school.isEmpty ? 'Category' : s.state),
            ]),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (s.desc.isNotEmpty) Text(s.desc, style: t.bodyLarge?.copyWith(color: StallColors.muted)),
            if (s.spot.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  const Icon(Icons.place_outlined, size: 18, color: StallColors.indigo),
                  const SizedBox(width: 6),
                  Expanded(child: Text(s.spot)),
                ]),
              ),
            DeliveryLine(d: s.deliv),
            if (mine)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('This is your store. Managing it in the app arrives with selling; for now use stall.com.ng.',
                    style: TextStyle(color: StallColors.muted)),
              ),
          ]),
        ),
        if (s.items.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: EmptyState(icon: Icons.inventory_2_outlined, title: 'No items yet', text: 'Check back soon.'),
          )
        else
          for (final it in s.items) _StoreItemRow(item: it, store: s),
        const SizedBox(height: 32),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Bricolage', fontWeight: FontWeight.w800, fontSize: 18)),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ]),
      );
}

class _StoreItemRow extends StatelessWidget {
  const _StoreItemRow({required this.item, required this.store});
  final StoreItem item;
  final Store store;
  @override
  Widget build(BuildContext context) {
    final ok = store.open && item.avail;
    final t = Theme.of(context).textTheme;
    final l = item.qtyLeft;
    return InkWell(
      key: Key('sitem-${item.id}'),
      onTap: () => _showStoreItem(context, item, store),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox.square(
                dimension: 72, child: Photo(path: item.imgs.firstOrNull, cat: store.cat, icon: storeIcon(store.emoji, store.cat), )),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.title, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (item.desc.isNotEmpty) Text(item.desc, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall),
              if (l != null && l > 0 && l <= 5) Text('Only $l left', style: const TextStyle(color: StallColors.amber, fontWeight: FontWeight.w700, fontSize: 13)),
              Text(naira(item.price), style: const TextStyle(fontFamily: 'Bricolage', fontWeight: FontWeight.w800, fontSize: 17)),
            ]),
          ),
          if (!ok)
            Text(store.open ? 'Sold out' : 'Closed', style: t.bodySmall)
          else if (SessionScope.of(context).user?.uid != store.ownerId)
            IconButton.filledTonal(
              key: Key('add-${item.id}'),
              tooltip: 'Add to bag',
              onPressed: () => addToBag(context, storeLine(item, store)),
              icon: const Icon(Icons.add_rounded),
            ),
        ]),
      ),
    );
  }
}

void _showStoreItem(BuildContext context, StoreItem it, Store s) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: StallColors.cream,
      builder: (context) {
        final t = Theme.of(context).textTheme;
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Gallery(imgs: it.imgs, cat: s.cat, icon: storeIcon(s.emoji, s.cat)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(naira(it.price), style: t.headlineMedium),
                  const SizedBox(height: 4),
                  Text(it.title, style: t.titleLarge),
                  if (it.desc.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(it.desc)),
                  const SizedBox(height: 8),
                  Text('${s.name}${s.spot.isEmpty ? '' : ' · ${s.spot}'}', style: t.bodySmall),
                  const SizedBox(height: 16),
                  if (s.open && it.avail)
                    FilledButton(
                      key: const Key('addStoreItem'),
                      onPressed: () {
                        addToBag(context, storeLine(it, s));
                        Navigator.pop(context);
                      },
                      child: const Text('Add to bag'),
                    )
                  else
                    Text(s.open ? 'Sold out right now.' : 'This store is closed right now.', style: const TextStyle(color: StallColors.muted)),
                ]),
              ),
            ]),
          ),
        );
      },
    );

BagLine storeLine(StoreItem it, Store s) =>
    BagLine(id: it.id, title: it.title, price: it.price, cat: s.cat, img: it.imgs.firstOrNull, seller: s.name, max: it.qtyLeft, multi: true);
