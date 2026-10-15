import 'main_channel_post.dart';

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
