import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../auth/auth_notifier.dart';

/// What the waiting screen shows, from GET /api/cycles/next.
class NextJourney {
  /// When the journey starts; null when none is planned.
  final DateTime? startsAt;

  /// Requests are being taken for this journey.
  final bool open;
  final int requesters;

  /// The user has a request in progress for this journey.
  final bool requested;

  /// False with an open cycle too, for who was removed from it by an admin.
  final bool canRequest;

  const NextJourney({
    this.startsAt,
    this.open = false,
    this.requesters = 0,
    this.requested = false,
    this.canRequest = false,
  });

  factory NextJourney.fromJson(Map<String, dynamic> json) {
    final cycle = json['cycle'] as Map<String, dynamic>?;
    return NextJourney(
      startsAt: cycle == null ? null : DateTime.parse(cycle['startsAt'] as String),
      open: cycle?['open'] as bool? ?? false,
      requesters: json['requesters'] as int,
      requested: json['requested'] as bool,
      canRequest: json['canRequest'] as bool,
    );
  }
}

final nextJourneyProvider = FutureProvider.autoDispose<NextJourney>((ref) async {
  final api = ref.watch(apiClientProvider);
  try {
    return NextJourney.fromJson(await api.get('/api/cycles/next') as Map<String, dynamic>);
  } on ApiException catch (e) {
    // Already in a group: the session is out of date, and reading it again leaves this screen.
    if (e.statusCode == 403) await ref.read(authProvider.notifier).refreshUser();
    rethrow;
  }
});
