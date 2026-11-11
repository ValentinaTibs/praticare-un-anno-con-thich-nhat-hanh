import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../auth/panel_auth_notifier.dart';

/// Italian names of the days of the week, ISO order: Monday is day 1.
const weekdayNames = ['lunedì', 'martedì', 'mercoledì', 'giovedì', 'venerdì', 'sabato', 'domenica'];

/// The single weekly appointment shared by every group's circle, in Italian time.
class CircleSchedule {
  /// ISO day of the week: 1 = Monday … 7 = Sunday.
  final int dayOfWeek;

  /// HH:MM in Italian time.
  final String startTime;
  final int durationMinutes;

  const CircleSchedule({required this.dayOfWeek, required this.startTime, required this.durationMinutes});

  factory CircleSchedule.fromJson(Map<String, dynamic> json) => CircleSchedule(
        dayOfWeek: json['dayOfWeek'] as int,
        startTime: json['startTime'] as String,
        durationMinutes: json['durationMinutes'] as int,
      );

  Map<String, dynamic> toJson() => {'dayOfWeek': dayOfWeek, 'startTime': startTime, 'durationMinutes': durationMinutes};

  String get description => 'Ogni ${weekdayNames[dayOfWeek - 1]} alle $startTime, per $durationMinutes minuti';
}

/// A group's circle while it is open, as the open circles list shows it.
class OpenCircle {
  final String id;
  final DateTime groupStartedAt;
  final DateTime scheduledClosedAt;
  final int memberCount;
  final int postCount;

  const OpenCircle({
    required this.id,
    required this.groupStartedAt,
    required this.scheduledClosedAt,
    required this.memberCount,
    required this.postCount,
  });

  factory OpenCircle.fromJson(Map<String, dynamic> json) => OpenCircle(
        id: json['id'] as String,
        groupStartedAt: DateTime.parse((json['group'] as Map<String, dynamic>)['startedAt'] as String),
        scheduledClosedAt: DateTime.parse(json['scheduledClosedAt'] as String),
        memberCount: json['memberCount'] as int,
        postCount: json['postCount'] as int,
      );
}

/// The open circles of every group.
final openCirclesProvider = FutureProvider.autoDispose<List<OpenCircle>>((ref) async {
  final data = await ref.watch(panelApiClientProvider).get('/api/sharing-channel/channels') as List<dynamic>;
  return [for (final c in data) OpenCircle.fromJson(c as Map<String, dynamic>)];
});

/// A message written in a circle.
class CircleMessage {
  final String id;
  final String author;
  final String content;
  final DateTime createdAt;

  const CircleMessage({required this.id, required this.author, required this.content, required this.createdAt});
}

/// Who is in an open circle and what they wrote, read by an admin without joining.
class CircleDetail {
  final List<String> members;
  final List<CircleMessage> messages;

  const CircleDetail({required this.members, required this.messages});

  static String _fullName(Object? person) {
    final p = person as Map<String, dynamic>;
    return '${p['name']} ${p['surname']}';
  }

  factory CircleDetail.fromJson(Map<String, dynamic> json) => CircleDetail(
        members: [for (final m in json['members'] as List<dynamic>) _fullName((m as Map<String, dynamic>)['user'])],
        messages: [
          for (final p in (json['posts'] as List<dynamic>).cast<Map<String, dynamic>>())
            CircleMessage(
              id: p['id'] as String,
              author: _fullName(p['author']),
              content: p['content'] as String,
              createdAt: DateTime.parse(p['createdAt'] as String),
            ),
        ],
      );
}

/// Members and messages of the open circle with this id.
final circleDetailProvider = FutureProvider.autoDispose.family<CircleDetail, String>((ref, id) async {
  final data = await ref.watch(panelApiClientProvider).get('/api/sharing-channel/channels/$id');
  return CircleDetail.fromJson(data as Map<String, dynamic>);
});

/// The weekly appointment, or null while none has been set.
final circleScheduleProvider = FutureProvider.autoDispose<CircleSchedule?>((ref) async {
  try {
    final data = await ref.watch(panelApiClientProvider).get('/api/sharing-channel/schedule');
    return CircleSchedule.fromJson(data as Map<String, dynamic>);
  } on ApiException catch (e) {
    if (e.statusCode == 404) return null;
    rethrow;
  }
});
