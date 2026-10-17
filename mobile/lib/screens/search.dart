import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../models.dart';
import '../theme.dart';
import '../voice.dart';
import 'browse.dart';
import 'stores.dart';

/// Your last few searches, kept on the phone.
class RecentSearches {
  static const _key = 'recent_searches';
  static Future<List<String>> load() async => (await SharedPreferences.getInstance()).getStringList(_key) ?? const [];
  static Future<List<String>> add(String q) async {
    final p = await SharedPreferences.getInstance();
    final l = [q, ...(p.getStringList(_key) ?? const []).where((x) => x.toLowerCase() != q.toLowerCase())].take(8).toList();
    await p.setStringList(_key, l);
    return l;
  }

  static Future<void> clear() async => (await SharedPreferences.getInstance()).remove(_key);
}

/// Search: type, pick filters and sort; shows matching store items first, then listings.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.initial});
  final String? initial;
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _q = TextEditingController();
  ListingPager? _pager;
  String? _scope;
  String _cat = 'all';
  Filters _f = const Filters();
  List<String> _recent = const [];
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    RecentSearches.load().then((l) => mounted ? setState(() => _recent = l) : null);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pager == null) {
      final s = SessionScope.of(context);
      _pager = ListingPager(s.api);
      _scope = Scope.initial(s.user);
      if (widget.initial != null) {
        _q.text = widget.initial!;
        _run();
      }
    }
  }

  @override
  void dispose() {
    _q.dispose();
    _pager?.dispose();
    super.dispose();
  }

  void _run() {
    final q = _q.text.trim();
    if (q.isEmpty && _f.count == 0 && _cat == 'all') {
      setState(() => _searched = false);
      return;
    }
    if (q.isNotEmpty) RecentSearches.add(q).then((l) => mounted ? setState(() => _recent = l) : null);
    setState(() => _searched = true);
    _pager!.reset({'scope': _scope!, if (q.isNotEmpty) 'q': q, if (_cat != 'all') 'cat': _cat, ..._f.query});
  }

  Future<void> _filters() async {
    final f = await showModalBottomSheet<Filters>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: StallColors.cream,
      builder: (_) => FilterSheet(initial: _f),
    );
    if (f != null) {
      setState(() => _f = f);
      _run();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          key: const Key('searchField'),
          controller: _q,
          autofocus: widget.initial == null,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _run(),
          decoration: InputDecoration(
            hintText: 'Search Stall',
            isDense: true,
            filled: true,
            fillColor: StallColors.card,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: StallColors.line)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: StallColors.line)),
            suffixIcon: IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Clear',
                onPressed: () {
                  _q.clear();
                  setState(() => _searched = false);
                }),
          ),
        ),
        actions: [
          IconButton(
            key: const Key('voice'),
            tooltip: 'Search by voice',
            icon: const Icon(Icons.mic_none_rounded),
            onPressed: () async {
              final said = await listenOnce(context);
              if (said == null || said.isEmpty || !mounted) return;
              _q.text = said;
              _run();
            },
          ),
          IconButton(
            key: const Key('filters'),
            tooltip: 'Filters',
            onPressed: _filters,
            icon: Badge(isLabelVisible: _f.count > 0, label: Text('${_f.count}'), child: const Icon(Icons.tune_rounded)),
          ),
          PopupMenuButton<String>(
            key: const Key('sort'),
            tooltip: 'Sort',
            icon: const Icon(Icons.swap_vert_rounded),
            initialValue: _f.sort,
            onSelected: (v) {
              setState(() => _f = _f.copyWith(sort: v));
              _run();
            },
            itemBuilder: (_) => [for (final e in Filters.sorts.entries) PopupMenuItem(value: e.key, child: Text(e.value))],
          ),
        ],
      ),
      body: CustomScrollView(slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
        SliverToBoxAdapter(
          child: ChipRow(
              options: Scope.options(s.user),
              value: _scope!,
              onPick: (v) {
                setState(() => _scope = v);
                _run();
              }),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
        SliverToBoxAdapter(
          child: ChipRow(
            options: [('all', 'All'), for (final c in Category.all) (c.id, c.name)],
            icons: {for (final c in Category.all) c.id: c.icon},
            value: _cat,
            onPick: (v) {
              setState(() => _cat = v);
              _run();
            },
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        if (!_searched) ..._recentSlivers() else ...[
          ListenableBuilder(
            listenable: _pager!,
            builder: (context, _) => _pager!.storeHits.isEmpty
                ? const SliverToBoxAdapter()
                : SliverToBoxAdapter(child: StoreHitsRow(hits: _pager!.storeHits)),
          ),
          ListingSlivers(pager: _pager!, emptyTitle: 'Nothing found', emptyText: 'Try other words, fewer filters, or look across all of Nigeria.'),
        ],
      ]),
    );
  }

  List<Widget> _recentSlivers() {
    if (_recent.isEmpty) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('Search for textbooks, phones, food, hair and more.', textAlign: TextAlign.center, style: TextStyle(color: StallColors.muted)),
          ),
        ),
      ];
    }
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 8, 0),
          child: Row(children: [
            Text('Recent searches', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            TextButton(
                onPressed: () async {
                  await RecentSearches.clear();
                  setState(() => _recent = const []);
                },
                child: const Text('Clear')),
          ]),
        ),
      ),
      SliverList.builder(
        itemCount: _recent.length,
        itemBuilder: (_, i) => ListTile(
          leading: const Icon(Icons.history_rounded, color: StallColors.muted),
          title: Text(_recent[i]),
          onTap: () {
            _q.text = _recent[i];
            _run();
          },
        ),
      ),
    ];
  }
}

/// Items in open stores that matched the search ("jollof" finds food stalls too).
class StoreHitsRow extends StatelessWidget {
  const StoreHitsRow({super.key, required this.hits});
  final List<StoreHit> hits;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text('From stores', style: Theme.of(context).textTheme.titleMedium),
        ),
        SizedBox(
          height: 84,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: hits.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final h = hits[i];
              final c = Category.of(h.cat);
              return SizedBox(
                width: 230,
                child: Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StoreScreen(storeId: h.storeId))),
                    child: Row(children: [
                      Container(width: 64, color: c.bg, child: Icon(storeIcon(h.emoji, h.cat), color: c.fg)),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(h.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(naira(h.price), style: const TextStyle(fontFamily: 'Bricolage', fontWeight: FontWeight.w800)),
                            Text(h.storeName, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                          ]),
                        ),
                      ),
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
      ]);
}

/// Price range, condition, "delivers", "verified sellers" and "4 stars and up", like the web app's filter panel.
class FilterSheet extends StatefulWidget {
  const FilterSheet({super.key, required this.initial});
  final Filters initial;
  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late final _min = TextEditingController(text: widget.initial.min?.toString() ?? '');
  late final _max = TextEditingController(text: widget.initial.max?.toString() ?? '');
  late String? _cond = widget.initial.cond;
  late bool _dl = widget.initial.delivers, _vf = widget.initial.verified, _r4 = widget.initial.topRated;

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  int? _n(TextEditingController c) {
    final v = int.tryParse(c.text.replaceAll(RegExp(r'\D'), ''));
    return v == null || v <= 0 ? null : v;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    InputDecoration dec(String l) => InputDecoration(labelText: l, prefixText: '₦ ');
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Filters', style: t.headlineSmall),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: TextField(key: const Key('fMin'), controller: _min, keyboardType: TextInputType.number, decoration: dec('Min price'))),
          const SizedBox(width: 12),
          Expanded(child: TextField(key: const Key('fMax'), controller: _max, keyboardType: TextInputType.number, decoration: dec('Max price'))),
        ]),
        const SizedBox(height: 16),
        Text('Condition', style: t.titleMedium),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          for (final c in const [null, 'New', 'Like new', 'Used'])
            ChoiceChip(label: Text(c ?? 'Any'), selected: _cond == c, onSelected: (_) => setState(() => _cond = c)),
        ]),
        const SizedBox(height: 8),
        SwitchListTile(
            contentPadding: EdgeInsets.zero, title: const Text('Seller delivers'), value: _dl, onChanged: (v) => setState(() => _dl = v)),
        SwitchListTile(
            contentPadding: EdgeInsets.zero, title: const Text('Verified sellers only'), value: _vf, onChanged: (v) => setState(() => _vf = v)),
        SwitchListTile(
            contentPadding: EdgeInsets.zero, title: const Text('4 stars and up'), value: _r4, onChanged: (v) => setState(() => _r4 = v)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton(
                onPressed: () => Navigator.pop(context, Filters(sort: widget.initial.sort)), child: const Text('Reset')),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              key: const Key('fApply'),
              onPressed: () => Navigator.pop(
                  context,
                  Filters(
                      min: _n(_min), max: _n(_max), cond: _cond, delivers: _dl, verified: _vf, topRated: _r4, sort: widget.initial.sort)),
              child: const Text('Show results'),
            ),
          ),
        ]),
      ]),
    );
  }
}
