import 'dart:convert';

import 'package:flutter/material.dart';

import '../api.dart';
import '../main.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'sell.dart' show pickListingPhotos, sellerRules;

class _Row {
  final title = TextEditingController(), price = TextEditingController(), qty = TextEditingController(text: '1');
  String? photo, status, error;
  bool get empty => title.text.trim().isEmpty && price.text.trim().isEmpty && photo == null;
  int get p => int.tryParse(price.text.replaceAll(RegExp(r'\D'), '')) ?? 0;
  void dispose() {
    title.dispose();
    price.dispose();
    qty.dispose();
  }
}

/// Add several items at once: one photo, a name and a price each, up to 10. To your listings, or (with [storeName]) to your store.
class BulkAddScreen extends StatefulWidget {
  const BulkAddScreen({super.key, this.storeName});
  final String? storeName;
  @override
  State<BulkAddScreen> createState() => _BulkAddScreenState();
}

class _BulkAddScreenState extends State<BulkAddScreen> {
  final _rows = List.generate(3, (_) => _Row());
  final _spot = TextEditingController();
  String _cat = Category.all.first.id, _cond = 'Like new';
  String? _err;
  bool _busy = false;

  bool get _store => widget.storeName != null;

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    _spot.dispose();
    super.dispose();
  }

  Future<void> _post({bool retried = false}) async {
    final rows = _rows.where((r) => !r.empty && r.status != '✓').toList();
    if (rows.isEmpty) return setState(() => _err = 'Fill in at least one item.');
    final bad = rows.where((r) => r.title.text.trim().length < 3 || r.p < 500 || r.photo == null).toList();
    if (bad.isNotEmpty || (!_store && _spot.text.trim().length < 2)) {
      return setState(() => _err = !_store && _spot.text.trim().length < 2
          ? 'Add a meet-up spot.'
          : 'Each item needs a photo, a name and a price of at least ₦500.');
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    final s = SessionScope.of(context);
    var ok = 0;
    for (final r in rows) {
      setState(() => r.status = '…');
      try {
        final qty = int.tryParse(r.qty.text.trim());
        if (_store) {
          await s.api.post('stores/item', {'title': r.title.text.trim(), 'price': r.p, 'qty': qty ?? '', 'desc': '', 'imgs': [r.photo]});
        } else {
          await s.api.post('listings', {
            'title': r.title.text.trim(),
            'price': r.p,
            'qty': qty ?? 1,
            'cat': _cat,
            'cond': _cond,
            'spot': _spot.text.trim(),
            'desc': '',
            'seller': s.user?.name ?? '',
            'phone': s.user?.phone ?? '',
            'imgs': [r.photo],
          });
        }
        ok++;
        setState(() {
          r.status = '✓';
          r.error = null;
        });
      } on ApiError catch (e) {
        if (e.data['need'] == 'seller_ok' && !retried && mounted) {
          setState(() {
            r.status = null;
            _busy = false;
          });
          if (await sellerRules(context)) return _post(retried: true);
          return;
        }
        setState(() {
          r.status = '✕';
          r.error = e.message;
        });
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok == rows.length) {
      toast(context, 'Posted $ok item${ok == 1 ? '' : 's'}. Stall is checking the photos.');
      Navigator.pop(context, true);
    } else {
      setState(() => _err = '$ok posted, ${rows.length - ok} need fixing (see below).');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = SessionScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Add several items')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_store ? 'Add up to 10 items to ${widget.storeName}.' : 'One photo, a name and a price for each, up to 10 at a time. You can add more photos and details later.',
              style: t.bodyMedium?.copyWith(color: StallColors.muted)),
          if (!_store) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _cat,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [for (final c in Category.all) DropdownMenuItem(value: c.id, child: Text(c.name))],
                  onChanged: (v) => setState(() => _cat = v ?? _cat),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _cond,
                  decoration: const InputDecoration(labelText: 'Condition'),
                  items: [for (final c in const ['New', 'Like new', 'Used']) DropdownMenuItem(value: c, child: Text(c))],
                  onChanged: (v) => setState(() => _cond = v ?? _cond),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(key: const Key('bkSpot'), controller: _spot, maxLength: 40, decoration: const InputDecoration(labelText: 'Meet-up spot', hintText: 'e.g. Library steps', counterText: '')),
          ],
          for (final (i, r) in _rows.indexed)
            Card(
              margin: const EdgeInsets.only(top: 12),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  InkWell(
                    key: Key('bkPhoto-$i'),
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      final got = await pickListingPhotos(context, 1);
                      if (got.isNotEmpty && mounted) setState(() => r.photo = got.first);
                    },
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(color: StallColors.cream2, borderRadius: BorderRadius.circular(12)),
                      clipBehavior: Clip.antiAlias,
                      child: r.photo == null
                          ? const Icon(Icons.add_a_photo_outlined, color: StallColors.indigo)
                          : Image.memory(base64Decode(r.photo!.split(',').last), fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      TextField(
                          key: Key('bkTitle-$i'),
                          controller: r.title,
                          maxLength: 60,
                          decoration: const InputDecoration(hintText: 'What is it?', isDense: true, counterText: '')),
                      const SizedBox(height: 6),
                      Row(children: [
                        Expanded(
                          child: TextField(
                              key: Key('bkPrice-$i'),
                              controller: r.price,
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(hintText: 'Price', prefixText: '₦ ', isDense: true)),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 74,
                          child: TextField(
                              controller: r.qty,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(hintText: 'How many', isDense: true)),
                        ),
                      ]),
                      if (r.p >= 500)
                        Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('You get ${naira(r.p - s.feeOf(r.p))} after Stall\'s ${naira(s.feeOf(r.p))} fee', style: t.bodySmall)),
                      if (r.error != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(r.error!, style: const TextStyle(color: StallColors.red))),
                    ]),
                  ),
                  if (r.status != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 6, top: 10),
                      child: Text(r.status!, key: Key('bkSt-$i'), style: TextStyle(fontWeight: FontWeight.w900, color: r.status == '✕' ? StallColors.red : StallColors.green)),
                    ),
                ]),
              ),
            ),
          if (_rows.length < 10)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                  key: const Key('bkMore'), onPressed: () => setState(() => _rows.add(_Row())), icon: const Icon(Icons.add_rounded), label: const Text('Add another item')),
            ),
          if (_err != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_err!, key: const Key('bkErr'), style: const TextStyle(color: StallColors.red))),
          FilledButton(key: const Key('bkPost'), onPressed: _busy ? null : _post, child: Text(_busy ? 'Posting…' : 'Post all')),
        ]),
      ),
    );
  }
}
