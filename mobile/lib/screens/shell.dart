import 'package:flutter/material.dart';

import '../api.dart';
import '../main.dart';
import '../news.dart';
import '../place.dart';
import '../push.dart';
import '../theme.dart';
import '../widgets.dart';
import 'account_setup.dart';
import 'browse.dart';
import 'chat.dart';
import 'collections.dart';
import 'extras.dart';
import 'item.dart' show showReviews;
import 'orders.dart';
import 'settings.dart';
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

  /// Kept, so dispose() can stop its checks without looking up the session.
  News? _news;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _news ??= SessionScope.of(context).news;
  }

  @override
  void initState() {
    super.initState();
    pushTarget.addListener(_go);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _news?.start();
      _go(); // a notification tapped before Stall opened
      final u = SessionScope.of(context).user;
      if (_asked || u == null || u.area.isNotEmpty || !mounted) return;
      _asked = true;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlaceScreen(prompt: true)));
    });
  }

  @override
  void dispose() {
    pushTarget.removeListener(_go);
    _news?.stop();
    ordersSelling.value = false; // the next person to sign in starts on Buying
    super.dispose();
  }

  /// Opens what a tapped notification points to: an order list, a chat, or Messages.
  void _go() {
    final u = pushTarget.value;
    if (u == null || !mounted) return;
    pushTarget.value = null;
    final go = u.queryParameters['go'] ?? '';
    final nav = navKey.currentState ?? Navigator.of(context);
    nav.popUntil((r) => r.isFirst);
    final collect = u.queryParameters['collect'];
    if (collect != null && collect.isNotEmpty) {
      nav.push(MaterialPageRoute(builder: (_) => CollectionScreen(code: collect.toUpperCase())));
      return;
    }
    switch (go) {
      case 'orders' || 'selling':
        ordersSelling.value = go == 'selling';
        setState(() => _tab = 3);
      case 'messages':
        final t = int.tryParse(u.queryParameters['t'] ?? '');
        nav.push(MaterialPageRoute(builder: (_) => t == null ? const MessagesScreen() : ChatScreen(tid: t)));
      case 'payments' || 'badges' || 'invite':
        setState(() => _tab = 4);
    }
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
    final news = SessionScope.of(context).news;
    return Scaffold(
      body: SafeArea(bottom: false, child: body),
      bottomNavigationBar: ListenableBuilder(
        listenable: news,
        builder: (context, _) => NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: [
            const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
            const NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'Stores'),
            const NavigationDestination(icon: Icon(Icons.sell_outlined), selectedIcon: Icon(Icons.sell), label: 'Sell'),
            NavigationDestination(
              icon: Badge(isLabelVisible: news.orders > 0, label: Text('${news.orders}'), child: const Icon(Icons.receipt_long_outlined)),
              selectedIcon: Badge(isLabelVisible: news.orders > 0, label: Text('${news.orders}'), child: const Icon(Icons.receipt_long)),
              label: 'Orders',
            ),
            const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Account'),
          ],
        ),
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
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
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
              subtitle: Text(
                u.emailVerified ? '${u.email} ✓' : (u.email.isEmpty ? 'Add an email for order updates and password resets' : '${u.email} · not confirmed'),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EmailScreen())),
            ),
          ),
        if (u != null && s.emailOn && u.email.isNotEmpty)
          Card(
            child: SwitchListTile(
              key: const Key('emailNotify'),
              secondary: const Icon(Icons.notifications_outlined, color: StallColors.indigo),
              title: const Text('Email updates'),
              subtitle: const Text('Order updates and receipts by email'),
              value: u.emailNotify,
              onChanged: (v) async {
                try {
                  await s.api.post('me/notify', {'on': v});
                  await s.refresh();
                } on ApiError catch (e) {
                  if (context.mounted) toast(context, e.message);
                }
              },
            ),
          ),
        Card(
          child: Column(
            children: [
              ListTile(
                key: const Key('collectTile'),
                leading: const Icon(Icons.groups_outlined, color: StallColors.indigo),
                title: const Text('Class collections'),
                subtitle: const Text('Collect money from your class, or pay into one'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CollectionsScreen())),
              ),
              const Divider(height: 1),
              ListTile(
                key: const Key('badgesTile'),
                leading: const Icon(Icons.military_tech_outlined, color: StallColors.indigo),
                title: const Text('Badges'),
                subtitle: const Text('Milestones for selling and buying safely'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BadgesScreen())),
              ),
              const Divider(height: 1),
              ListTile(
                key: const Key('paymentsTile'),
                leading: const Icon(Icons.receipt_long_outlined, color: StallColors.indigo),
                title: const Text('Payments to Stall'),
                subtitle: const Text('Store fee, featuring, reach and collections, with receipts'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PaymentsScreen())),
              ),
              const Divider(height: 1),
              ListTile(
                key: const Key('inviteTile'),
                leading: const Icon(Icons.card_giftcard_rounded, color: StallColors.indigo),
                title: const Text('Invite friends'),
                subtitle: Text(u != null && u.credit > 0 ? 'You have ${naira(u.credit)} credit' : 'Earn credit when friends join'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InviteScreen())),
              ),
              const Divider(height: 1),
              ListTile(
                key: const Key('guideTile'),
                leading: const Icon(Icons.menu_book_outlined, color: StallColors.indigo),
                title: const Text('How Stall works'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => GuideScreen(selling: u?.isVendor ?? false))),
              ),
              const Divider(height: 1),
              ListTile(
                key: const Key('helpTile'),
                leading: const Icon(Icons.help_outline_rounded, color: StallColors.indigo),
                title: const Text('Help'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HelpScreen())),
              ),
            ],
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
        OutlinedButton.icon(key: const Key('signOut'), onPressed: s.signOut, icon: const Icon(Icons.logout_rounded), label: const Text('Sign out')),
        if (u != null && !u.isAdmin)
          TextButton(
            key: const Key('deleteAccount'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DeleteAccountScreen())),
            child: const Text('Delete my account', style: TextStyle(color: StallColors.red)),
          ),
        const SizedBox(height: 16),
        Text('This is an early version of the Stall app. More of Stall arrives with each update.', textAlign: TextAlign.center, style: t.bodySmall),
      ],
    );
  }
}
