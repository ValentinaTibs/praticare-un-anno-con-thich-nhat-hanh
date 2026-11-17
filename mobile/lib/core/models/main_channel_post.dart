// A post of the user's group Main Channel. Plain text with links, and no author:
// participants never see who wrote it.
class MainChannelPost {
  final String id;
  final String content;
  final DateTime publishedAt;

  const MainChannelPost({required this.id, required this.content, required this.publishedAt});

  factory MainChannelPost.fromJson(Map<String, dynamic> json) => MainChannelPost(
        id: json['id'] as String,
        content: json['content'] as String,
        publishedAt: DateTime.parse(json['publishedAt'] as String),
      );
}
