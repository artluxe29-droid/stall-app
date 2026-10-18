import 'package:flutter/material.dart';

import '../api.dart';
import '../bag.dart';
import '../main.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'browse.dart';
import 'chat.dart';
import 'checkout.dart';
import 'extras.dart' show StoreQrScreen;
import 'item.dart';
import 'my_store.dart' show MyStoreScreen, StoreItemScreen, loadMyStore;

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
          key: ValueKey(_scope),
          future: _f,
          builder: (context, snap) {
            Widget fill(Widget w) => SliverFillRemaining(hasScrollBody: false, child: w);
            if (snap.connectionState != ConnectionState.done && !snap.hasData) return fill(const Center(child: CircularProgressIndicator()));
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
            ? NetImage(SessionScope.of(context).api.url(store.logo!), error: CatTile(cat: store.cat, icon: storeIcon(store.emoji, store.cat)))
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
                      if (s.founding > 0) Tag('Founding Seller', bg: StallColors.indigo),
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

class _StoreBody extends StatefulWidget {
  const _StoreBody({required this.store});
  final Store store;
  @override
  State<_StoreBody> createState() => _StoreBodyState();
}

class _StoreBodyState extends State<_StoreBody> {
  late Store _s = widget.store;

  /// The owner went to add or change something: show the store as it is now.
  Future<void> _manage(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (!mounted) return;
    try {
      final st = await loadMyStore(SessionScope.of(context).api);
      if (st != null && mounted) setState(() => _s = st);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final t = Theme.of(context).textTheme;
    final c = Category.of(s.cat);
    final mine = SessionScope.of(context).user?.uid == s.ownerId;
    const onDark = Color(0xFFCBD5E1);
    Widget round(Widget icon, {Key? key, String? tip, VoidCallback? onTap}) => Material(
          color: Colors.white.withValues(alpha: .1),
          shape: const CircleBorder(),
          child: IconButton(key: key, tooltip: tip, onPressed: onTap, color: Colors.white, icon: icon),
        );
    return Scaffold(
      body: ListView(padding: EdgeInsets.zero, children: [
        // The website's store banner: dark, rounded at the bottom, logo in a white ring, stats split by thin lines.
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF161A33), Color(0xFF1E2552)]),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
          ),
          padding: EdgeInsets.fromLTRB(14, MediaQuery.paddingOf(context).top + 10, 14, 26),
          child: Column(children: [
            Row(children: [
              round(const Icon(Icons.arrow_back_rounded), tip: 'Back', onTap: () => Navigator.of(context).maybePop()),
              const Spacer(),
              const IconTheme(data: IconThemeData(color: Colors.white), child: BagButton()),
              round(const Icon(Icons.ios_share_rounded),
                  key: const Key('share'), tip: 'Share store', onTap: () => shareThing(context, id: s.id, text: 'Check out ${s.name} on Stall')),
            ]),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .9), shape: BoxShape.circle),
              child: ClipOval(child: StoreAvatar(store: s, size: 84)),
            ),
            const SizedBox(height: 12),
            Text(s.name, textAlign: TextAlign.center, style: t.headlineMedium?.copyWith(color: Colors.white)),
            if (s.founding > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Tag('Founding Seller #${s.founding}${s.school.isEmpty ? '' : ' · ${s.school}'}', bg: StallColors.lime, fg: StallColors.limeInk),
              ),
            const SizedBox(height: 4),
            VerifyBadge(verified: s.verified, vlevel: s.vlevel),
            if (s.rating.n > 0)
              TextButton(
                onPressed: () => showReviews(context, uid: s.ownerId, name: s.name),
                style: TextButton.styleFrom(foregroundColor: const Color(0xFFF5B83D)),
                child: StarText('${s.rating.label} · reviews', style: const TextStyle(color: Color(0xFFF5B83D), fontWeight: FontWeight.w700)),
              ),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: s.open ? const Color(0xFF22C55E) : const Color(0xFFEF4444), shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text('${s.open ? 'Open now' : 'Closed'}${s.vendor ? ' · Business' : ''}', style: const TextStyle(color: onDark, fontSize: 13.5)),
            ]),
            const SizedBox(height: 18),
            IntrinsicHeight(
              child: Row(children: [
                _Stat('${s.availableCount}', 'Available'),
                const VerticalDivider(width: 1, color: Color(0x26FFFFFF)),
                _Stat('${s.items.length}', 'Items'),
                const VerticalDivider(width: 1, color: Color(0x26FFFFFF)),
                _Stat(s.school.isEmpty ? c.name : s.school, s.school.isEmpty ? 'Category' : s.state),
              ]),
            ),
            const SizedBox(height: 20),
            if (mine)
              FilledButton.icon(
                key: const Key('storeKit'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StoreQrScreen(store: s))),
                style: FilledButton.styleFrom(
                    backgroundColor: StallColors.cream2, foregroundColor: StallColors.ink, minimumSize: const Size(0, 50), padding: const EdgeInsets.symmetric(horizontal: 24)),
                icon: const Icon(Icons.campaign_outlined),
                label: const Text('Now on Stall kit'),
              )
            else
              Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 10, children: [
                FilledButton.icon(
                  key: Key('msg-${s.id}'),
                  onPressed: () => openChat(context, s.id),
                  style: FilledButton.styleFrom(
                      backgroundColor: StallColors.lime, foregroundColor: StallColors.limeInk, minimumSize: const Size(0, 48), padding: const EdgeInsets.symmetric(horizontal: 20)),
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                  label: const Text('Message the store'),
                ),
                OutlinedButton.icon(
                  onPressed: () => shareThing(context, id: s.id, text: 'Check out ${s.name} on Stall'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.white.withValues(alpha: .1),
                      side: BorderSide(color: Colors.white.withValues(alpha: .25)),
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 20)),
                  icon: const Icon(Icons.ios_share_rounded, size: 18),
                  label: const Text('Share store'),
                ),
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
                  Icon(Icons.place_outlined, size: 18, color: StallColors.indigo),
                  const SizedBox(width: 6),
                  Expanded(child: Text(s.spot)),
                ]),
              ),
            DeliveryLine(d: s.deliv),
            if (mine) ...[
              // Like the website: the owner runs the store from its own page.
              if (s.logo == null)
                Card(
                  key: const Key('logoNudge'),
                  margin: const EdgeInsets.only(top: 14),
                  child: ListTile(
                    leading: Icon(Icons.photo_camera_outlined, color: StallColors.indigo),
                    title: const Text('Add your logo'),
                    subtitle: const Text('Many stores use the same icon. A logo helps buyers spot you and remember you.'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _manage(const MyStoreScreen()),
                  ),
                ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('ownerAddItem'),
                    onPressed: () => _manage(StoreItemScreen(cat: s.cat)),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add item'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('ownerManage'),
                    onPressed: () => _manage(const MyStoreScreen()),
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    label: const Text('Manage store'),
                  ),
                ),
              ]),
            ],
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
          Text(value,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Bricolage', fontWeight: FontWeight.w800, fontSize: 18, color: Colors.white)),
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF9AA1C9))),
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
                    Text(s.open ? 'Sold out right now.' : 'This store is closed right now.', style: TextStyle(color: StallColors.muted)),
                ]),
              ),
            ]),
          ),
        );
      },
    );

BagLine storeLine(StoreItem it, Store s) =>
    BagLine(id: it.id, title: it.title, price: it.price, cat: s.cat, img: it.imgs.firstOrNull, seller: s.name, max: it.qtyLeft, multi: true);
