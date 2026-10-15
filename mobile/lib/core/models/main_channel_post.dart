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

class MainChannelPost {
  final String id;
  final PostAuthor? author;
  final String content;
  final String? mediaUrl;
  final DateTime? publishedAt;
  final DateTime createdAt;

  const MainChannelPost({
    required this.id,
    this.author,
    required this.content,
    this.mediaUrl,
    this.publishedAt,
    required this.createdAt,
  });

  factory MainChannelPost.fromJson(Map<String, dynamic> json) => MainChannelPost(
        id: json['id'] as String,
        author: json['author'] != null
            ? PostAuthor.fromJson(json['author'] as Map<String, dynamic>)
            : null,
        content: json['content'] as String,
        mediaUrl: json['mediaUrl'] as String?,
        publishedAt: json['publishedAt'] != null
            ? DateTime.parse(json['publishedAt'] as String)
            : null,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
