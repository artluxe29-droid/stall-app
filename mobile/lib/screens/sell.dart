import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../main.dart';
import '../models.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets.dart';
import 'account_setup.dart';
import 'browse.dart';
import 'checkout.dart' show confirm;
import 'selling.dart';

/// Picks listing photos (1 to 8), shrunk like the web app does (720px, JPEG), as data URLs for the API.
/// Tests replace this.
typedef PhotoPicker = Future<List<String>> Function(BuildContext context, int max);
PhotoPicker pickListingPhotos = (context, max) async {
  final src = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    backgroundColor: StallColors.cream,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Take a photo'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
        ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
      ]),
    ),
  );
  if (src == null) return const [];
  final p = ImagePicker();
  final files = src == ImageSource.camera
      ? [?await p.pickImage(source: src, maxWidth: 720, maxHeight: 720, imageQuality: 65)]
      : await p.pickMultiImage(maxWidth: 720, maxHeight: 720, imageQuality: 65, limit: max);
  final out = <String>[];
  for (final f in files.take(max)) {
    out.add('data:image/jpeg;base64,${base64Encode(await f.readAsBytes())}');
  }
  return out;
};

/// The banks Stall can pay out to (GET /api/banks).
Future<List<(String, String)>> loadBanks(Api api) async {
  final r = await api.get('banks');
  return [for (final b in (r['banks'] as List? ?? const [])) ((b as Map)['code'].toString(), b['name'].toString())];
}

/// "Before you sell": the same rules and two ticks as the web app. Returns true once agreed (and saved).
Future<bool> sellerRules(BuildContext context) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: StallColors.cream,
    builder: (_) => const _SellerRulesSheet(),
  );
  if (ok != true || !context.mounted) return false;
  try {
    await SessionScope.of(context).api.post('me/seller-ok');
    return true;
  } on ApiError catch (e) {
    if (context.mounted) toast(context, e.message);
    return false;
  }
}

class _SellerRulesSheet extends StatefulWidget {
  const _SellerRulesSheet();
  @override
  State<_SellerRulesSheet> createState() => _SellerRulesSheetState();
}

class _SellerRulesSheetState extends State<_SellerRulesSheet> {
  bool _school = false, _rules = false;
  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    final tm = (s.config['timers'] as Map?) ?? const {};
    String hrs(String k, num d) {
      final n = (tm[k] as num?) ?? d;
      return n == 1 ? '1 hour' : '$n hours';
    }

    final hand = (tm['hand'] as num?) ?? 30;
    final handT = hand >= 60 && hand % 60 == 0 ? (hand == 60 ? '1 hour' : '${hand ~/ 60} hours') : '$hand minutes';
    final t = Theme.of(context).textTheme;
    Widget li(String x) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(padding: EdgeInsets.only(top: 7, right: 10), child: Icon(Icons.circle, size: 6, color: StallColors.indigo)),
            Expanded(child: Text(x)),
          ]),
        );
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .85,
      maxChildSize: .95,
      builder: (context, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
        Text('Before you sell', style: t.headlineSmall),
        const SizedBox(height: 6),
        Text('These rules are the same for buyers and sellers, so nobody can hold the other\'s money or walk away unfairly.', style: t.bodyMedium?.copyWith(color: StallColors.muted)),
        const SizedBox(height: 14),
        li('Buyers pay Stall, and Stall holds the money until the handover.'),
        li('You\'re paid when the buyer gives you their release code or taps I\'ve got it. Let them check the item first: once they give the code, the sale is final.'),
        li('If the buyer has the item but won\'t give the code, tap I handed it over. They get $handT to confirm or report a problem, then you\'re paid.'),
        li('Once you mark an order on the way or ready for pickup, you\'re paid automatically after ${hrs('pay', 24)} if the buyer reports no problem. If you don\'t move a new order on within ${hrs('send', 24)}, the buyer is refunded.'),
        li('Either side can report a problem. Accept it or give your side, with photos, within ${hrs('answer', 4)}, or it\'s decided for the other side.'),
        li('Strikes for late cancels, no-shows, and problem reports you lose or don\'t answer. 3 in 30 days is a warning; 5 pauses your account for 14 days. Buyers get strikes too.'),
        CheckboxListTile(
          key: const Key('rulesSchool'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _school,
          onChanged: (v) => setState(() => _school = v ?? false),
          title: const Text('I\'m responsible for making sure my school or campus allows me to sell, and for following its rules.'),
        ),
        CheckboxListTile(
          key: const Key('rulesAgree'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _rules,
          onChanged: (v) => setState(() => _rules = v ?? false),
          title: const Text('I agree to these rules, the seller rules and the Terms.'),
        ),
        Wrap(spacing: 4, children: [
          TextButton(onPressed: () => openLink('/rules'), child: const Text('Seller rules')),
          TextButton(onPressed: () => openLink('/terms'), child: const Text('Terms')),
        ]),
        const SizedBox(height: 8),
        FilledButton(key: const Key('rulesOk'), onPressed: _school && _rules ? () => Navigator.pop(context, true) : null, child: const Text('I agree')),
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
      ]),
    );
  }
}

/// Sell: post an item, see your listings and their review status, and manage stock, sold and delivery.
class SellTab extends StatefulWidget {
  const SellTab({super.key});
  @override
  State<SellTab> createState() => _SellTabState();
}

class _SellTabState extends State<SellTab> {
  Future<List<Listing>>? _f;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _f ??= _load();
  }

  Future<List<Listing>> _load() async {
    final r = await SessionScope.of(context).api.get('listings', {'mine': '1'});
    return (r['listings'] as List? ?? const []).map((e) => Listing(e as Map<String, dynamic>)).toList();
  }

  Future<void> _refresh() async {
    final f = _load();
    setState(() {
      _f = f;
    });
    await f.catchError((_) => <Listing>[]);
  }

  Future<void> _sell() async {
    final posted = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const SellScreen()));
    if (posted == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    final u = s.user;
    final t = Theme.of(context).textTheme;
    if (u != null && u.isVendor) {
      return const EmptyState(
        icon: Icons.storefront_outlined,
        title: 'Campus vendors sell through a store',
        text: 'Opening and running your store in the app arrives in the next update. For now, manage it on stall.com.ng.',
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 32), children: [
        Text('Sell', style: t.headlineMedium),
        const SizedBox(height: 4),
        Text('Free to list. Stall holds the buyer\'s payment until they have the item, then pays you.', style: t.bodyLarge?.copyWith(color: StallColors.muted)),
        const SizedBox(height: 16),
        FilledButton.icon(key: const Key('sellItem'), onPressed: _sell, icon: const Icon(Icons.add_rounded), label: const Text('Sell an item')),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: Column(children: [
            ListTile(
              key: const Key('deliveryTile'),
              leading: const Icon(Icons.local_shipping_outlined, color: StallColors.indigo),
              title: const Text('Delivery'),
              subtitle: Text(u?.deliv['on'] == true
                  ? 'You deliver${((u!.deliv['fee'] as num?) ?? 0) > 0 ? ' for ${naira(u.deliv['fee'] as num)}' : ' for free'}'
                  : 'Off: buyers collect from you'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DeliveryScreen())),
            ),
            const Divider(height: 1),
            ListTile(
              key: const Key('weeklyTile'),
              leading: const Icon(Icons.bar_chart_rounded, color: StallColors.indigo),
              title: const Text('Weekly statement'),
              subtitle: const Text('What you sold and were paid this week'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WeeklyScreen())),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(u?.acctSet == true ? Icons.account_balance_rounded : Icons.account_balance_outlined, color: StallColors.indigo),
              title: const Text('Payout account'),
              subtitle: Text(u?.acctSet == true ? 'Saved. Sales are paid into it.' : 'Added when you post your first item.'),
            ),
          ]),
        ),
        const SizedBox(height: 24),
        Text('Your listings', style: t.titleLarge),
        const SizedBox(height: 8),
        FutureBuilder<List<Listing>>(
          future: _f,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
            if (snap.hasError) {
              return Text(snap.error is ApiError ? (snap.error as ApiError).message : 'Couldn\'t load your listings. Pull down to try again.');
            }
            final ls = snap.data!;
            if (ls.isEmpty) return const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('Nothing listed yet. Tap Sell an item to post your first.'));
            return Column(children: [for (final l in ls) MyListingRow(item: l, onChanged: _refresh)]);
          },
        ),
      ]),
    );
  }
}

/// The web app's review states for a seller's own listing.
String? reviewLabel(Listing l) => switch (l.raw['review']) {
      'checking' => 'Checking the photo…',
      'review' => 'Needs a look by the Stall team',
      'rejected' => 'Not approved',
      _ => null,
    };

class MyListingRow extends StatelessWidget {
  const MyListingRow({super.key, required this.item, required this.onChanged});
  final Listing item;
  final VoidCallback onChanged;

  Future<void> _post(BuildContext context, String path, Map<String, dynamic> body, String done) async {
    try {
      await SessionScope.of(context).api.post(path, body);
      if (!context.mounted) return;
      toast(context, done);
      onChanged();
    } on ApiError catch (e) {
      if (context.mounted) toast(context, e.message);
    }
  }

  Future<void> _stock(BuildContext context) async {
    final c = TextEditingController(text: '${item.qtyLeft ?? 1}');
    final n = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('How many do you have left?'),
        content: TextField(key: const Key('stockField'), controller: c, keyboardType: TextInputType.number, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(key: const Key('stockSave'), onPressed: () => Navigator.pop(ctx, int.tryParse(c.text.trim())), child: const Text('Save')),
        ],
      ),
    );
    if (n != null && context.mounted) await _post(context, 'listings/stock', {'id': item.id, 'qty': n}, n > 0 ? 'Stock updated' : 'Marked sold out');
  }

  @override
  Widget build(BuildContext context) {
    final rv = reviewLabel(item);
    final rejected = item.raw['review'] == 'rejected';
    final note = (item.raw['reviewNote'] ?? '').toString();
    final st = item.status;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox.square(dimension: 64, child: Photo(path: item.imgs.firstOrNull, cat: item.cat))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(naira(item.price), style: const TextStyle(fontFamily: 'Bricolage', fontWeight: FontWeight.w800)),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  if (st != null) Tag(st),
                  if (st == null && rv == null) const Tag('Live', bg: Color(0xFFDCF7E6), fg: StallColors.green),
                  if (rv != null) Tag(rv, bg: rejected ? const Color(0xFFFDE2E4) : const Color(0xFFFEF3C7), fg: rejected ? StallColors.red : StallColors.amber),
                  if (item.stockLine != null) Tag(item.stockLine!, bg: StallColors.cream2, fg: StallColors.ink),
                ]),
              ]),
            ),
          ]),
          if (rejected)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('${note.isEmpty ? '' : '$note. '}Delete it and post again with a clear photo of the actual item.', style: const TextStyle(color: StallColors.red)),
            ),
          if (item.raw['stuOff'] == true)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Hidden from buyers: students can\'t sell at your school right now.', style: TextStyle(color: StallColors.amber)),
            ),
          Wrap(spacing: 4, children: [
            if (!rejected) TextButton(key: Key('stock-${item.id}'), onPressed: () => _stock(context), child: Text('Stock${item.qtyLeft != null ? ' (${item.qtyLeft})' : ''}')),
            if (!rejected)
              TextButton(
                key: Key('sold-${item.id}'),
                onPressed: () => _post(context, 'listings/sold', {'id': item.id, 'sold': !item.sold}, item.sold ? 'Back on sale' : 'Marked as sold'),
                child: Text(item.sold ? 'Mark available' : 'Mark as sold'),
              ),
            TextButton(
              key: Key('del-${item.id}'),
              onPressed: () async {
                if (await confirm(context, 'Delete this listing?', '"${item.title}" will be removed from Stall.', yes: 'Delete', no: 'Keep it')) {
                  if (context.mounted) await _post(context, 'listings/delete', {'id': item.id}, 'Listing deleted');
                }
              },
              child: const Text('Delete', style: TextStyle(color: StallColors.red)),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// Post an item: photos, title, price (with a price hint and what you'll get), category, how many, condition,
/// where to meet, details, and the payout account the first time.
class SellScreen extends StatefulWidget {
  const SellScreen({super.key});
  @override
  State<SellScreen> createState() => _SellScreenState();
}

class _SellScreenState extends State<SellScreen> {
  final _form = GlobalKey<FormState>();
  final _c = {for (final k in ['title', 'price', 'qty', 'spot', 'desc', 'acct', 'acctName']) k: TextEditingController()};
  final _photos = <String>[];
  String _cat = Category.all.first.id, _cond = 'Like new';
  String? _bank, _verifiedName, _bankMsg, _photoErr, _error;
  List<(String, String)> _banks = const [];
  bool _busy = false, _checking = false, _manual = false, _tried = false;
  int _fails = 0;
  Map<String, dynamic>? _hint;
  Timer? _hintT;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _c['qty']!.text = '1';
    _c['title']!.addListener(_hintSoon);
    _c['price']!.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = SessionScope.of(context);
    if (_banks.isEmpty && !(s.user?.acctSet ?? true)) {
      loadBanks(s.api).then((b) => mounted ? setState(() => _banks = b) : null).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _hintT?.cancel();
    _scroll.dispose();
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _hintSoon() {
    _hintT?.cancel();
    final t = _c['title']!.text.trim();
    if (t.length < 3) {
      if (_hint != null) setState(() => _hint = null);
      return;
    }
    _hintT = Timer(const Duration(milliseconds: 600), () async {
      try {
        final r = await SessionScope.of(context).api.get('price-hint', {'t': t, 'cond': _cond});
        if (mounted && _c['title']!.text.trim() == t) setState(() => _hint = ((r['n'] as num?) ?? 0) >= 3 ? r : null);
      } catch (_) {}
    });
  }

  int get _price => int.tryParse(_c['price']!.text.replaceAll(RegExp(r'\D'), '')) ?? 0;

  Widget _earn(Session s) {
    final p = _price, free = s.user?.freeLeft ?? 0, sales = free == 1 ? 'sale' : '$free sales';
    final (head, more) = p <= 0
        ? (free > 0 ? 'Launch offer: no fee on your next $sales' : 'Enter a price', free > 0 ? 'Enter a price to see exactly what you get.' : 'We\'ll show exactly what you get when it sells.')
        : p < 500
            ? ('The minimum price is ₦500', '')
            : free > 0
                ? ('You get ${naira(p)}', 'Launch offer: no Stall fee on your next $sales. After that you\'d get ${naira(p - s.feeOf(p))} (fee ${naira(s.feeOf(p))}: ${s.feeDesc}). Delivery fees are always yours.')
                : ('You get ${naira(p - s.feeOf(p))}', 'Buyer pays ${naira(p)} · Stall\'s fee ${naira(s.feeOf(p))}: ${s.feeDesc}. Delivery fees are all yours.');
    return Container(
      key: const Key('earn'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: p > 0 && p < 500 ? const Color(0xFFFDE2E4) : const Color(0xFFEEF8C8), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(head, style: const TextStyle(fontWeight: FontWeight.w800)),
        if (more.isNotEmpty) Text(more, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: StallColors.ink)),
      ]),
    );
  }

  Future<void> _addPhotos() async {
    final got = await pickListingPhotos(context, 8 - _photos.length);
    if (!mounted) return;
    setState(() {
      _photos.addAll(got.where((p) => p.length <= 450000));
      _photoErr = got.any((p) => p.length > 450000) ? 'One photo was too large. Try another.' : null;
    });
  }

  Future<void> _verifyBank() async {
    final acct = _c['acct']!.text.replaceAll(RegExp(r'\D'), '');
    if (_bank == null || acct.length != 10) return setState(() => _bankMsg = 'Choose your bank and enter your 10-digit account number.');
    setState(() {
      _checking = true;
      _bankMsg = null;
    });
    try {
      final r = await SessionScope.of(context).api.post('bank/resolve', {'bank_code': _bank, 'acct_no': acct});
      setState(() => _verifiedName = r['name'].toString());
    } on ApiError catch (e) {
      setState(() {
        _fails++;
        _bankMsg = e.message;
        // Paystack can't always check an account (busy, or not set up). After that, accept the name typed in.
        if (_fails >= 2 || e.status == 503 || e.message.contains('Type the name')) _manual = true;
      });
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _submit({bool retried = false}) async {
    final s = SessionScope.of(context);
    final needBank = !(s.user?.acctSet ?? false);
    setState(() {
      _tried = true;
      _error = null;
      _photoErr = _photos.isEmpty ? 'Add at least one photo.' : null;
    });
    if (_photos.isEmpty) {
      // The photos are at the top of the form: show them.
      _scroll.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      _form.currentState!.validate();
      return;
    }
    if (!_form.currentState!.validate()) return;
    if (needBank && _verifiedName == null && !(_manual && _c['acctName']!.text.trim().length >= 3)) {
      return setState(() => _bankMsg = _c['acct']!.text.trim().length == 10 ? 'Tap "Verify account" first.' : 'Enter your 10-digit account number, then tap "Verify account".');
    }
    setState(() => _busy = true);
    try {
      final u = s.user!;
      await s.api.post('listings', {
        'title': _c['title']!.text.trim(),
        'price': _price,
        'cat': _cat,
        'cond': _cond,
        'qty': int.tryParse(_c['qty']!.text.trim()) ?? 1,
        'spot': _c['spot']!.text.trim(),
        'desc': _c['desc']!.text.trim(),
        'seller': u.name,
        'phone': u.phone,
        'imgs': _photos,
        if (needBank) ...{
          'bank_code': _bank,
          'acct_no': _c['acct']!.text.replaceAll(RegExp(r'\D'), ''),
          'acct_name': _verifiedName ?? _c['acctName']!.text.trim(),
          if (_verifiedName == null) 'bank_manual': '1',
        },
      });
      await s.refresh();
      if (!mounted) return;
      toast(context, 'Posted. Stall is checking the photo; it shows to buyers in a moment.');
      Navigator.pop(context, true);
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.data['need'] == 'seller_ok' && !retried) {
        setState(() => _busy = false);
        if (await sellerRules(context)) return _submit(retried: true);
        return;
      }
      if (e.data['verify'] == true || e.data['needVerify'] == true) {
        setState(() => _error = e.message);
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VerifyStudentScreen()));
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
    final needBank = !(s.user?.acctSet ?? false);
    final h = _hint;
    InputDecoration dec(String l, {String? hint, String? prefix}) => InputDecoration(labelText: l, hintText: hint, prefixText: prefix, counterText: '');
    return Scaffold(
      appBar: AppBar(title: const Text('Sell an item')),
      body: Form(
        key: _form,
        autovalidateMode: _tried ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
        child: ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: [
          Text('Photos (1 to 8)', style: t.titleMedium),
          const SizedBox(height: 8),
          SizedBox(
            height: 92,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (var i = 0; i < _photos.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Stack(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(base64Decode(_photos[i].split(',').last), width: 92, height: 92, fit: BoxFit.cover),
                    ),
                    Positioned(
                      right: 2,
                      top: 2,
                      child: InkWell(
                        onTap: () => setState(() => _photos.removeAt(i)),
                        child: const CircleAvatar(radius: 12, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 14, color: Colors.white)),
                      ),
                    ),
                  ]),
                ),
              if (_photos.length < 8)
                InkWell(
                  key: const Key('addPhotos'),
                  onTap: _addPhotos,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 92,
                    decoration: BoxDecoration(color: StallColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: StallColors.line)),
                    child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_a_photo_outlined, color: StallColors.indigo), Text('Add', style: TextStyle(fontSize: 13))]),
                  ),
                ),
            ]),
          ),
          if (_photoErr != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_photoErr!, style: const TextStyle(color: StallColors.red))),
          const SizedBox(height: 16),
          TextFormField(
            key: const Key('s-title'),
            controller: _c['title'],
            maxLength: 60,
            textCapitalization: TextCapitalization.sentences,
            decoration: dec('What are you selling?', hint: 'e.g. Engineering Mathematics textbook'),
            validator: (v) => (v ?? '').trim().length < 3 ? 'Enter a title of 3 to 80 characters.' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('s-price'),
            controller: _c['price'],
            keyboardType: TextInputType.number,
            decoration: dec('Price', prefix: '₦ '),
            validator: (_) => _price < 500 ? 'The minimum price is ₦500.' : null,
          ),
          if (h != null) ...[
            const SizedBox(height: 8),
            Container(
              key: const Key('priceHint'),
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              decoration: BoxDecoration(color: StallColors.cream2, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Expanded(
                  child: Text(
                      'Similar items on Stall${h['cond'] != null ? ' (${h['cond'].toString().toLowerCase()})' : ''}: ${naira(h['low'] as num)}${(h['high'] as num) > (h['low'] as num) ? ' – ${naira(h['high'] as num)}' : ''}, most around ${naira(h['mid'] as num)} (${h['n']} items)',
                      style: t.bodySmall?.copyWith(color: StallColors.ink)),
                ),
                TextButton(
                  onPressed: () {
                    _c['price']!.text = '${(h['mid'] as num).round()}';
                    toast(context, 'Price set to ${naira(h['mid'] as num)}. You can still change it.');
                  },
                  child: Text('Use ${naira(h['mid'] as num)}'),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 8),
          _earn(s),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _cat,
            decoration: dec('Category'),
            items: [for (final c in Category.all) DropdownMenuItem(value: c.id, child: Text(c.name))],
            onChanged: (v) => setState(() => _cat = v ?? _cat),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextFormField(
                key: const Key('s-qty'),
                controller: _c['qty'],
                keyboardType: TextInputType.number,
                decoration: dec('How many?'),
                validator: (v) => (int.tryParse((v ?? '').trim()) ?? 0) < 1 ? 'Enter how many you have (1 or more).' : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _cond,
                decoration: dec('Condition'),
                items: [for (final c in const ['New', 'Like new', 'Used']) DropdownMenuItem(value: c, child: Text(c))],
                onChanged: (v) {
                  setState(() => _cond = v ?? _cond);
                  _hintSoon();
                },
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('s-spot'),
            controller: _c['spot'],
            maxLength: 40,
            decoration: dec('Meet-up spot or delivery area', hint: 'e.g. Library steps'),
            validator: (v) => (v ?? '').trim().length < 2 ? 'Where can buyers meet you?' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(controller: _c['desc'], maxLength: 240, maxLines: 3, decoration: dec('Details', hint: 'Edition, size, defects')),
          if (needBank) ...[
            const SizedBox(height: 16),
            Text('Payout account', style: t.titleMedium),
            Text('Where Stall sends your money when you sell. You only add it once.', style: t.bodySmall),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: const Key('s-bank'),
              isExpanded: true,
              initialValue: _bank,
              decoration: dec('Bank'),
              items: [for (final b in _banks) DropdownMenuItem(value: b.$1, child: Text(b.$2))],
              onChanged: (v) => setState(() {
                _bank = v;
                _verifiedName = null;
                _fails = 0;
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('s-acct'),
              controller: _c['acct'],
              keyboardType: TextInputType.number,
              maxLength: 10,
              onChanged: (_) => setState(() {
                _verifiedName = null;
                _fails = 0;
              }),
              decoration: dec('Account number', hint: '10 digits'),
            ),
            Row(children: [
              OutlinedButton(key: const Key('verifyBank'), style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)), onPressed: _checking ? null : _verifyBank, child: Text(_checking ? 'Checking…' : 'Verify account')),
              const SizedBox(width: 12),
              if (_verifiedName != null)
                Expanded(child: Text('✓ $_verifiedName', key: const Key('bankName'), style: const TextStyle(color: StallColors.green, fontWeight: FontWeight.w700))),
            ]),
            if (_bankMsg != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_bankMsg!, style: const TextStyle(color: StallColors.red))),
            if (_manual && _verifiedName == null) ...[
              const SizedBox(height: 10),
              TextField(
                key: const Key('s-acctName'),
                controller: _c['acctName'],
                textCapitalization: TextCapitalization.characters,
                decoration: dec('Name on the account', hint: 'Exactly as your bank shows it'),
              ),
              Text('The Stall team checks this name before your first payout.', style: t.bodySmall),
            ],
          ],
          const SizedBox(height: 12),
          Text('Free to list. Stall holds each buyer\'s payment until they have their order, then sends it to your account minus a sale fee of ${s.feeDesc}.',
              style: t.bodySmall),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, key: const Key('s-error'), style: const TextStyle(color: StallColors.red, fontWeight: FontWeight.w600))),
          const SizedBox(height: 16),
          FilledButton(key: const Key('postListing'), onPressed: _busy ? null : _submit, child: Text(_busy ? 'Posting…' : 'Post listing')),
        ]),
      ),
    );
  }
}

/// Delivery settings for the items you list: buyers can always collect; if you deliver, they can pay your fee with their order.
class DeliveryScreen extends StatefulWidget {
  const DeliveryScreen({super.key});
  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  late bool _on;
  final _fee = TextEditingController(), _note = TextEditingController();
  bool _init = false, _busy = false;
  String? _err;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final d = SessionScope.of(context).user?.deliv ?? const {};
    _on = d['on'] == true;
    _fee.text = '${(d['fee'] as num?) ?? 0}';
    _note.text = (d['note'] ?? '').toString();
  }

  @override
  void dispose() {
    _fee.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    final s = SessionScope.of(context);
    try {
      await s.api.post('me/delivery', {'on': _on, 'fee': int.tryParse(_fee.text.trim()) ?? 0, 'note': _note.text.trim()});
      await s.refresh();
      if (!mounted) return;
      toast(context, 'Delivery settings saved');
      Navigator.pop(context);
    } on ApiError catch (e) {
      setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Delivery')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: [
        Text('For the items you list. Buyers can always collect from you. If you also deliver, they can choose delivery and pay your fee with their order. Stall\'s fee is on the item price only; you keep the whole delivery fee.',
            style: t.bodyMedium?.copyWith(color: StallColors.muted)),
        SwitchListTile(key: const Key('deliverOn'), contentPadding: EdgeInsets.zero, title: const Text('I deliver'), value: _on, onChanged: (v) => setState(() => _on = v)),
        if (_on) ...[
          TextField(key: const Key('deliverFee'), controller: _fee, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Delivery fee', prefixText: '₦ ')),
          const SizedBox(height: 12),
          TextField(controller: _note, maxLength: 80, decoration: const InputDecoration(labelText: 'Where and when (optional)', hintText: 'e.g. Anywhere on campus, same day')),
        ],
        if (_err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err!, style: const TextStyle(color: StallColors.red))),
        const SizedBox(height: 16),
        FilledButton(key: const Key('deliverSave'), onPressed: _busy ? null : _save, child: const Text('Save')),
      ]),
    );
  }
}
