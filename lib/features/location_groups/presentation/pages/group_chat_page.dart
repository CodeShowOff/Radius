import 'package:flutter/material.dart';
import 'package:stream_chat_flutter/stream_chat_flutter.dart';

/// Page for group chat using Stream Chat.
class GroupChatPage extends StatelessWidget {
  final String groupId;

  const GroupChatPage({
    super.key,
    required this.groupId,
  });

  @override
  Widget build(BuildContext context) {
    // Obtain the channel from the Stream client using the groupId
    final channel = StreamChat.of(context).client.channel(
      'team', // We mapped Location Groups to 'team' channels
      id: groupId,
    );

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
