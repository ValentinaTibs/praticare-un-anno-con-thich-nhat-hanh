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

  /// The user's group; null while waiting for the next path.
  final String? groupId;

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
  });

  bool get isWaiting => groupId == null;

  bool get isAdmin => role == 'admin' || role == 'super_admin';
  bool get isSuperAdmin => role == 'super_admin';
  bool get isActive => status == 'active';
  bool get isSuspended => status == 'suspended';
  bool get isBanned => status == 'banned';

  String get roleLabel => switch (role) {
        'super_admin' => 'Super admin',
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
      );
}
