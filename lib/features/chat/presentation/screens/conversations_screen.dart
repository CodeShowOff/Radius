import 'package:flutter/material.dart';
import 'package:stream_chat_flutter/stream_chat_flutter.dart';

/// Screen showing the list of conversations for a user using Stream Chat.
class ConversationsScreen extends StatefulWidget {
  final String currentUserId;
  final void Function(Channel channel) onConversationTap;

  const ConversationsScreen({
    super.key,
    required this.currentUserId,
    required this.onConversationTap,
  });

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  late final _listController = StreamChannelListController(
    client: StreamChat.of(context).client,
    filter: Filter.and([
      Filter.equal('type', 'messaging'),
      Filter.in_('members', [widget.currentUserId]),
    ]),
    channelStateSort: const [SortOption.desc('last_message_at')],
    limit: 20,
  );

  @override
  void dispose() {
    _listController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamChannelListView(
      controller: _listController,
      onChannelTap: (channel) {
        widget.onConversationTap(channel);
      },
      itemBuilder: (context, channels, index, defaultWidget) {
        final channel = channels[index];
        return StreamChannelListTile(
          channel: channel,
          leading: StreamChannelAvatar(
            channel: channel,
            constraints: const BoxConstraints.tightFor(width: 56, height: 56),
          ),
          title: StreamChannelName(
            channel: channel,
            textStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          onTap: () => widget.onConversationTap(channel),
        );
      },
      loadingBuilder: (context) => const SizedBox.shrink(),
      emptyBuilder: (context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.chat_bubble_outline,
                size: 80,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 24),
              Text(
                'No conversations yet',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Start a chat with people nearby to begin messaging',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
