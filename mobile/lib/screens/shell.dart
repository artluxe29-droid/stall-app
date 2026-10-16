import 'package:flutter/material.dart';

import '../main.dart';
import '../theme.dart';
import '../widgets.dart';
import 'browse.dart';
import 'stores.dart';

/// The signed-in app: Home, Stores, Sell, Orders and Account, like the web app's tab bar.
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  static const _soon = {
    2: (Icons.sell_outlined, 'Selling is coming soon', 'You\'ll list items and run your store from here. For now, sell on stall.com.ng.'),
    3: (Icons.receipt_long_outlined, 'Orders are coming soon', 'Your orders, handover codes and receipts will live here.'),
  };

  @override
  Widget build(BuildContext context) {
    final body = switch (_tab) {
      0 => const HomeTab(),
      1 => const StoresTab(),
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
