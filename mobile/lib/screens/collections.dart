import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../api.dart';
import '../bank.dart';
import '../collect_export.dart';
import '../main.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'account_setup.dart' show VerifyStudentScreen;
import 'my_store.dart' show payStall;

/// The link people open to pay into a collection.
String collectLink(String code) => '$apiBase/?collect=$code';

Future<void> shareCollection(String code, String title) =>
    SharePlus.instance.share(ShareParams(text: 'Pay for "$title" on Stall: ${collectLink(code)} (or enter code $code in Stall → Account → Class collections)', subject: title));

/// Class collections: money a class rep collects (handouts, dues, a party), paid straight to their bank through Paystack.
class CollectionsScreen extends StatefulWidget {
  const CollectionsScreen({super.key});
  @override
  State<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends State<CollectionsScreen> {
  Future<Map<String, dynamic>>? _f;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _f ??= SessionScope.of(context).api.get('collect/mine');
  }

  void _reload() => setState(() {
        _f = SessionScope.of(context).api.get('collect/mine');
      });

  Future<void> _enterCode() async {
    var code = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pay into a collection'),
        content: TextField(
          key: const Key('coCode'),
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          onChanged: (v) => code = v,
          decoration: const InputDecoration(hintText: 'The code from your class rep, e.g. AB12CD'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(key: const Key('coCodeGo'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Open')),
        ],
      ),
    );
    // Accept a pasted link too.
    final c = (RegExp(r'collect=([A-Za-z0-9]+)').firstMatch(code)?.group(1) ?? code).trim().toUpperCase();
    if (ok == true && c.isNotEmpty && mounted) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CollectionScreen(code: c)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Class collections')),
        body: FutureBuilder<Map<String, dynamic>>(
          future: _f,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            final t = Theme.of(context).textTheme;
            final items = (snap.data?['items'] as List? ?? const []).cast<Map<String, dynamic>>();
            return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
              Text('Collect money from your class for handouts, dues or a party. It goes straight to your bank through Paystack, and you see who has paid.',
                  style: t.bodyMedium?.copyWith(color: StallColors.muted)),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('coNew'),
                onPressed: () async {
                  final made = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => NewCollectionScreen(bankSet: snap.data?['bank'] != null)));
                  if (made == true) _reload();
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text('New collection'),
              ),
              OutlinedButton.icon(
                key: const Key('coPay'),
                onPressed: _enterCode,
                icon: const Icon(Icons.qr_code_rounded),
                label: const Text('Pay into a collection'),
              ),
              if (snap.hasError) Padding(padding: const EdgeInsets.only(top: 16), child: Text(snap.error.toString())),
              if (items.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('Your collections', style: t.titleMedium),
                for (final c in items)
                  Card(
                    margin: const EdgeInsets.only(top: 10),
                    child: ListTile(
                      key: Key('co-${c['code']}'),
                      title: Text((c['title'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                          '${naira((c['amount'] as num?) ?? 0)} each · ${c['n']}${c['expected'] != null ? ' of ${c['expected']}' : ''} paid · ${naira((c['total'] as num?) ?? 0)}'
                          '${c['open'] == true ? '' : ' · Closed'}'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () async {
                        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CollectionScreen(code: c['code'].toString())));
                        _reload();
                      },
                    ),
                  ),
              ],
            ]);
          },
        ),
      );
}

/// Start a collection: what it's for, how much each person pays, optional head count and closing date.
class NewCollectionScreen extends StatefulWidget {
  const NewCollectionScreen({super.key, required this.bankSet});
  final bool bankSet;
  @override
  State<NewCollectionScreen> createState() => _NewCollectionScreenState();
}

class _NewCollectionScreenState extends State<NewCollectionScreen> {
  final _c = {for (final k in ['title', 'cls', 'descr', 'amount', 'expected']) k: TextEditingController()};
  DateTime? _deadline;
  bool _public = false, _busy = false;
  BankChoice? _bank;
  String? _err;

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String v(String k) => _c[k]!.text.trim();

  Future<void> _create() async {
    if (!widget.bankSet && _bank == null) return setState(() => _err = 'Add and verify the account the money goes to.');
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final d = _deadline;
      final r = await SessionScope.of(context).api.post('collect/create', {
        'title': v('title'),
        'cls': v('cls'),
        'descr': v('descr'),
        'amount': int.tryParse(v('amount').replaceAll(RegExp(r'\D'), '')) ?? 0,
        if (v('expected').isNotEmpty) 'expected': int.tryParse(v('expected')) ?? 0,
        if (d != null) 'deadline': '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
        'public_list': _public,
        if (_bank != null) ...{'bank_code': _bank!.code, 'acct_no': _bank!.acct},
      });
      if (!mounted) return;
      final code = r['code'].toString();
      toast(context, 'Collection created. Share the link with your class.');
      Navigator.of(context).pop(true);
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => CollectionScreen(code: code)));
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _err = e.message);
      if (e.data['verify'] == true) Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VerifyStudentScreen()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final d = _deadline;
    return Scaffold(
      appBar: AppBar(title: const Text('New collection')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
              key: const Key('coTitle'),
              controller: _c['title'],
              maxLength: 80,
              decoration: const InputDecoration(labelText: 'What it\'s for', hintText: 'e.g. CSC 301 handout', counterText: '')),
          const SizedBox(height: 12),
          TextField(controller: _c['cls'], maxLength: 60, decoration: const InputDecoration(labelText: 'Class or group (optional)', hintText: 'e.g. 300L Computer Science', counterText: '')),
          const SizedBox(height: 12),
          TextField(
              key: const Key('coAmount'),
              controller: _c['amount'],
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Amount per person', prefixText: '₦ ')),
          const SizedBox(height: 12),
          TextField(
              controller: _c['expected'],
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'How many should pay? (optional)', hintText: 'Shows "45 of 60 paid"')),
          const SizedBox(height: 12),
          TextField(controller: _c['descr'], maxLength: 300, maxLines: 3, decoration: const InputDecoration(labelText: 'Details (optional)')),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.event_outlined, color: StallColors.indigo),
            title: Text(d == null ? 'No closing date' : 'Closes at the end of ${d.day}/${d.month}/${d.year}'),
            trailing: TextButton(
              onPressed: () async {
                final now = DateTime.now();
                final p = await showDatePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 365)), initialDate: d ?? now.add(const Duration(days: 7)));
                if (p != null) setState(() => _deadline = p);
              },
              child: Text(d == null ? 'Add one' : 'Change'),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show who has paid to everyone in the collection'),
            subtitle: const Text('Names only, never amounts or references. You always see the full list.'),
            value: _public,
            onChanged: (x) => setState(() => _public = x),
          ),
          if (!widget.bankSet) ...[
            const SizedBox(height: 8),
            Text('Where the money goes', style: t.titleMedium),
            const SizedBox(height: 8),
            BankBox(keyPrefix: 'co', onChanged: (b) => setState(() => _bank = b)),
          ],
          if (_err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_err!, key: const Key('coErr'), style: const TextStyle(color: StallColors.red))),
          const SizedBox(height: 16),
          FilledButton(key: const Key('coCreate'), onPressed: _busy ? null : _create, child: Text(_busy ? 'Creating…' : 'Create collection')),
        ]),
      ),
    );
  }
}

/// One collection. The class rep sees who paid (and can tick off who collected), open or close it, and share it;
/// everyone else can pay, or see that they already did.
class CollectionScreen extends StatefulWidget {
  const CollectionScreen({super.key, required this.code});
  final String code;
  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  /// The class rep's list of who paid, A to Z: a PDF to print or send, or a spreadsheet.
  Future<void> _download(Map<String, dynamic> c, List<Map<String, dynamic>> paid) async {
    final kind = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: StallColors.cream,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('A branded list, A to Z, with page numbers. Long lists continue onto more pages.'),
          ),
          ListTile(
              key: const Key('coPdf'),
              leading: Icon(Icons.picture_as_pdf_outlined, color: StallColors.indigo),
              title: const Text('PDF'),
              onTap: () => Navigator.pop(ctx, 'pdf')),
          ListTile(
              key: const Key('coCsv'),
              leading: Icon(Icons.table_chart_outlined, color: StallColors.indigo),
              title: const Text('Spreadsheet (CSV)'),
              onTap: () => Navigator.pop(ctx, 'csv')),
        ]),
      ),
    );
    if (kind == null) return;
    final name = collectionFileName(c);
    try {
      final file = kind == 'pdf'
          ? XFile.fromData(await paidPdf(c, paid, host: Uri.parse(apiBase).host), mimeType: 'application/pdf', name: '$name.pdf')
          : XFile.fromData(paidCsv(paid), mimeType: 'text/csv', name: '$name.csv');
      await SharePlus.instance.share(ShareParams(files: [file], subject: '${c['title']}: who has paid'));
    } catch (_) {
      if (mounted) toast(context, 'Couldn\'t make the file. Try again.');
    }
  }

  Future<Map<String, dynamic>>? _f;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _f ??= _get();
  }

  Future<Map<String, dynamic>> _get() => SessionScope.of(context).api.get('collect/view', {'code': widget.code});

  void _reload() => setState(() {
        _f = _get();
      });

  Future<void> _post(String path, Map<String, dynamic> body, [String? done]) async {
    setState(() => _busy = true);
    try {
      await SessionScope.of(context).api.post(path, {'code': widget.code, ...body});
      if (mounted && done != null) toast(context, done);
      if (mounted) _reload();
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pay() async {
    setState(() => _busy = true);
    try {
      if (await payStall(context, {'kind': 'collect', 'target': widget.code}) && mounted) {
        toast(context, 'Paid. The class rep can see it.');
        _reload();
      }
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _report() async {
    var why = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Report this collection?'),
        content: TextField(onChanged: (v) => why = v, maxLength: 300, decoration: const InputDecoration(hintText: 'What\'s wrong with it?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Report')),
        ],
      ),
    );
    if (ok == true && mounted) await _post('collect/report', {'reason': why.trim()}, 'Reported. The Stall team will look at it.');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Collection')),
        body: FutureBuilder<Map<String, dynamic>>(
          future: _f,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            if (snap.hasError) {
              return EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'Collection not found',
                  text: snap.error is ApiError ? (snap.error as ApiError).message : 'Check the code with your class rep.');
            }
            final d = snap.data!;
            final c = d['c'] as Map<String, dynamic>;
            final owner = d['owner'] == true, open = c['open'] == true;
            final paid = (d['paid'] as List? ?? const []).cast<Map<String, dynamic>>();
            final n = (d['n'] as num?)?.toInt() ?? 0, expected = (c['expected'] as num?)?.toInt();
            final t = Theme.of(context).textTheme;
            final deadline = (c['deadline'] as num?)?.toInt();
            return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
              Text((c['title'] ?? '').toString(), style: t.headlineSmall),
              Text(
                  [
                    if ((c['cls'] ?? '').toString().isNotEmpty) c['cls'],
                    'by ${c['rep']}${c['repVerified'] == true ? ' ✓' : ''}',
                    if (c['school'] != null) c['school'],
                  ].join(' · '),
                  style: t.bodyMedium?.copyWith(color: StallColors.muted)),
              if ((c['descr'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(c['descr'].toString())),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: _big(context, naira((c['amount'] as num?) ?? 0), 'each')),
                Expanded(child: _big(context, '$n${expected != null ? ' of $expected' : ''}', 'paid')),
                if (owner) Expanded(child: _big(context, naira((d['total'] as num?) ?? 0), 'collected')),
              ]),
              if (expected != null && expected > 0) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(value: (n / expected).clamp(0, 1).toDouble(), minHeight: 8, borderRadius: BorderRadius.circular(8)),
              ],
              const SizedBox(height: 8),
              Text(
                  !open
                      ? 'Closed: no more payments.'
                      : deadline != null
                          ? 'Open until ${when(deadline)}.'
                          : 'Open.',
                  style: t.bodySmall),
              const SizedBox(height: 16),
              if (owner) ...[
                FilledButton.icon(
                  key: const Key('coShare'),
                  onPressed: () => shareCollection(widget.code, (c['title'] ?? '').toString()),
                  icon: const Icon(Icons.ios_share_rounded),
                  label: Text('Share the link (code ${widget.code})'),
                ),
                SwitchListTile(
                  key: const Key('coOpen'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(open ? 'Open for payments' : 'Closed'),
                  value: open,
                  onChanged: _busy ? null : (x) => _post('collect/status', {'open': x}, x ? 'Opened' : 'Closed'),
                ),
                SwitchListTile(
                  key: const Key('coPublic'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show names of who paid to the class'),
                  value: c['publicList'] == true,
                  onChanged: _busy ? null : (x) => _post('collect/visibility', {'public': x}),
                ),
                const SizedBox(height: 8),
                Text('Who has paid', style: t.titleMedium),
                if (paid.isEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Nobody yet. Share the link with your class.')),
                for (final p in paid)
                  CheckboxListTile(
                    key: Key('coTick-${p['id']}'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: p['ticked'] == true,
                    onChanged: _busy ? null : (x) => _post('collect/tick', {'id': p['id'], 'on': x == true}),
                    title: Text((p['name'] ?? '').toString()),
                    subtitle: Text('${when((p['t'] as num?)?.toInt() ?? 0)} · ${p['ref']}'),
                  ),
                if (paid.isNotEmpty) Text('Tick people off as they collect, so you know who\'s had theirs.', style: t.bodySmall),
                if (paid.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    key: const Key('coDownload'),
                    onPressed: () => _download(c, paid),
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Download the list'),
                  ),
                ],
              ] else ...[
                if (d['mine'] != null)
                  Container(
                    key: const Key('coPaid'),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: StallColors.greenTint, borderRadius: BorderRadius.circular(14)),
                    child: Text('You paid on ${when((d['mine']['t'] as num?)?.toInt() ?? 0)} ✓'),
                  )
                else if (open) ...[
                  FilledButton(
                    key: const Key('coPayNow'),
                    onPressed: _busy ? null : _pay,
                    child: Text('Pay ${naira((c['total'] as num?) ?? (c['amount'] as num?) ?? 0)}'),
                  ),
                  if (((c['charge'] as num?) ?? 0) > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('${naira((c['amount'] as num?) ?? 0)} plus a ${naira(c['charge'] as num)} payment charge. It goes straight to ${c['rep']}\'s bank: Stall never holds it.',
                          style: t.bodySmall),
                    )
                  else
                    Padding(padding: const EdgeInsets.only(top: 6), child: Text('It goes straight to ${c['rep']}\'s bank: Stall never holds it.', style: t.bodySmall)),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Only pay if you know who is collecting.', style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                ],
                if (paid.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('Who has paid', style: t.titleMedium),
                  for (final p in paid) ListTile(contentPadding: EdgeInsets.zero, dense: true, title: Text((p['name'] ?? '').toString())),
                ],
                TextButton(onPressed: _busy ? null : _report, child: Text('Report this collection', style: TextStyle(color: StallColors.muted))),
              ],
            ]);
          },
        ),
      );

  Widget _big(BuildContext context, String n, String label) => Column(children: [
        Text(n, style: Theme.of(context).textTheme.titleLarge),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ]);
}
