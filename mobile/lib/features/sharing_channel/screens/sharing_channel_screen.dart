import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../sharing_channel_notifier.dart';
import '../../../core/models/sharing_channel_post.dart';
import '../../auth/auth_notifier.dart';

class SharingChannelScreen extends ConsumerStatefulWidget {
  const SharingChannelScreen({super.key});

  @override
  ConsumerState<SharingChannelScreen> createState() => _SharingChannelScreenState();
}

class _SharingChannelScreenState extends ConsumerState<SharingChannelScreen> {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    try {
      await ref.read(sharingChannelProvider.notifier).sendPost(text);
      _scrollToBottom();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sharingChannelProvider);
    final me = ref.watch(authProvider).user;

    ref.listen(sharingChannelProvider, (prev, next) {
      if (next.posts.length > (prev?.posts.length ?? 0)) _scrollToBottom();
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sharing'),
        actions: [
          if (state.phase == SharingChannelPhase.joined)
            TextButton(
              onPressed: () => ref.read(sharingChannelProvider.notifier).leave(),
              child: const Text('Leave'),
            ),
        ],
      ),
      body: switch (state.phase) {
        SharingChannelPhase.closed => const _ClosedView(),
        SharingChannelPhase.openNotJoined => _JoinView(loading: state.loading),
        SharingChannelPhase.joined => _ChatView(
            state: state,
            me: me,
            scrollCtrl: _scrollCtrl,
            ctrl: _ctrl,
            onSend: _send,
          ),
      },
    );
  }
}

class _ClosedView extends StatelessWidget {
  const _ClosedView();

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('No sharing session right now', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('You\'ll be notified when one opens.', style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
}

class _JoinView extends ConsumerWidget {
  final bool loading;
  const _JoinView({required this.loading});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sharingChannelProvider);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.group_outlined, size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text('Sharing session is open!', style: Theme.of(context).textTheme.titleLarge),
            if (state.scheduledClosedAt != null) ...[
              const SizedBox(height: 8),
              Text(
                'Closes at ${DateFormat('HH:mm').format(state.scheduledClosedAt!.toLocal())}',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: loading ? null : () => ref.read(sharingChannelProvider.notifier).join(),
              icon: const Icon(Icons.login),
              label: loading ? const Text('Joining…') : const Text('Join session'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatView extends StatelessWidget {
  final SharingChannelState state;
  final dynamic me;
  final ScrollController scrollCtrl;
  final TextEditingController ctrl;
  final VoidCallback onSend;

  const _ChatView({
    required this.state,
    required this.me,
    required this.scrollCtrl,
    required this.ctrl,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (state.closingSoon)
          MaterialBanner(
            content: Text('Closing in ${state.minutesRemaining} minutes'),
            backgroundColor: Colors.orange[100],
            actions: [TextButton(onPressed: () {}, child: const Text('OK'))],
          ),
        Expanded(
          child: state.posts.isEmpty
              ? Center(child: Text('No messages yet. Say something!', style: TextStyle(color: Colors.grey[500])))
              : ListView.builder(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  itemCount: state.posts.length,
                  itemBuilder: (_, i) => _Bubble(post: state.posts[i], isMe: me?.id == state.posts[i].author.id),
                ),
        ),
        _InputBar(ctrl: ctrl, onSend: onSend),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  final SharingChannelPost post;
  final bool isMe;
  const _Bubble({required this.post, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            CircleAvatar(radius: 14, child: Text(post.author.name[0].toUpperCase())),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2, left: 4),
                    child: Text(post.author.fullName, style: Theme.of(context).textTheme.labelSmall),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isMe ? scheme.primary : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isMe ? 16 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 16),
                    ),
                  ),
                  child: Text(
                    post.content,
                    style: TextStyle(color: isMe ? scheme.onPrimary : scheme.onSurface),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
                  child: Text(
                    DateFormat('HH:mm').format(post.createdAt.toLocal()),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController ctrl;
  final VoidCallback onSend;
  const _InputBar({required this.ctrl, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: ctrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Message…',
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: onSend,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}
