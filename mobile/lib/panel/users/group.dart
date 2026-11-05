import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/panel_auth_notifier.dart';
import '../format.dart';

/// A group as the admin panel lists it. Groups have no name: the panel calls
/// them by their start date.
class PanelGroup {
  final String id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int memberCount;

  const PanelGroup({required this.id, required this.startedAt, this.endedAt, this.memberCount = 0});

  /// Ended groups are archived. Until groups end automatically (#82) none is.
  bool get isArchived => endedAt != null && !endedAt!.isAfter(DateTime.now());

  String get label => 'Gruppo iniziato il ${formatDate(startedAt)}';

  String get membersLabel => memberCount == 1 ? '1 membro' : '$memberCount membri';

  factory PanelGroup.fromJson(Map<String, dynamic> json) => PanelGroup(
        id: json['id'] as String,
        startedAt: DateTime.parse(json['startedAt'] as String),
        endedAt: json['endedAt'] != null ? DateTime.parse(json['endedAt'] as String) : null,
        memberCount: json['memberCount'] as int? ?? 0,
      );
}

/// Every group, newest first, with its member count.
final groupsProvider = FutureProvider.autoDispose<List<PanelGroup>>((ref) async {
  final data = await ref.watch(panelApiClientProvider).get('/api/groups') as List<dynamic>;
  return [for (final g in data) PanelGroup.fromJson(g as Map<String, dynamic>)];
});
