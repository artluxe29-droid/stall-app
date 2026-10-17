import 'dart:math' as math;

import 'package:flutter/material.dart';

/// One of the website's four badge looks (MST in index.html): first, rising (dots), trusted (night) and legend.
class _Look {
  const _Look(this.bg, this.ink, this.mut, this.fill, this.ring, this.num, this.wm, {this.top, this.mark, this.img, required this.edge});
  final Color bg, ink, mut, fill, ring, num;
  final String wm, edge;
  final String? top, mark, img;
}

const _indigo = Color(0xFF26306E), _lime = Color(0xFFC8F03C), _night = Color(0xFF141A3D), _cream = Color(0xFFF6F1E7), _muted = Color(0xFF5B6077);

_Look _look(int n) => n == 1
    ? const _Look(_cream, _indigo, _muted, _lime, _indigo, _indigo, 'wm-indigo', top: 'awning-cream', edge: 'edge-cream')
    : n < 20
        ? const _Look(Colors.white, _indigo, _muted, _indigo, _lime, _lime, 'wm-indigo', mark: 'mark-indigo', img: 'dots', edge: 'edge-white')
        : n < 50
            ? const _Look(_night, _cream, Color(0xFF9AA1C9), _lime, _night, _night, 'wm-cream', top: 'awning-night', img: 'night-glow', edge: 'edge-night')
            : const _Look(_indigo, _cream, Color(0xFFCDD2F0), _lime, _cream, _indigo, 'wm-cream', mark: 'mark-cream', edge: 'edge-indigo');

String _ord(int n) => '$n${(n % 100 >= 11 && n % 100 <= 13) ? 'th' : ({1: 'st', 2: 'nd', 3: 'rd'}[n % 10] ?? 'th')}';

/// The scalloped rosette behind the number: the awning's scallops all the way round, with a ring inside.
class MedalPainter extends CustomPainter {
  const MedalPainter(this.fill, this.ring);
  final Color fill, ring;
  @override
  void paint(Canvas c, Size s) {
    final k = s.width / 480, cx = s.width / 2, cy = s.height / 2, r = 176 * k;
    const n = 20;
    final p = Paint()..color = fill;
    c.drawCircle(Offset(cx, cy), r, p);
    for (var i = 0; i < n; i++) {
      final a = i / n * math.pi * 2;
      c.drawCircle(Offset(cx + math.cos(a) * r, cy + math.sin(a) * r), r * math.pi / n * 1.02, p);
    }
    c.drawCircle(Offset(cx, cy), r - 26 * k, Paint()
      ..color = ring
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7 * k);
  }

  @override
  bool shouldRepaint(MedalPainter o) => o.fill != fill || o.ring != ring;
}

/// A rosette with the milestone number, for lists (the website's medal at a small size).
class Rosette extends StatelessWidget {
  const Rosette({super.key, required this.n, this.size = 64, this.dim = false});
  final int n;
  final double size;
  final bool dim;
  @override
  Widget build(BuildContext context) {
    final t = _look(n);
    final fill = dim ? const Color(0xFFEDE7DA) : t.fill, ring = dim ? const Color(0xFFE2DCCD) : t.ring, num = dim ? _muted : t.num;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: MedalPainter(fill, ring),
        child: Center(
          child: Text(n == 1 ? '1st' : '$n',
              style: TextStyle(fontFamily: 'Bricolage', fontWeight: FontWeight.w800, fontSize: size * (n >= 100 ? .26 : .3), color: num, height: 1)),
        ),
      ),
    );
  }
}

/// The milestone badge exactly as the website draws it (badgeHtml in index.html), 360 wide.
class BadgeCard extends StatelessWidget {
  const BadgeCard({super.key, required this.kind, required this.n, this.who = '', this.school = '', this.host = 'stall.com.ng'});
  final String kind, who, school, host;
  final int n;

  String get kicker => kind == 'sell'
      ? (n == 1 ? 'Milestone unlocked' : n < 20 ? 'Rising seller' : n < 50 ? 'Trusted seller' : 'Stall legend')
      : (n == 1 ? 'Milestone unlocked' : n < 20 ? 'Smart buyer' : n < 50 ? 'Trusted buyer' : 'Stall loyal');
  String get title => kind == 'sell' ? (n == 1 ? 'First sale on Stall!' : '${_ord(n)} sale on Stall') : (n == 1 ? 'First safe buy on Stall' : '${_ord(n)} safe buy on Stall');
  String get line => kind == 'sell' ? (n == 1 ? 'Paid safely, straight to the bank.' : 'Paid safely, every single time.') : 'My money was held until it reached me.';

  @override
  Widget build(BuildContext context) {
    final t = _look(n);
    Widget img(String f, {double? w, double? h}) => Image.asset('assets/receipt/$f.png', width: w, height: h, fit: BoxFit.fill);
    final unit = kind == 'sell' ? (n == 1 ? 'sale' : 'sales') : (n == 1 ? 'buy' : 'buys');
    return SizedBox(
      width: 360,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (t.top != null)
          ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(22)), child: Container(color: t.bg, child: img(t.top!, w: 360, h: 74))),
        Container(
          width: 360,
          padding: EdgeInsets.fromLTRB(26, t.top != null ? 10 : 26, 26, 22),
          decoration: BoxDecoration(
            color: t.bg,
            borderRadius: t.top != null ? null : const BorderRadius.vertical(top: Radius.circular(22)),
            image: t.img == null
                ? null
                : DecorationImage(
                    image: AssetImage('assets/receipt/${t.img}.png'),
                    repeat: t.img == 'dots' ? ImageRepeat.repeat : ImageRepeat.noRepeat,
                    alignment: Alignment.topCenter,
                    scale: t.img == 'dots' ? 2 : 2, // the files are drawn at twice the size they show
                  ),
          ),
          child: Column(children: [
            if (t.mark != null) Padding(padding: const EdgeInsets.only(bottom: 4), child: img(t.mark!, w: 86, h: 80)),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(kicker.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 11 * .18, color: t.mut)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
              child: SizedBox.square(
                dimension: 190,
                child: CustomPaint(
                  painter: MedalPainter(t.fill, t.ring),
                  child: Stack(children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: n == 1 ? 52 : 46,
                      child: Text(n == 1 ? '1st' : '$n',
                          key: const Key('badgeN'),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontFamily: 'Bricolage', fontWeight: FontWeight.w800, fontSize: n >= 100 ? 52 : n == 1 ? 60 : 64, height: 1, color: t.num)),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: n == 1 ? 118 : 116,
                      child: Text(unit.toUpperCase(),
                          textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 12 * .2, color: t.num)),
                    ),
                  ]),
                ),
              ),
            ),
            Text(title,
                textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Bricolage', fontWeight: FontWeight.w800, fontSize: 27, height: 1.1, color: t.ink)),
            if (who.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: who),
                    if (school.isNotEmpty) TextSpan(text: ' · $school', style: TextStyle(fontWeight: FontWeight.w500, color: t.mut)),
                  ]),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: t.ink),
                ),
              ),
            Padding(padding: const EdgeInsets.only(top: 4), child: Text(line, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: t.mut))),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 16, 0, 12),
              child: CustomPaint(size: const Size(double.infinity, 1.5), painter: _Dashes(t.mut.withValues(alpha: .9))),
            ),
            img(t.wm, w: 63, h: 26),
            Padding(padding: const EdgeInsets.only(top: 6), child: Text('Buy and sell safely · $host', style: TextStyle(fontSize: 11.5, color: t.mut))),
          ]),
        ),
        img(t.edge, w: 360, h: 14),
      ]),
    );
  }
}

class _Dashes extends CustomPainter {
  const _Dashes(this.color);
  final Color color;
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = color
      ..strokeWidth = s.height;
    for (double x = 0; x < s.width; x += 7) {
      c.drawLine(Offset(x, s.height / 2), Offset(math.min(x + 4, s.width), s.height / 2), p);
    }
  }

  @override
  bool shouldRepaint(_Dashes o) => o.color != color;
}
