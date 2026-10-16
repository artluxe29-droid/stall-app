import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../main.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'checkout.dart';

/// "Send code on WhatsApp", with the same message as the web app.
Uri? waCode(String phone, String code, String title) {
  final n = phone.replaceAll(RegExp(r'\D'), '').replaceFirst(RegExp(r'^0'), '234');
  if (n.isEmpty) return null;
  return Uri.parse('https://wa.me/$n?text=${Uri.encodeComponent('Hi, my Stall payment for $title has been verified. My release code is $code.')}');
}

/// The big release code, where to use it, and a WhatsApp shortcut to send it to the seller.
class ReleaseCodeCard extends StatelessWidget {
  const ReleaseCodeCard({super.key, required this.order});
  final Order order;
  @override
  Widget build(BuildContext context) {
    final o = order;
    final t = Theme.of(context).textTheme;
    final wa = o.code == null ? null : waCode(o.sellerPhone, o.code!, o.title);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(children: [
          Text(o.title, style: t.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Text('Your release code', style: t.bodySmall),
          GestureDetector(
            onLongPress: o.code == null
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: o.code!));
                    toast(context, 'Code copied');
                  },
            child: Text(o.code ?? '', key: Key('code-${o.id}'), style: t.headlineMedium?.copyWith(letterSpacing: 1.5)),
          ),
          if (o.method != null) ...[const SizedBox(height: 12), Tracker(order: o)],
          const SizedBox(height: 12),
          Text(
            o.method == 'delivery'
                ? 'Give this code to ${o.sellerName} when your order arrives at ${o.addr}.'
                : 'Show this to ${o.sellerName} when you collect your order${o.pickup.isEmpty ? '' : ' at ${o.pickup}'}, or send it ahead on WhatsApp so they know it\'s coming.',
            textAlign: TextAlign.center,
            style: t.bodyMedium?.copyWith(color: StallColors.muted),
          ),
          const SizedBox(height: 6),
          Text('Check the item first: once you give the code, the sale is final.', textAlign: TextAlign.center, style: t.bodySmall),
          if (wa != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => launchUrl(wa, mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.chat_outlined),
              label: const Text('Send code on WhatsApp'),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Paid → Packed → On the way → Delivered (or Paid → Ready → Collected).
class Tracker extends StatelessWidget {
  const Tracker({super.key, required this.order});
  final Order order;
  @override
  Widget build(BuildContext context) {
    final s = order.steps;
    Widget line(bool on) => Expanded(child: Container(height: 3, color: on ? StallColors.green : StallColors.line));
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < s.length; i++)
        Expanded(
          child: Column(children: [
            Row(children: [
              i == 0 ? const Spacer() : line(s[i].$2),
              Icon(s[i].$2 ? Icons.check_circle_rounded : Icons.radio_button_unchecked, size: 20, color: s[i].$2 ? StallColors.green : StallColors.muted),
              i == s.length - 1 ? const Spacer() : line(i + 1 < s.length && s[i + 1].$2),
            ]),
            const SizedBox(height: 4),
            Text(s[i].$1,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(fontSize: 11.5, fontWeight: s[i].$2 ? FontWeight.w700 : FontWeight.w500)),
          ]),
        ),
    ]);
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.order);
  final Order order;
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (order.status) {
      'released' => (const Color(0xFFDCF7E6), StallColors.green),
      'verified' => (const Color(0xFFEEF8C8), const Color(0xFF4E6106)),
      'pending' || 'under_review' => (const Color(0xFFFEF3C7), StallColors.amber),
      'disputed' || 'rejected' => (const Color(0xFFFDE2E4), StallColors.red),
      _ => (StallColors.cream2, StallColors.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(order.badge, style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w700)),
    );
  }
}

/// Orders: what you've bought, newest first. (Selling orders arrive with Phase 2.)
class OrdersTab extends StatefulWidget {
  const OrdersTab({super.key});
  @override
  State<OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<OrdersTab> {
  Future<List<Order>>? _f;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _f ??= _load();
  }

  Future<List<Order>> _load() async {
    final r = await SessionScope.of(context).api.get('orders/mine');
    return (r['orders'] as List? ?? const []).map((e) => Order(e as Map<String, dynamic>)).toList();
  }

  Future<void> _refresh() async {
    final f = _load();
    setState(() {
      _f = f;
    });
    await f.catchError((_) => <Order>[]);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
          sliver: SliverToBoxAdapter(child: Row(children: [Expanded(child: Text('Orders', style: t.headlineMedium)), const BagButton()])),
        ),
        FutureBuilder<List<Order>>(
          future: _f,
          builder: (context, snap) {
            Widget fill(Widget w) => SliverFillRemaining(hasScrollBody: false, child: w);
            if (snap.connectionState != ConnectionState.done) return fill(const Center(child: CircularProgressIndicator()));
            if (snap.hasError) {
              return fill(EmptyState(
                  icon: Icons.wifi_off_rounded,
                  title: 'Couldn\'t load your orders',
                  text: snap.error is ApiError ? (snap.error as ApiError).message : 'Pull down to try again.'));
            }
            final os = snap.data!;
            if (os.isEmpty) {
              return fill(const EmptyState(
                  icon: Icons.receipt_long_outlined, title: 'No orders yet', text: 'When you buy something, your release code and order updates show here.'));
            }
            return SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: SliverList.separated(
                itemCount: os.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final o = os[i];
                  return Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      key: Key('order-${o.id}'),
                      contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                      title: Text(o.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${naira(o.amount)} · ${o.sellerName}'),
                        const SizedBox(height: 6),
                        _Chip(o),
                      ]),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () async {
                        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrderScreen(order: o)));
                        _refresh();
                      },
                    ),
                  );
                },
              ),
            );
          },
        ),
      ]),
    );
  }
}

/// One order from the buyer's side: what's happening, the money Stall holds, and what you can do now.
class OrderScreen extends StatefulWidget {
  const OrderScreen({super.key, required this.order});
  final Order order;
  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  late Order o = widget.order;
  bool _busy = false;
  int _stars = 0;
  final _review = TextEditingController();

  @override
  void dispose() {
    _review.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final r = await SessionScope.of(context).api.get('orders/mine');
    final n = (r['orders'] as List? ?? const []).map((e) => Order(e as Map<String, dynamic>)).where((x) => x.id == o.id).firstOrNull;
    if (n != null && mounted) setState(() => o = n);
  }

  Future<void> _act(String path, Map<String, dynamic> body, String done) async {
    setState(() => _busy = true);
    try {
      await SessionScope.of(context).api.post(path, body);
      if (!mounted) return;
      toast(context, done);
      await _reload();
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _note(String text, {bool bad = false}) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: bad ? const Color(0xFFFDE2E4) : StallColors.cream2, borderRadius: BorderRadius.circular(14)),
        child: Text(text),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final ps = o.paidVia == 'paystack';
    return Scaffold(
      appBar: AppBar(title: Text('Order #${o.id}')),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text(o.title, style: t.headlineSmall)),
            _Chip(o),
          ]),
          const SizedBox(height: 4),
          Text('${naira(o.amount)} · from ${o.sellerName}', style: t.bodyMedium?.copyWith(color: StallColors.muted)),
          if (o.verified) ...[const SizedBox(height: 16), ReleaseCodeCard(order: o)],
          if (o.status == 'released' && o.method != null) ...[const SizedBox(height: 16), Tracker(order: o)],
          if (o.status == 'pending')
            o.payable
                ? _note('Waiting for your payment. Pay within ${clock(o.deadline - DateTime.now().millisecondsSinceEpoch)} or the items go back on sale.')
                : _note('This order was placed before online payment started, or its payment window ended. Add the item to your bag again to buy it.'),
          if (o.status == 'under_review') _note('Stall is checking this order. You will see the result here, usually within a few hours.'),
          if (o.status == 'rejected') _note('Payment not accepted${o.note.isEmpty ? '' : ': ${o.note}'}. If you did pay, contact the seller or the Stall team.', bad: true),
          if (o.verified && o.method == 'delivery') _note('Delivering to ${o.addr}'),
          if (o.verified && o.method == 'pickup') _note('${o.stage == 'ready' ? 'Ready for pickup' : 'Pick up'}${o.pickup.isEmpty ? '' : ' at ${o.pickup}'}. Bring your release code.'),
          if (o.verified && ps)
            _note(o.handedAt != null
                ? 'The seller says they handed it over. If you have it, tap I\'ve got it. If not, report a problem on the website by ${when(o.handUntil ?? 0)}. After that the seller is paid automatically.'
                : 'Stall is holding your ${naira(o.amount)} until you have your order.'
                    '${o.holdUntil != null ? ' If you don\'t report a problem, the seller is paid on ${dayOf(o.holdUntil!)}.' : ''}'
                    '${o.refundAt != null ? ' If the seller hasn\'t sent it by ${dayOf(o.refundAt!)}, you\'re refunded automatically.' : ''}'),
          if (o.status == 'disputed')
            _note('A problem was reported on this order: ${o.note}. The money stays on hold while Stall looks at both sides. Reply on the website for now.', bad: true),
          if (o.status == 'refunded') _note('Refunded to you. It can take a few working days to show in your account.${o.note.isEmpty ? '' : ' ${o.note}'}'),
          if (o.status == 'expired') _note(o.note.isEmpty ? 'You did not complete payment in time. Add it to your bag again to retry.' : o.note),
          const SizedBox(height: 20),
          if (o.payable) ...[
            FilledButton(
              key: const Key('payNow'),
              onPressed: _busy ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PayScreen(orders: [o]))).then((_) => _reload()),
              child: const Text('Pay now'),
            ),
            TextButton(
              key: const Key('cancelPending'),
              onPressed: _busy
                  ? null
                  : () async {
                      if (await confirm(context, 'Cancel this order?', 'You haven\'t paid, so nothing is charged.')) {
                        await _act('orders/cancel', {'id': o.id}, 'Order cancelled');
                      }
                    },
              child: const Text('Cancel order', style: TextStyle(color: StallColors.muted)),
            ),
          ],
          if (o.verified && ps) ...[
            FilledButton(
              key: const Key('gotIt'),
              onPressed: _busy
                  ? null
                  : () async {
                      if (await confirm(context, 'Got your order?', 'This pays ${o.sellerName} now. Only tap yes if you have the item and it\'s as described.',
                          yes: 'Yes, I\'ve got it', no: 'Not yet')) {
                        await _act('orders/received', {'id': o.id}, 'Thanks! The seller is being paid');
                      }
                    },
              child: const Text('I\'ve got it'),
            ),
            if (o.early && o.handedAt == null)
              TextButton(
                key: const Key('buyerCancel'),
                onPressed: _busy
                    ? null
                    : () async {
                        if (await confirm(context, 'Cancel this order?', 'The seller hasn\'t packed it yet, so you\'ll get a full refund.',
                            yes: 'Cancel and refund', no: 'Keep it')) {
                          await _act('orders/cancel', {'id': o.id}, 'Cancelled. Your refund is on its way');
                        }
                      },
                child: const Text('Cancel order'),
              ),
            Text('Something wrong? Report a problem from your orders on stall.com.ng. Reporting in the app arrives soon.',
                textAlign: TextAlign.center, style: t.bodySmall),
          ],
          if (o.status == 'released')
            o.rated != null
                ? _note('You rated this seller ${'★' * o.rated!}')
                : Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Text('How was ${o.sellerName}?', style: t.titleMedium),
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          for (var n = 1; n <= 5; n++)
                            IconButton(
                              key: Key('star-$n'),
                              tooltip: '$n star${n > 1 ? 's' : ''}',
                              onPressed: () => setState(() => _stars = n),
                              icon: Icon(n <= _stars ? Icons.star_rounded : Icons.star_outline_rounded, color: starColor, size: 34),
                            ),
                        ]),
                        TextField(
                          controller: _review,
                          maxLength: 300,
                          maxLines: 2,
                          decoration: const InputDecoration(hintText: 'Say something about the item or the seller (optional)'),
                        ),
                        FilledButton(
                          key: const Key('sendRating'),
                          onPressed: _busy || _stars == 0 ? null : () => _act('orders/rate', {'id': o.id, 'stars': _stars, 'text': _review.text.trim()}, 'Thanks for rating'),
                          child: const Text('Send rating'),
                        ),
                      ]),
                    ),
                  ),
        ]),
      ),
    );
  }
}
