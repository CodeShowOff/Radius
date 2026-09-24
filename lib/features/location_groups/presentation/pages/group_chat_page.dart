import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:stream_chat_flutter/stream_chat_flutter.dart';

import '../../../../core/router/routes.dart';

/// Page for group chat using Stream Chat.
class GroupChatPage extends StatefulWidget {
  final String groupId;

  const GroupChatPage({
    super.key,
    required this.groupId,
  });

  @override
  State<GroupChatPage> createState() => _GroupChatPageState();
}

class _GroupChatPageState extends State<GroupChatPage> {
  late Channel _channel;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _channel = StreamChat.of(context).client.channel(
      'team', // We mapped Location Groups to 'team' channels
      id: widget.groupId,
    );

    _channel.watch().then((_) async {
      // Sync group name to Stream Chat if it's missing
      if (_channel.extraData['name'] == null) {
        final doc = await FirebaseFirestore.instance
            .collection('location_groups')
            .doc(widget.groupId)
            .get();
        if (doc.exists) {
          final data = doc.data()!;
          _channel.updatePartial(set: {
            'name': data['name'],
            if (data['avatarUrl'] != null) 'image': data['avatarUrl'],
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamChannel(
      channel: _channel,
      child: Scaffold(
        appBar: StreamChannelHeader(
          onImageTap: () => context.push(Routes.locationGroupDetailWith(widget.groupId)),
          onTitleTap: () => context.push(Routes.locationGroupDetailWith(widget.groupId)),
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
