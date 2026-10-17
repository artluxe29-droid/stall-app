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

/// Swipeable photos with dots.
class Gallery extends StatefulWidget {
  const Gallery({super.key, required this.imgs, required this.cat, this.heroTag, this.icon});
  final List<String> imgs;
  final String cat;
  final String? heroTag;
  final IconData? icon;
  @override
  State<Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<Gallery> {
  int _i = 0;
  @override
  Widget build(BuildContext context) {
    final imgs = widget.imgs;
    Widget page(int i) {
      final p = Photo(path: imgs.isEmpty ? null : imgs[i], cat: widget.cat, icon: widget.icon);
      return i == 0 && widget.heroTag != null ? Hero(tag: widget.heroTag!, child: p) : p;
    }

    return AspectRatio(
      aspectRatio: 1,
      child: Stack(children: [
        PageView.builder(
          itemCount: imgs.isEmpty ? 1 : imgs.length,
          onPageChanged: (i) => setState(() => _i = i),
          itemBuilder: (_, i) => page(i),
        ),
        if (imgs.length > 1)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < imgs.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _i ? 18 : 7,
                  height: 7,
                  decoration: BoxDecoration(color: i == _i ? Colors.white : Colors.white70, borderRadius: BorderRadius.circular(9)),
                ),
            ]),
          ),
      ]),
    );
  }
}

/// "Verified student" / "School email" badge, from the seller's verification level.
class VerifyBadge extends StatelessWidget {
  const VerifyBadge({super.key, required this.verified, required this.vlevel});
  final bool verified;
  final int vlevel;
  @override
  Widget build(BuildContext context) {
    final label = verified ? 'Verified' : (vlevel >= 2 ? 'Verified student' : (vlevel == 1 ? 'School email' : null));
    if (label == null) return const SizedBox.shrink();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.verified_rounded, size: 16, color: StallColors.green),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(color: StallColors.green, fontWeight: FontWeight.w700, fontSize: 13)),
    ]);
  }
}

class DeliveryLine extends StatelessWidget {
  const DeliveryLine({super.key, required this.d});
  final Delivery d;
  @override
  Widget build(BuildContext context) {
    if (!d.on) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.local_shipping_outlined, size: 18, color: StallColors.indigo),
        const SizedBox(width: 6),
        Expanded(
          child: Text('Delivers ${d.fee > 0 ? 'for ${naira(d.fee)}' : 'for free'}${d.note.isEmpty ? '' : ' · ${d.note}'}',
              style: Theme.of(context).textTheme.bodyMedium),
        ),
      ]),
    );
  }
}

/// A listing: photos, price, condition, where to meet, delivery, stock, description and seller.
class ItemScreen extends StatelessWidget {
  const ItemScreen({super.key, required this.item});
  final Listing item;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final st = item.status;
    return Scaffold(
      bottomNavigationBar: item.mine ? null : BuyBar(item: item),
      body: CustomScrollView(slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: MediaQuery.sizeOf(context).width,
          backgroundColor: StallColors.cream,
          leading: const _RoundBack(),
          actions: [
            Container(
              margin: const EdgeInsets.only(right: 4),
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: const BagButton(),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton.filledTonal(
                key: const Key('share'),
                tooltip: 'Share',
                style: IconButton.styleFrom(backgroundColor: Colors.white),
                onPressed: () => shareThing(context, id: item.id, text: '${item.title} for ${naira(item.price)} on Stall'),
                icon: const Icon(Icons.ios_share_rounded),
              ),
            ),
          ],
          flexibleSpace: FlexibleSpaceBar(background: Gallery(imgs: item.imgs, cat: item.cat, heroTag: 'img-${item.id}')),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          sliver: SliverList.list(children: [
            Text(naira(item.price), style: t.displaySmall),
            const SizedBox(height: 6),
            Text(item.title, style: t.headlineSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (st != null) Tag(st),
              if (st == null && item.featured) const Tag('Featured', bg: StallColors.lime, fg: StallColors.limeInk),
              Text([item.cond, 'Meet at ${item.spot}', ago(item.time)].where((x) => x.isNotEmpty).join(' · '), style: t.bodySmall),
            ]),
            DeliveryLine(d: item.deliv),
            if (item.stockLine != null) ...[
              const SizedBox(height: 8),
              Text(item.stockLine!,
                  style: TextStyle(fontWeight: FontWeight.w700, color: (item.qtyLeft ?? 9) <= 5 ? StallColors.amber : StallColors.green)),
            ],
            const Divider(height: 32),
            Text(item.desc.isEmpty ? 'No extra details.' : item.desc, style: t.bodyLarge?.copyWith(color: StallColors.muted)),
            const SizedBox(height: 20),
            SellerCard(
              name: item.seller,
              school: item.school,
              uid: item.sellerId,
              rating: item.rating,
              verified: item.verified,
              vlevel: item.vlevel,
            ),
            if (!item.mine) ...[const SizedBox(height: 10), Align(alignment: Alignment.centerLeft, child: MessageButton(ref: item.id, label: 'Message seller'))],
            const SizedBox(height: 16),
          ]),
        ),
      ]),
    );
  }
}

class _RoundBack extends StatelessWidget {
  const _RoundBack();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(8),
        child: IconButton.filledTonal(
          tooltip: 'Back',
          style: IconButton.styleFrom(backgroundColor: Colors.white),
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      );
}

/// Add to bag / Buy now, at the bottom of an item page.
class BuyBar extends StatelessWidget {
  const BuyBar({super.key, required this.item});
  final Listing item;

  BagLine get _line => BagLine(
        id: item.id,
        title: item.title,
        price: item.price,
        cat: item.cat,
        img: item.imgs.firstOrNull,
        seller: item.seller,
        max: item.qtyLeft,
        multi: item.qty > 1,
      );

  @override
  Widget build(BuildContext context) {
    final st = item.status;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(children: [
          Expanded(
            child: OutlinedButton(
              key: const Key('addToBag'),
              onPressed: st != null ? null : () => addToBag(context, _line),
              child: const Text('Add to bag'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              key: const Key('buyNow'),
              onPressed: st != null
                  ? null
                  : () {
                      final bag = SessionScope.of(context).bag;
                      if (bag.qtyOf(item.id) == 0) bag.add(_line);
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CheckoutScreen()));
                    },
              child: Text(st ?? 'Buy now'),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Who's selling, their rating and a way to read their reviews.
class SellerCard extends StatelessWidget {
  const SellerCard(
      {super.key, required this.name, required this.uid, required this.rating, this.school = '', this.verified = false, this.vlevel = 0});
  final String name;
  final String school;
  final int uid;
  final Rating rating;
  final bool verified;
  final int vlevel;
  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          key: const Key('seller'),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: CircleAvatar(
            backgroundColor: StallColors.indigo,
            foregroundColor: StallColors.cream,
            child: Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          title: Text('Sold by $name${school.isEmpty ? '' : ' · $school'}', style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            VerifyBadge(verified: verified, vlevel: vlevel),
            StarText(rating.n > 0 ? '${rating.label} · See reviews' : 'No ratings yet'),
          ]),
          trailing: rating.n > 0 ? const Icon(Icons.chevron_right_rounded) : null,
          onTap: rating.n > 0 ? () => showReviews(context, uid: uid, name: name) : null,
        ),
      );
}

Future<void> showReviews(BuildContext context, {required int uid, required String name}) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: StallColors.cream,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .7,
        maxChildSize: .95,
        builder: (context, sc) => ReviewsView(uid: uid, name: name, controller: sc),
      ),
    );

/// A seller's rating, how reliably they've sent orders, and their latest reviews with replies.
class ReviewsView extends StatefulWidget {
  const ReviewsView({super.key, required this.uid, required this.name, this.controller});
  final int uid;
  final String name;
  final ScrollController? controller;
  @override
  State<ReviewsView> createState() => _ReviewsViewState();
}

class _ReviewsViewState extends State<ReviewsView> {
  Future<Map<String, dynamic>>? _f;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _f ??= SessionScope.of(context).api.get('reviews', {'uid': '${widget.uid}'});
  }

  /// Sellers can reply once to each review of them.
  Future<void> _reply(Map<String, dynamic> x) async {
    var text = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reply to this review'),
        content: TextField(
            key: const Key('replyText'),
            onChanged: (v) => text = v,
            maxLength: 300,
            maxLines: 3,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Thank them, or explain what happened. Everyone can see it.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(key: const Key('replySend'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Post reply')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final api = SessionScope.of(context).api;
    try {
      await api.post('reviews/reply', {'id': x['id'], 'text': text.trim()});
      if (!mounted) return;
      toast(context, 'Reply posted');
      setState(() {
        _f = api.get('reviews', {'uid': '${widget.uid}'});
      });
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return FutureBuilder<Map<String, dynamic>>(
      future: _f,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snap.hasError) {
          return Center(child: Text(snap.error is ApiError ? (snap.error as ApiError).message : 'Couldn\'t load reviews.'));
        }
        final d = snap.data!;
        final r = Rating.from(d['rating']);
        final cn = d['cancels'] as Map? ?? const {};
        final n = (cn['n'] as num? ?? 0).toInt(), of = (cn['of'] as num? ?? 0).toInt();
        final revs = (d['reviews'] as List? ?? const []).cast<Map<String, dynamic>>();
        final mine = SessionScope.of(context).user?.uid == widget.uid;
        return ListView(controller: widget.controller, padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: [
          Text(widget.name, style: t.headlineSmall),
          const SizedBox(height: 4),
          StarText(r.n > 0 ? '${r.label} from ${r.n} buyer${r.n > 1 ? 's' : ''}' : 'No ratings yet', style: t.bodyLarge),
          if (of > 0)
            Text(
                n > 0
                    ? 'Cancelled or didn\'t send $n of $of order${of > 1 ? 's' : ''} in the last 90 days'
                    : 'Sent all $of order${of > 1 ? 's' : ''} in the last 90 days ✓',
                style: t.bodySmall),
          const SizedBox(height: 12),
          for (final x in revs)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  StarText('★' * ((x['stars'] as num?)?.toInt() ?? 0), style: const TextStyle(fontSize: 15)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: (x['who'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                        TextSpan(text: ' · ${ago((x['t'] as num?)?.toInt() ?? 0)}', style: t.bodySmall),
                      ]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
                if ((x['title'] ?? '').toString().isNotEmpty) Text('Bought ${x['title']}', style: t.bodySmall),
                if ((x['text'] ?? '').toString().isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 4), child: Text(x['text'].toString())),
                if ((x['reply'] ?? '').toString().isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: StallColors.cream2, borderRadius: BorderRadius.circular(12)),
                    child: Text.rich(TextSpan(children: [
                      const TextSpan(text: 'Seller\'s reply: ', style: TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: x['reply'].toString()),
                    ])),
                  )
                else if (mine)
                  TextButton(key: Key('reply-${x['id']}'), onPressed: () => _reply(x), child: const Text('Reply')),
              ]),
            ),
        ]);
      },
    );
  }
}
