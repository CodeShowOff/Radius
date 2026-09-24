import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:stream_chat_flutter/stream_chat_flutter.dart';

/// Page for nearby group chat using Stream Chat.
class NearbyGroupChatPage extends StatefulWidget {
  final String groupId;

  const NearbyGroupChatPage({
    super.key,
    required this.groupId,
  });

  @override
  State<NearbyGroupChatPage> createState() => _NearbyGroupChatPageState();
}

class _NearbyGroupChatPageState extends State<NearbyGroupChatPage> {
  late Channel _channel;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _channel = StreamChat.of(context).client.channel(
      'livestream', // We mapped Nearby Groups to 'livestream' channels
      id: widget.groupId,
    );

    _channel.watch().then((_) async {
      // Sync group name to Stream Chat if it's missing
      if (_channel.extraData['name'] == null) {
        final doc = await FirebaseFirestore.instance
            .collection('nearby_groups')
            .doc(widget.groupId)
            .get();
        if (doc.exists) {
          final data = doc.data()!;
          _channel.updatePartial(set: {
            'name': data['name'],
            if (data['avatarUrl'] != null) 'image': data['avatarUrl'],
            if (data['photoUrl'] != null) 'image': data['photoUrl'],
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
