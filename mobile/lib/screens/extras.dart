import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../api.dart';
import '../main.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

// ---- Milestone badges: a seller's 1st, 5th, 10th… sale and a buyer's safe buys, the same as the website.

String ordinal(int n) => '$n${(n % 100 >= 11 && n % 100 <= 13) ? 'th' : ({1: 'st', 2: 'nd', 3: 'rd'}[n % 10] ?? 'th')}';
String badgeName(String k, int n) => k == 'sell' ? (n == 1 ? 'First sale' : '$n sales') : (n == 1 ? 'First safe buy' : '$n safe buys');
String badgeKicker(String k, int n) => k == 'sell'
    ? (n == 1 ? 'Milestone unlocked' : n < 20 ? 'Rising seller' : n < 50 ? 'Trusted seller' : 'Stall legend')
    : (n == 1 ? 'Milestone unlocked' : n < 20 ? 'Smart buyer' : n < 50 ? 'Trusted buyer' : 'Stall loyal');

/// A rosette medal with the milestone number.
class Medal extends StatelessWidget {
  const Medal({super.key, required this.n, this.size = 64, this.dim = false});
  final int n;
  final double size;
  final bool dim;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: dim ? StallColors.cream2 : StallColors.lime,
          border: Border.all(color: dim ? StallColors.line : StallColors.indigo, width: size / 16),
        ),
        alignment: Alignment.center,
        child: Text('$n', style: TextStyle(fontSize: size * .34, fontWeight: FontWeight.w900, color: dim ? StallColors.muted : StallColors.indigo)),
      );
}

/// Account → Badges: what you've earned for selling and buying safely, and how far to the next one.
class BadgesScreen extends StatefulWidget {
  const BadgesScreen({super.key});
  @override
  State<BadgesScreen> createState() => _BadgesScreenState();
}

class _BadgesScreenState extends State<BadgesScreen> {
  Future<Map<String, dynamic>>? _f;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _f ??= _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final api = SessionScope.of(context).api;
    final r = await api.get('me/milestones');
    // Seen now: a new badge is celebrated once.
    for (final k in const ['sell', 'buy']) {
      final fresh = (r[k] as Map?)?['fresh'];
      if (fresh != null) api.post('me/milestones', {'kind': k, 'n': fresh}).catchError((_) => <String, dynamic>{});
    }
    return r;
  }

  Future<void> _share(String k, int n) {
    final d = _data ?? const {};
    final who = (k == 'sell' && d['store'] != null ? d['store'] : d['name']) ?? '';
    return Navigator.of(context).push(MaterialPageRoute(builder: (_) => BadgeCardScreen(kind: k, n: n, who: who.toString())));
  }

  Map<String, dynamic>? _data;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Badges')),
        body: FutureBuilder<Map<String, dynamic>>(
          future: _f,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            if (snap.hasError) return EmptyState(icon: Icons.wifi_off_rounded, title: 'Couldn\'t load your badges', text: snap.error.toString());
            final d = _data = snap.data!;
            final t = Theme.of(context).textTheme;
            final fresh = [for (final k in const ['sell', 'buy']) if ((d[k] as Map?)?['fresh'] != null) (k, ((d[k] as Map)['fresh'] as num).toInt())];
            return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
              for (final (k, n) in fresh)
                Container(
                  key: Key('fresh-$k'),
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: StallColors.indigo, borderRadius: BorderRadius.circular(20)),
                  child: Column(children: [
                    Text(badgeKicker(k, n).toUpperCase(), style: t.bodySmall?.copyWith(color: StallColors.lime, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    Medal(n: n, size: 88),
                    const SizedBox(height: 10),
                    Text(k == 'sell' ? (n == 1 ? 'First sale on Stall!' : '${ordinal(n)} sale on Stall') : (n == 1 ? 'First safe buy on Stall' : '${ordinal(n)} safe buy on Stall'),
                        style: t.titleLarge?.copyWith(color: StallColors.cream)),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: StallColors.lime, foregroundColor: StallColors.indigo),
                      onPressed: () => _share(k, n),
                      icon: const Icon(Icons.ios_share_rounded),
                      label: const Text('Share it'),
                    ),
                  ]),
                ),
              for (final k in const ['sell', 'buy']) ..._side(context, k, d[k] as Map<String, dynamic>? ?? const {}),
            ]);
          },
        ),
      );

  List<Widget> _side(BuildContext context, String k, Map<String, dynamic> s) {
    final t = Theme.of(context).textTheme;
    final count = (s['count'] as num?)?.toInt() ?? 0, next = (s['next'] as num?)?.toInt();
    final earned = (s['earned'] as List? ?? const []).map((e) => (e as num).toInt()).toList();
    return [
      Text(k == 'sell' ? 'Selling' : 'Buying', style: t.titleLarge),
      Text(
          '${k == 'sell' ? '$count completed sale${count == 1 ? '' : 's'}' : '$count safe buy${count == 1 ? '' : 's'}'}'
          '${next != null ? ' · ${next - count} more to ${badgeName(k, next).toLowerCase()}' : ''}',
          key: Key('count-$k'),
          style: t.bodyMedium?.copyWith(color: StallColors.muted)),
      const SizedBox(height: 12),
      Wrap(spacing: 14, runSpacing: 14, children: [
        for (final n in earned)
          InkWell(
            onTap: () => _share(k, n),
            child: Column(children: [Medal(n: n), const SizedBox(height: 4), Text(badgeName(k, n), style: t.bodySmall)]),
          ),
        if (next != null) Column(children: [Medal(n: next, dim: true), const SizedBox(height: 4), Text('Next', style: t.bodySmall)]),
      ]),
      const SizedBox(height: 28),
    ];
  }
}

/// The badge as a picture to share (WhatsApp status), in the website's four looks: first, rising, trusted, legend.
class BadgeCardScreen extends StatefulWidget {
  const BadgeCardScreen({super.key, required this.kind, required this.n, required this.who});
  final String kind, who;
  final int n;
  @override
  State<BadgeCardScreen> createState() => _BadgeCardScreenState();
}

class _BadgeCardScreenState extends State<BadgeCardScreen> {
  final _card = GlobalKey();

  String get _title => widget.kind == 'sell'
      ? (widget.n == 1 ? 'First sale on Stall!' : '${ordinal(widget.n)} sale on Stall')
      : (widget.n == 1 ? 'First safe buy on Stall' : '${ordinal(widget.n)} safe buy on Stall');
  String get _line => widget.kind == 'sell'
      ? (widget.n == 1 ? 'Paid safely, straight to the bank.' : 'Paid safely, every single time.')
      : 'My money was held until it reached me.';

  Future<void> _shareImage() async {
    final api = SessionScope.of(context).api;
    var link = apiBase;
    try {
      link = (await api.get('me/referral'))['link']?.toString() ?? link;
    } catch (_) {}
    final text = '$_title. $_line Join me on Stall: $link';
    try {
      final b = _card.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final png = await (await b.toImage(pixelRatio: 3)).toByteData(format: ui.ImageByteFormat.png);
      await SharePlus.instance.share(ShareParams(files: [XFile.fromData(png!.buffer.asUint8List(), mimeType: 'image/png', name: 'stall-badge.png')], text: text));
    } catch (_) {
      await SharePlus.instance.share(ShareParams(text: text));
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.n;
    // first, rising (dots), trusted (night), legend
    final (bg, ink, mut, fill, ring) = n == 1
        ? (StallColors.cream, StallColors.indigo, StallColors.muted, StallColors.lime, StallColors.indigo)
        : n < 20
            ? (Colors.white, StallColors.indigo, StallColors.muted, StallColors.indigo, StallColors.lime)
            : n < 50
                ? (StallColors.night, StallColors.cream, const Color(0xFF9AA1C9), StallColors.lime, StallColors.night)
                : (StallColors.indigo, StallColors.cream, const Color(0xFFCDD2F0), StallColors.lime, StallColors.cream);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(badgeName(widget.kind, n))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Center(
          child: RepaintBoundary(
            key: _card,
            child: Container(
              width: 320,
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(24), border: Border.all(color: StallColors.line)),
              child: Column(children: [
                Text(badgeKicker(widget.kind, n).toUpperCase(),
                    style: t.labelMedium?.copyWith(color: n >= 20 ? StallColors.lime : StallColors.indigo, letterSpacing: 1.4, fontWeight: FontWeight.w800)),
                const SizedBox(height: 16),
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: fill, border: Border.all(color: ring, width: 7)),
                  alignment: Alignment.center,
                  child: Text('$n',
                      key: const Key('badgeN'),
                      style: TextStyle(fontSize: 44, fontWeight: FontWeight.w900, color: fill == StallColors.lime ? StallColors.indigo : StallColors.lime)),
                ),
                const SizedBox(height: 16),
                Text(_title, textAlign: TextAlign.center, style: t.headlineSmall?.copyWith(color: ink)),
                const SizedBox(height: 6),
                Text(_line, textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: mut)),
                if (widget.who.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(widget.who, textAlign: TextAlign.center, style: t.titleMedium?.copyWith(color: ink)),
                ],
                const SizedBox(height: 18),
                Wordmark(height: 22, light: n >= 20),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(key: const Key('shareBadge'), onPressed: _shareImage, icon: const Icon(Icons.ios_share_rounded), label: const Text('Share the picture')),
        const SizedBox(height: 8),
        Text('Your invite link goes with it, so friends who join give you credit.', textAlign: TextAlign.center, style: t.bodySmall),
      ]),
    );
  }
}

// ---- Receipts

/// Show receipts as the designed page (off in tests, which can't run a web view).
bool receiptWebView = true;

/// A receipt from the server: for an order (path 'orders/receipt', {'id': ..}) or a payment to Stall ('pay/receipt', {'ref': ..}).
class ReceiptScreen extends StatefulWidget {
  const ReceiptScreen({super.key, required this.path, required this.query});
  final String path;
  final Map<String, String> query;
  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  Future<Map<String, dynamic>>? _f;
  WebViewController? _web;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _f ??= SessionScope.of(context).api.get(widget.path, widget.query).then((r) {
      if (receiptWebView) {
        _web = WebViewController()
          ..setBackgroundColor(StallColors.cream)
          ..loadHtmlString('<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">'
              '<body style="margin:0;padding:16px;background:#F6F1E7;display:flex;justify-content:center">${r['html'] ?? ''}</body>', baseUrl: apiBase);
      }
      return r;
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
        future: _f,
        builder: (context, snap) {
          final r = snap.data;
          return Scaffold(
            appBar: AppBar(title: const Text('Receipt'), actions: [
              if (r != null)
                IconButton(
                  key: const Key('shareReceipt'),
                  tooltip: 'Share receipt',
                  onPressed: () => SharePlus.instance.share(ShareParams(text: (r['text'] ?? '').toString(), subject: (r['title'] ?? 'Stall receipt').toString())),
                  icon: const Icon(Icons.ios_share_rounded),
                ),
            ]),
            body: snap.connectionState != ConnectionState.done
                ? const Center(child: CircularProgressIndicator())
                : snap.hasError
                    ? EmptyState(icon: Icons.receipt_long_outlined, title: 'No receipt', text: snap.error is ApiError ? (snap.error as ApiError).message : 'Try again.')
                    : _web != null
                        ? WebViewWidget(controller: _web!)
                        : SingleChildScrollView(padding: const EdgeInsets.all(20), child: SelectableText((r?['text'] ?? '').toString(), key: const Key('receiptText'))),
          );
        },
      );
}

/// Account → Payments to Stall: featuring, store reach, store fee and collections, with receipts.
class PaymentsScreen extends StatelessWidget {
  const PaymentsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Payments to Stall')),
        body: FutureBuilder<Map<String, dynamic>>(
          future: SessionScope.of(context).api.get('pay/mine'),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            final pays = (snap.data?['pays'] as List? ?? const []).cast<Map<String, dynamic>>();
            if (pays.isEmpty) {
              return const EmptyState(
                  icon: Icons.receipt_long_outlined, title: 'No payments yet', text: 'Store fees, featuring, store reach and class collections you pay for show here, with receipts.');
            }
            return ListView.separated(
              itemCount: pays.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final p = pays[i];
                final paid = (p['paid'] as num?)?.toInt() ?? 0, credit = (p['credit'] as num?)?.toInt() ?? 0;
                return ListTile(
                  key: Key('pay-${p['ref']}'),
                  title: Text((p['label'] ?? '').toString()),
                  subtitle: Text('${when((p['t'] as num?)?.toInt() ?? 0)}${credit > 0 ? ' · ${naira(credit)} credit used' : ''}'),
                  trailing: Text(naira(paid), style: const TextStyle(fontWeight: FontWeight.w700)),
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => ReceiptScreen(path: 'pay/receipt', query: {'ref': p['ref'].toString()}))),
                );
              },
            );
          },
        ),
      );
}

// ---- Partner banners (student unions, associations, sponsors), counted for their reach stats.

class PartnerBanner extends StatefulWidget {
  const PartnerBanner({super.key, required this.p});
  final Map<String, dynamic> p;
  @override
  State<PartnerBanner> createState() => _PartnerBannerState();
}

class _PartnerBannerState extends State<PartnerBanner> {
  static final _seen = <Object?>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Counted once per app run; the server keeps one row per person per day.
    if (_seen.add(widget.p['id'])) SessionScope.of(context).api.post('partner/seen', {'id': widget.p['id']}).catchError((_) => <String, dynamic>{});
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p, t = Theme.of(context).textTheme;
    final url = (p['url'] ?? '').toString(), img = (p['img'] ?? '').toString();
    return Card(
      key: Key('partner-${p['id']}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: url.isEmpty
            ? null
            : () {
                SessionScope.of(context).api.post('partner/seen', {'id': p['id'], 'tap': true}).catchError((_) => <String, dynamic>{});
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            if (img.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network('$apiBase$img', width: 56, height: 56, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink())),
              ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text((p['label'] ?? 'Partner').toString().toUpperCase(), style: t.labelSmall?.copyWith(color: StallColors.muted, letterSpacing: 1)),
                Text((p['title'] ?? p['name'] ?? '').toString(), style: t.titleMedium),
                if ((p['text'] ?? '').toString().isNotEmpty) Text(p['text'].toString(), style: t.bodySmall),
                if (url.isNotEmpty && (p['cta'] ?? '').toString().isNotEmpty)
                  Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('${p['cta']} →', style: const TextStyle(color: StallColors.indigo, fontWeight: FontWeight.w700))),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---- Store QR card: print it or put it on your stall, so people can scan straight to your store.

class StoreQrScreen extends StatefulWidget {
  const StoreQrScreen({super.key, required this.store});
  final Store store;
  @override
  State<StoreQrScreen> createState() => _StoreQrScreenState();
}

class _StoreQrScreenState extends State<StoreQrScreen> {
  final _card = GlobalKey();

  String get _link => '$apiBase/?store=${widget.store.id}';

  Future<void> _shareImage() async {
    try {
      final b = _card.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 3);
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      await SharePlus.instance.share(ShareParams(
          files: [XFile.fromData(png!.buffer.asUint8List(), mimeType: 'image/png', name: 'stall-store.png')],
          text: 'Order from ${widget.store.name} on Stall: $_link'));
    } catch (_) {
      await SharePlus.instance.share(ShareParams(text: 'Order from ${widget.store.name} on Stall: $_link'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Store QR card')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Center(
          child: RepaintBoundary(
            key: _card,
            child: Container(
              width: 300,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(color: StallColors.cream, borderRadius: BorderRadius.circular(22), border: Border.all(color: StallColors.line)),
              child: Column(children: [
                const Wordmark(height: 26),
                const SizedBox(height: 14),
                Text(widget.store.name, textAlign: TextAlign.center, style: t.titleLarge),
                if (widget.store.spot.isNotEmpty) Text(widget.store.spot, textAlign: TextAlign.center, style: t.bodySmall),
                const SizedBox(height: 14),
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(10),
                  child: QrImageView(
                    key: const Key('qr'),
                    data: _link,
                    size: 200,
                    eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: StallColors.indigo),
                    dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: StallColors.indigo),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Scan to order. Pay safely: your money is held until you have it.', textAlign: TextAlign.center, style: t.bodySmall),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(key: const Key('shareQr'), onPressed: _shareImage, icon: const Icon(Icons.ios_share_rounded), label: const Text('Share or save the card')),
        const SizedBox(height: 8),
        Text('Print it, or put it on your WhatsApp status.', textAlign: TextAlign.center, style: t.bodySmall),
      ]),
    );
  }
}
