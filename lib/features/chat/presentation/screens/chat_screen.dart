import 'package:flutter/material.dart';
import 'package:stream_chat_flutter/stream_chat_flutter.dart';

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
    // Obtain the channel from the Stream client using the conversationId
    final channel = StreamChat.of(context).client.channel(
      'messaging',
      id: conversationId,
    );

    // Watch the channel so we have realtime updates (if not already watched)
    channel.watch();

    return StreamChannel(
      channel: channel,
      child: Scaffold(
        appBar: const StreamChannelHeader(),
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
