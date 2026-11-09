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
    final directory = await guarded(context, () async {
      final out = <UserAccount>[];
      String? cursor;
      do {
        final page = await _v.users(cursor: cursor, limit: 200);
        out.addAll(page.items);
        cursor = page.hasMore ? page.nextCursor : null;
      } while (cursor != null);
      return out;
    });
    if (directory == null || !mounted) return null;
    final selected = <String>{};
    final currentUser = ref.read(userProvider)?.userName;
    String search = '';

    return showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final q = search.toLowerCase();
          final users = directory.where((u) {
            final text = '${u.displayName} ${u.userName} ${u.email ?? ''}'
                .toLowerCase();
            return q.isEmpty || text.contains(q);
          }).toList();
          return AlertDialog(
            title: const Text('Select Recipients'),
            insetPadding: const EdgeInsets.all(16),
            content: SizedBox(
              width: double.maxFinite,
              height: (MediaQuery.sizeOf(ctx).height - MediaQuery.viewInsetsOf(ctx).bottom - 200)
                  .clamp(120.0, 520.0)
                  .toDouble(),
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search users',
                    ),
                    onChanged: (v) => set(() => search = v),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      selected.isEmpty
                          ? 'No recipients selected.'
                          : '${selected.length} selected.',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: ListView.builder(
                      itemCount: users.length,
                      itemBuilder: (_, i) {
                        final u = users[i];
                        final isSelf = currentUser != null &&
                            u.userName.toLowerCase() == currentUser.toLowerCase();
                        final checked = selected.contains(u.userName);
                        return CheckboxListTile(
                          value: checked,
                          onChanged: isSelf
                              ? null
                              : (v) => set(
                                  () => v == true
                                      ? selected.add(u.userName)
                                      : selected.remove(u.userName),
                                ),
                          secondary: CircleAvatar(
                            child: Text(
                              u.userName.isEmpty
                                  ? '?'
                                  : u.userName[0].toUpperCase(),
                            ),
                          ),
                          title: Text(u.displayName),
                          subtitle: Text(isSelf ? '${u.userName} · You cannot message yourself' : u.userName),
                          controlAffinity: ListTileControlAffinity.trailing,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.pop(ctx, selected.toList()),
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

    final currentUser = ref.read(userProvider)?.userName;
    if (currentUser != null && recipients.any((r) => r.toLowerCase() == currentUser.toLowerCase())) {
      toast(context, 'You cannot send a message to yourself.', error: true);
      return;
    }

    final draft = await showDialog<_MessageDraft>(
      context: context,
      builder: (_) => _MessageDraftDialog(
        title: replyTo == null ? 'New Message' : 'Reply',
        audience: '${recipients.length} recipient${recipients.length == 1 ? '' : 's'}',
        initialSubject: subject ?? '',
        sendLabel: 'Send Message',
      ),
    );
    if (draft == null || !mounted) return;
    final sent = await guarded(context, () async {
      await _v.send(recipients, draft.subject, draft.body, replyTo: replyTo);
      return true;
    });
    if (sent != true || !mounted) return;
    toast(context, 'Message sent.');
    _refreshAll();
  }

  Future<void> _broadcast() async {
    final draft = await showDialog<_MessageDraft>(
      context: context,
      builder: (_) => const _MessageDraftDialog(
        title: 'Broadcast to Everyone',
        audience: 'All users will receive this message.',
        sendLabel: 'Send to Everyone',
        broadcast: true,
      ),
    );
    if (draft == null || !mounted) return;
    final n = await guarded(
      context,
      () => _v.broadcast(draft.subject, draft.body),
    );
    if (n != null && mounted) {
      toast(context, 'Delivered to $n user${n == 1 ? '' : 's'}.');
      _refreshAll();
    }
  }

  Future<void> _open(Msg m, bool inbox) async {
    final full = await guarded(context, () => _v.message(m.id));
    if (full == null || !mounted) return;
    _refreshAll();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(full.subject),
        insetPadding: const EdgeInsets.all(16),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${inbox ? 'From' : 'To'}: ${inbox ? full.sender : full.recipient}  ·  ${fmtDate(full.createdAt)}',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const Divider(),
                SelectableText(full.body ?? full.preview),
              ],
            ),
          ),
        ),
        actionsOverflowDirection: VerticalDirection.down,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          if (inbox && !full.isSystem)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _compose(
                  to: full.sender,
                  subject: full.subject.startsWith('Re: ')
                      ? full.subject
                      : 'Re: ${full.subject}',
                  replyTo: full.id,
                );
              },
              child: const Text('Reply'),
            ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await guarded(context, () => _v.deleteMessage(m.id));
              _refreshAll();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _list(bool inbox) {
    return CursorList<Msg>(
      key: ValueKey('${inbox}_${_unreadOnly}_$_gen'),
      empty: inbox ? 'Inbox is empty.' : 'No sent messages.',
      emptyIcon: Icons.mail_outline,
      fetch: (c) => inbox
          ? _v.inbox(cursor: c, unread: _unreadOnly ? true : null)
          : _v.sent(cursor: c),
      itemBuilder: (ctx, m, i) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _open(m, inbox),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  child: Icon(
                    m.isSystem ? Icons.campaign_outlined : Icons.person_outline,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              m.subject,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: inbox && !m.isRead
                                    ? FontWeight.bold
                                    : null,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              fmtShort(m.createdAt),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(ctx).textTheme.labelSmall,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        inbox ? m.sender : m.recipient,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(ctx).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        m.preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canBroadcast =
        ref.watch(userProvider)?.has(Scopes.messagesBroadcast) ?? false;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Messages'),
          actions: [
            IconButton(
              tooltip: _unreadOnly ? 'Show All' : 'Unread Only',
              icon: Icon(
                _unreadOnly
                    ? Icons.mark_email_unread
                    : Icons.mark_email_unread_outlined,
              ),
              onPressed: () => setState(() => _unreadOnly = !_unreadOnly),
            ),
            IconButton(
              tooltip: 'Mark All Read',
              icon: const Icon(Icons.done_all),
              onPressed: () async {
                await guarded(context, _v.readAll);
                _refreshAll();
              },
            ),
            if (canBroadcast)
              IconButton(
                tooltip: 'Broadcast',
                icon: const Icon(Icons.campaign_outlined),
                onPressed: _broadcast,
              ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Inbox'),
              Tab(text: 'Sent'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _compose(),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Compose'),
        ),
        body: TabBarView(children: [_list(true), _list(false)]),
      ),
    );
  }
}


class _MessageDraft {
  const _MessageDraft(this.subject, this.body);
  final String subject;
  final String body;
}

class _MessageDraftDialog extends StatefulWidget {
  const _MessageDraftDialog({
    required this.title,
    required this.audience,
    required this.sendLabel,
    this.initialSubject = '',
    this.broadcast = false,
  });

  final String title;
  final String audience;
  final String sendLabel;
  final String initialSubject;
  final bool broadcast;

  @override
  State<_MessageDraftDialog> createState() => _MessageDraftDialogState();
}

class _MessageDraftDialogState extends State<_MessageDraftDialog> {
  late final _subject = TextEditingController(text: widget.initialSubject);
  final _body = TextEditingController();

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canSend = _subject.text.trim().isNotEmpty && _body.text.trim().isNotEmpty;
    return AlertDialog(
      insetPadding: const EdgeInsets.all(16),
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        height: (MediaQuery.sizeOf(context).height - MediaQuery.viewInsetsOf(context).bottom - 220)
            .clamp(140.0, 520.0)
            .toDouble(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    widget.broadcast ? Icons.campaign_outlined : Icons.people_alt_outlined,
                    color: cs.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(widget.audience, style: Theme.of(context).textTheme.bodyMedium)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _subject,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Subject',
                prefixIcon: Icon(Icons.short_text),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => FocusScope.of(context).nextFocus(),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                controller: _body,
                expands: true,
                minLines: null,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Message',
                  alignLabelWithHint: true,
                  hintText: 'Write your message…',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: canSend
              ? () => Navigator.pop(
                    context,
                    _MessageDraft(_subject.text.trim(), _body.text.trim()),
                  )
              : null,
          icon: const Icon(Icons.send_outlined),
          label: Text(widget.sendLabel),
        ),
      ],
    );
  }
}
