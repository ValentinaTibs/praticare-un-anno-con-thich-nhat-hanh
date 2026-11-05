import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/models/user.dart';
import '../auth/panel_auth_notifier.dart';
import 'group.dart';
import 'user_actions.dart';

const usersPageSize = 50;

const _keep = Object();

/// Filters of the users list, sent to GET /api/users.
class UserFilters {
  /// Matches name, surname or email.
  final String search;
  final String? groupId;

  /// 'active', 'suspended' or 'banned'; null for every status.
  final String? status;
  final bool onlyToReview;

  const UserFilters({this.search = '', this.groupId, this.status, this.onlyToReview = false});

  UserFilters copyWith({String? search, Object? groupId = _keep, Object? status = _keep, bool? onlyToReview}) =>
      UserFilters(
        search: search ?? this.search,
        groupId: identical(groupId, _keep) ? this.groupId : groupId as String?,
        status: identical(status, _keep) ? this.status : status as String?,
        onlyToReview: onlyToReview ?? this.onlyToReview,
      );

  Map<String, dynamic> toQuery(int page) => {
        'page': '$page',
        'limit': '$usersPageSize',
        if (search.trim().isNotEmpty) 'q': search.trim(),
        if (groupId != null) 'groupId': groupId,
        if (status != null) 'status': status,
        if (onlyToReview) 'reviewed': 'false',
      };
}

class UsersState {
  final UserFilters filters;
  final List<User> users;

  /// Users matching the filters, across all pages.
  final int total;
  final int page;
  final bool loading;
  final String? error;

  const UsersState({
    this.filters = const UserFilters(),
    this.users = const [],
    this.total = 0,
    this.page = 1,
    this.loading = false,
    this.error,
  });

  int get pageCount => total == 0 ? 1 : (total + usersPageSize - 1) ~/ usersPageSize;
}

/// The users list of the panel: filters, current page and the admin actions,
/// each followed by a reload so the list shows the backend's state.
class UsersNotifier extends StateNotifier<UsersState> {
  final ApiClient _api;
  final void Function() _onUsersChanged;

  /// Only the answer to the latest request is shown: filters may change
  /// faster than the backend answers.
  int _latestRequest = 0;

  UsersNotifier(this._api, {void Function()? onUsersChanged})
      : _onUsersChanged = onUsersChanged ?? (() {}),
        super(const UsersState(loading: true)) {
    load();
  }

  Future<void> load({int page = 1}) async {
    final request = ++_latestRequest;
    final filters = state.filters;
    state = UsersState(filters: filters, users: state.users, total: state.total, page: state.page, loading: true);
    try {
      final data = await _api.get('/api/users', query: filters.toQuery(page)) as Map<String, dynamic>;
      if (!mounted || request != _latestRequest) return;
      final users = [for (final u in data['users'] as List<dynamic>) User.fromJson(u as Map<String, dynamic>)];
      final total = data['total'] as int;
      state = UsersState(filters: filters, users: users, total: total, page: page);
      // E.g. the last user of the last page was just removed.
      if (users.isEmpty && page > 1 && total > 0) await load(page: state.pageCount);
    } catch (e) {
      if (!mounted || request != _latestRequest) return;
      state = UsersState(
        filters: filters,
        page: page,
        error: e is ApiException ? e.message : 'Impossibile caricare gli utenti.',
      );
    }
  }

  Future<void> retry() => load(page: state.page);

  Future<void> goToPage(int page) => load(page: page);

  Future<void> setSearch(String search) => _filter(state.filters.copyWith(search: search));

  Future<void> setGroup(String? groupId) => _filter(state.filters.copyWith(groupId: groupId));

  Future<void> setStatus(String? status) => _filter(state.filters.copyWith(status: status));

  Future<void> setOnlyToReview(bool value) => _filter(state.filters.copyWith(onlyToReview: value));

  /// Every member of the group, whatever the other filters said.
  Future<void> showGroup(String groupId) => _filter(UserFilters(groupId: groupId));

  Future<void> _filter(UserFilters filters) {
    state = UsersState(filters: filters, users: state.users, total: state.total, page: state.page, loading: true);
    return load();
  }

  /// Runs [action] on [user], then reloads the list, whether it succeeded or
  /// not (e.g. someone else already removed the user). Throws on failure.
  Future<void> act(UserAction action, User user) async {
    try {
      await action.run(_api, user.id);
    } finally {
      if (mounted) {
        _onUsersChanged();
        await load(page: state.page);
      }
    }
  }
}

final usersProvider = StateNotifierProvider.autoDispose<UsersNotifier, UsersState>((ref) => UsersNotifier(
      ref.watch(panelApiClientProvider),
      // Member counts change when someone is removed.
      onUsersChanged: () => ref.invalidate(groupsProvider),
    ));
