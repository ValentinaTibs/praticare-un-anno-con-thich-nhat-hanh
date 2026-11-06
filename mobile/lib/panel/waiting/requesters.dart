import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/user.dart';
import '../auth/panel_auth_notifier.dart';

/// A journey not started yet, with who asked to join it.
class RequestedJourney {
  final DateTime startsAt;
  final bool open;
  final DateTime? scheduledClosedAt;
  final List<User> requesters;

  const RequestedJourney({
    required this.startsAt,
    required this.open,
    required this.requesters,
    this.scheduledClosedAt,
  });

  int get toReview => requesters.where((u) => !u.reviewedByAdmin).length;

  factory RequestedJourney.fromJson(Map<String, dynamic> json) => RequestedJourney(
        startsAt: DateTime.parse(json['startsAt'] as String),
        open: json['status'] == 'open',
        scheduledClosedAt: json['scheduledClosedAt'] == null ? null : DateTime.parse(json['scheduledClosedAt'] as String),
        requesters: [for (final r in json['requests'] as List<dynamic>) User.fromJson(r as Map<String, dynamic>)],
      );
}

/// Journeys not started yet, soonest first; who needs a review comes first in each.
final requestedJourneysProvider = FutureProvider.autoDispose<List<RequestedJourney>>((ref) async {
  final data = await ref.watch(panelApiClientProvider).get('/api/cycles/requests') as List<dynamic>;
  return [for (final c in data) RequestedJourney.fromJson(c as Map<String, dynamic>)];
});
