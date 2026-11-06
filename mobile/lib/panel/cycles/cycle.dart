import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/panel_auth_notifier.dart';

const defaultDurationDays = 365;
const maxDurationDays = 3650;

/// A registration cycle as the Super Admin manages it from the panel.
class PanelCycle {
  final String id;
  final bool isOpen;
  final DateTime startsAt;
  final int durationDays;

  /// Who asked to join and is active; what counts until the journey starts.
  final int requesters;

  /// Members of the group; what counts once the journey has started.
  final int participants;

  /// Cycles migrated from before closing dates were required may have none.
  final DateTime? scheduledClosedAt;
  final DateTime? closedAt;

  const PanelCycle({
    required this.id,
    required this.isOpen,
    required this.startsAt,
    required this.durationDays,
    this.requesters = 0,
    this.participants = 0,
    this.scheduledClosedAt,
    this.closedAt,
  });

  /// Once the journey has started nothing can be changed.
  bool get hasStarted => !startsAt.isAfter(DateTime.now());

  factory PanelCycle.fromJson(Map<String, dynamic> json) => PanelCycle(
        id: json['id'] as String,
        isOpen: json['status'] == 'open',
        startsAt: DateTime.parse(json['startsAt'] as String),
        durationDays: json['durationDays'] as int,
        requesters: json['requesters'] as int? ?? 0,
        participants: json['participants'] as int? ?? 0,
        scheduledClosedAt: _date(json['scheduledClosedAt']),
        closedAt: _date(json['closedAt']),
      );

  static DateTime? _date(Object? value) => value == null ? null : DateTime.parse(value as String);
}

/// Every cycle, latest start first.
final cyclesProvider = FutureProvider.autoDispose<List<PanelCycle>>((ref) async {
  final data = await ref.watch(panelApiClientProvider).get('/api/cycles') as List<dynamic>;
  return [for (final c in data) PanelCycle.fromJson(c as Map<String, dynamic>)];
});
