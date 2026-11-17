import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_notifier.dart';

/// Whether the group's circle is open, for the entry on the home. Read once,
/// unlike the circle screen, which reloads it every few seconds.
class CircleStatus {
  final bool open;
  final bool joined;
  final DateTime? closesAt;

  const CircleStatus({this.open = false, this.joined = false, this.closesAt});

  factory CircleStatus.fromJson(Map<String, dynamic> json) => CircleStatus(
        open: json['status'] == 'open',
        joined: json['joined'] as bool? ?? false,
        closesAt: switch (json['scheduledClosedAt']) {
          final String date => DateTime.parse(date),
          _ => null,
        },
      );
}

final circleStatusProvider = FutureProvider.autoDispose<CircleStatus>((ref) async {
  final data = await ref.watch(apiClientProvider).get('/api/sharing-channel/status');
  return CircleStatus.fromJson(data as Map<String, dynamic>);
});
