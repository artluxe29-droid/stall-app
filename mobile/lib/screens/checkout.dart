import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../api.dart';
import '../bag.dart';
import '../main.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'account_setup.dart' show openLink;
import 'browse.dart';
import 'orders.dart';

/// The bag icon with a count, for app bars and the Home header.
class BagButton extends StatelessWidget {
  const BagButton({super.key});
  @override
  Widget build(BuildContext context) {
    final bag = SessionScope.of(context).bag;
    return ListenableBuilder(
      listenable: bag,
      builder: (context, _) => IconButton(
        key: const Key('bagButton'),
        tooltip: 'Bag',
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BagScreen())),
        icon: Badge(
          isLabelVisible: bag.count > 0,
          label: Text('${bag.count}'),
          backgroundColor: StallColors.indigo,
          child: const Icon(Icons.shopping_bag_outlined),
        ),
      ),
    );
  }
}

/// Adds a line to the bag and says what happened.
void addToBag(BuildContext context, BagLine line) {
  final ok = SessionScope.of(context).bag.add(line);
  toast(context, ok ? 'Added to your bag' : (line.multi ? 'No more in stock' : 'Already in your bag'));
}

class BagScreen extends StatelessWidget {
  const BagScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final bag = SessionScope.of(context).bag;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Bag')),
      body: ListenableBuilder(
        listenable: bag,
        builder: (context, _) {
          if (bag.lines.isEmpty) {
            return EmptyState(
              icon: Icons.shopping_bag_outlined,
              title: 'Your bag is empty',
              text: 'Add something from the shop or a store.',
              action: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Browse')),
            );
          }
          return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
            for (final l in bag.lines) _BagRow(line: l),
            const Divider(height: 32),
            Row(children: [
              Text('Total', style: t.titleLarge),
              const Spacer(),
              Text(naira(bag.total), key: const Key('bagTotal'), style: t.headlineSmall),
            ]),
            const SizedBox(height: 8),
            Text('You pay online, then collect your items or have them delivered where the seller offers it.', style: t.bodySmall),
            const SizedBox(height: 20),
            FilledButton(
              key: const Key('checkout'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CheckoutScreen())),
              child: const Text('Check out'),
            ),
          ]);
        },
      ),
    );
  }
}

class _BagRow extends StatelessWidget {
  const _BagRow({required this.line});
  final BagLine line;
  @override
  Widget build(BuildContext context) {
    final bag = SessionScope.of(context).bag;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox.square(dimension: 56, child: Photo(path: line.img, cat: line.cat))),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(line.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(line.seller, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(naira(line.total), style: const TextStyle(fontWeight: FontWeight.w800)),
          if (line.multi)
            Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                  key: Key('dec-${line.id}'),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Remove one',
                  onPressed: () => bag.dec(line.id),
                  icon: const Icon(Icons.remove_circle_outline)),
              Text('${line.q}', style: const TextStyle(fontWeight: FontWeight.w700)),
              IconButton(
                  key: Key('inc-${line.id}'),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Add one',
                  onPressed: line.canAdd ? () => bag.add(line) : null,
                  icon: const Icon(Icons.add_circle_outline)),
            ])
          else
            TextButton(key: Key('rm-${line.id}'), onPressed: () => bag.remove(line.id), child: const Text('Remove')),
        ]),
      ]),
    );
  }
}

/// Check out: review, agree to how Stall holds the money, then place the orders (one per seller).
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});
  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  bool _agree = false, _busy = false, _nudge = false;

  Future<void> _place() async {
    if (!_agree) return setState(() => _nudge = true);
    setState(() => _busy = true);
    final s = SessionScope.of(context);
    try {
      final r = await s.api.post('orders/create', {'items': s.bag.apiItems, 'consent': true});
      final orders = (r['orders'] as List? ?? const []).map((e) => Order(e as Map<String, dynamic>)).toList();
      s.bag.clear();
      if (!mounted) return;
      // The bag is now empty and the orders exist, so going back from paying returns to the app (they wait in Orders).
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => PayScreen(orders: orders)), (r) => r.isFirst);
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bag = SessionScope.of(context).bag;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Check out')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
        for (final l in bag.lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Expanded(child: Text('${l.q > 1 ? '${l.q} × ' : ''}${l.title}', style: const TextStyle(fontWeight: FontWeight.w600))),
              Text(naira(l.total), style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
          ),
        const Divider(height: 28),
        Row(children: [Text('Total', style: t.titleLarge), const Spacer(), Text(naira(bag.total), style: t.headlineSmall)]),
        const SizedBox(height: 12),
        Text('Next you pay each seller securely through Paystack by card, transfer or USSD. Stall confirms the payment and gives you a code to release your order.',
            style: t.bodyMedium?.copyWith(color: StallColors.muted)),
        const SizedBox(height: 16),
        Material(
          color: StallColors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: _nudge && !_agree ? StallColors.red : StallColors.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: CheckboxListTile(
            key: const Key('agree'),
            value: _agree,
            onChanged: (v) => setState(() => _agree = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text.rich(TextSpan(children: [
              TextSpan(text: 'I agree that Stall holds my payment until I have the item. I\'ll check it before I give my release code, because '),
              TextSpan(text: 'giving the code means I accept it', style: TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: '. I\'ve read the buyer rules and Terms.'),
            ])),
            subtitle: _nudge && !_agree ? const Text('Tick the box to agree to how Stall holds your payment.', style: TextStyle(color: StallColors.red)) : null,
          ),
        ),
        Wrap(spacing: 4, children: [
          TextButton(onPressed: () => openLink('/rules'), child: const Text('Buyer rules')),
          TextButton(onPressed: () => openLink('/terms'), child: const Text('Terms')),
        ]),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('placeOrder'),
          onPressed: _busy || bag.lines.isEmpty ? null : _place,
          child: Text(_busy ? 'Placing order…' : 'Continue'),
        ),
      ]),
    );
  }
}

/// Opens Paystack's checkout page and returns the payment reference once Paystack sends the buyer back,
/// or null if they closed it. Tests replace this.
typedef PaystackOpener = Future<String?> Function(BuildContext context, String url);
PaystackOpener openPaystack = (context, url) =>
    Navigator.of(context).push<String>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => PaystackScreen(url: url)));

/// Pay for the new orders: pickup or delivery per seller, where to deliver, then one Paystack payment for all of them.
class PayScreen extends StatefulWidget {
  const PayScreen({super.key, required this.orders});
  final List<Order> orders;
  @override
  State<PayScreen> createState() => _PayScreenState();
}

class _PayScreenState extends State<PayScreen> {
  late final _method = {for (final o in widget.orders) o.id: 'pickup'};
  final _addr = TextEditingController();
  late final _phone = TextEditingController();
  Timer? _tick;
  bool _busy = false;
  String? _err;

  List<Order> get _payable => widget.orders.where((o) => o.payable).toList();
  bool get _anyDelivery => _payable.any((o) => _method[o.id] == 'delivery');
  int get _total => _payable.fold(0, (s, o) => s + o.sub + (_method[o.id] == 'delivery' ? o.deliv.fee : 0));

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_phone.text.isEmpty) _phone.text = SessionScope.of(context).user?.phone ?? '';
  }

  @override
  void dispose() {
    _tick?.cancel();
    _addr.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    if (_anyDelivery && _addr.text.trim().length < 5) {
      return setState(() => _err = 'Enter where your order should be brought (hostel, room, landmark).');
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    final api = SessionScope.of(context).api;
    try {
      final r = await api.post('pay/start', {
        'kind': 'cart',
        'orders': [for (final o in _payable) {'id': o.id, 'method': _method[o.id]}],
        'addr': _addr.text.trim(),
        'dphone': _phone.text.trim(),
      });
      if (!mounted) return;
      final ref = await openPaystack(context, r['url'].toString()) ?? r['ref']?.toString();
      if (!mounted || ref == null) return;
      // Ask Stall to check the payment with Paystack. If they closed Paystack without paying, this says so.
      try {
        await api.post('pay/confirm', {'reference': ref});
      } on ApiError catch (e) {
        if (e.status != 402) rethrow;
        if (mounted) setState(() => _err = 'Payment not finished. If you were charged, it will show in your orders shortly.');
        return;
      }
      final mine = await api.get('orders/mine');
      final ids = widget.orders.map((o) => o.id).toSet();
      final done = (mine['orders'] as List? ?? const []).map((e) => Order(e as Map<String, dynamic>)).where((o) => ids.contains(o.id)).toList();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => PaidScreen(orders: done)));
    } on ApiError catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final ok = await confirm(context, _payable.length > 1 ? 'Cancel these ${_payable.length} orders?' : 'Cancel this order?',
        'You haven\'t paid, so nothing is charged. The items go back on sale.');
    if (!ok || !mounted) return;
    final api = SessionScope.of(context).api;
    try {
      for (final o in _payable) {
        await api.post('orders/cancel', {'id': o.id});
      }
      if (!mounted) return;
      toast(context, _payable.length > 1 ? 'Orders cancelled' : 'Order cancelled');
      Navigator.pop(context);
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = _payable;
    if (p.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
            icon: Icons.timer_off_outlined, title: 'Payment window expired', text: 'You did not complete payment in time. Add the items to your bag again to retry.'),
      );
    }
    final left = p.map((o) => o.deadline).reduce((a, b) => a < b ? a : b) - DateTime.now().millisecondsSinceEpoch;
    return Scaffold(
      appBar: AppBar(title: Text(p.length > 1 ? 'Pay ${p.length} sellers' : 'Pay ${p.first.sellerName}')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
        for (final o in p) ...[
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(o.title, style: t.titleMedium)),
                  Text(naira(o.sub), style: const TextStyle(fontWeight: FontWeight.w800)),
                ]),
                Text(o.sellerName, style: t.bodySmall),
                RadioGroup<String>(
                  groupValue: _method[o.id],
                  onChanged: (v) => setState(() => _method[o.id] = v ?? 'pickup'),
                  child: Column(children: [
                    RadioListTile<String>(
                      key: Key('pickup-${o.id}'),
                      contentPadding: EdgeInsets.zero,
                      value: 'pickup',
                      title: const Text('Pick up'),
                      subtitle: Text('${o.pickup.isEmpty ? '' : 'At ${o.pickup}. '}Free. Arrange a time with the seller.'),
                    ),
                    if (o.deliv.on)
                      RadioListTile<String>(
                        key: Key('delivery-${o.id}'),
                        contentPadding: EdgeInsets.zero,
                        value: 'delivery',
                        title: Text('Delivery · ${o.deliv.fee > 0 ? naira(o.deliv.fee) : 'free'}'),
                        subtitle: Text('${o.deliv.note.isEmpty ? '' : '${o.deliv.note}. '}The seller brings it to you.'),
                      ),
                  ]),
                ),
              ]),
            ),
          ),
        ],
        if (_anyDelivery) ...[
          TextField(
            key: const Key('addr'),
            controller: _addr,
            maxLength: 160,
            decoration: const InputDecoration(labelText: 'Where should they bring it?', hintText: 'Hostel, room number or landmark', counterText: ''),
          ),
          const SizedBox(height: 12),
          TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              maxLength: 20,
              decoration: const InputDecoration(labelText: 'Phone for delivery', counterText: '')),
          const SizedBox(height: 12),
        ],
        Row(children: [Text('Total', style: t.titleLarge), const Spacer(), Text(naira(_total), key: const Key('payTotal'), style: t.headlineSmall)]),
        const SizedBox(height: 8),
        Text('Pay by card, bank transfer or USSD on Paystack\'s secure page. Stall holds your money until you have your order, and gives you a release code for the seller.',
            style: t.bodySmall),
        if (_err != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_err!, key: const Key('payError'), style: const TextStyle(color: StallColors.red))),
        const SizedBox(height: 16),
        FilledButton(key: const Key('pay'), onPressed: _busy ? null : _pay, child: Text(_busy ? 'Opening Paystack…' : 'Pay ${naira(_total)} securely')),
        const SizedBox(height: 10),
        Text.rich(
            TextSpan(children: [const TextSpan(text: 'Complete payment within '), TextSpan(text: clock(left), style: const TextStyle(fontWeight: FontWeight.w700)), const TextSpan(text: '.')]),
            textAlign: TextAlign.center),
        TextButton(onPressed: _busy ? null : _cancel, child: Text(p.length > 1 ? 'Cancel these orders' : 'Cancel this order', style: const TextStyle(color: StallColors.muted))),
      ]),
    );
  }
}

/// Paystack's checkout inside the app. When Paystack sends the buyer back to stall.com.ng/app?reference=…,
/// this closes and returns the reference instead of opening the website.
class PaystackScreen extends StatefulWidget {
  const PaystackScreen({super.key, required this.url});
  final String url;
  @override
  State<PaystackScreen> createState() => _PaystackScreenState();
}

class _PaystackScreenState extends State<PaystackScreen> {
  late final WebViewController _c;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => mounted ? setState(() => _progress = p) : null,
        onNavigationRequest: (req) {
          final u = Uri.tryParse(req.url);
          // Bank apps and USSD links open outside the app; Paystack keeps checking the payment meanwhile.
          if (u != null && u.scheme != 'https' && u.scheme != 'http' && u.scheme != 'about') {
            launchUrl(u, mode: LaunchMode.externalApplication).catchError((_) => false);
            return NavigationDecision.prevent;
          }
          final ref = u?.queryParameters['reference'] ?? u?.queryParameters['trxref'];
          if (u != null && u.host == Uri.parse(apiBase).host && ref != null) {
            Navigator.pop(context, ref);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Pay securely'),
          leading: IconButton(tooltip: 'Close', icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
          bottom: _progress < 100 ? PreferredSize(preferredSize: const Size.fromHeight(3), child: LinearProgressIndicator(value: _progress / 100)) : null,
        ),
        body: WebViewWidget(controller: _c),
      );
}

/// After paying: each seller's release code, and how to hand it over.
class PaidScreen extends StatelessWidget {
  const PaidScreen({super.key, required this.orders});
  final List<Order> orders;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final paid = orders.where((o) => o.verified || o.status == 'released').toList();
    final review = orders.where((o) => o.status == 'under_review').toList();
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false, actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))]),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: [
        const Icon(Icons.check_circle_rounded, size: 72, color: StallColors.green),
        const SizedBox(height: 8),
        Text(paid.isNotEmpty ? 'Payment verified' : 'Payment received', style: t.displaySmall, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        for (final o in paid) Padding(padding: const EdgeInsets.only(bottom: 12), child: ReleaseCodeCard(order: o)),
        for (final o in review)
          Card(
            child: ListTile(
              title: Text(o.title),
              subtitle: Text(o.note.isNotEmpty ? o.note : 'The Stall team is checking your payment. You\'ll see your release code in Orders once it\'s approved.'),
            ),
          ),
        if (paid.isEmpty && review.isEmpty)
          const Text('Your orders will update in a moment. Check Orders for your release code.', textAlign: TextAlign.center),
      ]),
    );
  }
}

Future<bool> confirm(BuildContext context, String title, String text, {String yes = 'Yes', String no = 'No'}) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(no)),
          FilledButton(key: const Key('confirmYes'), onPressed: () => Navigator.pop(ctx, true), child: Text(yes)),
        ],
      ),
    ) ??
    false;
