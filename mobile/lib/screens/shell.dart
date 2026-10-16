import 'package:flutter/material.dart';

import '../api.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets.dart';

/// The signed-in app: Home, Stores, Sell, Orders and Account, like the web app's tab bar.
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  static const _soon = {
    1: (Icons.storefront_outlined, 'Stores are coming next', 'Browse campus stores and food stalls here in the next update.'),
    2: (Icons.sell_outlined, 'Selling is coming soon', 'You\'ll list items and run your store from here. For now, sell on stall.com.ng.'),
    3: (Icons.receipt_long_outlined, 'Orders are coming soon', 'Your orders, handover codes and receipts will live here.'),
  };

  @override
  Widget build(BuildContext context) {
    final body = switch (_tab) {
      0 => const HomeTab(),
      4 => const AccountTab(),
      _ => EmptyState(icon: _soon[_tab]!.$1, title: _soon[_tab]!.$2, text: _soon[_tab]!.$3),
    };
    return Scaffold(
      body: SafeArea(bottom: false, child: body),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'Stores'),
          NavigationDestination(icon: Icon(Icons.sell_outlined), selectedIcon: Icon(Icons.sell), label: 'Sell'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Orders'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Account'),
        ],
      ),
    );
  }
}

/// Home: greeting, the short break message when it's on, and the latest items at your school.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  Future<Map<String, dynamic>>? _feed;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _feed ??= _load();
  }

  Future<Map<String, dynamic>> _load() => SessionScope.of(context).api.get('listings', {'scope': 'school', 'n': '24'});

  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    final t = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: () async {
        final f = _load();
        setState(() => _feed = f);
        await f.catchError((_) => <String, dynamic>{});
      },
      child: CustomScrollView(slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          sliver: SliverList.list(children: [
            const Align(alignment: Alignment.centerLeft, child: Wordmark(height: 28)),
            const SizedBox(height: 20),
            if (s.breakMessage != null) ...[BreakCard(message: s.breakMessage!), const SizedBox(height: 20)],
            Text('Hi ${s.user?.firstName ?? ''}', style: t.headlineMedium),
            const SizedBox(height: 4),
            Text(
                s.user?.schoolName.isNotEmpty == true
                    ? 'What\'s new at ${s.user!.schoolName}'
                    : 'What\'s new near you',
                style: t.bodyLarge?.copyWith(color: StallColors.muted)),
            const SizedBox(height: 16),
          ]),
        ),
        FutureBuilder<Map<String, dynamic>>(
          future: _feed,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()));
            }
            if (snap.hasError) {
              return SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                    icon: Icons.wifi_off_rounded,
                    title: 'Couldn\'t load items',
                    text: snap.error is ApiError ? (snap.error as ApiError).message : 'Pull down to try again.'),
              );
            }
            final d = snap.data!;
            final items = (d['listings'] as List? ?? []).cast<Map<String, dynamic>>();
            if (d['soon'] == true) {
              return const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                    icon: Icons.school_outlined,
                    title: 'Stall isn\'t open at your school yet',
                    text: 'We\'ll tell you the moment it opens.'),
              );
            }
            if (items.isEmpty) {
              return const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(icon: Icons.inventory_2_outlined, title: 'No items yet', text: 'Be the first to sell something at your school.'),
              );
            }
            return SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: .72),
                itemCount: items.length,
                itemBuilder: (_, i) => ItemCard(item: items[i]),
              ),
            );
          },
        ),
      ]),
    );
  }
}

class ItemCard extends StatelessWidget {
  const ItemCard({super.key, required this.item});
  final Map<String, dynamic> item;
  @override
  Widget build(BuildContext context) {
    final api = SessionScope.of(context).api;
    final imgs = (item['imgs'] as List? ?? []).cast<String>();
    final sold = item['sold'] == 1 || item['sold'] == true;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: Stack(fit: StackFit.expand, children: [
            Container(color: StallColors.cream2),
            if (imgs.isNotEmpty)
              Image.network(api.url(imgs.first), fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
            if (sold)
              Positioned(
                left: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: StallColors.night, borderRadius: BorderRadius.circular(99)),
                  child: const Text('Sold', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((item['title'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(naira((item['price'] as num?) ?? 0),
                style: const TextStyle(fontFamily: 'Bricolage', fontWeight: FontWeight.w800, fontSize: 17)),
          ]),
        ),
      ]),
    );
  }
}

/// Account: who's signed in, and sign out.
class AccountTab extends StatelessWidget {
  const AccountTab({super.key});
  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    final u = s.user;
    final t = Theme.of(context).textTheme;
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text('Account', style: t.headlineMedium),
      const SizedBox(height: 16),
      Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: CircleAvatar(
            backgroundColor: StallColors.indigo,
            foregroundColor: StallColors.cream,
            child: Text((u?.name.isNotEmpty ?? false) ? u!.name[0].toUpperCase() : '?', style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          title: Text(u?.name ?? '', style: t.titleMedium),
          subtitle: Text([u?.phone, u?.schoolName].where((x) => x != null && x.isNotEmpty).join(' · ')),
        ),
      ),
      const SizedBox(height: 12),
      if (u?.isStaff ?? false)
        const Card(
          child: ListTile(
            leading: Icon(Icons.admin_panel_settings_outlined, color: StallColors.indigo),
            title: Text('Admin'),
            subtitle: Text('Admin stays on the web: open stall.com.ng/staff on a phone or computer.'),
          ),
        ),
      const SizedBox(height: 24),
      OutlinedButton.icon(
        key: const Key('signOut'),
        onPressed: s.signOut,
        icon: const Icon(Icons.logout_rounded),
        label: const Text('Sign out'),
      ),
      const SizedBox(height: 16),
      Text('This is an early version of the Stall app. More of Stall arrives with each update.',
          textAlign: TextAlign.center, style: t.bodySmall),
    ]);
  }
}
