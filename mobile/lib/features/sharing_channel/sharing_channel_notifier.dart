import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/models/sharing_channel_post.dart';
import '../../core/services/socket_service.dart';
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
  final ApiClient _api;
  final SocketService _socket;
  final List<StreamSubscription> _subs = [];

  SharingChannelNotifier(this._api, this._socket) : super(const SharingChannelState()) {
    _subs.addAll([
      _socket.onSharingOpened.listen(_onOpened),
      _socket.onSharingClosed.listen(_onClosed),
      _socket.onSharingNewPost.listen(_onNewPost),
      _socket.onSharingPostDeleted.listen(_onPostDeleted),
      _socket.onSharingClosingSoon.listen(_onClosingSoon),
    ]);
    _fetchStatus();
  }

  Future<void> _fetchStatus() async {
    try {
      final data = await _api.get('/api/sharing-channel/status');
      final d = data as Map<String, dynamic>;
      if (d['status'] == 'closed') {
        state = const SharingChannelState(phase: SharingChannelPhase.closed);
        return;
      }
      final joined = d['joined'] as bool;
      final closeTime = d['scheduledClosedAt'] != null
          ? DateTime.parse(d['scheduledClosedAt'] as String)
          : null;
      state = state.copyWith(
        phase: joined ? SharingChannelPhase.joined : SharingChannelPhase.openNotJoined,
        channelId: d['channelId'] as String,
        scheduledClosedAt: closeTime,
      );
      if (joined) await _loadHistory(d['channelId'] as String);
    } catch (_) {}
  }

  Future<void> _loadHistory(String channelId) async {
    final data = await _api.get('/api/sharing-channel/posts');
    final posts = (data as List)
        .map((e) => SharingChannelPost.fromJson(e as Map<String, dynamic>))
        .toList();
    state = state.copyWith(posts: posts);
    _socket.subscribeToSharingChannel(channelId);
  }

  Future<void> join() async {
    state = state.copyWith(loading: true);
    try {
      final data = await _api.post('/api/sharing-channel/join');
      final d = data as Map<String, dynamic>;
      final history = (d['history'] as List)
          .map((e) => SharingChannelPost.fromJson(e as Map<String, dynamic>))
          .toList();
      state = state.copyWith(
        phase: SharingChannelPhase.joined,
        posts: history,
        loading: false,
      );
      if (state.channelId != null) _socket.subscribeToSharingChannel(state.channelId!);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> sendPost(String content) async {
    await _api.post('/api/sharing-channel/posts', data: {'content': content});
    // Post will arrive via socket
  }

  void _onOpened(SharingChannelStatus status) {
    state = state.copyWith(
      phase: SharingChannelPhase.openNotJoined,
      channelId: status.channelId,
      scheduledClosedAt: status.scheduledClosedAt,
      posts: [],
    );
  }

  void _onClosed(String channelId) {
    state = const SharingChannelState(phase: SharingChannelPhase.closed);
  }

  void _onNewPost(SharingChannelPost post) {
    if (state.phase != SharingChannelPhase.joined) return;
    if (state.posts.any((p) => p.id == post.id)) return;
    state = state.copyWith(posts: [...state.posts, post]);
  }

  void _onPostDeleted(String postId) {
    state = state.copyWith(posts: state.posts.where((p) => p.id != postId).toList());
  }

  void _onClosingSoon(SharingChannelStatus status) {
    state = state.copyWith(closingSoon: true, minutesRemaining: status.minutesRemaining);
  }

  @override
  void dispose() {
    for (final s in _subs) s.cancel();
    super.dispose();
  }
}

final sharingChannelProvider =
    StateNotifierProvider<SharingChannelNotifier, SharingChannelState>((ref) {
  return SharingChannelNotifier(ref.watch(apiClientProvider), ref.watch(socketServiceProvider));
});
