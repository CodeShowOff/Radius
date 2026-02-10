import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../core/router/routes.dart';
import 'chat/domain/entities/conversation.dart';
import 'chat/presentation/bloc/conversations_bloc.dart';
import 'random_chat/presentation/bloc/random_chat_bloc.dart';

/// Main scaffold with bottom navigation for the app.
class MainScaffold extends StatefulWidget {
  final Widget child;
  final String location;

  const MainScaffold({
    super.key,
    required this.child,
    required this.location,
  });

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _getCurrentIndex() {
    final location = widget.location;
    if (location == Routes.home || location == '/') {
      return 2;
    } else if (location.startsWith('/connections')) {
      return 3;
    } else if (location.startsWith('/nearby-groups')) {
      return 1;
    } else if (location.startsWith('/random-groups')) {
      return 0;
    } else if (location.startsWith('/my-groups')) {
      return 4;
    }
    return 2;
  }

  void _onItemTapped(int index) {
    switch (index) {
      case 0:
        context.go(Routes.randomGroups);
        break;
      case 1:
        context.go(Routes.nearbyGroups);
        break;
      case 2:
        context.go(Routes.home);
        break;
      case 3:
        context.go(Routes.connections);
        break;
      case 4:
        context.go(Routes.myGroups);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _getCurrentIndex(),
        onDestinationSelected: _onItemTapped,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.public_outlined),
            selectedIcon: Icon(Icons.public),
            label: 'Random',
          ),
          NavigationDestination(
            icon: Icon(Icons.all_inclusive_outlined),
            selectedIcon: Icon(Icons.all_inclusive),
            label: 'Nearby',
          ),
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: _ConnectionsIcon(selected: false),
            selectedIcon: _ConnectionsIcon(selected: true),
            label: 'Connections',
          ),
          NavigationDestination(
            icon: _GroupsIcon(selected: false),
            selectedIcon: _GroupsIcon(selected: true),
            label: 'Groups',
          ),
        ],
      ),
    );
  }
}

class _ConnectionsIcon extends StatelessWidget {
  final bool selected;

  const _ConnectionsIcon({required this.selected});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConversationsBloc, ConversationsState>(
      buildWhen: (previous, current) {
        // Rebuild when conversations list changes or current user changes
        return previous.conversations != current.conversations ||
            previous.currentUserId != current.currentUserId;
      },
      builder: (context, conversationsState) {
        return BlocBuilder<RandomChatBloc, RandomChatState>(
          buildWhen: (previous, current) {
            // Rebuild when active connection changes
            if (previous is RandomChatLoaded && current is RandomChatLoaded) {
              return previous.activeConnection != current.activeConnection;
            }
            return previous.runtimeType != current.runtimeType;
          },
          builder: (context, randomChatState) {
            // Get random chat conversation ID to exclude
            String? randomChatConversationId;
            if (randomChatState is RandomChatLoaded &&
                randomChatState.activeConnection != null &&
                conversationsState.currentUserId != null) {
              final connection = randomChatState.activeConnection!;
              final currentUserId = conversationsState.currentUserId!;
              final otherUserId = connection.getOtherUserId(currentUserId);
              randomChatConversationId =
                  Conversation.createConversationId(currentUserId, otherUserId);
            }

            // Count the number of connection chats with unread messages
            // (excluding random chat)
            final userId = conversationsState.currentUserId ?? '';
            final chatsWithUnread = conversationsState.conversations
                .where((conversation) =>
                    conversation.id != randomChatConversationId &&
                    conversation.getUnreadCount(userId) > 0)
                .length;

            if (chatsWithUnread == 0) {
              return Icon(selected ? Icons.people : Icons.people_outlined);
            }

            return Badge(
              label: Text(chatsWithUnread > 99 ? '99+' : chatsWithUnread.toString()),
              child: Icon(selected ? Icons.people : Icons.people_outlined),
            );
          },
        );
      },
    );
  }
}

class _GroupsIcon extends StatelessWidget {
  final bool selected;

  const _GroupsIcon({required this.selected});

  @override
  Widget build(BuildContext context) {
    return Icon(selected ? Icons.groups : Icons.groups_outlined);
  }
}
