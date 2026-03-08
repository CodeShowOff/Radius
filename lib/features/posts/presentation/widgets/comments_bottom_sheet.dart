import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/widgets/cached_avatar.dart';
import '../../domain/entities/comment.dart';
import '../bloc/post_interaction_cubit.dart';

/// Instagram-style comments bottom sheet.
///
/// Shows a scrollable list of comments with a text input at the bottom.
class CommentsBottomSheet extends StatefulWidget {
  final String postId;
  final String currentUserId;
  final String currentUserName;
  final String? currentUserPhotoUrl;

  const CommentsBottomSheet({
    super.key,
    required this.postId,
    required this.currentUserId,
    required this.currentUserName,
    this.currentUserPhotoUrl,
  });

  /// Shows the comments bottom sheet.
  static void show({
    required BuildContext context,
    required String postId,
    required String currentUserId,
    required String currentUserName,
    String? currentUserPhotoUrl,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => BlocProvider.value(
        value: context.read<PostInteractionCubit>(),
        child: CommentsBottomSheet(
          postId: postId,
          currentUserId: currentUserId,
          currentUserName: currentUserName,
          currentUserPhotoUrl: currentUserPhotoUrl,
        ),
      ),
    );
  }

  @override
  State<CommentsBottomSheet> createState() => _CommentsBottomSheetState();
}

class _CommentsBottomSheetState extends State<CommentsBottomSheet> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    context.read<PostInteractionCubit>().loadComments();
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submitComment() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    context.read<PostInteractionCubit>().addComment(
          authorName: widget.currentUserName,
          authorPhotoUrl: widget.currentUserPhotoUrl,
          text: text,
        );

    _textController.clear();
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle bar
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outline.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Title
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Comments',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            Divider(
                height: 1,
                color: theme.dividerColor.withValues(alpha: 0.3)),

            // Comments list
            Expanded(
              child: BlocBuilder<PostInteractionCubit, PostInteractionState>(
                buildWhen: (prev, curr) =>
                    prev.comments != curr.comments ||
                    prev.isLoadingComments != curr.isLoadingComments,
                builder: (context, state) {
                  if (state.isLoadingComments && state.comments.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (state.comments.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 48,
                              color: theme.colorScheme.outline,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No comments yet',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Be the first to comment!',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    controller: scrollController,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: state.comments.length,
                    itemBuilder: (context, index) {
                      final comment = state.comments[index];
                      return _CommentTile(
                        comment: comment,
                        isOwnComment:
                            comment.authorId == widget.currentUserId,
                        onDelete: () {
                          context
                              .read<PostInteractionCubit>()
                              .deleteComment(comment.id);
                        },
                      );
                    },
                  );
                },
              ),
            ),

            // Input field
            Divider(
                height: 1,
                color: theme.dividerColor.withValues(alpha: 0.3)),
            _CommentInput(
              controller: _textController,
              focusNode: _focusNode,
              userPhotoUrl: widget.currentUserPhotoUrl,
              userName: widget.currentUserName,
              onSubmit: _submitComment,
            ),
          ],
        );
      },
    );
  }
}

// ─── Comment Tile ─────────────────────────────────────────────────────────

class _CommentTile extends StatelessWidget {
  final Comment comment;
  final bool isOwnComment;
  final VoidCallback onDelete;

  const _CommentTile({
    required this.comment,
    required this.isOwnComment,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CachedAvatar(
            imageUrl: comment.authorPhotoUrl,
            name: comment.authorName,
            radius: 16,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: comment.authorName,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const TextSpan(text: '  '),
                      TextSpan(
                        text: comment.text,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatTimeAgo(comment.createdAt),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
          if (isOwnComment)
            IconButton(
              icon: Icon(
                Icons.delete_outline,
                size: 16,
                color: theme.colorScheme.outline,
              ),
              onPressed: onDelete,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inHours < 1) return '${difference.inMinutes}m';
    if (difference.inDays < 1) return '${difference.inHours}h';
    if (difference.inDays < 7) return '${difference.inDays}d';
    return '${(difference.inDays / 7).floor()}w';
  }
}

// ─── Comment Input ────────────────────────────────────────────────────────

class _CommentInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String? userPhotoUrl;
  final String userName;
  final VoidCallback onSubmit;

  const _CommentInput({
    required this.controller,
    required this.focusNode,
    this.userPhotoUrl,
    required this.userName,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 8, 8, 8 + bottomPadding),
      child: Row(
        children: [
          CachedAvatar(
            imageUrl: userPhotoUrl,
            name: userName,
            radius: 16,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: BlocBuilder<PostInteractionCubit, PostInteractionState>(
              buildWhen: (prev, curr) =>
                  prev.isSubmittingComment != curr.isSubmittingComment,
              builder: (context, state) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: !state.isSubmittingComment,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSubmit(),
                  maxLines: 3,
                  minLines: 1,
                  maxLength: 1000,
                  decoration: InputDecoration(
                    hintText: 'Add a comment...',
                    hintStyle: TextStyle(color: theme.colorScheme.outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(
                        color: theme.colorScheme.outline.withValues(alpha: 0.3),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(
                        color: theme.colorScheme.outline.withValues(alpha: 0.3),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    counterText: '',
                    isDense: true,
                    suffixIcon: state.isSubmittingComment
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child:
                                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : IconButton(
                            icon: Icon(
                              Icons.send_rounded,
                              color: theme.colorScheme.primary,
                            ),
                            onPressed: onSubmit,
                          ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
