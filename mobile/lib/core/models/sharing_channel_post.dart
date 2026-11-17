class PostAuthor {
  final String id;
  final String name;
  final String surname;

  const PostAuthor({required this.id, required this.name, required this.surname});

  factory PostAuthor.fromJson(Map<String, dynamic> json) => PostAuthor(
        id: json['id'] as String,
        name: json['name'] as String,
        surname: json['surname'] as String,
      );

  String get fullName => '$name $surname';
}

class SharingChannelPost {
  final String id;
  final String sharingChannelId;
  final PostAuthor author;
  final String content;
  final String? mediaUrl;
  final DateTime createdAt;

  const SharingChannelPost({
    required this.id,
    required this.sharingChannelId,
    required this.author,
    required this.content,
    this.mediaUrl,
    required this.createdAt,
  });

  factory SharingChannelPost.fromJson(Map<String, dynamic> json) => SharingChannelPost(
        id: json['id'] as String,
        sharingChannelId: json['sharingChannelId'] as String,
        author: PostAuthor.fromJson(json['author'] as Map<String, dynamic>),
        content: json['content'] as String,
        mediaUrl: json['mediaUrl'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
