import 'package:flutter/material.dart';

import '../api.dart';
import '../appearance.dart';
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
import 'my_store.dart' show MyStoreScreen;
import 'orders.dart';
import 'settings.dart';
import 'sell.dart';
import 'selling.dart' show WeeklyScreen;
import 'stores.dart';

/// The signed-in app: Home, Stores, Sell, Orders and Account, like the web app's tab bar.
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int get _tab => shellTab.value;

  /// Tabs are built the first time they're opened, then kept, so going back to one is instant.
  final _built = <int>{0};

  void _show(int i) => setState(() {
        _built.add(i);
        shellTab.value = i;
      });

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
    shellTab.addListener(_tabChanged);
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
    shellTab.removeListener(_tabChanged);
    shellTab.value = 0;
    _news?.stop();
    ordersSelling.value = false; // the next person to sign in starts on Buying
    super.dispose();
  }

  /// Another screen (Home's "Sell something") can switch tabs too.
  void _tabChanged() {
    if (mounted) setState(() => _built.add(_tab));
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
        _show(3);
      case 'messages':
        final t = int.tryParse(u.queryParameters['t'] ?? '');
        nav.push(MaterialPageRoute(builder: (_) => t == null ? const MessagesScreen() : ChatScreen(tid: t)));
      case 'payments' || 'badges' || 'invite':
        _show(4);
    }
  }

  @override
  Widget build(BuildContext context) {
    const tabs = [HomeTab(), StoresTab(), SellTab(), OrdersTab(), AccountTab()];
    final body = IndexedStack(
      index: _tab,
      children: [
        for (var i = 0; i < tabs.length; i++)
          // A hidden tab doesn't animate or take taps, and isn't built until first opened.
          TickerMode(enabled: i == _tab, child: _built.contains(i) ? tabs[i] : const SizedBox.shrink()),
      ],
    );
    final news = SessionScope.of(context).news;
    return Scaffold(
      body: SafeArea(bottom: false, child: body),
      bottomNavigationBar: ListenableBuilder(
        listenable: news,
        builder: (context, _) => NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: _show,
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

/// Account, arranged like the website's (shortcut tiles, then Selling, Your profile and Help) in the app's own style.
class AccountTab extends StatelessWidget {
  const AccountTab({super.key});

  void _open(BuildContext context, Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    final u = s.user;
    final t = Theme.of(context).textTheme;
    final school = u?.school;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Row(children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: StallColors.indigo,
            foregroundColor: StallColors.cream,
            child: Text((u?.name.isNotEmpty ?? false) ? u!.name[0].toUpperCase() : '?', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(u?.name ?? '', style: t.headlineSmall),
              const SizedBox(height: 2),
              Text(
                [if (u?.isVendor ?? false) 'Business' else u?.phone ?? '', if (school != null) u!.schoolName].where((x) => x.isNotEmpty).join(' · '),
                style: t.bodyMedium?.copyWith(color: StallColors.muted),
              ),
              if (u != null && u.isStudent && u.vlevel >= 1) ...[
                const SizedBox(height: 6),
                _Chip(u.vlevel >= 2 ? 'Student ✓' : 'School email ✓', hot: true),
              ],
            ]),
          ),
        ]),
        if (u?.pausedUntil != null) ...[const SizedBox(height: 16), PausedCard(until: u!.pausedUntil!)],
        if (u?.isStaff ?? false) ...[
          const SizedBox(height: 16),
          const _Section(rows: [
            _Row(icon: Icons.tune_rounded, title: 'Admin', sub: 'Admin stays on the web: open stall.com.ng/staff on a phone or computer.', arrow: false),
          ]),
        ],
        const SizedBox(height: 16),
        ListenableBuilder(
          listenable: s.news,
          builder: (context, _) {
            final tiles = [
              _Tile(
                key: const Key('messagesTile'),
                icon: Icons.chat_bubble_outline_rounded,
                title: 'Messages',
                sub: s.news.chats > 0 ? '${s.news.chats} unread' : 'Buyers and sellers',
                n: s.news.chats,
                onTap: () => _open(context, const MessagesScreen()),
              ),
              _Tile(
                key: const Key('fulfilTile'),
                icon: Icons.inventory_2_outlined,
                title: 'Orders to fulfil',
                sub: s.news.sell > 0 ? '${s.news.sell} new' : 'What people bought',
                n: s.news.sell,
                onTap: () {
                  ordersSelling.value = true;
                  shellTab.value = 3;
                },
              ),
              _Tile(
                key: const Key('collectTile'),
                icon: Icons.groups_outlined,
                title: 'Collections',
                sub: 'Collect money from a group',
                onTap: () => _open(context, const CollectionsScreen()),
              ),
              _Tile(
                key: const Key('inviteTile'),
                icon: Icons.card_giftcard_rounded,
                title: 'Invite & credit',
                sub: u != null && u.credit > 0 ? '${naira(u.credit)} credit' : 'Earn when friends order',
                onTap: () => _open(context, const InviteScreen()),
              ),
              _Tile(
                key: const Key('paymentsTile'),
                icon: Icons.account_balance_wallet_outlined,
                title: 'Payments',
                sub: 'Receipts for featuring and more',
                onTap: () => _open(context, const PaymentsScreen()),
              ),
              _Tile(
                key: const Key('badgesTile'),
                icon: Icons.verified_outlined,
                title: 'Badges',
                sub: 'Share your milestones',
                onTap: () => _open(context, const BadgesScreen()),
              ),
            ];
            return Column(children: [
              for (var i = 0; i < tiles.length; i += 2) ...[
                if (i > 0) const SizedBox(height: 10),
                IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(child: tiles[i]),
                    const SizedBox(width: 10),
                    Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox.shrink()),
                  ]),
                ),
              ],
            ]);
          },
        ),
        if (u != null) ...[
          _Section(title: 'Selling', rows: [
            _Row(
              key: const Key('accStore'),
              icon: Icons.storefront_outlined,
              title: 'Your store',
              sub: 'Items, logo, open and closed, reach',
              onTap: () => _open(context, const MyStoreScreen()),
            ),
            _Row(
              key: const Key('accDelivery'),
              icon: Icons.local_shipping_outlined,
              title: 'Delivery',
              sub: u.deliv['on'] == true
                  ? 'You deliver · ${((u.deliv['fee'] as num?) ?? 0) > 0 ? naira(u.deliv['fee'] as num) : 'free'}'
                  : 'Off · buyers collect from you',
              onTap: () => _open(context, const DeliveryScreen()),
            ),
            _Row(
              key: const Key('myReviews'),
              icon: Icons.star_outline_rounded,
              title: 'Your reviews',
              sub: 'What buyers said about you, and your replies',
              onTap: () => showReviews(context, uid: u.uid, name: u.name),
            ),
            _Row(
              key: const Key('accWeekly'),
              icon: Icons.bar_chart_rounded,
              title: 'Weekly statement',
              sub: 'What you sold and were paid this week',
              onTap: () => _open(context, const WeeklyScreen()),
            ),
          ]),
          _Section(title: 'Your profile', rows: [
            _Row(
              key: const Key('myArea'),
              icon: Icons.place_outlined,
              title: 'My area',
              sub: u.area.isEmpty ? 'Choose your state and area' : '${u.area}, ${u.state}',
              onTap: () => _open(context, const PlaceScreen()),
            ),
            _Row(
              key: const Key('student'),
              icon: Icons.school_outlined,
              title: u.isVendor ? 'Campus (optional)' : 'Student',
              sub: school != null ? (school['name'] ?? u.schoolName).toString() : (u.isVendor ? 'Not on a campus' : 'Not a student · tap if you are'),
              onTap: () => openStudentSettings(context),
            ),
            if (u.isStudent)
              _Row(
                key: const Key('verify'),
                icon: u.vlevel >= 1 ? Icons.verified_rounded : Icons.verified_outlined,
                title: u.vlevel >= 2 ? 'Student verification' : 'Verify you\'re a student',
                sub: verifyLabel(u),
                trailing: u.vlevel >= 2 ? null : _Chip(u.idCheck == 'pending' ? 'Pending' : 'Get ✓', hot: u.idCheck != 'pending'),
                onTap: () => _open(context, const VerifyStudentScreen()),
              ),
            if (s.emailOn)
              _Row(
                key: const Key('emailTile'),
                icon: Icons.mail_outline_rounded,
                title: 'Email',
                sub: u.emailVerified
                    ? '${u.emailNotify ? 'Updates on' : 'Updates off'} · ${u.email}'
                    : (u.email.isEmpty ? 'Add your email for order updates and password resets' : '${u.email} · not confirmed'),
                trailing: u.emailVerified ? null : const _Chip('Add', hot: true),
                onTap: () => _open(context, const EmailScreen()),
              ),
            if (s.emailOn && u.email.isNotEmpty)
              _SwitchRow(
                tileKey: const Key('emailNotify'),
                icon: Icons.notifications_outlined,
                title: 'Email updates',
                sub: 'Order updates and receipts by email',
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
            _Row(
              key: const Key('accPw'),
              icon: Icons.lock_outline_rounded,
              title: 'Change password',
              onTap: () => _open(context, const ChangePasswordScreen()),
            ),
          ]),
        ],
        _Section(title: 'App & preferences', rows: [
          ListenableBuilder(
            listenable: appearance,
            builder: (context, _) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Row(children: [
                  _RowIcon(Icons.contrast_rounded),
                  SizedBox(width: 12),
                  Text('Theme', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  key: const Key('themeMode'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'auto', label: Text('Auto')),
                    ButtonSegment(value: 'light', label: Text('Light')),
                    ButtonSegment(value: 'dark', label: Text('Dark')),
                  ],
                  selected: {appearance.mode},
                  onSelectionChanged: (v) => appearance.set(v.first),
                ),
              ]),
            ),
          ),
          FutureBuilder<String>(
            future: Push.status(),
            builder: (context, snap) => _Row(
              key: const Key('accPush'),
              icon: Icons.notifications_outlined,
              title: 'Notifications',
              sub: Push.label(snap.data),
              onTap: () => _open(context, const NotificationsScreen()),
            ),
          ),
          _Row(
            key: const Key('guideTile'),
            icon: Icons.menu_book_outlined,
            title: 'How Stall works',
            sub: 'Buying, selling, collections and staying safe',
            onTap: () => _open(context, GuideScreen(selling: u?.isVendor ?? false)),
          ),
        ]),
        _Section(title: 'Help', rows: [
          _Row(
            key: const Key('helpTile'),
            icon: Icons.help_outline_rounded,
            title: 'Help',
            sub: 'Contact us, rules, terms and privacy',
            onTap: () => _open(context, const HelpScreen()),
          ),
        ]),
        const SizedBox(height: 24),
        OutlinedButton.icon(key: const Key('signOut'), onPressed: s.signOut, icon: const Icon(Icons.logout_rounded), label: const Text('Sign out')),
        if (u != null && !u.isAdmin)
          TextButton(
            key: const Key('deleteAccount'),
            onPressed: () => _open(context, const DeleteAccountScreen()),
            child: Text('Delete my account', style: TextStyle(color: StallColors.muted, fontSize: 13.5)),
          ),
      ],
    );
  }
}

/// A shortcut tile in Account's 2-column grid, with a red count when there's something new.
class _Tile extends StatelessWidget {
  const _Tile({super.key, required this.icon, required this.title, required this.sub, required this.onTap, this.n = 0});
  final IconData icon;
  final String title;
  final String sub;
  final VoidCallback onTap;
  final int n;
  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Stack(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: StallColors.cream2, borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, size: 20, color: StallColors.indigo),
                ),
                const SizedBox(height: 10),
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 2),
                Text(sub, style: TextStyle(color: StallColors.muted, fontSize: 12.5, height: 1.3)),
              ]),
              if (n > 0)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 22),
                    height: 22,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: StallColors.red, borderRadius: BorderRadius.circular(99)),
                    child: Text(n > 99 ? '99+' : '$n', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ),
            ]),
          ),
        ),
      );
}

/// A titled group of rows ("SELLING", "YOUR PROFILE"), as on the website, on the app's white card.
class _Section extends StatelessWidget {
  const _Section({this.title, required this.rows});
  final String? title;
  final List<Widget> rows;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
              child: Text(title!.toUpperCase(),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .9, color: StallColors.muted)),
            ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (var i = 0; i < rows.length; i++) ...[if (i > 0) Divider(height: 1, color: StallColors.line), rows[i]],
            ]),
          ),
        ]),
      );
}

class _RowIcon extends StatelessWidget {
  const _RowIcon(this.icon);
  final IconData icon;
  @override
  Widget build(BuildContext context) => SizedBox(width: 28, child: Icon(icon, color: StallColors.indigo));
}

class _Row extends StatelessWidget {
  const _Row({super.key, required this.icon, required this.title, this.sub, this.onTap, this.trailing, this.arrow = true});
  final IconData icon;
  final String title;
  final String? sub;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool arrow;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 62),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [
              _RowIcon(icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  if (sub != null && sub!.isNotEmpty)
                    Text(sub!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: StallColors.muted, fontSize: 13)),
                ]),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              if (arrow && onTap != null) Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.chevron_right_rounded, color: StallColors.muted)),
            ]),
          ),
        ),
      );
}

class _SwitchRow extends StatelessWidget {
  final Key tileKey;
  const _SwitchRow({required this.tileKey, required this.icon, required this.title, required this.sub, required this.value, required this.onChanged});
  final IconData icon;
  final String title;
  final String sub;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => SwitchListTile(
        key: tileKey,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        secondary: _RowIcon(icon),
        title: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        subtitle: Text(sub, style: TextStyle(color: StallColors.muted, fontSize: 13)),
        value: value,
        onChanged: onChanged,
      );
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, {this.hot = false});
  final String text;
  final bool hot;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: hot ? StallColors.lime : StallColors.cream2, borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: hot ? StallColors.limeInk : StallColors.muted)),
      );
}
