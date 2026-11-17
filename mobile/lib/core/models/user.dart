class User {
  final String id;
  final String name;
  final String surname;
  final String? email;
  final String role;
  final String status;
  final bool reviewedByAdmin;
  final String? motivation;
  final DateTime? lastConfirmedAt;
  final DateTime? createdAt;

  /// The user's group. Only the admin list (/api/users) and /api/users/me say it:
  /// elsewhere it is null even for a group member.
  final String? groupId;

  /// When the user's group ended. Only the session user has it.
  final DateTime? groupEndedAt;

  /// When the user's group started, and how many days its journey lasts. Only
  /// the session user has them; the home shows "Giorno N di D" with them.
  final DateTime? groupStartedAt;
  final int? groupDurationDays;

  const User({
    required this.id,
    required this.name,
    required this.surname,
    this.email,
    required this.role,
    required this.status,
    this.reviewedByAdmin = false,
    this.motivation,
    this.lastConfirmedAt,
    this.createdAt,
    this.groupId,
    this.groupEndedAt,
    this.groupStartedAt,
    this.groupDurationDays,
  });

  User copyWith({String? status, bool? reviewedByAdmin, DateTime? lastConfirmedAt}) => User(
        id: id,
        name: name,
        surname: surname,
        email: email,
        role: role,
        status: status ?? this.status,
        reviewedByAdmin: reviewedByAdmin ?? this.reviewedByAdmin,
        motivation: motivation,
        lastConfirmedAt: lastConfirmedAt ?? this.lastConfirmedAt,
        createdAt: createdAt,
        groupId: groupId,
        groupEndedAt: groupEndedAt,
        groupStartedAt: groupStartedAt,
        groupDurationDays: groupDurationDays,
      );

  bool get isAdmin => role == 'admin' || role == 'super_admin';
  bool get isSuperAdmin => role == 'super_admin';
  bool get isActive => status == 'active';
  bool get isSuspended => status == 'suspended';
  bool get isBanned => status == 'banned';

  /// Not in an active group: the app shows only the waiting screen. Only for
  /// the session user, whose group is always known.
  bool get isWaiting => groupId == null || (groupEndedAt != null && !groupEndedAt!.isAfter(DateTime.now()));

  String get roleLabel => switch (role) {
        'super_admin' => 'Super Admin',
        'admin' => 'Admin',
        'user' => 'Utente',
        _ => role,
      };

  String get statusLabel => switch (status) {
        'active' => 'Attivo',
        'suspended' => 'Sospeso',
        'banned' => 'Bannato',
        _ => status,
      };

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as String,
        name: json['name'] as String,
        surname: json['surname'] as String,
        email: json['email'] as String?,
        role: json['role'] as String,
        status: json['status'] as String,
        reviewedByAdmin: json['reviewedByAdmin'] as bool? ?? false,
        motivation: json['motivation'] as String?,
        lastConfirmedAt: json['lastConfirmedAt'] != null
            ? DateTime.parse(json['lastConfirmedAt'] as String)
            : null,
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'] as String)
            : null,
        // The admin list sends groupId, /api/users/me the whole group.
        groupId: json['groupId'] as String? ?? (json['group'] as Map<String, dynamic>?)?['id'] as String?,
        groupEndedAt: switch ((json['group'] as Map<String, dynamic>?)?['endedAt']) {
          final String date => DateTime.parse(date),
          _ => null,
        },
        groupStartedAt: switch ((json['group'] as Map<String, dynamic>?)?['startedAt']) {
          final String date => DateTime.parse(date),
          _ => null,
        },
        groupDurationDays: (json['group'] as Map<String, dynamic>?)?['durationDays'] as int?,
      );
}
