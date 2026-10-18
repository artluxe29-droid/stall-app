import 'dart:convert';

import 'package:flutter/material.dart';

import '../api.dart';
import '../bank.dart';
import '../main.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'account_setup.dart' show phoneError, VerifyStudentScreen;
import 'browse.dart' show Photo, shareThing;
import 'bulk.dart';
import 'checkout.dart' show confirm, openPaystack;
import 'extras.dart' show StoreQrScreen;
import 'sell.dart';
import 'stores.dart';

/// Prices for store extras, the same as the server's PRICE and STORE_FEE.
const storeFee = 5000;
const reachPrice = {'state': 2000, 'national': 5000};
const featurePrice = {3: 500, 7: 1000};

/// The icons a store can use instead of a logo (the web app's STORE_ICONS).
const storeIcons = ['bowl', 'bread', 'cup', 'book', 'shirt', 'laptop', 'headphones', 'scissors', 'bag', 'store'];

/// Your store, or null if you haven't opened one.
Future<Store?> loadMyStore(Api api) async {
  final r = await api.get('stores', {'mine': '1'});
  final l = (r['stores'] as List? ?? const []);
  return l.isEmpty ? null : Store(l.first as Map<String, dynamic>);
}

/// Pays Stall for something (store fee, reach, featuring) through Paystack, the same way checkout does.
/// Returns true once paid. A free store code or Stall credit can finish it without Paystack.
Future<bool> payStall(BuildContext context, Map<String, dynamic> body) async {
  final api = SessionScope.of(context).api;
  final r = await api.post('pay/start', body);
  if (r['ok'] == true) return true;
  if (!context.mounted) return false;
  final ref = await openPaystack(context, r['url'].toString()) ?? r['ref']?.toString();
  if (ref == null) return false;
  try {
    await api.post('pay/confirm', {'reference': ref});
    return true;
  } on ApiError catch (e) {
    if (e.status == 402) throw ApiError('Payment not finished. If you were charged, it will show here shortly.');
    rethrow;
  }
}

/// Featuring and reach: offers the person's Stall credit (from invites) first, then pays the rest with [payStall].
/// Returns true once paid. Refreshes the account afterwards, since credit may have been used.
Future<bool> payWithCredit(BuildContext context, Map<String, dynamic> body) async {
  final s = SessionScope.of(context);
  final credit = s.user?.credit ?? 0;
  if (credit > 0) {
    final pct = (s.config['creditPct'] as num?)?.toInt() ?? 50;
    final use = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Use your credit?'),
        content: Text('You have ${naira(credit)} Stall credit. It can pay up to $pct% of this; the rest is paid on Paystack.'),
        actions: [
          TextButton(key: const Key('noCredit'), onPressed: () => Navigator.pop(ctx, false), child: const Text('Pay it all')),
          FilledButton(key: const Key('useCredit'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Use credit')),
        ],
      ),
    );
    if (use == null || !context.mounted) return false;
    if (use) body = {...body, 'credit': true};
  }
  final paid = await payStall(context, body);
  if (paid) await s.refresh();
  return paid;
}

/// Square store logo, shrunk like a listing photo. Tests replace this.
Future<String?> Function(BuildContext context) pickLogo = (context) async => (await pickListingPhotos(context, 1)).firstOrNull;

/// A row of store icons to choose from.
class IconPicker extends StatelessWidget {
  const IconPicker({super.key, required this.value, required this.cat, required this.onPick});
  final String value, cat;
  final ValueChanged<String> onPick;
  @override
  Widget build(BuildContext context) {
    final c = Category.of(cat);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final k in storeIcons)
          InkWell(
            key: Key('icon-$k'),
            onTap: () => onPick(k),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: k == value ? c.bg : StallColors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: k == value ? c.fg : StallColors.line, width: k == value ? 2 : 1),
              ),
              child: Icon(storeIcon(k, cat), color: k == value ? c.fg : StallColors.muted),
            ),
          ),
      ],
    );
  }
}

/// Open your store: name, category, icon or logo, about, pickup spot, WhatsApp, payout account,
/// then the one-time fee through Paystack, or a free store code.
class OpenStoreScreen extends StatefulWidget {
  const OpenStoreScreen({super.key});
  @override
  State<OpenStoreScreen> createState() => _OpenStoreScreenState();
}

class _OpenStoreScreenState extends State<OpenStoreScreen> {
  final _form = GlobalKey<FormState>();
  final _c = {
    for (final k in ['name', 'desc', 'spot', 'phone', 'code']) k: TextEditingController(),
  };
  String _cat = Category.all.first.id, _icon = 'bowl';
  String? _logo, _bankMsg, _error;
  BankChoice? _acct;
  bool _busy = false, _tried = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c['phone']!.text.isEmpty) _c['phone']!.text = SessionScope.of(context).user?.phone ?? '';
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String v(String k) => _c[k]!.text.trim();
  bool get _free => v('code').isNotEmpty;

  Future<void> _submit({bool retried = false}) async {
    setState(() {
      _tried = true;
      _error = null;
    });
    if (!_form.currentState!.validate()) return;
    if (_acct == null) return setState(() => _bankMsg = 'Enter your 10-digit account number, then tap "Verify account".');
    setState(() => _busy = true);
    final s = SessionScope.of(context);
    try {
      final ok = await payStall(context, {
        'kind': 'store',
        'd': {
          'name': v('name'),
          'emoji': _icon,
          'cat': _cat,
          'desc': v('desc'),
          'spot': v('spot'),
          'phone': v('phone'),
          'bank_code': _acct!.code,
          'acct': _acct!.acct,
          'acctName': _acct!.name,
          'bank_manual': _acct!.manual ? '1' : '',
          'logo': ?_logo,
        },
        if (_free) 'code': v('code').toUpperCase(),
      });
      if (!ok || !mounted) return;
      await s.refresh();
      if (!mounted) return;
      toast(context, _free ? 'Your store is open, free with your code' : 'Store fee paid. Your store is open');
      Navigator.pop(context, true);
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.data['need'] == 'seller_ok' && !retried) {
        setState(() => _busy = false);
        if (await sellerRules(context)) return _submit(retried: true);
        return;
      }
      setState(() => _error = e.message);
      if (e.data['verify'] == true) Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VerifyStudentScreen()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    final t = Theme.of(context).textTheme;
    InputDecoration dec(String l, {String? hint}) => InputDecoration(labelText: l, hintText: hint, counterText: '');
    return Scaffold(
      appBar: AppBar(title: const Text('Open your store')),
      body: Form(
        key: _form,
        autovalidateMode: _tried ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
        // Every field is built (not a lazy list), so the form can check them all, even ones scrolled away.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'A store gives your business one page with all your items, a logo, open and closed hours, and delivery. Single items stay free to list.',
                style: t.bodyMedium?.copyWith(color: StallColors.muted),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('st-name'),
                controller: _c['name'],
                maxLength: 40,
                textCapitalization: TextCapitalization.words,
                decoration: dec('Store name', hint: 'e.g. Iya Debo\'s Canteen'),
                validator: (x) => (x ?? '').trim().length < 2 ? 'Enter a store name.' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const Key('st-cat'),
                isExpanded: true,
                initialValue: _cat,
                decoration: dec('Category'),
                items: [for (final c in Category.all) DropdownMenuItem(value: c.id, child: Text(c.name))],
                onChanged: (x) => setState(() => _cat = x ?? _cat),
              ),
              const SizedBox(height: 16),
              Text('Icon', style: t.titleSmall),
              const SizedBox(height: 8),
              IconPicker(value: _icon, cat: _cat, onPick: (k) => setState(() => _icon = k)),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (_logo != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.memory(base64Decode(_logo!.split(',').last), width: 56, height: 56, fit: BoxFit.cover),
                      ),
                    ),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('st-logo'),
                      onPressed: () async {
                        final l = await pickLogo(context);
                        if (l != null && mounted) setState(() => _logo = l);
                      },
                      icon: const Icon(Icons.image_outlined),
                      label: Text(_logo == null ? 'Add a logo (recommended)' : 'Change logo'),
                    ),
                  ),
                ],
              ),
              Text('A logo makes your store easy to tell apart. Without one, buyers see the icon.', style: t.bodySmall),
              const SizedBox(height: 12),
              TextFormField(
                controller: _c['desc'],
                maxLength: 120,
                maxLines: 2,
                decoration: dec('About your store', hint: 'What you sell and when you\'re open'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('st-spot'),
                controller: _c['spot'],
                maxLength: 40,
                decoration: dec('Pickup spot', hint: 'e.g. Cafeteria, Stall 4'),
                validator: (x) => (x ?? '').trim().length < 2 ? 'Where can buyers find you?' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('st-phone'),
                controller: _c['phone'],
                keyboardType: TextInputType.phone,
                decoration: dec('WhatsApp number'),
                validator: (x) => phoneError((x ?? '').trim()),
              ),
              const SizedBox(height: 16),
              Text('Payout account', style: t.titleMedium),
              Text('Where Stall sends the money for your orders.', style: t.bodySmall),
              const SizedBox(height: 10),
              BankBox(
                keyPrefix: 'st',
                error: _bankMsg,
                onChanged: (c) => setState(() {
                  _acct = c;
                  if (c != null) _bankMsg = null;
                }),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: _free ? StallColors.cream2 : StallColors.limeTint, borderRadius: BorderRadius.circular(14)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_free ? 'Free with your store code' : 'One-time store fee: ${naira(storeFee)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text(_free ? 'Your code opens the store with no fee.' : 'Paid securely with Paystack when you open your store.', style: t.bodySmall),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Have a free store code?'),
                children: [
                  TextField(
                    key: const Key('st-code'),
                    controller: _c['code'],
                    maxLength: 20,
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (_) => setState(() {}),
                    decoration: dec('Free store code', hint: 'e.g. FREE-AB12CD'),
                  ),
                ],
              ),
              Text(
                'Stall holds each buyer\'s payment until they have their order, then sends it to your account minus a sale fee of ${s.feeDesc}.',
                style: t.bodySmall,
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _error!,
                    key: const Key('st-error'),
                    style: const TextStyle(color: StallColors.red, fontWeight: FontWeight.w600),
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('st-open'),
                onPressed: _busy ? null : _submit,
                child: Text(_busy ? 'Opening…' : (_free ? 'Open my store free' : 'Pay ${naira(storeFee)} and open store')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Your store, to run it: open or closed, items, look, delivery, reach and featuring.
class MyStoreScreen extends StatelessWidget {
  const MyStoreScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Your store')),
    body: const MyStoreView(),
  );
}

class MyStoreView extends StatefulWidget {
  const MyStoreView({super.key, this.heading = false});

  /// Show a "Your store" title (when it's the Sell tab itself, for businesses).
  final bool heading;
  @override
  State<MyStoreView> createState() => _MyStoreViewState();
}

class _MyStoreViewState extends State<MyStoreView> {
  Future<Store?>? _f;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _f ??= loadMyStore(SessionScope.of(context).api);
  }

  Future<void> _reload() async {
    final f = loadMyStore(SessionScope.of(context).api);
    setState(() {
      _f = f;
    });
    await f.catchError((_) => null);
  }

  Future<void> _post(String path, Map<String, dynamic> body, String done) async {
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

  Future<void> _pay(Map<String, dynamic> body, String done) async {
    setState(() => _busy = true);
    try {
      if (await payWithCredit(context, body) && mounted) {
        toast(context, done);
        await _reload();
      }
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _look(Store st) async {
    var icon = st.emoji.isEmpty ? 'store' : st.emoji;
    final r = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      backgroundColor: StallColors.cream,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Logo and icon', style: Theme.of(ctx).textTheme.headlineSmall),
                const SizedBox(height: 12),
                IconPicker(value: icon, cat: st.cat, onPick: (k) => set(() => icon = k)),
                const SizedBox(height: 12),
                FilledButton(key: const Key('lookIcon'), onPressed: () => Navigator.pop(ctx, {'emoji': icon}), child: const Text('Use this icon')),
                OutlinedButton.icon(
                  key: const Key('lookLogo'),
                  onPressed: () async {
                    final l = await pickLogo(ctx);
                    if (l != null && ctx.mounted) Navigator.pop(ctx, {'logo': l});
                  },
                  icon: const Icon(Icons.image_outlined),
                  label: Text(st.logo == null ? 'Upload a logo' : 'Change logo'),
                ),
                if (st.logo != null)
                  TextButton(
                    key: const Key('lookNoLogo'),
                    onPressed: () => Navigator.pop(ctx, {'removeLogo': true}),
                    child: const Text('Remove logo (show the icon)', style: TextStyle(color: StallColors.red)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (r != null && mounted) await _post('stores/look', r, 'Saved');
  }

  Future<void> _stock(StoreItem it) async {
    // The typed value, not a controller: a controller disposed here would still be in use while the dialog animates closed.
    var typed = it.qtyLeft == null ? '' : '${it.qtyLeft}';
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('How many do you have?'),
        content: TextFormField(
          key: const Key('itemStock'),
          initialValue: typed,
          onChanged: (x) => typed = x,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Leave empty for no limit'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(key: const Key('itemStockSave'), onPressed: () => Navigator.pop(ctx, typed.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (r == null || !mounted) return;
    await _post('stores/item/stock', {'id': it.id, 'qty': r.isEmpty ? '' : int.tryParse(r) ?? ''}, 'Stock updated');
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Store?>(
    future: _f,
    builder: (context, snap) {
      if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (snap.hasError) {
        return EmptyState(
          icon: Icons.wifi_off_rounded,
          title: 'Couldn\'t load your store',
          text: snap.error is ApiError ? (snap.error as ApiError).message : 'Pull down to try again.',
        );
      }
      final st = snap.data;
      return RefreshIndicator(onRefresh: _reload, child: st == null ? _none(context) : _store(context, st));
    },
  );

  Widget _none(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        if (widget.heading) Text('Your store', style: t.headlineMedium),
        const SizedBox(height: 24),
        Icon(Icons.storefront_rounded, size: 64, color: StallColors.indigo),
        const SizedBox(height: 12),
        Text('Open your store', style: t.headlineSmall, textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text(
          'One page for your business: a menu of items, your logo, open and closed, and delivery. ${naira(storeFee)} once, or free with a store code.',
          textAlign: TextAlign.center,
          style: t.bodyMedium?.copyWith(color: StallColors.muted),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          key: const Key('openStore'),
          onPressed: () async {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OpenStoreScreen()));
            if (mounted) _reload();
          },
          icon: const Icon(Icons.add_business_rounded),
          label: const Text('Open a store'),
        ),
      ],
    );
  }

  Widget _store(BuildContext context, Store st) {
    final t = Theme.of(context).textTheme;
    final now = DateTime.now().millisecondsSinceEpoch;
    final reachUntil = (st.raw['reachUntil'] as num?)?.toInt() ?? 0, featUntil = (st.raw['featuredUntil'] as num?)?.toInt() ?? 0;
    final reached = st.reach != 'school' && reachUntil > now;
    final home = [SessionScope.of(context).user?.area, st.school].where((x) => (x ?? '').isNotEmpty).join(' and ');
    Widget section(String title, List<Widget> kids) => Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: t.titleMedium),
            const SizedBox(height: 8),
            ...kids,
          ],
        ),
      ),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (widget.heading)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Text('Your store', style: t.headlineMedium),
          ),
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    StoreAvatar(store: st, size: 64),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(st.name, style: t.titleLarge),
                          Text(
                            '${st.items.length} item${st.items.length == 1 ? '' : 's'}${st.featured ? ' · Featured' : ''}${st.founding > 0 ? ' · Founding Seller #${st.founding}' : ''}',
                            style: t.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  key: const Key('storeOpen'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(st.open ? 'Open: taking orders' : 'Closed: buyers can look but not order'),
                  value: st.open,
                  onChanged: _busy ? null : (_) => _post('stores/toggle', {}, st.open ? 'Store closed' : 'Store open'),
                ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: const Key('seeStore'),
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StoreScreen(store: st))),
                        child: const Text('See your store'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('shareStore'),
                        onPressed: () => shareThing(context, id: st.id, text: 'Order from ${st.name} on Stall'),
                        icon: const Icon(Icons.ios_share_rounded, size: 18),
                        label: const Text('Share'),
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  key: const Key('qrStore'),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StoreQrScreen(store: st))),
                  icon: const Icon(Icons.qr_code_rounded, size: 18),
                  label: const Text('Store QR card to print or share'),
                ),
              ],
            ),
          ),
        ),
        section('Items', [
          FilledButton.icon(
            key: const Key('addStoreItem'),
            onPressed: () async {
              final added = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => StoreItemScreen(cat: st.cat)));
              if (added == true) _reload();
            },
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add an item'),
          ),
          TextButton.icon(
            key: const Key('bulkStore'),
            onPressed: () async {
              final added = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => BulkAddScreen(storeName: st.name)));
              if (added == true) _reload();
            },
            icon: const Icon(Icons.library_add_outlined),
            label: const Text('Add several at once'),
          ),
          if (st.items.isEmpty) const Padding(padding: EdgeInsets.only(top: 12), child: Text('No items yet. Add what you sell so buyers can order.')),
          for (final it in st.items) _itemRow(context, st, it),
        ]),
        section('Look and delivery', [
          ListTile(
            key: const Key('storeLook'),
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.palette_outlined, color: StallColors.indigo),
            title: const Text('Logo and icon'),
            subtitle: Text(st.logo != null ? 'Your logo shows on your store' : 'Showing an icon. Add a logo to stand out.'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _busy ? null : () => _look(st),
          ),
          ListTile(
            key: const Key('storeDelivery'),
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.local_shipping_outlined, color: StallColors.indigo),
            title: const Text('Delivery'),
            subtitle: Text(st.deliv.on ? 'You deliver${st.deliv.fee > 0 ? ' for ${naira(st.deliv.fee)}' : ' for free'}' : 'Off: buyers collect at ${st.spot}'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () async {
              final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => DeliveryScreen(store: st.deliv)));
              if (saved == true) _reload();
            },
          ),
        ]),
        section(reached ? '${st.reach == 'national' ? 'Nationwide' : 'State-wide'} until ${dayOf(reachUntil)}' : 'Reach more buyers', [
          Text(
            'Your store shows to people ${home.isEmpty ? 'near you' : 'in $home'}. Upgrade to show it across ${st.state.isEmpty ? 'your state' : st.state}, or across Nigeria, for 30 days.',
            style: t.bodySmall,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('reach-state'),
                  onPressed: _busy ? null : () => _pay({'kind': 'reach', 'target': st.id, 'level': 'state'}, 'Store reach upgraded'),
                  child: Text('State-wide · ${naira(reachPrice['state']!)}', textAlign: TextAlign.center),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  key: const Key('reach-national'),
                  onPressed: _busy ? null : () => _pay({'kind': 'reach', 'target': st.id, 'level': 'national'}, 'Store reach upgraded'),
                  child: Text('Nationwide · ${naira(reachPrice['national']!)}', textAlign: TextAlign.center),
                ),
              ),
            ],
          ),
        ]),
        section(st.featured && featUntil > now ? 'Featured until ${dayOf(featUntil)}' : 'Get more buyers', [
          Text(st.featured ? 'Add more days to stay at the top.' : 'Featured stores show first, with a Featured tag.', style: t.bodySmall),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final d in const [3, 7]) ...[
                if (d == 7) const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    key: Key('feature-$d'),
                    style: d == 7 ? null : FilledButton.styleFrom(backgroundColor: StallColors.cream2, foregroundColor: StallColors.indigo),
                    onPressed: _busy ? null : () => _pay({'kind': 'boost', 'target': st.id, 'days': d}, 'Your store is featured'),
                    child: Text('${st.featured ? 'Add' : 'Feature for'} $d days · ${naira(featurePrice[d]!)}', textAlign: TextAlign.center),
                  ),
                ),
              ],
            ],
          ),
        ]),
        const SizedBox(height: 8),
        TextButton(
          key: const Key('deleteStore'),
          onPressed: _busy
              ? null
              : () async {
                  if (await confirm(
                    context,
                    'Delete your store?',
                    'Your store and all its items are removed for good. Orders already placed carry on as normal. The store fee isn\'t refunded.',
                    yes: 'Delete store',
                    no: 'Keep it',
                  )) {
                    await _post('stores/delete', {}, 'Store deleted');
                  }
                },
          child: const Text('Delete store', style: TextStyle(color: StallColors.red)),
        ),
      ],
    );
  }

  Widget _itemRow(BuildContext context, Store st, StoreItem it) {
    final t = Theme.of(context).textTheme;
    final rv = switch (it.raw['review']) {
      'checking' => 'Checking the photo…',
      'review' => 'Needs a look by the Stall team',
      'rejected' => 'Not approved${(it.raw['reviewNote'] ?? '').toString().isEmpty ? '' : ': ${it.raw['reviewNote']}'}',
      _ => null,
    };
    final soldOut = it.qtyLeft == 0;
    return Padding(
      key: Key('item-${it.id}'),
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox.square(
              dimension: 56,
              child: Photo(path: it.imgs.firstOrNull, cat: st.cat, icon: storeIcon(st.emoji, st.cat)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  it.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${naira(it.price)} · ${it.qtyLeft == null
                      ? 'No stock limit'
                      : soldOut
                      ? 'Sold out'
                      : '${it.qtyLeft} left'}',
                  style: t.bodySmall,
                ),
                if (rv != null) Text(rv, style: t.bodySmall?.copyWith(color: it.raw['review'] == 'rejected' ? StallColors.red : StallColors.muted)),
                Wrap(
                  spacing: 4,
                  children: [
                    TextButton(
                      key: Key('avail-${it.id}'),
                      onPressed: _busy ? null : () => _post('stores/item/avail', {'id': it.id}, it.avail ? 'Marked sold out' : 'Marked available'),
                      child: Text(it.avail ? 'Mark sold out' : 'Mark available'),
                    ),
                    TextButton(key: Key('stock-${it.id}'), onPressed: _busy ? null : () => _stock(it), child: const Text('Stock')),
                    TextButton(
                      key: Key('del-${it.id}'),
                      onPressed: _busy
                          ? null
                          : () async {
                              if (await confirm(context, 'Delete this item?', '"${it.title}" is removed from your store.', yes: 'Delete', no: 'Keep it')) {
                                await _post('stores/item/delete', {'id': it.id}, 'Item deleted');
                              }
                            },
                      child: const Text('Delete', style: TextStyle(color: StallColors.red)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Add an item to your store: photos, name, price, details and how many you have.
class StoreItemScreen extends StatefulWidget {
  const StoreItemScreen({super.key, required this.cat});
  final String cat;
  @override
  State<StoreItemScreen> createState() => _StoreItemScreenState();
}

class _StoreItemScreenState extends State<StoreItemScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController(), _price = TextEditingController(), _desc = TextEditingController(), _qty = TextEditingController();
  final _photos = <String>[];
  String? _photoErr, _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_title, _price, _desc, _qty]) {
      c.dispose();
    }
    super.dispose();
  }

  int get _priceN => int.tryParse(_price.text.replaceAll(RegExp(r'\D'), '')) ?? 0;

  Future<void> _save({bool retried = false}) async {
    setState(() {
      _error = null;
      _photoErr = _photos.isEmpty ? 'Add at least one photo.' : null;
    });
    if (!_form.currentState!.validate() || _photos.isEmpty) return;
    setState(() => _busy = true);
    try {
      await SessionScope.of(context).api.post('stores/item', {
        'title': _title.text.trim(),
        'price': _priceN,
        'desc': _desc.text.trim(),
        'qty': _qty.text.trim().isEmpty ? '' : int.tryParse(_qty.text.trim()) ?? '',
        'imgs': _photos,
      });
      if (!mounted) return;
      toast(context, 'Added. Stall is checking the photo; it shows to buyers in a moment.');
      Navigator.pop(context, true);
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.data['need'] == 'seller_ok' && !retried) {
        setState(() => _busy = false);
        if (await sellerRules(context)) return _save(retried: true);
        return;
      }
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    final t = Theme.of(context).textTheme;
    final p = _priceN;
    return Scaffold(
      appBar: AppBar(title: const Text('Add an item')),
      body: Form(
        key: _form,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Photos (1 to 8)', style: t.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _photos.length; i++)
                    GestureDetector(
                      onTap: () => setState(() => _photos.removeAt(i)),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(base64Decode(_photos[i].split(',').last), width: 76, height: 76, fit: BoxFit.cover),
                      ),
                    ),
                  if (_photos.length < 8)
                    InkWell(
                      key: const Key('it-photos'),
                      onTap: () async {
                        final got = await pickListingPhotos(context, 8 - _photos.length);
                        if (mounted) setState(() => _photos.addAll(got.where((x) => x.length <= 450000)));
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: StallColors.card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: StallColors.line),
                        ),
                        child: Icon(Icons.add_a_photo_outlined, color: StallColors.indigo),
                      ),
                    ),
                ],
              ),
              if (_photos.isNotEmpty) Text('Tap a photo to remove it.', style: t.bodySmall),
              if (_photoErr != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_photoErr!, style: const TextStyle(color: StallColors.red)),
                ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('it-title'),
                controller: _title,
                maxLength: 80,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Item name', hintText: 'e.g. Jollof rice and chicken', counterText: ''),
                validator: (x) => (x ?? '').trim().length < 3 ? 'Enter a name of 3 to 80 characters.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('it-price'),
                controller: _price,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Price', prefixText: '₦ '),
                validator: (_) => _priceN < 500 ? 'The minimum price is ₦500.' : null,
              ),
              if (p >= 500)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('You get ${naira(p - s.feeOf(p))} per sale (Stall\'s fee ${naira(s.feeOf(p))}).', style: t.bodySmall),
                ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('it-qty'),
                controller: _qty,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'How many do you have? (optional)', hintText: 'Leave empty for no limit'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _desc,
                maxLength: 300,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Details (optional)'),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: StallColors.red, fontWeight: FontWeight.w600),
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton(key: const Key('it-save'), onPressed: _busy ? null : _save, child: Text(_busy ? 'Adding…' : 'Add to store')),
            ],
          ),
        ),
      ),
    );
  }
}
