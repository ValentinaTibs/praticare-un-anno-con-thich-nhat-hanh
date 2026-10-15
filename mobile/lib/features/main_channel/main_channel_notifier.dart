import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/models/main_channel_post.dart';
import '../../core/services/socket_service.dart';
import '../auth/auth_notifier.dart';

class MainChannelState {
  final List<MainChannelPost> posts;
  final bool loading;
  final bool hasMore;
  final String? error;

  const MainChannelState({
    this.posts = const [],
    this.loading = false,
    this.hasMore = true,
    this.error,
  });

  MainChannelState copyWith({List<MainChannelPost>? posts, bool? loading, bool? hasMore, String? error}) =>
      MainChannelState(
        posts: posts ?? this.posts,
        loading: loading ?? this.loading,
        hasMore: hasMore ?? this.hasMore,
        error: error,
      );
}

class MainChannelNotifier extends StateNotifier<MainChannelState> {
  final ApiClient _api;
  final SocketService _socket;
  StreamSubscription? _sub;
  int _page = 1;

  MainChannelNotifier(this._api, this._socket) : super(const MainChannelState()) {
    _sub = _socket.onNewMainPost.listen(_onNewPost);
    load();
  }

  Future<void> load({bool refresh = false}) async {
    if (refresh) _page = 1;
    if (state.loading) return;
    state = state.copyWith(loading: true);
    try {
      final data = await _api.get('/api/main-channel/posts', query: {'page': '$_page', 'limit': '20'});
      final d = data as Map<String, dynamic>;
      final incoming = (d['posts'] as List).map((e) => MainChannelPost.fromJson(e as Map<String, dynamic>)).toList();
      final posts = refresh ? incoming : [...state.posts, ...incoming];
      final total = d['total'] as int;
      state = state.copyWith(posts: posts, loading: false, hasMore: posts.length < total);
      _page++;
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  void _onNewPost(MainChannelPost post) {
    // Prepend new real-time post if not already present
    if (state.posts.any((p) => p.id == post.id)) return;
    state = state.copyWith(posts: [post, ...state.posts]);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final mainChannelProvider = StateNotifierProvider<MainChannelNotifier, MainChannelState>((ref) {
  return MainChannelNotifier(ref.watch(apiClientProvider), ref.watch(socketServiceProvider));
});
