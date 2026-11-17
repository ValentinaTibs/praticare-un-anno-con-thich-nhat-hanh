import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/api/api_client.dart';
import '../../../core/constants.dart';
import '../../../core/journey_day.dart';
import '../../../core/models/main_channel_post.dart';
import '../../../core/models/user.dart';
import '../../../core/theme/lanterna_theme.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/lanterna_marks.dart';
import '../../../core/widgets/link_text.dart';
import '../../auth/auth_notifier.dart';
import '../../daily_quote/daily_quote.dart';
import '../../sharing_channel/circle_status.dart';
import '../main_channel_notifier.dart';

const _gutter = 24.0;

/// The home of a group member: journey day, today's quote, the way into the
/// circle while it is open, and the Main Channel.
class MainChannelScreen extends ConsumerStatefulWidget {
  const MainChannelScreen({super.key});

  @override
  ConsumerState<MainChannelScreen> createState() => _MainChannelScreenState();
}

class _MainChannelScreenState extends ConsumerState<MainChannelScreen> {
  bool _entering = false;

  Future<void> _refresh() async {
    ref.invalidate(circleStatusProvider);
    await ref.read(mainChannelProvider.notifier).load(refresh: true);
  }

  // Touching the entry is the consent to join the circle (spec, section 9).
  Future<void> _enterCircle(CircleStatus circle) async {
    if (!circle.joined) {
      setState(() => _entering = true);
      try {
        await ref.read(apiClientProvider).post('/api/sharing-channel/join');
      } on ApiException catch (e) {
        // 409: already in, from another device.
        if (e.statusCode != 409) {
          if (mounted) {
            setState(() => _entering = false);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
            ref.invalidate(circleStatusProvider);
          }
          return;
        }
      }
      if (!mounted) return;
      setState(() => _entering = false);
    }
    context.go('/home/sharing');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(mainChannelProvider);
    final user = ref.watch(authProvider).user;
    final quote = ref.watch(dailyQuoteProvider);
    final circle = ref.watch(circleStatusProvider).valueOrNull;

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _JourneyHeader(user: user),
        if (quote != null) ...[
          const SizedBox(height: 44),
          const Center(child: Lantern()),
          const SizedBox(height: 18),
          DailyQuoteText(quote),
        ],
        if (circle != null && circle.open) ...[
          const SizedBox(height: 36),
          _CircleEntry(circle: circle, busy: _entering, onTap: () => _enterCircle(circle)),
        ],
        const SizedBox(height: 40),
        Semantics(header: true, child: const Text('CANALE PRINCIPALE', style: LanternaText.sectionLabel)),
        const SizedBox(height: 20),
      ],
    );

    final Widget? placeholder = switch (state) {
      MainChannelState(loading: true, posts: []) => const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      MainChannelState(error: final String _, posts: []) => ErrorRetry(
          message: 'Impossibile caricare il Canale Principale.',
          onRetry: () => ref.read(mainChannelProvider.notifier).load(refresh: true),
        ),
      MainChannelState(posts: []) => const Text('Non ci sono ancora post.', style: LanternaText.caption),
      _ => null,
    };

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.pixels >= n.metrics.maxScrollExtent - 200 && state.hasMore && state.posts.isNotEmpty) {
                ref.read(mainChannelProvider.notifier).load();
              }
              return false;
            },
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(_gutter, 20, _gutter, 32),
              itemCount: placeholder != null ? 2 : 1 + state.posts.length + (state.hasMore ? 1 : 0),
              itemBuilder: (context, i) {
                if (i == 0) return header;
                if (placeholder != null) return placeholder;
                final index = i - 1;
                if (index == state.posts.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return _TimelinePost(
                  post: state.posts[index],
                  latest: index == 0,
                  groupStartedAt: user?.groupStartedAt,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Day ring, journey name and "Giorno N di D", in place of an app bar.
class _JourneyHeader extends StatelessWidget {
  final User? user;
  const _JourneyHeader({required this.user});

  @override
  Widget build(BuildContext context) {
    final startedAt = user?.groupStartedAt;
    final duration = user?.groupDurationDays ?? 365;
    if (startedAt == null) {
      return Semantics(header: true, child: Text(AppConstants.appName, style: Theme.of(context).textTheme.titleLarge));
    }
    final day = journeyDay(startedAt, DateTime.now()).clamp(1, duration);
    return Row(
      children: [
        ExcludeSemantics(child: DayRing(day: day, duration: duration)),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(AppConstants.appName, style: LanternaText.caption),
              const SizedBox(height: 2),
              Semantics(
                header: true,
                child: Text('Giorno $day di $duration', style: Theme.of(context).textTheme.titleLarge),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The amber way into the circle, shown while it is open.
class _CircleEntry extends StatelessWidget {
  final CircleStatus circle;
  final bool busy;
  final VoidCallback onTap;

  const _CircleEntry({required this.circle, required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final closesAt = circle.closesAt;
    final subtitle = closesAt == null ? 'Entra' : 'Entra · fino alle ${DateFormat('H:mm').format(closesAt.toLocal())}';
    return Material(
      color: LanternaColors.accent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: busy ? null : onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: [
                const CircleDots(size: 30, filledColor: LanternaColors.onAccent),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Il cerchio è aperto',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: LanternaColors.onAccent),
                      ),
                      const SizedBox(height: 2),
                      Text(subtitle, style: const TextStyle(fontSize: 13, color: LanternaColors.onAccent)),
                    ],
                  ),
                ),
                if (busy)
                  const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: LanternaColors.onAccent),
                  )
                else
                  const Icon(Icons.arrow_forward, color: LanternaColors.onAccent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A Main Channel post on the timeline. No author: participants do not see it.
class _TimelinePost extends StatelessWidget {
  final MainChannelPost post;
  final bool latest;
  final DateTime? groupStartedAt;

  const _TimelinePost({required this.post, required this.latest, required this.groupStartedAt});

  String _when(DateTime date) {
    final now = DateTime.now();
    final local = date.toLocal();
    final daysAgo = journeyDay(local, now) - 1;
    final day = switch (daysAgo) {
      0 => 'Oggi',
      1 => 'Ieri',
      _ => DateFormat(local.year == now.year ? 'd MMMM' : 'd MMMM y').format(local),
    };
    final label = '$day, ${DateFormat('H:mm').format(local)}';
    final start = groupStartedAt;
    if (start == null) return label;
    final journey = journeyDay(start, local);
    return journey >= 1 ? '$label · giorno $journey' : label;
  }

  @override
  Widget build(BuildContext context) {
    const dot = 11.0;
    return Stack(
      children: [
        // The timeline, through the dot.
        Positioned(
          left: dot / 2 - 0.5,
          top: 0,
          bottom: 0,
          child: Container(width: 1, color: LanternaColors.line),
        ),
        Positioned(
          left: 0,
          top: 3,
          child: Container(
            width: dot,
            height: dot,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: latest ? LanternaColors.accent : LanternaColors.background,
              border: latest ? null : Border.all(color: LanternaColors.muted, width: 1.5),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 28, bottom: 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_when(post.publishedAt ?? post.createdAt), style: LanternaText.caption),
              const SizedBox(height: 6),
              LinkText(post.content, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}
