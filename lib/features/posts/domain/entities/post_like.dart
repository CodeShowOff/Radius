import 'package:equatable/equatable.dart';

/// Domain entity representing a like on a post.
class PostLike extends Equatable {
  final String postId;
  final String userId;
  final String userName;
  final String? userPhotoUrl;
  final DateTime createdAt;

  const PostLike({
    required this.postId,
    required this.userId,
    required this.userName,
    this.userPhotoUrl,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [postId, userId, userName, userPhotoUrl, createdAt];
}
