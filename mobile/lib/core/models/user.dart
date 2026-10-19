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
  });

  bool get isAdmin => role == 'admin' || role == 'super_admin';
  bool get isSuperAdmin => role == 'super_admin';
  bool get isActive => status == 'active';
  bool get isSuspended => status == 'suspended';
  bool get isBanned => status == 'banned';

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
      );
}
