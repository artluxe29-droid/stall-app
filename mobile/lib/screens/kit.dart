import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../api.dart';
import '../main.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

// ---- The "Now on Stall" kit: the website's store cards (Status, Post, Sign, Founding Seller), drawn 360 wide
// like the website and saved at 3x, with captions to copy. Their colours are fixed: they're pictures to share.

const _indigo = Color(0xFF26306E), _deep = Color(0xFF1C2457), _lime = Color(0xFFC8F03C), _cream = Color(0xFFF6F1E7), _grey = Color(0xFFCCCACF);
const _ink = Color(0xFF141A3D);

/// The store's link, with your invite code so you earn when someone joins through it.
Future<String> storeLink(Api api, String id) async {
  var link = '$apiBase/?store=$id';
  try {
    final code = (await api.get('me/referral'))['code']?.toString();
    if (code != null && code.isNotEmpty) link += '&r=$code';
  } catch (_) {}
  return link;
}

String _slug(Store st) {
  final s = st.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
  return 'stall-${s.length > 40 ? s.substring(0, 40) : s}';
}

TextStyle _display(double size, {Color color = _cream}) =>
    TextStyle(fontFamily: 'Bricolage', fontWeight: FontWeight.w800, fontSize: size, height: 1.05, color: color);

/// The striped awning across the top of every card.
class _Awning extends StatelessWidget {
  const _Awning();
  @override
  Widget build(BuildContext context) => Column(children: [
        Container(height: 16, color: _deep),
        SizedBox(
          height: 22,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < 6; i++)
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(color: i.isOdd ? _cream : _lime, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(22))),
                ),
              ),
          ]),
        ),
      ]);
}

/// A card's contents: clipped at the card's edge if a long name or a large phone font makes them run over.
class _Body extends StatelessWidget {
  const _Body(this.child);
  final Widget child;
  @override
  Widget build(BuildContext context) => Positioned.fill(
        child: SingleChildScrollView(physics: const NeverScrollableScrollPhysics(), child: child),
      );
}

/// "No more stalling. Stall it." along the bottom.
class _Band extends StatelessWidget {
  const _Band();
  @override
  Widget build(BuildContext context) => Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Container(
          color: _lime,
          padding: const EdgeInsets.fromLTRB(0, 11, 0, 12),
          alignment: Alignment.center,
          child: Text('No more stalling. Stall it.', style: _display(16, color: _deep)),
        ),
      );
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {this.size = 10.5});
  final String text;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(color: _lime, borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: TextStyle(color: _deep, fontSize: size, fontWeight: FontWeight.w800, letterSpacing: size * .16)),
      );
}

class _Wordmark extends StatelessWidget {
  const _Wordmark({this.w = 63});
  final double w;
  @override
  Widget build(BuildContext context) => Image.asset('assets/receipt/wm-cream.png', width: w, height: w * 26 / 63);
}

/// A QR code that scans well even printed small: high error correction, soft round dots, square eyes.
class KitQr extends StatelessWidget {
  const KitQr(this.url, {super.key, required this.size});
  final String url;
  final double size;
  @override
  Widget build(BuildContext context) => QrImageView(
        key: const Key('qr'),
        data: url,
        size: size,
        padding: EdgeInsets.zero,
        backgroundColor: Colors.white,
        errorCorrectionLevel: QrErrorCorrectLevel.Q,
        eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: _ink),
        dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.circle, color: _ink),
      );
}

class _StoreLogo extends StatelessWidget {
  const _StoreLogo(this.st);
  final Store st;
  @override
  Widget build(BuildContext context) {
    final api = SessionScope.of(context).api;
    final letter = st.name.trim().isEmpty ? 'S' : st.name.trim()[0].toUpperCase();
    final fallback = Container(
      width: 64,
      height: 64,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: _lime, shape: BoxShape.circle),
      child: Text(letter, style: _display(30, color: _deep)),
    );
    if (st.logo == null) return fallback;
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _lime, width: 3)),
      child: ClipOval(child: NetImage(api.url(st.logo!), fit: BoxFit.cover, error: fallback)),
    );
  }
}

/// Status (tall, for WhatsApp Status), Sign (to print for the stand) or Share (anyone sharing a store they like).
class QrCard extends StatelessWidget {
  const QrCard({super.key, required this.st, required this.kind, required this.url});
  final Store st;
  final String kind; // status, print, share
  final String url;

  @override
  Widget build(BuildContext context) {
    final status = kind == 'status';
    final where = [st.school, st.spot].where((x) => x.isNotEmpty).join(' · ');
    return Container(
      width: 360,
      height: status ? 640 : 560,
      color: _indigo,
      child: Stack(children: [
        _Body(Column(children: [
          const _Awning(),
          Padding(
            padding: EdgeInsets.fromLTRB(26, status ? 34 : 20, 26, 0),
            child: Column(children: [
              const _Wordmark(),
              SizedBox(height: status ? 18 : 12),
              _Pill(status ? 'NOW ON STALL' : (kind == 'share' ? 'ORDER ON STALL' : 'ORDER FROM US ON STALL')),
              SizedBox(height: status ? 22 : 14),
              _StoreLogo(st),
              const SizedBox(height: 12),
              Text(st.name, textAlign: TextAlign.center, maxLines: 2, style: _display(st.name.length > 18 ? 24 : 30)),
              if (where.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(where, textAlign: TextAlign.center, style: const TextStyle(color: _grey, fontSize: 12.5)),
              ],
              SizedBox(height: status ? 24 : 16),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: _lime, width: 6)),
                child: KitQr(url, size: status ? 176 : 150),
              ),
              const SizedBox(height: 12),
              Text(status ? 'Find my store on Stall' : 'Scan to see the menu and order', style: _display(17)),
              const SizedBox(height: 4),
              const Text('Pay safely. Your money is held until it reaches you.',
                  textAlign: TextAlign.center, style: TextStyle(color: _grey, fontSize: 12)),
            ]),
          ),
        ])),
        const _Band(),
      ]),
    );
  }
}

/// The square post for Instagram, Facebook and WhatsApp groups.
class PostCard extends StatelessWidget {
  const PostCard({super.key, required this.st, required this.url});
  final Store st;
  final String url;
  @override
  Widget build(BuildContext context) {
    final where = [st.school, st.spot].where((x) => x.isNotEmpty).join(' · ');
    return Container(
      width: 360,
      height: 360,
      color: _indigo,
      child: Stack(children: [
        _Body(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const _Awning(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const _Wordmark(w: 53),
                  const SizedBox(height: 14),
                  Text.rich(TextSpan(style: _display(33, color: _cream).copyWith(height: 1), children: const [
                    TextSpan(text: 'We\'re now on '),
                    TextSpan(text: 'Stall.', style: TextStyle(color: _lime)),
                  ])),
                  const SizedBox(height: 12),
                  Text(st.name, maxLines: 2, style: _display(st.name.length > 18 ? 14 : 20, color: _lime)),
                  if (where.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(where, style: const TextStyle(color: _grey, fontSize: 11.5)),
                  ],
                ]),
              ),
              const SizedBox(width: 14),
              Column(children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _lime, width: 5)),
                  child: KitQr(url, size: 98),
                ),
                const SizedBox(height: 6),
                const Text('Scan to order', style: TextStyle(color: _cream, fontSize: 11, fontWeight: FontWeight.w700)),
              ]),
            ]),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text('Order from us in a few taps and pay safely. Your money is held until your order reaches you.',
                style: TextStyle(color: _grey, fontSize: 12.5, height: 1.4)),
          ),
        ])),
        Positioned(
          left: 20,
          right: 20,
          bottom: 54,
          child: Row(children: [
            for (final (i, t) in const ['Pay safely', 'Order in-app', 'Pickup or delivery'].indexed) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(color: _deep, borderRadius: BorderRadius.circular(99)),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.check_rounded, size: 12, color: _lime),
                      const SizedBox(width: 3),
                      Text(t, style: const TextStyle(color: _cream, fontSize: 10.5, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              ),
            ],
          ]),
        ),
        const _Band(),
      ]),
    );
  }
}

/// The Founding Seller medal: a lime rosette with ribbons, the store's number in the middle.
class _FoundingMedal extends CustomPainter {
  const _FoundingMedal();
  @override
  void paint(Canvas c, Size s) {
    final k = s.width / 220;
    c.scale(k);
    final cream = Paint()..color = _cream;
    c.drawPath(Path()..moveTo(62, 150)..lineTo(40, 246)..lineTo(72, 226)..lineTo(92, 248)..lineTo(110, 160)..close(), cream);
    c.drawPath(Path()..moveTo(158, 150)..lineTo(180, 246)..lineTo(148, 226)..lineTo(128, 248)..lineTo(110, 160)..close(), cream);
    final lime = Paint()..color = _lime;
    for (var i = 0; i < 24; i++) {
      final a = i * math.pi / 12;
      c.drawCircle(Offset(110 + 92 * math.cos(a), 110 + 92 * math.sin(a)), 15, lime);
    }
    c.drawCircle(const Offset(110, 110), 94, lime);
    c.drawCircle(const Offset(110, 110), 78, Paint()..color = _deep);
    final dash = Paint()
      ..color = _lime
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    const r = 70.0, steps = 63;
    for (var i = 0; i < steps; i++) {
      final a0 = i * 2 * math.pi / steps;
      c.drawArc(Rect.fromCircle(center: const Offset(110, 110), radius: r), a0, 2 * math.pi / steps * .43, false, dash);
    }
  }

  @override
  bool shouldRepaint(_FoundingMedal old) => false;
}

class FoundingCard extends StatelessWidget {
  const FoundingCard({super.key, required this.st, required this.url, required this.firstN});
  final Store st;
  final String url;
  final int firstN;
  @override
  Widget build(BuildContext context) {
    final school = st.school.isEmpty ? 'STALL' : st.school.toUpperCase();
    return Container(
      width: 360,
      height: 640,
      color: _indigo,
      child: Stack(children: [
        _Body(Column(children: [
          const _Awning(),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 0),
            child: Column(children: [
              const _Wordmark(),
              const SizedBox(height: 14),
              const _Pill('FOUNDING SELLER', size: 11),
              const SizedBox(height: 16),
              SizedBox(
                width: 220,
                height: 250,
                child: Stack(children: [
                  const Positioned.fill(child: CustomPaint(painter: _FoundingMedal())),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 56,
                    child: Column(children: [
                      const Text('NO.', style: TextStyle(color: _lime, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.7)),
                      const SizedBox(height: 2),
                      Text('${st.founding}', style: _display(st.founding > 99 ? 54 : 68).copyWith(height: 1)),
                      const SizedBox(height: 6),
                      Text(school.length > 14 ? school.substring(0, 14) : school,
                          style: const TextStyle(color: _lime, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .7)),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 8),
              Text(st.name, textAlign: TextAlign.center, maxLines: 2, style: _display(st.name.length > 18 ? 22 : 28)),
              const SizedBox(height: 6),
              Text('One of the first $firstN sellers${st.school.isEmpty ? '' : ' at ${st.school}'} on Stall',
                  textAlign: TextAlign.center, style: const TextStyle(color: _grey, fontSize: 13)),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
                decoration: BoxDecoration(color: _cream, borderRadius: BorderRadius.circular(16)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  KitQr(url, size: 74),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Shop with us', style: _display(16, color: _deep)),
                    const SizedBox(height: 3),
                    const Text('Scan to visit the store', style: TextStyle(color: _deep, fontSize: 11.5)),
                  ]),
                ]),
              ),
            ]),
          ),
        ])),
        const _Band(),
      ]),
    );
  }
}

/// Turns the card on screen into a PNG at 3x (1080 wide), the same size the website saves.
Future<Uint8List> _png(GlobalKey key) async {
  final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final img = await b.toImage(pixelRatio: 3);
  return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

/// One card with Share, (for the sign) Save PDF, and the captions to copy.
class _KitSheet extends StatefulWidget {
  const _KitSheet({super.key, required this.card, required this.note, required this.file, required this.text, this.pdf = false, this.captions = const []});
  final Widget card;
  final String note, file, text;
  final bool pdf;
  final List<String> captions;
  @override
  State<_KitSheet> createState() => _KitSheetState();
}

class _KitSheetState extends State<_KitSheet> {
  final _key = GlobalKey();
  bool _busy = false;

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } catch (_) {
      if (mounted) toast(context, 'Couldn\'t make the picture. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    final png = await _png(_key);
    await SharePlus.instance.share(ShareParams(files: [XFile.fromData(png, mimeType: 'image/png', name: '${widget.file}.png')], text: widget.text));
  }

  /// The sign as an A5 PDF to print, with the card filling the page.
  Future<void> _pdf() async {
    final png = await _png(_key);
    final doc = pw.Document();
    final img = pw.MemoryImage(png);
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(18),
      build: (_) => pw.Center(child: pw.Image(img, fit: pw.BoxFit.contain)),
    ));
    final bytes = await doc.save();
    await SharePlus.instance.share(ShareParams(files: [XFile.fromData(bytes, mimeType: 'application/pdf', name: '${widget.file}.pdf')]));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Container(
            decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Color(0x38161A33), blurRadius: 26, offset: Offset(0, 18))]),
            child: RepaintBoundary(key: _key, child: widget.card),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Text(widget.note, textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: StallColors.muted)),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(
          child: FilledButton.icon(
            key: const Key('kitShare'),
            onPressed: _busy ? null : () => _run(_share),
            icon: const Icon(Icons.ios_share_rounded),
            label: const Text('Share or save'),
          ),
        ),
        if (widget.pdf) ...[
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              key: const Key('kitPdf'),
              onPressed: _busy ? null : () => _run(_pdf),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('PDF to print'),
            ),
          ),
        ],
      ]),
      if (widget.captions.isNotEmpty) ...[
        const SizedBox(height: 22),
        Text('Captions to copy', style: t.titleMedium),
        const SizedBox(height: 8),
        for (final (i, c) in widget.captions.indexed)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(c, style: const TextStyle(fontSize: 14)),
              trailing: TextButton(
                key: Key('copy-$i'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: c));
                  if (context.mounted) toast(context, 'Copied');
                },
                child: const Text('Copy'),
              ),
            ),
          ),
      ],
    ]);
  }
}

/// Your store's "Now on Stall" kit. [fresh] when the store has just opened.
class StallKitScreen extends StatefulWidget {
  const StallKitScreen({super.key, required this.store, this.tab, this.fresh = false});
  final Store store;
  final String? tab;
  final bool fresh;
  @override
  State<StallKitScreen> createState() => _StallKitScreenState();
}

class _StallKitScreenState extends State<StallKitScreen> {
  late String _tab = widget.tab ?? (widget.fresh && widget.store.founding > 0 ? 'founding' : 'status');
  Future<String>? _url;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _url ??= storeLink(SessionScope.of(context).api, widget.store.id);
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.store;
    final t = Theme.of(context).textTheme;
    final firstN = (SessionScope.of(context).config['foundingN'] as num?)?.toInt() ?? 50;
    final sch = st.school.isEmpty ? '' : ' at ${st.school}';
    return Scaffold(
      appBar: AppBar(title: const Text('Now on Stall kit')),
      body: FutureBuilder<String>(
        future: _url,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final url = snap.data!;
          final tabs = <String, (String, Widget, String, String, bool)>{
            'status': (
              'Status',
              QrCard(st: st, kind: 'status', url: url),
              'Post it on your WhatsApp Status. Anyone who scans lands on your store.',
              'We\'re now on Stall! Order from ${st.name} and pay safely. Your money is held until your order reaches you: $url',
              false
            ),
            'post': (
              'Post',
              PostCard(st: st, url: url),
              'A square post for Instagram, Facebook or your WhatsApp groups.',
              '${st.name} is now on Stall 🎉 Order from us in a few taps. Pay safely, your money is held until it reaches you. No more stalling. Stall it: $url',
              false
            ),
            'sign': (
              'Sign',
              QrCard(st: st, kind: 'print', url: url),
              'Print it and stick it on your stand, counter or door. Laminate it if it goes outside.',
              'Order from ${st.name} on Stall: $url',
              true
            ),
            if (st.founding > 0)
              'founding': (
                'Founding Seller',
                FoundingCard(st: st, url: url, firstN: firstN),
                'You\'re Founding Seller No. ${st.founding}$sch. This badge stays on your store for life.',
                'We\'re Founding Seller No. ${st.founding}$sch on Stall 🏅 One of the first $firstN stores here. Shop with us: $url',
                false
              ),
          };
          final tab = tabs.containsKey(_tab) ? _tab : 'status';
          final (_, card, note, text, pdf) = tabs[tab]!;
          return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
            if (widget.fresh) ...[
              Text(st.founding > 0 ? 'You are Founding Seller No. ${st.founding}' : 'Your store is live',
                  textAlign: TextAlign.center, style: t.titleLarge),
              const SizedBox(height: 4),
              Text('Tell people where to find you.', textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: StallColors.muted)),
              const SizedBox(height: 12),
            ],
            Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
              for (final e in tabs.entries)
                ChoiceChip(
                  key: Key('kit-${e.key}'),
                  label: Text(e.value.$1),
                  avatar: e.key == 'founding' ? Icon(Icons.military_tech_outlined, size: 18, color: e.key == tab ? StallColors.onBrand : StallColors.indigo) : null,
                  selected: e.key == tab,
                  showCheckmark: false,
                  selectedColor: StallColors.indigo,
                  labelStyle: TextStyle(fontWeight: FontWeight.w600, color: e.key == tab ? StallColors.onBrand : StallColors.ink),
                  onSelected: (_) => setState(() => _tab = e.key),
                ),
            ]),
            const SizedBox(height: 16),
            _KitSheet(
              key: ValueKey(tab),
              card: card,
              note: note,
              file: '${_slug(st)}-$tab',
              text: text,
              pdf: pdf,
              captions: [for (final v in tabs.values) v.$4],
            ),
          ]);
        },
      ),
    );
  }
}

/// Anyone can share a store they like: a branded card with its QR code, plus the link to copy.
class ShareStoreScreen extends StatefulWidget {
  const ShareStoreScreen({super.key, required this.store});
  final Store store;
  @override
  State<ShareStoreScreen> createState() => _ShareStoreScreenState();
}

class _ShareStoreScreenState extends State<ShareStoreScreen> {
  Future<String>? _url;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _url ??= storeLink(SessionScope.of(context).api, widget.store.id);
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.store;
    return Scaffold(
      appBar: AppBar(title: const Text('Share this store')),
      body: FutureBuilder<String>(
        future: _url,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final url = snap.data!;
          return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
            _KitSheet(
              card: QrCard(st: st, kind: 'share', url: url),
              note: 'Send it to friends or post it. Anyone who scans lands on this store.',
              file: _slug(st),
              text: 'Order from ${st.name} on Stall. Pay safely, your money is held until it reaches you: $url',
            ),
            const SizedBox(height: 14),
            Card(
              child: ListTile(
                title: Text(url, style: const TextStyle(fontSize: 13)),
                trailing: TextButton(
                  key: const Key('copyLink'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: url));
                    if (context.mounted) toast(context, 'Copied');
                  },
                  child: const Text('Copy link'),
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }
}
