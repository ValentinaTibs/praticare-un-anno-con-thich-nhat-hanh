import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/models/main_channel_post.dart';
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
  int _page = 1;

  MainChannelNotifier(this._api) : super(const MainChannelState()) {
    load();
  }

  Future<void> load({bool refresh = false}) async {
    if (refresh) _page = 1;
    if (state.loading) return;
    state = state.copyWith(loading: true);
    try {
      final data = await _api.get('/api/main-channel/posts', query: {'page': '$_page', 'limit': '20'});
      if (!mounted) return;
      final d = data as Map<String, dynamic>;
      final incoming = (d['posts'] as List).map((e) => MainChannelPost.fromJson(e as Map<String, dynamic>)).toList();
      final posts = refresh ? incoming : [...state.posts, ...incoming];
      final total = d['total'] as int;
      state = state.copyWith(posts: posts, loading: false, hasMore: posts.length < total);
      _page++;
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

}

// The backend sends no live updates: the posts are read again each time the screen opens,
// when the app comes back to the foreground, and on pull to refresh.
final mainChannelProvider = StateNotifierProvider.autoDispose<MainChannelNotifier, MainChannelState>((ref) {
  return MainChannelNotifier(ref.watch(apiClientProvider));
});
