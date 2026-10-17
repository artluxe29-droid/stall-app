import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../main.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'account_setup.dart' show pickPhoto;
import 'checkout.dart' show confirm;
import 'chat.dart';
import 'extras.dart';
import 'orders.dart';
import 'trip.dart';

/// The handover timer, worded like the web app ("30 minutes", "2 hours").
String handText(Map config) {
  final n = ((config['timers'] as Map?)?['hand'] as num?) ?? 30;
  return n >= 60 && n % 60 == 0 ? (n == 60 ? '1 hour' : '${n ~/ 60} hours') : '$n minutes';
}

/// One order from the seller's side: who's buying, where it goes, what Stall holds for you, and the next step.
class SellingOrderScreen extends StatefulWidget {
  const SellingOrderScreen({super.key, required this.order});
  final Order order;
  @override
  State<SellingOrderScreen> createState() => _SellingOrderScreenState();
}

class _SellingOrderScreenState extends State<SellingOrderScreen> {
  late Order o = widget.order;
  bool _busy = false;
  int _stars = 0;
  final _code = TextEditingController();
  String? _codeErr;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final r = await SessionScope.of(context).api.get('orders/selling');
    final n = (r['orders'] as List? ?? const []).map((e) => Order(e as Map<String, dynamic>)).where((x) => x.id == o.id).firstOrNull;
    if (n != null && mounted) setState(() => o = n);
  }

  Future<bool> _act(String path, Map<String, dynamic> body, String done) async {
    setState(() => _busy = true);
    try {
      await SessionScope.of(context).api.post(path, body);
      if (!mounted) return true;
      toast(context, done);
      await _reload();
      return true;
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _release() async {
    final c = _code.text.trim().toUpperCase();
    if (c.length < 6) return setState(() => _codeErr = 'Enter the buyer\'s release code, like STALL-AB12CD.');
    setState(() {
      _busy = true;
      _codeErr = null;
    });
    try {
      await SessionScope.of(context).api.post('orders/code', {'id': o.id, 'code': c});
      if (!mounted) return;
      toast(context, 'Code accepted. You\'re being paid');
      await _reload();
    } on ApiError catch (e) {
      setState(() => _codeErr = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handed() async {
    final s = SessionScope.of(context);
    final r = await showModalBottomSheet<(String, String?)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: StallColors.cream,
      builder: (_) => NoteSheet(
        title: 'I handed it over',
        text: 'The buyer will be asked to confirm or report a problem within ${handText(s.config)}. After that you\'re paid automatically. Add a note or photo of the handover if you can.',
        hint: 'e.g. Met at the faculty gate at 2pm (optional)',
        button: 'Confirm handover',
      ),
    );
    if (r == null || !mounted) return;
    await _act('orders/handed', {'id': o.id, 'note': r.$1, 'text': r.$1, 'reason': r.$1, 'photo': r.$2}, 'Buyer asked to confirm');
  }

  /// A problem report on this order: accept it (refund the buyer), give your side, or withdraw your own report.
  Future<void> _settle(String how) async {
    final accept = how == 'accept';
    if (!await confirm(
        context,
        accept ? 'Accept and refund?' : 'Withdraw your report?',
        accept
            ? 'The buyer gets their ${naira(o.amount)} back and the order is closed. Nobody gets a strike.'
            : 'The order carries on as normal, and you\'re paid when the buyer confirms.',
        yes: accept ? 'Accept and refund' : 'Withdraw report',
        no: 'Not now')) {
      return;
    }
    if (mounted) await _act('orders/settle', {'id': o.id, 'how': how}, accept ? 'Buyer refunded' : 'Report withdrawn');
  }

  Future<void> _side() async {
    final r = await showModalBottomSheet<(String, String?)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: StallColors.cream,
      builder: (_) => const NoteSheet(
        title: 'Give your side',
        text: 'Explain what happened. A photo helps Stall decide fairly, e.g. the item, the handover spot or a chat screenshot.',
        hint: 'Write it here',
        button: 'Send',
        needText: true,
      ),
    );
    if (r == null || !mounted) return;
    await _act('orders/evidence', {'id': o.id, 'reason': r.$1, 'text': r.$1, 'note': r.$1, 'photo': r.$2}, 'Sent to Stall');
  }

  /// On a delivery that's on its way: tell the buyer roughly when you'll arrive.
  Future<void> _eta({int? min}) => _act('orders/eta', {'id': o.id, if (min == null) 'here': true else 'min': min},
      min == null ? 'Buyer told you\'re here' : 'Buyer told you\'re about $min min away');

  Future<void> _cancel({bool noshow = false}) async {
    if (noshow) {
      if (await confirm(context, 'Buyer didn\'t show up?',
          'Cancel because the buyer didn\'t come to collect it or can\'t be reached? They are refunded and get a strike. They can say it isn\'t true, so only do this if you tried to reach them.',
          yes: 'Cancel order', no: 'Keep it')) {
        await _act('orders/cancel', {'id': o.id, 'noshow': true}, 'Order cancelled');
      }
      return;
    }
    // The typed reason, not a controller: a controller disposed here would still be in use while the dialog animates closed.
    var why = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel and refund?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(o.early
              ? 'Cancel this order and refund the buyer?'
              : 'You already packed or sent this order, so cancelling now counts as a strike. Cancel and refund the buyer?'),
          const SizedBox(height: 12),
          TextField(
              key: const Key('cancelWhy'), onChanged: (x) => why = x, maxLength: 300, decoration: const InputDecoration(hintText: 'Tell them why (optional)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
          FilledButton(key: const Key('cancelYes'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancel and refund')),
        ],
      ),
    );
    if (ok == true && mounted) await _act('orders/cancel', {'id': o.id, 'reason': why.trim()}, 'Order cancelled. Buyer refunded');
  }

  Widget _note(String text, {bool bad = false, bool good = false}) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: bad ? const Color(0xFFFDE2E4) : (good ? const Color(0xFFDCF7E6) : StallColors.cream2), borderRadius: BorderRadius.circular(14)),
        child: Text(text),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final ver = o.verified, ps = o.paidVia == 'paystack';
    final next = ver && o.handedAt == null ? o.nextStage : null;
    final phone = o.method == 'delivery' && o.dphone.isNotEmpty ? o.dphone : o.buyerPhone;
    return Scaffold(
      appBar: AppBar(title: Text('Order #${o.id}')),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: [
          Text(o.title, style: t.headlineSmall),
          const SizedBox(height: 4),
          Text('${naira(o.amount)} · ${o.badge}', style: t.bodyMedium?.copyWith(color: StallColors.muted)),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.person_outline, color: StallColors.indigo),
              title: Text(o.buyerName),
              subtitle: o.buyerRating.n > 0 ? StarText('Buyer ${o.buyerRating.label}') : const Text('New buyer'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  key: Key('msg-O${o.id}'),
                  tooltip: 'Message the buyer',
                  onPressed: () => openChat(context, 'O${o.id}'),
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                ),
                if (phone.isNotEmpty)
                  IconButton(
                    tooltip: 'Call the buyer',
                    onPressed: () => launchUrl(Uri.parse('tel:$phone')),
                    icon: const Icon(Icons.call_outlined),
                  ),
              ]),
            ),
          ),
          if ((ver || o.status == 'released') && o.method != null) ...[const SizedBox(height: 16), Tracker(order: o)],
          if (ver && o.method != null && o.handedAt == null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('liveMap'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TripScreen(order: o, seller: true))),
              icon: const Icon(Icons.map_outlined),
              label: Text(o.method == 'delivery' ? 'Delivery map: share your location' : 'Pickup map: set the meeting spot'),
            ),
          ],
          if (o.status == 'under_review') _note('Stall is checking this order. Don\'t hand over the item yet.'),
          if (ver && o.method == 'delivery') _note('Deliver to: ${o.addr}${o.dphone.isEmpty ? '' : ' · ${o.dphone}'}'),
          if (ver && o.method == 'pickup') _note('The buyer collects${o.pickup.isEmpty ? '' : ' at ${o.pickup}'}.'),
          if (ver && o.handedAt == null)
            _note('Payment confirmed by Stall. Hand over the item when the buyer gives you their release code. Let them check it first: once they give the code, the sale is final.'),
          if (ps && (ver || o.status == 'disputed'))
            _note('Stall is holding ${naira(o.sellerGets)} for you (${o.fee > 0 ? 'after Stall\'s fee of ${naira(o.fee)}' : 'no Stall fee: launch offer'}). It\'s sent to your bank as soon as the buyer\'s release code is entered'
                '${o.holdUntil != null ? ', or automatically on ${dayOf(o.holdUntil!)} if the buyer reports no problem' : ''}.'
                '${o.refundAt != null ? ' Move this order on by ${dayOf(o.refundAt!)}, or the buyer is refunded automatically and you get a strike.' : ''}'),
          if (ver && o.handedAt != null)
            _note('You marked this as handed over. The buyer has until ${when(o.handUntil ?? 0)} to confirm or report a problem. After that you\'re paid automatically.'),
          if (ps && o.status == 'released')
            _note(
              o.payout == 'paid'
                  ? '${naira(o.sellerGets)} sent to your bank ✓'
                  : o.payout == 'failed'
                      ? 'Your ${naira(o.sellerGets)} payout is delayed. The Stall team is on it.'
                      : 'Sending ${naira(o.sellerGets)} to your bank…',
              good: o.payout == 'paid',
            ),
          if (o.status == 'disputed')
            _note(
                '${o.note}. The money stays on hold, so don\'t hand over anything until it\'s sorted.'
                '${o.dispBy == 'buyer' && !o.dispReplied && o.dispDue != null ? ' Accept it or give your side by ${when(o.dispDue!)}, or it\'s decided for the buyer.' : ''}'
                '${o.dispReplied ? ' Both sides have spoken: the Stall team will decide.' : ''}',
                bad: true),
          if (o.status == 'disputed') ...[
            const SizedBox(height: 12),
            TextButton(
                key: const Key('bothSides'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EvidenceScreen(orderId: o.id))),
                child: const Text('See both sides')),
            if (o.dispBy == 'buyer')
              FilledButton.tonal(key: const Key('settleAccept'), onPressed: _busy ? null : () => _settle('accept'), child: const Text('Accept and refund'))
            else
              FilledButton.tonal(key: const Key('settleWithdraw'), onPressed: _busy ? null : () => _settle('withdraw'), child: const Text('Withdraw report')),
            OutlinedButton(
                key: const Key('giveSide'), onPressed: _busy ? null : _side, child: Text(o.dispBy == 'buyer' && !o.dispReplied ? 'Give your side' : 'Add more')),
          ],
          if (o.status == 'refunded') _note('This order was cancelled and the buyer refunded.${o.note.isEmpty ? '' : ' ${o.note}'}'),
          const SizedBox(height: 20),
          if (ver) ...[
            Text('Release code', style: t.titleMedium),
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: TextField(
                  key: const Key('releaseCode'),
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]'))],
                  decoration: InputDecoration(hintText: 'STALL-XXXXXX', errorText: _codeErr, errorMaxLines: 3),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                key: const Key('release'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 54)),
                onPressed: _busy ? null : _release,
                child: const Text('Release'),
              ),
            ]),
            const SizedBox(height: 16),
            if (next != null)
              FilledButton.tonal(
                key: const Key('nextStage'),
                onPressed: _busy ? null : () => _act('orders/stage', {'id': o.id, 'stage': next.$1}, 'Buyer updated'),
                child: Text(next.$2),
              ),
            if (o.method == 'delivery' && o.stage == 'on_way' && o.handedAt == null) ...[
              Text('Tell the buyer when you\'ll arrive', style: t.titleSmall),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final m in const [5, 10, 20, 30])
                  ActionChip(key: Key('eta-$m'), label: Text('$m min'), onPressed: _busy ? null : () => _eta(min: m)),
                ActionChip(
                    key: const Key('eta-here'),
                    avatar: const Icon(Icons.place_rounded, size: 18),
                    label: const Text('I\'m here'),
                    onPressed: _busy ? null : () => _eta()),
              ]),
              const SizedBox(height: 12),
            ],
            if (o.handedAt == null && (o.moved || o.stage == 'packed'))
              OutlinedButton(key: const Key('handed'), onPressed: _busy ? null : _handed, child: const Text('I handed it over')),
            if (o.handedAt == null) ...[
              if (o.moved) TextButton(key: const Key('noShow'), onPressed: _busy ? null : () => _cancel(noshow: true), child: const Text('Buyer didn\'t show up?')),
              TextButton(
                key: const Key('sellerCancel'),
                onPressed: _busy ? null : _cancel,
                child: Text(o.early ? 'Can\'t deliver? Cancel and refund the buyer' : 'Cancel and refund (counts as a strike)',
                    style: const TextStyle(color: StallColors.red)),
              ),
            ],
          ],
          if (o.status == 'released')
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('receipt'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReceiptScreen(path: 'orders/receipt', query: {'id': '${o.id}'}))),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Sale receipt'),
              ),
            ),
          if (o.status == 'released')
            o.brate != null
                ? _note('You rated this buyer ${'★' * o.brate!}')
                : Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Text('How was ${o.buyerName} as a buyer?', style: t.titleMedium),
                        Text('Turned up on time, polite, paid as agreed.', style: t.bodySmall),
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          for (var n = 1; n <= 5; n++)
                            IconButton(
                              key: Key('bstar-$n'),
                              tooltip: '$n star${n > 1 ? 's' : ''}',
                              onPressed: () => setState(() => _stars = n),
                              icon: Icon(n <= _stars ? Icons.star_rounded : Icons.star_outline_rounded, color: starColor, size: 34),
                            ),
                        ]),
                        FilledButton(
                          key: const Key('rateBuyer'),
                          onPressed: _busy || _stars == 0 ? null : () => _act('orders/rate-buyer', {'id': o.id, 'stars': _stars}, 'Thanks for rating'),
                          child: const Text('Rate buyer'),
                        ),
                      ]),
                    ),
                  ),
        ]),
      ),
    );
  }
}

/// A note and optional photo: handover proof, a problem report, or your side of one.
class NoteSheet extends StatefulWidget {
  const NoteSheet({super.key, required this.title, required this.text, required this.hint, required this.button, this.needText = false});
  final String title, text, hint, button;

  /// Ask for a written note (at least 10 characters) or a photo.
  final bool needText;
  @override
  State<NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<NoteSheet> {
  final _t = TextEditingController();
  String? _photo, _err;
  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(widget.text),
          const SizedBox(height: 12),
          TextField(
              key: const Key('noteText'),
              controller: _t,
              maxLength: 300,
              maxLines: 3,
              decoration: InputDecoration(hintText: widget.hint, errorText: _err)),
          OutlinedButton.icon(
            onPressed: () async {
              try {
                final p = await pickPhoto(context);
                if (p != null) setState(() => _photo = p);
              } on ApiError catch (e) {
                if (context.mounted) toast(context, e.message);
              }
            },
            icon: Icon(_photo == null ? Icons.add_a_photo_outlined : Icons.check_circle_rounded, color: _photo == null ? null : StallColors.green),
            label: Text(_photo == null ? 'Add a photo' : 'Photo added'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('noteSend'),
            onPressed: () {
              final x = _t.text.trim();
              if (widget.needText && x.length < 10 && _photo == null) return setState(() => _err = 'Write what happened (a sentence or two) or add a photo.');
              Navigator.pop(context, (x, _photo));
            },
            child: Text(widget.button),
          ),
        ]),
      );
}

/// Opens a [NoteSheet] and returns (text, photo), or null if closed.
Future<(String, String?)?> askNote(BuildContext context, {required String title, required String text, required String hint, required String button, bool needText = true}) =>
    showModalBottomSheet<(String, String?)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: StallColors.cream,
      builder: (_) => NoteSheet(title: title, text: text, hint: hint, button: button, needText: needText),
    );

/// Both sides of a problem report: what each person wrote, with photos.
class EvidenceScreen extends StatefulWidget {
  const EvidenceScreen({super.key, required this.orderId});
  final int orderId;
  @override
  State<EvidenceScreen> createState() => _EvidenceScreenState();
}

class _EvidenceScreenState extends State<EvidenceScreen> {
  Future<Map<String, dynamic>>? _f;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _f ??= SessionScope.of(context).api.get('orders/evidence', {'id': '${widget.orderId}'});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Both sides')),
        body: FutureBuilder<Map<String, dynamic>>(
          future: _f,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            if (snap.hasError) return EmptyState(icon: Icons.wifi_off_rounded, title: 'Couldn\'t load it', text: snap.error.toString());
            final items = (snap.data!['items'] as List? ?? const []).cast<Map<String, dynamic>>();
            if (items.isEmpty) return const EmptyState(icon: Icons.forum_outlined, title: 'Nothing yet', text: 'Notes and photos from either side show here.');
            final t = Theme.of(context).textTheme;
            return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: [
              for (final x in items)
                Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${x['who']} (${x['side']}) · ${when((x['t'] as num?)?.toInt() ?? 0)}', style: t.bodySmall),
                      if ((x['text'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(x['text'].toString())),
                      if ((x['photo'] ?? '').toString().startsWith('data:image'))
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: ClipRRect(
                              borderRadius: BorderRadius.circular(12), child: Image.memory(base64Decode(x['photo'].toString().split(',').last), fit: BoxFit.cover)),
                        ),
                    ]),
                  ),
                ),
            ]);
          },
        ),
      );
}

/// This week's sales statement, as the server writes it (same as the weekly email).
class WeeklyScreen extends StatefulWidget {
  const WeeklyScreen({super.key});
  @override
  State<WeeklyScreen> createState() => _WeeklyScreenState();
}

class _WeeklyScreenState extends State<WeeklyScreen> {
  Future<Map<String, dynamic>>? _f;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _f ??= SessionScope.of(context).api.get('orders/weekly');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Weekly statement')),
        body: FutureBuilder<Map<String, dynamic>>(
          future: _f,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            if (snap.hasError) return EmptyState(icon: Icons.wifi_off_rounded, title: 'Couldn\'t load it', text: snap.error.toString());
            final d = snap.data!;
            if (((d['n'] as num?) ?? 0) == 0) {
              return const EmptyState(icon: Icons.bar_chart_rounded, title: 'No sales this week yet', text: 'Your completed sales and payouts show here each week.');
            }
            final t = Theme.of(context).textTheme;
            return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: [
              Text((d['label'] ?? '').toString(), style: t.titleMedium),
              const SizedBox(height: 4),
              Text(naira((d['total'] as num?) ?? 0), style: t.displaySmall),
              Text('${d['n']} sale${d['n'] == 1 ? '' : 's'}', style: t.bodyMedium?.copyWith(color: StallColors.muted)),
              const Divider(height: 32),
              SelectableText((d['text'] ?? '').toString(), style: t.bodyMedium),
            ]);
          },
        ),
      );
}
