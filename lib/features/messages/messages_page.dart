import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/scopes.dart';
import '../../core/util.dart';
import '../../core/vaulton.dart';
import '../../core/widgets.dart';

class MessagesPage extends ConsumerStatefulWidget {
  const MessagesPage({super.key});
  @override
  ConsumerState<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends ConsumerState<MessagesPage> {


  bool _unreadOnly = false;
  int _gen = 0;
  Vaulton get _v => ref.read(vaultonProvider);

  void _refreshAll() {
    setState(() => _gen++);
    ref.invalidate(unreadProvider);
  }

  Future<List<String>?> _selectRecipients() async {
    final page = await guarded(context, () => _v.users(limit: 200));
    if (page == null || !mounted) return null;
    final selected = <String>{};
    String search = '';

    return showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final q = search.toLowerCase();
          final users = page.items.where((u) {
            final text = '${u.displayName} ${u.userName} ${u.email ?? ''}'.toLowerCase();
            return q.isEmpty || text.contains(q);
          }).toList();
          return AlertDialog(
            title: const Text('Select Recipients'),
            content: SizedBox(
              width: 520,
              height: 520,
              child: Column(children: [
                TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search Users',
                  ),
                  onChanged: (v) => set(() => search = v),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    selected.isEmpty ? 'No Recipients Selected' : '${selected.length} Selected',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: ListView.builder(
                    itemCount: users.length,
                    itemBuilder: (_, i) {
                      final u = users[i];
                      final checked = selected.contains(u.userName);
                      return CheckboxListTile(
                        value: checked,
                        onChanged: (v) => set(() => v == true ? selected.add(u.userName) : selected.remove(u.userName)),
                        secondary: CircleAvatar(child: Text(u.userName.isEmpty ? '?' : u.userName[0].toUpperCase())),
                        title: Text(u.displayName),
                        subtitle: Text(u.userName),
                        controlAffinity: ListTileControlAffinity.trailing,
                      );
                    },
                  ),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: selected.isEmpty ? null : () => Navigator.pop(ctx, selected.toList()),
                child: const Text('Continue'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _compose({String? to, String? subject, String? replyTo}) async {
    List<String> recipients;
    if (to != null && to.isNotEmpty) {
      recipients = splitList(to);
    } else {
      final picked = await _selectRecipients();
      if (picked == null || picked.isEmpty || !mounted) return;
      recipients = picked;
    }

    final f = await formDialog(context, replyTo == null ? 'New Message' : 'Reply', [
      FieldSpec('subject', 'Subject', initial: subject ?? '', required: true),
      const FieldSpec('body', 'Message', kind: 'multiline', required: true),
    ], ok: 'Send');
    if (f == null) return;
    await guarded(context, () => _v.send(recipients, f['subject']!, f['body']!, replyTo: replyTo));
    if (!mounted) return;
    toast(context, 'Sent');
    _refreshAll();
  }

  Future<void> _broadcast() async {
    final f = await formDialog(context, 'Broadcast to Everyone', [
      const FieldSpec('subject', 'Subject', required: true),
      const FieldSpec('body', 'Message', kind: 'multiline', required: true),
    ], ok: 'Send to All');
    if (f == null) return;
    final n = await guarded(context, () => _v.broadcast(f['subject']!, f['body']!));
    if (n != null && mounted) toast(context, 'Delivered to $n user${n == 1 ? '' : 's'}');
  }

  Future<void> _open(Msg m, bool inbox) async {
    final full = await guarded(context, () => _v.message(m.id));
    if (full == null || !mounted) return;
    _refreshAll();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(full.subject),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${inbox ? 'From' : 'To'}: ${inbox ? full.sender : full.recipient}  ·  ${fmtDate(full.createdAt)}', style: Theme.of(ctx).textTheme.bodySmall),
              const Divider(),
              SelectableText(full.body ?? full.preview),
            ]),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await guarded(context, () => _v.deleteMessage(m.id));
              _refreshAll();
            },
            child: const Text('Delete'),
          ),
          if (inbox && !full.isSystem)
            TextButton(onPressed: () { Navigator.pop(ctx); _compose(to: full.sender, subject: full.subject.startsWith('Re: ') ? full.subject : 'Re: ${full.subject}', replyTo: full.id); }, child: const Text('Reply')),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _list(bool inbox) {
    return CursorList<Msg>(
      key: ValueKey('${inbox}_${_unreadOnly}_$_gen'),
      empty: inbox ? 'Inbox is empty' : 'No sent messages',
      emptyIcon: Icons.mail_outline,
      fetch: (c) => inbox ? _v.inbox(cursor: c, unread: _unreadOnly ? true : null) : _v.sent(cursor: c),
      itemBuilder: (ctx, m, i) => ListTile(
        leading: CircleAvatar(child: Icon(m.isSystem ? Icons.campaign_outlined : Icons.person_outline)),
        title: Text(m.subject, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: inbox && !m.isRead ? FontWeight.bold : null)),
        subtitle: Text('${inbox ? m.sender : m.recipient} — ${m.preview}', maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: Text(fmtShort(m.createdAt), style: Theme.of(ctx).textTheme.labelSmall),
        onTap: () => _open(m, inbox),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canBroadcast = ref.watch(userProvider)?.has(Scopes.messagesBroadcast) ?? false;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Messages'),
          actions: [
            IconButton(tooltip: _unreadOnly ? 'Show All' : 'Unread Only', icon: Icon(_unreadOnly ? Icons.mark_email_unread : Icons.mark_email_unread_outlined), onPressed: () => setState(() => _unreadOnly = !_unreadOnly)),
            IconButton(
              tooltip: 'Mark All Read',
              icon: const Icon(Icons.done_all),
              onPressed: () async {
                await guarded(context, _v.readAll);
                _refreshAll();
              },
            ),
            if (canBroadcast) IconButton(tooltip: 'Broadcast', icon: const Icon(Icons.campaign_outlined), onPressed: _broadcast),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Inbox'), Tab(text: 'Sent')]),
        ),
        floatingActionButton: FloatingActionButton.extended(onPressed: () => _compose(), icon: const Icon(Icons.edit_outlined), label: const Text('Compose')),
        body: TabBarView(children: [_list(true), _list(false)]),
      ),
    );
  }
}
