import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/models/sharing_channel_post.dart';
import '../auth/auth_notifier.dart';

enum SharingChannelPhase { closed, openNotJoined, joined }

class SharingChannelState {
  final SharingChannelPhase phase;
  final String? channelId;
  final DateTime? scheduledClosedAt;
  final List<SharingChannelPost> posts;
  final bool closingSoon;
  final int? minutesRemaining;
  final bool loading;
  final String? error;

  const SharingChannelState({
    this.phase = SharingChannelPhase.closed,
    this.channelId,
    this.scheduledClosedAt,
    this.posts = const [],
    this.closingSoon = false,
    this.minutesRemaining,
    this.loading = false,
    this.error,
  });

  SharingChannelState copyWith({
    SharingChannelPhase? phase,
    String? channelId,
    DateTime? scheduledClosedAt,
    List<SharingChannelPost>? posts,
    bool? closingSoon,
    int? minutesRemaining,
    bool? loading,
    String? error,
  }) =>
      SharingChannelState(
        phase: phase ?? this.phase,
        channelId: channelId ?? this.channelId,
        scheduledClosedAt: scheduledClosedAt ?? this.scheduledClosedAt,
        posts: posts ?? this.posts,
        closingSoon: closingSoon ?? this.closingSoon,
        minutesRemaining: minutesRemaining ?? this.minutesRemaining,
        loading: loading ?? this.loading,
        error: error,
      );
}

class SharingChannelNotifier extends StateNotifier<SharingChannelState> {
  /// How often the screen reloads the circle: the backend sends no live updates.
  static const refreshInterval = Duration(seconds: 10);

  /// How long before closing the screen warns, as the backend's push does.
  static const closingWarning = Duration(minutes: 15);

  final ApiClient _api;
  late final Timer _refresh;

  SharingChannelNotifier(this._api) : super(const SharingChannelState()) {
    _fetchStatus();
    // Opening, closing, other members' messages and deletions show up here.
    _refresh = Timer.periodic(refreshInterval, (_) => _fetchStatus());
  }

  Future<void> _fetchStatus() async {
    try {
      final data = await _api.get('/api/sharing-channel/status');
      if (!mounted) return;
      final d = data as Map<String, dynamic>;
      if (d['status'] == 'closed') {
        state = const SharingChannelState(phase: SharingChannelPhase.closed);
        return;
      }
      final joined = d['joined'] as bool;
      final closeTime = d['scheduledClosedAt'] != null
          ? DateTime.parse(d['scheduledClosedAt'] as String)
          : null;
      final remaining = closeTime?.difference(DateTime.now());
      final closingSoon = remaining != null && remaining <= closingWarning;
      state = state.copyWith(
        phase: joined ? SharingChannelPhase.joined : SharingChannelPhase.openNotJoined,
        channelId: d['channelId'] as String,
        scheduledClosedAt: closeTime,
        closingSoon: closingSoon,
        minutesRemaining: closingSoon ? (remaining.inSeconds / 60).ceil().clamp(1, closingWarning.inMinutes) : null,
      );
      if (joined) await _loadHistory();
    } catch (_) {}
  }

  Future<void> _loadHistory() async {
    final data = await _api.get('/api/sharing-channel/posts');
    final posts = (data as List)
        .map((e) => SharingChannelPost.fromJson(e as Map<String, dynamic>))
        .toList();
    if (!mounted) return;
    state = state.copyWith(posts: posts);
  }

  Future<void> join() async {
    state = state.copyWith(loading: true);
    try {
      final data = await _api.post('/api/sharing-channel/join');
      final d = data as Map<String, dynamic>;
      final history = (d['history'] as List)
          .map((e) => SharingChannelPost.fromJson(e as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      state = state.copyWith(
        phase: SharingChannelPhase.joined,
        posts: history,
        loading: false,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  /// The sent message shows up at once, from the backend's answer.
  Future<void> sendPost(String content) async {
    final data = await _api.post('/api/sharing-channel/posts', data: {'content': content});
    if (!mounted || state.phase != SharingChannelPhase.joined) return;
    final post = SharingChannelPost.fromJson(data as Map<String, dynamic>);
    if (state.posts.any((p) => p.id == post.id)) return;
    state = state.copyWith(posts: [...state.posts, post]);
  }

  @override
  void dispose() {
    _refresh.cancel();
    super.dispose();
  }
}

// Disposed when the screen closes, so the circle is reloaded only while someone looks at it.
final sharingChannelProvider =
    StateNotifierProvider.autoDispose<SharingChannelNotifier, SharingChannelState>((ref) {
  return SharingChannelNotifier(ref.watch(apiClientProvider));
});
