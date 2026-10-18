import 'package:flutter/material.dart';

import '../api.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets.dart';
import 'my_store.dart' show payStall, payWithCredit;
import 'sell.dart' show pickListingPhotos;

/// The one-off fee for the green "Verified" seller badge, paid only after Stall approves you.
const verifyFee = 1000;

/// Featuring a single listing: days → price (stores have their own prices).
const listingFeaturePrice = {3: 300, 7: 500};

/// Account → Verified seller badge: apply (who you are + a photo of your ID or shop), wait, then pay to switch it on.
class VerifySellerScreen extends StatefulWidget {
  const VerifySellerScreen({super.key});
  @override
  State<VerifySellerScreen> createState() => _VerifySellerScreenState();
}

class _VerifySellerScreenState extends State<VerifySellerScreen> {
  final _note = TextEditingController();
  String? _photo, _err;
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_note.text.trim().isEmpty) return setState(() => _err = 'Say who you are and what you sell.');
    if (_photo == null) return setState(() => _err = 'Add a photo of your ID card or shop front.');
    setState(() {
      _busy = true;
      _err = null;
    });
    final s = SessionScope.of(context);
    try {
      await s.api.post('verify/apply', {'note': _note.text.trim(), 'photo': _photo});
      await s.refresh();
      if (mounted) toast(context, 'Sent. We\'ll review it soon.');
    } on ApiError catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pay() async {
    setState(() => _busy = true);
    final s = SessionScope.of(context);
    try {
      if (await payStall(context, {'kind': 'verify'})) {
        await s.refresh();
        if (mounted) toast(context, 'Your verified badge is on ✓');
      }
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final u = SessionScope.of(context).user;
    final st = u?.verifyState;
    return Scaffold(
      appBar: AppBar(title: const Text('Verified seller')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
        Row(children: [
          const Icon(Icons.verified_rounded, color: StallColors.green, size: 28),
          const SizedBox(width: 8),
          Flexible(child: Text('Verified seller', style: t.headlineSmall)),
        ]),
        const SizedBox(height: 8),
        Text(
          'A green Verified badge on your listings and store tells buyers Stall has checked who you are. '
          'One-off fee of ${naira(verifyFee)}, paid only after we approve you.',
          style: t.bodyLarge?.copyWith(color: StallColors.muted),
        ),
        const SizedBox(height: 20),
        if (u?.verified ?? false)
          const Text('You\'re verified. Your badge is showing.', key: Key('verOn'), style: TextStyle(fontWeight: FontWeight.w700))
        else if (st == 'pending')
          const Text('Waiting for review. We\'ll check your details soon; come back here to see the result.',
              key: Key('verPending'), style: TextStyle(fontWeight: FontWeight.w700))
        else if (st == 'approved') ...[
          const Text('You\'ve been approved. Pay to switch on your badge.', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          FilledButton(key: const Key('verPay'), onPressed: _busy ? null : _pay, child: Text('Pay ${naira(verifyFee)} and get verified')),
        ] else ...[
          if (st == 'rejected')
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text('Last request not approved: ${u!.verifyReason}. You can apply again.', style: const TextStyle(color: StallColors.red)),
            ),
          TextField(
            key: const Key('verNote'),
            controller: _note,
            maxLines: 3,
            maxLength: 300,
            decoration: const InputDecoration(
                labelText: 'Who are you and what do you sell?', hintText: 'e.g. 300L Accounting student, I sell perfumes from Hall B'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('verPhoto'),
            onPressed: () async {
              final got = await pickListingPhotos(context, 1);
              if (got.isNotEmpty) setState(() => _photo = got.first);
            },
            icon: Icon(_photo == null ? Icons.add_a_photo_outlined : Icons.check_circle_rounded),
            label: Text(_photo == null
                ? 'Photo of your student ID${(u?.isVendor ?? false) ? ' or your shop front' : ''}'
                : 'Photo added · change it'),
          ),
          if (_err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_err!, style: const TextStyle(color: StallColors.red))),
          const SizedBox(height: 16),
          FilledButton(key: const Key('verSend'), onPressed: _busy ? null : _send, child: Text(_busy ? 'Sending…' : 'Send for review')),
        ],
      ]),
    );
  }
}

/// On your own listing: pay to feature it at the top of the feed and search for a few days.
class FeatureListingCard extends StatefulWidget {
  const FeatureListingCard({super.key, required this.id, required this.featured});
  final String id;
  final bool featured;
  @override
  State<FeatureListingCard> createState() => _FeatureListingCardState();
}

class _FeatureListingCardState extends State<FeatureListingCard> {
  bool _busy = false;

  Future<void> _go(int days) async {
    setState(() => _busy = true);
    try {
      if (await payWithCredit(context, {'kind': 'boost', 'target': widget.id, 'days': days}) && mounted) {
        toast(context, 'Featured for $days days');
      }
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(Icons.rocket_launch_outlined, color: StallColors.indigo),
              const SizedBox(width: 8),
              Text(widget.featured ? 'Featured now' : 'Feature this item', style: Theme.of(context).textTheme.titleMedium),
            ]),
            const SizedBox(height: 4),
            Text(
              widget.featured ? 'Add more days to stay at the top.' : 'Show it at the top of the feed and search, marked Featured.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(children: [
              for (final d in listingFeaturePrice.keys) ...[
                if (d != listingFeaturePrice.keys.first) const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    key: Key('feat-$d'),
                    onPressed: _busy ? null : () => _go(d),
                    child: Text('$d days · ${naira(listingFeaturePrice[d]!)}'),
                  ),
                ),
              ],
            ]),
          ]),
        ),
      );
}
