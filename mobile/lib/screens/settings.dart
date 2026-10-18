import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../main.dart';
import '../push.dart';
import '../theme.dart';
import '../widgets.dart';
import 'account_setup.dart' show openLink;

/// "How Stall works": short steps for buying and selling, the same rules as the website's guide.
class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key, this.selling = false});
  final bool selling;

  static const _buy = [
    (Icons.search_rounded, 'Find what you need', 'Home shows what\'s for sale near you: your campus if you\'re a student, your area, your state or all of Nigeria. Tap a category, or search for items and stores.'),
    (Icons.tune_rounded, 'Narrow it down', 'In search, tap Filters for a price range or condition, verified sellers, sellers who deliver, or sellers rated 4★ and up.'),
    (Icons.chat_bubble_outline_rounded, 'Ask the seller first', 'Tap Message on any item, store or order to chat inside Stall. Keep chats in Stall, so there\'s a record if anything goes wrong.'),
    (Icons.shopping_bag_outlined, 'Add to bag and pay', 'Add items, open your bag and check out. Choose pickup (free) or delivery if the seller offers it, then pay by card, transfer or USSD on Paystack\'s secure page.'),
    (Icons.map_outlined, 'Track your order', 'Orders shows each step: paid, packed, on the way or ready, delivered. On the order\'s map you can set the meeting spot and see the seller coming. Sharing your location is always optional.'),
    (Icons.key_rounded, 'Use your release code', 'After paying you get a release code. Only give it to the seller once the item is in your hands and you\'ve checked it. Or tap I\'ve got it.'),
    (Icons.report_problem_outlined, 'Something wrong?', 'Don\'t give your code. Tap Report a problem on the order and add a photo. Your money stays with Stall while the seller answers.'),
    (Icons.star_outline_rounded, 'Rate the seller', 'When your order is complete, give the seller 1 to 5 stars. It helps other buyers choose good sellers.'),
  ];

  static const _sell = [
    (Icons.add_a_photo_outlined, 'Post an item', 'Tap Sell, add photos, a title and a price, and say how many you have. Listing single items is free. Stall checks the photo before it goes live.'),
    (Icons.account_balance_outlined, 'Add your bank account once', 'With your first item, add the account you want to be paid into and tap Verify account, so the name is confirmed.'),
    (Icons.local_shipping_outlined, 'Offer delivery (optional)', 'Sell → Delivery: switch on "I deliver" and set your fee. You keep the whole delivery fee.'),
    (Icons.inventory_2_outlined, 'Handle orders', 'Paid orders show in Orders → Selling. Mark them packed, then out for delivery or ready for pickup. On deliveries you can share your location on the map, or just tell the buyer "10 min".'),
    (Icons.payments_outlined, 'Get paid', 'Stall holds the buyer\'s money until they have the item. Enter their release code and the money goes to your bank, minus Stall\'s sale fee. If the buyer goes quiet, you\'re paid automatically after the order is on its way or ready.'),
    (Icons.storefront_outlined, 'Open a store', 'Running a business? Sell → Your store gives you one page for all your items, with a logo, open and closed, delivery, and paid reach across your state or Nigeria.'),
    (Icons.gavel_rounded, 'Strikes', 'Late cancels, no-shows and problem reports you lose or don\'t answer are strikes, for buyers and sellers alike. 3 in 30 days is a warning; 5 pause the account for 14 days.'),
  ];

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        initialIndex: selling ? 1 : 0,
        child: Scaffold(
          appBar: AppBar(title: const Text('How Stall works'), bottom: const TabBar(tabs: [Tab(text: 'Buying'), Tab(text: 'Selling')])),
          body: TabBarView(children: [for (final steps in [_buy, _sell]) _Steps(steps: steps)]),
        ),
      );
}

class _Steps extends StatelessWidget {
  const _Steps({required this.steps});
  final List<(IconData, String, String)> steps;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 32), children: [
      for (final (i, s) in steps.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(backgroundColor: StallColors.cream2, foregroundColor: StallColors.indigo, child: Icon(s.$1, size: 20)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${i + 1}. ${s.$2}', style: t.titleMedium),
                const SizedBox(height: 2),
                Text(s.$3, style: t.bodyMedium?.copyWith(color: StallColors.muted)),
              ]),
            ),
          ]),
        ),
    ]);
  }
}

/// Invite friends: your code and link, how many joined, and the credit you've earned.
class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key});
  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  Future<Map<String, dynamic>>? _f;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _f ??= SessionScope.of(context).api.get('me/referral');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Invite friends')),
        body: FutureBuilder<Map<String, dynamic>>(
          future: _f,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            if (snap.hasError) {
              return EmptyState(
                  icon: Icons.wifi_off_rounded, title: 'Couldn\'t load it', text: snap.error is ApiError ? (snap.error as ApiError).message : 'Try again.');
            }
            final d = snap.data!;
            final t = Theme.of(context).textTheme;
            final code = (d['code'] ?? '').toString(), link = (d['link'] ?? '').toString();
            final reward = (d['reward'] as num?)?.toInt() ?? 0, min = (d['minOrder'] as num?)?.toInt() ?? 0, pct = (d['pct'] as num?)?.toInt() ?? 50;
            return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
              Text(reward > 0 ? 'Get ${naira(reward)} credit for each friend' : 'Bring your friends to Stall', style: t.headlineSmall),
              const SizedBox(height: 6),
              Text(
                  reward > 0
                      ? 'When a friend joins with your code and completes their first order${min > 0 ? ' of ${naira(min)} or more' : ''}, you get ${naira(reward)} in Stall credit. '
                          'Credit pays up to $pct% of featuring an item or upgrading your store\'s reach.'
                      : 'Share your code so friends can join you on Stall.',
                  style: t.bodyMedium?.copyWith(color: StallColors.muted)),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: StallColors.indigo, borderRadius: BorderRadius.circular(18)),
                child: Column(children: [
                  Text('Your code', style: t.bodySmall?.copyWith(color: StallColors.cream)),
                  SelectableText(code, key: const Key('refCode'), style: t.displaySmall?.copyWith(color: StallColors.cream, letterSpacing: 2)),
                ]),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('shareInvite'),
                onPressed: () => SharePlus.instance.share(ShareParams(
                    text: 'Join me on Stall, the safe way to buy and sell near you. Use my code $code when you sign up: $link', subject: 'Stall')),
                icon: const Icon(Icons.ios_share_rounded),
                label: const Text('Share your invite'),
              ),
              const SizedBox(height: 20),
              Row(children: [
                _Num('${d['invited'] ?? 0}', 'joined with your code'),
                _Num('${d['rewarded'] ?? 0}', 'earned you credit'),
                _Num(naira((d['credit'] as num?) ?? 0), 'credit to use'),
              ]),
            ]);
          },
        ),
      );
}

class _Num extends StatelessWidget {
  const _Num(this.n, this.label);
  final String n, label;
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Text(n, style: Theme.of(context).textTheme.titleLarge),
          Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
        ]),
      );
}

/// Help: WhatsApp and email for the Stall team, and the rules.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final c = SessionScope.of(context).config;
    final phone = (c['phone'] ?? '').toString().replaceAll(RegExp(r'\D'), '').replaceFirst(RegExp(r'^0'), '234');
    final email = (c['email'] ?? '').toString();
    return Scaffold(
      appBar: AppBar(title: const Text('Help')),
      body: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
        ListTile(
          leading: Icon(Icons.menu_book_outlined, color: StallColors.indigo),
          title: const Text('How Stall works'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GuideScreen())),
        ),
        if (phone.isNotEmpty)
          ListTile(
            key: const Key('helpWa'),
            leading: Icon(Icons.chat_outlined, color: StallColors.indigo),
            title: const Text('Message the Stall team on WhatsApp'),
            onTap: () => launchUrl(Uri.parse('https://wa.me/$phone'), mode: LaunchMode.externalApplication),
          ),
        if (email.isNotEmpty)
          ListTile(
            leading: Icon(Icons.mail_outline_rounded, color: StallColors.indigo),
            title: Text('Email $email'),
            onTap: () => launchUrl(Uri.parse('mailto:$email')),
          ),
        const Divider(),
        for (final (p, l) in const [('/rules', 'Rules for buyers and sellers'), ('/terms', 'Terms'), ('/privacy', 'Privacy Policy')])
          ListTile(title: Text(l), trailing: const Icon(Icons.open_in_new_rounded, size: 18), onTap: () => openLink(p)),
      ]),
    );
  }
}

/// Delete your account for good, after typing your password. Orders in progress must finish first (the server checks).
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});
  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _pw = TextEditingController();
  bool _busy = false;
  String? _err, _why;

  static const _reasons = {
    'problem': 'I had a problem with an order or payment',
    'unused': 'I don\'t use Stall anymore',
    'privacy': 'Privacy concerns',
    'other': 'Something else',
  };

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_why == null) return setState(() => _err = 'Choose why you\'re leaving.');
    if (_pw.text.isEmpty) return setState(() => _err = 'Type your password to confirm.');
    setState(() {
      _busy = true;
      _err = null;
    });
    final s = SessionScope.of(context);
    try {
      await s.api.post('me/delete', {'password': _pw.text, 'why': _why});
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
      await s.signOut();
    } on ApiError catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Delete account')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
        Text('This can\'t be undone', style: t.headlineSmall),
        const SizedBox(height: 8),
        const Text('Your listings, store, photos and verification documents are deleted, and you\'re signed out everywhere. '
            'Past orders and payments stay on record, as the law requires, but your name, phone and address are removed from them. '
            'Orders still in progress must be finished or cancelled first, so nobody loses money.'),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          key: const Key('delWhy'),
          initialValue: _why,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Why are you leaving?'),
          items: [for (final e in _reasons.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => setState(() => _why = v),
        ),
        if (_why == 'problem')
          Card(
            key: const Key('delFix'),
            margin: const EdgeInsets.only(top: 10),
            color: StallColors.amberTint,
            child: ListTile(
              title: const Text('Most order and payment problems are fixed within a day, and your money stays protected while we sort it.'),
              subtitle: const Text('Get help instead'),
              onTap: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HelpScreen())),
            ),
          ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('delPw'),
          controller: _pw,
          obscureText: true,
          decoration: InputDecoration(labelText: 'Your password', errorText: _err, errorMaxLines: 3),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('delGo'),
          style: FilledButton.styleFrom(backgroundColor: StallColors.red),
          onPressed: _busy ? null : _delete,
          child: Text(_busy ? 'Deleting…' : 'Delete my account'),
        ),
      ]),
    );
  }
}

/// Account → Change password: the current one, then a new one (8 or more characters). Other phones are signed out.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});
  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _old = TextEditingController(), _new = TextEditingController();
  bool _busy = false, _show = false;
  String? _err;

  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_old.text.isEmpty) return setState(() => _err = 'Type your current password.');
    if (_new.text.length < 8) return setState(() => _err = 'Use at least 8 characters for the new one.');
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await SessionScope.of(context).api.post('password', {'old': _old.text, 'password': _new.text});
      if (!mounted) return;
      toast(context, 'Password changed. Any other phones signed in to your account are signed out.');
      Navigator.of(context).pop();
    } on ApiError catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Change password')),
        body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
          TextField(
            key: const Key('pwOld'),
            controller: _old,
            obscureText: !_show,
            autofillHints: const [AutofillHints.password],
            decoration: const InputDecoration(labelText: 'Current password'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('pwNew'),
            controller: _new,
            obscureText: !_show,
            autofillHints: const [AutofillHints.newPassword],
            decoration: InputDecoration(
              labelText: 'New password',
              helperText: 'At least 8 characters',
              errorText: _err,
              errorMaxLines: 3,
              suffixIcon: IconButton(
                tooltip: _show ? 'Hide' : 'Show',
                onPressed: () => setState(() => _show = !_show),
                icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(key: const Key('pwSave'), onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving…' : 'Change password')),
        ]),
      );
}

/// Account → Notifications: whether this phone gets Stall's notifications, a way to turn them on, and a test one.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  String? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final st = await Push.status();
    if (mounted) setState(() => _status = st);
  }

  Future<void> _on() async {
    setState(() => _busy = true);
    await Push.start(SessionScope.of(context));
    await _check();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _test() async {
    try {
      await SessionScope.of(context).api.post('push/test');
      if (mounted) toast(context, 'Sent. It should arrive in a few seconds.');
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final st = _status;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
        Text(Push.label(st), key: const Key('pushStatus'), style: t.headlineSmall),
        const SizedBox(height: 8),
        Text(
          switch (st) {
            'on' => 'You\'ll hear from Stall when you sell something, get a message, or your order moves, even when the app is closed.',
            'blocked' => 'Notifications for Stall are turned off in your phone\'s settings. Turn them on in Settings → Apps → Stall → Notifications.',
            'unsupported' => 'This version of the app can\'t get notifications yet. You\'ll still see updates on the Orders tab and in Messages.',
            null => '',
            _ => 'Turn them on to hear when you sell something, get a message, or your order moves.',
          },
          style: t.bodyLarge?.copyWith(color: StallColors.muted),
        ),
        const SizedBox(height: 20),
        if (st == 'off') FilledButton(key: const Key('pushOn'), onPressed: _busy ? null : _on, child: const Text('Turn on notifications')),
        if (st == 'on') OutlinedButton(key: const Key('pushTest'), onPressed: _test, child: const Text('Send me a test notification')),
        if (st == 'on')
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('To turn them off, use Settings → Apps → Stall → Notifications on your phone.', style: t.bodySmall),
          ),
      ]),
    );
  }
}

/// Account → Manage account: help and a break first, then deleting the account.
class ManageAccountScreen extends StatelessWidget {
  const ManageAccountScreen({super.key, this.hasStore = false});
  final bool hasStore;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final u = SessionScope.of(context).user;
    Widget card(String title, String text, List<Widget> acts) => Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: t.titleMedium),
              const SizedBox(height: 4),
              Text(text, style: t.bodyMedium?.copyWith(color: StallColors.muted)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: acts),
            ]),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Manage account')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        card('Problem with an order or payment?',
            'Your money is protected until it\'s sorted. Report it on the order and we\'ll sort it, usually within a day.', [
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HelpScreen())),
            child: const Text('Get help'),
          ),
        ]),
        card(
          'Need a break?',
          hasStore
              ? 'Close your store for a while from Your store. Buyers just see it as closed, and your items and reviews stay.'
              : 'You can turn off emails and come back whenever you like.',
          [
            if (u != null && u.email.isNotEmpty)
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: () => Navigator.of(context).pop('email'),
                child: const Text('Email settings'),
              ),
            if (hasStore)
              OutlinedButton(
                key: const Key('mngStore'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: () => Navigator.of(context).pop('store'),
                child: const Text('Go to my store'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (u != null && !u.isAdmin)
          Center(
            child: TextButton(
              key: const Key('deleteAccount'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DeleteAccountScreen())),
              child: Text('Delete my account', style: TextStyle(color: StallColors.muted, decoration: TextDecoration.underline)),
            ),
          ),
      ]),
    );
  }
}
