import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:stream_chat_flutter/stream_chat_flutter.dart';

import '../../../../core/router/routes.dart';

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
  String? _groupName;

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
          if (mounted) {
            setState(() {
              _groupName = data['name'];
            });
          }
          try {
            await _channel.updatePartial(set: {
              'name': data['name'],
              if (data['avatarUrl'] != null) 'image': data['avatarUrl'],
              if (data['photoUrl'] != null) 'image': data['photoUrl'],
            });
          } catch (e) {
             // Ignore permission errors for normal users updating the channel name
             debugPrint('Could not update channel partial: $e');
          }
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
          title: Text(_groupName ?? _channel.extraData['name']?.toString() ?? 'Nearby Group'),
          onImageTap: () => context.push(Routes.nearbyGroupDetailWith(widget.groupId)),
          onTitleTap: () => context.push(Routes.nearbyGroupDetailWith(widget.groupId)),
          actions: [
            IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: () => context.push(Routes.nearbyGroupDetailWith(widget.groupId)),
            ),
          ],
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
