class ConfirmationRequest {
  final String id;
  final String userId;
  final DateTime dueAt;
  final String status;

  const ConfirmationRequest({
    required this.id,
    required this.userId,
    required this.dueAt,
    required this.status,
  });

  bool get isPending => status == 'pending';

  factory ConfirmationRequest.fromJson(Map<String, dynamic> json) => ConfirmationRequest(
        id: json['id'] as String,
        userId: json['userId'] as String,
        dueAt: DateTime.parse(json['dueAt'] as String),
        status: json['status'] as String,
      );
}
