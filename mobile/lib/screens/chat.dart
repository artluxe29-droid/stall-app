import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../main.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

/// Opens (or reuses) the chat about a listing ("L12"), store ("S4") or order ("O31").
Future<void> openChat(BuildContext context, String ref) async {
  try {
    final r = await SessionScope.of(context).api.post('chat/open', {'ref': ref});
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(tid: (r['id'] as num).toInt())));
  } on ApiError catch (e) {
    if (context.mounted) toast(context, e.message);
  }
}

/// A "Message" button for item, store and order pages.
class MessageButton extends StatelessWidget {
  const MessageButton({super.key, required this.ref, required this.label});
  final String ref, label;
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        key: Key('msg-$ref'),
        onPressed: () => openChat(context, ref),
        icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
        label: Text(label),
      );
}

/// All your chats, newest first, with unread ones marked.
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});
  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  Future<List<Map<String, dynamic>>>? _f;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _f ??= _load();
  }

  Future<List<Map<String, dynamic>>> _load() async =>
      ((await SessionScope.of(context).api.get('chat/list'))['threads'] as List? ?? const []).cast<Map<String, dynamic>>();

  Future<void> _refresh() async {
    final f = _load();
    setState(() {
      _f = f;
    });
    await f.catchError((_) => <Map<String, dynamic>>[]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Messages')),
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _f,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
              if (snap.hasError) {
                return EmptyState(
                    icon: Icons.wifi_off_rounded,
                    title: 'Couldn\'t load your messages',
                    text: snap.error is ApiError ? (snap.error as ApiError).message : 'Pull down to try again.');
              }
              final ts = snap.data!;
              if (ts.isEmpty) {
                return ListView(children: const [
                  SizedBox(height: 80),
                  EmptyState(
                      icon: Icons.chat_bubble_outline_rounded,
                      title: 'No messages yet',
                      text: 'Message a seller from an item, a store or an order. Chats stay in Stall, so there\'s a record if anything goes wrong.'),
                ]);
              }
              final t = Theme.of(context).textTheme;
              return ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: ts.length,
                separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
                itemBuilder: (context, i) {
                  final x = ts[i];
                  final unread = x['unread'] == true;
                  final who = (x['with'] ?? '').toString();
                  return ListTile(
                    key: Key('thread-${x['id']}'),
                    leading: CircleAvatar(
                      backgroundColor: StallColors.indigo,
                      foregroundColor: StallColors.cream,
                      child: Text(who.isEmpty ? '?' : who[0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    title: Row(children: [
                      Expanded(child: Text(who, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.w600))),
                      Text(ago((x['lastAt'] as num?)?.toInt() ?? 0), style: t.bodySmall),
                    ]),
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text((x['title'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall),
                      Text((x['last'] ?? '').toString(),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: unread ? StallColors.ink : StallColors.muted)),
                    ]),
                    trailing: unread ? const CircleAvatar(radius: 5, backgroundColor: StallColors.red) : null,
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(tid: (x['id'] as num).toInt())));
                      _refresh();
                    },
                  );
                },
              );
            },
          ),
        ),
      );
}

/// One chat. New messages arrive every few seconds while it's open.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.tid, this.poll = const Duration(seconds: 5)});
  final int tid;
  final Duration poll;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgs = <Map<String, dynamic>>[];
  final _text = TextEditingController();
  Map<String, dynamic>? _thread;
  String? _error;
  bool _sending = false, _warn = false, _loading = true;
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_timer == null) {
      _fetch();
      _timer = Timer.periodic(widget.poll, (_) => _fetch());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _text.dispose();
    super.dispose();
  }

  int get _last => _msgs.isEmpty ? 0 : (_msgs.last['id'] as num).toInt();

  Future<void> _fetch() async {
    try {
      final r = await SessionScope.of(context).api.get('chat/msgs', {'tid': '${widget.tid}', if (_last > 0) 'after': '$_last'});
      if (!mounted) return;
      final got = (r['msgs'] as List? ?? const []).cast<Map<String, dynamic>>();
      setState(() {
        _thread = r['thread'] as Map<String, dynamic>?;
        final have = _msgs.map((m) => m['id']).toSet();
        _msgs.addAll(got.where((m) => !have.contains(m['id'])));
        _loading = false;
        _error = null;
      });
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (_) {}
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final r = await SessionScope.of(context).api.post('chat/send', {'tid': widget.tid, 'body': body});
      _text.clear();
      if (r['warn'] == true) setState(() => _warn = true);
      await _fetch();
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _menu(String v) async {
    final api = SessionScope.of(context).api;
    if (v == 'report') {
      var why = '';
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Report this chat?'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('The Stall team will read the latest messages.'),
            const SizedBox(height: 8),
            TextField(
                key: const Key('reportWhy'),
                onChanged: (x) => why = x,
                maxLength: 200,
                decoration: const InputDecoration(hintText: 'What\'s wrong? (optional)')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(key: const Key('reportSend'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Report')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      try {
        await api.post('chat/report', {'tid': widget.tid, 'reason': why.trim()});
        if (mounted) toast(context, 'Reported. Thanks for telling us.');
      } on ApiError catch (e) {
        if (mounted) toast(context, e.message);
      }
    } else {
      final on = _thread?['iBlock'] != true;
      try {
        await api.post('chat/block', {'tid': widget.tid, 'on': on});
        if (!mounted) return;
        toast(context, on ? 'Blocked. They can\'t message you.' : 'Unblocked');
        setState(() => _thread = {...?_thread, 'iBlock': on});
      } on ApiError catch (e) {
        if (mounted) toast(context, e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final th = _thread;
    final blocked = th?['iBlock'] == true;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text((th?['with'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium),
          Text((th?['title'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall),
        ]),
        actions: [
          PopupMenuButton<String>(
            key: const Key('chatMenu'),
            onSelected: _menu,
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'report', child: Text('Report')),
              PopupMenuItem(value: 'block', child: Text(blocked ? 'Unblock' : 'Block')),
            ],
          ),
        ],
      ),
      body: Column(children: [
        Container(
          width: double.infinity,
          color: _warn ? StallColors.redTint : StallColors.cream2,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(
            _warn
                ? 'Only pay through Stall. Money sent straight to someone\'s account isn\'t protected, and Stall can\'t get it back.'
                : 'Pay only through Stall, so your money is held until you have your item.',
            key: const Key('chatTip'),
            style: t.bodySmall?.copyWith(color: StallColors.ink),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null && _msgs.isEmpty
                  ? EmptyState(icon: Icons.chat_bubble_outline_rounded, title: 'Couldn\'t open this chat', text: _error!)
                  : _msgs.isEmpty
                      ? const EmptyState(icon: Icons.waving_hand_outlined, title: 'Say hello', text: 'Ask about the item, the price or where to meet.')
                      : ListView.builder(
                          reverse: true,
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                          itemCount: _msgs.length,
                          itemBuilder: (context, i) {
                            final m = _msgs[_msgs.length - 1 - i];
                            final mine = m['mine'] == true;
                            return Align(
                              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
                                margin: const EdgeInsets.symmetric(vertical: 3),
                                padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                                decoration: BoxDecoration(
                                  color: mine ? StallColors.indigo : StallColors.card,
                                  borderRadius: BorderRadius.circular(16),
                                  border: mine ? null : Border.all(color: StallColors.line),
                                ),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                  Text((m['body'] ?? '').toString(), style: TextStyle(color: mine ? StallColors.cream : StallColors.ink)),
                                  Text(ago((m['t'] as num?)?.toInt() ?? 0),
                                      style: TextStyle(fontSize: 11, color: mine ? StallColors.cream.withValues(alpha: .7) : StallColors.muted)),
                                ]),
                              ),
                            );
                          },
                        ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
            child: blocked
                ? Text('You blocked this person. Unblock them from the menu to message again.', style: t.bodySmall)
                : Row(children: [
                    Expanded(
                      child: TextField(
                        key: const Key('chatText'),
                        controller: _text,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: 1000,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(hintText: 'Message', counterText: ''),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    IconButton(
                      key: const Key('chatSend'),
                      tooltip: 'Send',
                      onPressed: _sending ? null : _send,
                      icon: Icon(Icons.send_rounded, color: StallColors.indigo),
                    ),
                  ]),
          ),
        ),
      ]),
    );
  }
}
