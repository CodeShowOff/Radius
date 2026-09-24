import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:stream_chat_flutter/stream_chat_flutter.dart';

import '../../../../core/router/routes.dart';

/// Main chat screen for a 1-to-1 conversation using Stream Chat.
class ChatScreen extends StatelessWidget {
  final String conversationId; // Corresponds to Stream Channel ID
  final String currentUserId;
  final String otherUserId;
  final String otherUserName;
  final String? otherUserPhotoUrl;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.currentUserId,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserPhotoUrl,
  });

  @override
  Widget build(BuildContext context) {
    // Obtain the channel from the Stream client using the conversationId.
    // We must pass the 'members' array in extraData, otherwise Stream Chat throws 
    // a 403 Forbidden error because a user cannot create an empty channel.
    final channel = StreamChat.of(context).client.channel(
      'messaging',
      id: conversationId,
      extraData: {
        'members': [currentUserId, otherUserId],
      },
    );

    // Watch the channel so we have realtime updates (if not already watched)
    channel.watch();

    return StreamChannel(
      channel: channel,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: GestureDetector(
            onTap: () {
              if (otherUserId.isNotEmpty) {
                context.push(Routes.userProfileWith(otherUserId));
              }
            },
            child: Row(
              children: [
                CircleAvatar(
                  backgroundImage: otherUserPhotoUrl != null
                      ? NetworkImage(otherUserPhotoUrl!)
                      : null,
                  child: otherUserPhotoUrl == null
                      ? Text(otherUserName.isNotEmpty
                          ? otherUserName[0].toUpperCase()
                          : 'U')
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(otherUserName, style: const TextStyle(fontSize: 16)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: StreamMessageListView(),
            ),
            const StreamMessageInput(),
          ],
        ),
      ),
    );
  }
}
