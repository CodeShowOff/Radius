import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/widgets/cached_avatar.dart';
import '../../domain/entities/comment.dart';
import '../bloc/post_interaction_cubit.dart';

/// Premium Instagram-style Comments Bottom Sheet
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
      backgroundColor: Colors.transparent,
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
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                color: theme.colorScheme.surface.withValues(alpha: 0.9),
                child: Column(
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 12, bottom: 8),
                        height: 5,
                        width: 40,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    Text('Comments', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.1)),
                    
                    // Comments List
                    Expanded(
                      child: BlocBuilder<PostInteractionCubit, PostInteractionState>(
                        builder: (context, state) {
                          if (state.isLoadingComments && state.comments.isEmpty) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          if (state.comments.isEmpty) {
                            return _buildEmptyState(theme);
                          }
                          return ListView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.only(top: 16, bottom: 16),
                            itemCount: state.comments.length,
                            itemBuilder: (context, index) {
                              final comment = state.comments[index];
                              return _CommentTile(
                                comment: comment,
                                isOwnComment: comment.authorId == widget.currentUserId,
                                onDelete: () => context.read<PostInteractionCubit>().deleteComment(comment.id),
                              );
                            },
                          );
                        },
                      ),
                    ),
                    
                    // Input Area
                    Container(
                      padding: EdgeInsets.only(bottom: bottomInset > 0 ? bottomInset : MediaQuery.of(context).padding.bottom),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -5))],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            CachedAvatar(imageUrl: widget.currentUserPhotoUrl, name: widget.currentUserName, radius: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: TextField(
                                  controller: _textController,
                                  focusNode: _focusNode,
                                  maxLines: 4,
                                  minLines: 1,
                                  textCapitalization: TextCapitalization.sentences,
                                  decoration: InputDecoration(
                                    hintText: 'Add a comment...',
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            BlocBuilder<PostInteractionCubit, PostInteractionState>(
                              builder: (context, state) {
                                return state.isSubmittingComment
                                    ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                                    : IconButton(
                                        icon: Icon(Icons.send_rounded, color: theme.colorScheme.primary),
                                        onPressed: _submitComment,
                                      );
                              }
                            )
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 64, color: theme.colorScheme.outline.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text('No comments yet.', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Start the conversation.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  final Comment comment;
  final bool isOwnComment;
  final VoidCallback onDelete;

  const _CommentTile({required this.comment, required this.isOwnComment, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CachedAvatar(imageUrl: comment.authorPhotoUrl, name: comment.authorName, radius: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: theme.textTheme.bodyMedium,
                    children: [
                      TextSpan(text: '${comment.authorName} ', style: const TextStyle(fontWeight: FontWeight.bold)),
                      TextSpan(text: comment.text),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(_formatTimeAgo(comment.createdAt), style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
                    const SizedBox(width: 16),
                    Text('Reply', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
          if (isOwnComment)
            GestureDetector(
              onTap: onDelete,
              child: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
            ),
          const SizedBox(width: 8),
          const Icon(Icons.favorite_border, size: 16, color: Colors.grey),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }
}
