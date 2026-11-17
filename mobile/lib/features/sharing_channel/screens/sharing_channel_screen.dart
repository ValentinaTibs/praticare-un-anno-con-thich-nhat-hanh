import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/models/sharing_channel_post.dart';
import '../../../core/theme/lanterna_theme.dart';
import '../../../core/widgets/lanterna_marks.dart';
import '../../auth/auth_notifier.dart';
import '../circle_status.dart';
import '../sharing_channel_notifier.dart';

const _gutter = 24.0;

String _closesAt(DateTime date) => 'Si chiude alle ${DateFormat('H:mm').format(date.toLocal())}';

String _peopleLabel(int? count) => switch (count) {
      null => 'Il cerchio è aperto',
      1 => '1 persona è nel cerchio',
      _ => '$count persone sono nel cerchio',
    };

class SharingChannelScreen extends ConsumerStatefulWidget {
  const SharingChannelScreen({super.key});

  @override
  ConsumerState<SharingChannelScreen> createState() => _SharingChannelScreenState();
}

class _SharingChannelScreenState extends ConsumerState<SharingChannelScreen> {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _leaving = false;

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
    } catch (_) {
      // Give the text back, so nothing written is lost.
      if (_ctrl.text.isEmpty) _ctrl.text = text;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Messaggio non inviato. Riprova.')));
      }
    }
  }

  // The back arrow leaves the circle and goes back to the home.
  Future<void> _leave() async {
    setState(() => _leaving = true);
    try {
      await ref.read(sharingChannelProvider.notifier).leave();
      if (!mounted) return;
      ref.invalidate(circleStatusProvider);
      context.go('/home/main-channel');
    } catch (_) {
      if (!mounted) return;
      setState(() => _leaving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Non è stato possibile uscire dal cerchio. Riprova.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sharingChannelProvider);
    final me = ref.watch(authProvider).user;

    ref.listen(sharingChannelProvider, (prev, next) {
      if (next.posts.length > (prev?.posts.length ?? 0)) _scrollToBottom();
    });

    final joined = state.phase == SharingChannelPhase.joined;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(joined ? 8 : _gutter, 12, _gutter, 16),
              child: Row(
                children: [
                  if (joined) ...[
                    IconButton(
                      onPressed: _leaving ? null : _leave,
                      tooltip: 'Esci dal cerchio',
                      icon: const Icon(Icons.arrow_back),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Semantics(
                    header: true,
                    child: Text('Il cerchio', style: Theme.of(context).textTheme.headlineSmall),
                  ),
                ],
              ),
            ),
            Expanded(
              child: switch (state.phase) {
                SharingChannelPhase.closed => const _ClosedView(),
                SharingChannelPhase.openNotJoined => _JoinView(state: state),
                SharingChannelPhase.joined => _ChatView(
                    state: state,
                    myId: me?.id,
                    scrollCtrl: _scrollCtrl,
                    ctrl: _ctrl,
                    onSend: _send,
                  ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ClosedView extends StatelessWidget {
  const _ClosedView();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(_gutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircleDots(size: 64, filled: 0),
              const SizedBox(height: 24),
              Text('Il cerchio è chiuso', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text(
                'Riceverai una notifica quando si apre.',
                style: LanternaText.caption,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
}

/// Open, not joined yet: what joining means, and the button that joins.
class _JoinView extends ConsumerWidget {
  final SharingChannelState state;
  const _JoinView({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final closesAt = state.scheduledClosedAt;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(_gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleDots(size: 64, filled: state.memberCount ?? CircleDots.dots),
            const SizedBox(height: 24),
            Text('Il cerchio è aperto', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              [
                if (state.memberCount != null) _peopleLabel(state.memberCount),
                if (closesAt != null) _closesAt(closesAt),
              ].join(' · '),
              style: LanternaText.caption,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Text(
              'Entrando potrai leggere e scrivere i messaggi del cerchio: ognuno mostra nome e cognome '
              'di chi scrive. Alla chiusura i messaggi si cancellano.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: state.loading ? null : () => ref.read(sharingChannelProvider.notifier).join(),
              child: Text(state.loading ? 'Ingresso…' : 'Entra nel cerchio'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatView extends StatelessWidget {
  final SharingChannelState state;
  final String? myId;
  final ScrollController scrollCtrl;
  final TextEditingController ctrl;
  final VoidCallback onSend;

  const _ChatView({
    required this.state,
    required this.myId,
    required this.scrollCtrl,
    required this.ctrl,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _gutter),
          child: _StatusCard(state: state),
        ),
        Expanded(
          child: state.posts.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(_gutter),
                    child: Text('Ancora nessun messaggio.', style: LanternaText.caption),
                  ),
                )
              : ListView.builder(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(_gutter, 24, _gutter, 8),
                  itemCount: state.posts.length,
                  itemBuilder: (_, i) => _Message(post: state.posts[i], isMe: myId == state.posts[i].author.id),
                ),
        ),
        _InputBar(ctrl: ctrl, onSend: onSend),
      ],
    );
  }
}

/// How many people are in, when it closes, and that the messages go then.
class _StatusCard extends StatelessWidget {
  final SharingChannelState state;
  const _StatusCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final closesAt = state.scheduledClosedAt;
    final closing = state.closingSoon
        ? 'Chiude tra ${state.minutesRemaining} minuti · i messaggi poi si cancellano'
        : closesAt != null
            ? '${_closesAt(closesAt)} · i messaggi poi si cancellano'
            : 'Alla chiusura i messaggi si cancellano';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: LanternaColors.surface, borderRadius: BorderRadius.circular(18)),
      child: Row(
        children: [
          CircleDots(size: 44, filled: state.memberCount ?? CircleDots.dots),
          const SizedBox(width: 16),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _peopleLabel(state.memberCount),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: LanternaColors.text),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    closing,
                    style: LanternaText.caption.copyWith(color: state.closingSoon ? LanternaColors.accent : null),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A message without a bubble: name in amber, text in the reading serif. One's
/// own messages say "Tu" and have an amber rule on the left.
class _Message extends StatelessWidget {
  final SharingChannelPost post;
  final bool isMe;
  const _Message({required this.post, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('H:mm').format(post.createdAt.toLocal());
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Container(
        padding: EdgeInsets.only(left: isMe ? 14 : 0),
        decoration: isMe
            ? const BoxDecoration(border: Border(left: BorderSide(color: LanternaColors.accent, width: 2)))
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: isMe ? 'Tu' : post.author.fullName,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isMe ? LanternaColors.muted : LanternaColors.accent,
                    ),
                  ),
                  TextSpan(text: '  ·  $time', style: const TextStyle(color: LanternaColors.muted)),
                ],
              ),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(post.content, style: LanternaText.circleMessage),
          ],
        ),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(_gutter, 8, _gutter, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Scrivi al cerchio…'),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 10),
          IconButton.filled(
            onPressed: onSend,
            tooltip: 'Invia',
            style: IconButton.styleFrom(minimumSize: const Size.square(52)),
            icon: const Icon(Icons.arrow_upward),
          ),
        ],
      ),
    );
  }
}
