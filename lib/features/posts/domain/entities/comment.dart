import 'package:equatable/equatable.dart';

/// Domain entity representing a comment on a post.
class Comment extends Equatable {
  final String id;
  final String postId;
  final String authorId;
  final String authorName;
  final String? authorPhotoUrl;
  final String text;
  final DateTime createdAt;

  const Comment({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.authorName,
    this.authorPhotoUrl,
    required this.text,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [
        id,
        postId,
        authorId,
        authorName,
        authorPhotoUrl,
        text,
        createdAt,
      ];
}
