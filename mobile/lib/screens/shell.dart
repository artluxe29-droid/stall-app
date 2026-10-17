import 'package:flutter/material.dart';

import '../main.dart';
import '../place.dart';
import '../theme.dart';
import '../widgets.dart';
import 'account_setup.dart';
import 'browse.dart';
import 'chat.dart';
import 'item.dart' show showReviews;
import 'orders.dart';
import 'sell.dart';
import 'stores.dart';

/// The signed-in app: Home, Stores, Sell, Orders and Account, like the web app's tab bar.
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  /// Asked once per app launch, until they answer: accounts from before areas existed have none yet.
  static bool _asked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final u = SessionScope.of(context).user;
      if (_asked || u == null || u.area.isNotEmpty || !mounted) return;
      _asked = true;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlaceScreen(prompt: true)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final body = switch (_tab) {
      0 => const HomeTab(),
      1 => const StoresTab(),
      3 => const OrdersTab(),
      4 => const AccountTab(),
      _ => const SellTab(),
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

/// Account: who's signed in, where they are, their school, and sign out.
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
      if (u?.pausedUntil != null) ...[PausedCard(until: u!.pausedUntil!), const SizedBox(height: 12)],
      Card(
        child: ListTile(
          key: const Key('messagesTile'),
          leading: const Icon(Icons.chat_bubble_outline_rounded, color: StallColors.indigo),
          title: const Text('Messages'),
          subtitle: const Text('Your chats with buyers and sellers'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MessagesScreen())),
        ),
      ),
      if (u != null)
        Card(
          child: ListTile(
            key: const Key('myReviews'),
            leading: const Icon(Icons.star_outline_rounded, color: StallColors.indigo),
            title: const Text('Your reviews'),
            subtitle: const Text('What buyers said about you, and your replies'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => showReviews(context, uid: u.uid, name: u.name),
          ),
        ),
      if (u != null)
        Card(
          child: ListTile(
            key: const Key('myArea'),
            leading: const Icon(Icons.place_outlined, color: StallColors.indigo),
            title: const Text('My area'),
            subtitle: Text(u.area.isEmpty ? 'Choose your area to see things for sale near you' : '${u.area}, ${u.state}'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlaceScreen())),
          ),
        ),
      if (u != null)
        Card(
          child: ListTile(
            key: const Key('student'),
            leading: const Icon(Icons.school_outlined, color: StallColors.indigo),
            title: Text(u.isVendor ? 'Campus' : 'Student'),
            subtitle: Text(u.school != null ? u.schoolName : (u.isVendor ? 'Not linked to a campus' : 'Not a student')),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => openStudentSettings(context),
          ),
        ),
      if (u != null && u.isStudent)
        Card(
          child: ListTile(
            key: const Key('verify'),
            leading: Icon(u.vlevel >= 1 ? Icons.verified_rounded : Icons.verified_outlined, color: u.vlevel >= 1 ? StallColors.green : StallColors.indigo),
            title: const Text('Student verification'),
            subtitle: Text(verifyLabel(u)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VerifyStudentScreen())),
          ),
        ),
      if (u != null && s.emailOn)
        Card(
          child: ListTile(
            key: const Key('emailTile'),
            leading: const Icon(Icons.mail_outline_rounded, color: StallColors.indigo),
            title: const Text('Email'),
            subtitle: Text(u.emailVerified ? '${u.email} ✓' : (u.email.isEmpty ? 'Add an email for order updates and password resets' : '${u.email} · not confirmed')),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EmailScreen())),
          ),
        ),
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
