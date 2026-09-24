import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import '../core/router/routes.dart';
import 'package:stream_chat_flutter/stream_chat_flutter.dart';

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
    } else if (location.startsWith('/local-news')) {
      return 0;
    } else if (location.startsWith('/posts')) {
      return 1;
    } else if (location == Routes.profile) {
      return 4;
    }
    return 2;
  }

  void _onItemTapped(int index) {
    switch (index) {
      case 0:
        context.go(Routes.localNews);
        break;
      case 1:
        context.go(Routes.postFeed);
        break;
      case 2:
        context.go(Routes.home);
        break;
      case 3:
        context.go(Routes.connections);
        break;
      case 4:
        context.go(Routes.profile);
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
            icon: Icon(Icons.newspaper_outlined),
            selectedIcon: Icon(Icons.newspaper),
            label: 'Local',
          ),
          NavigationDestination(
            icon: Icon(Icons.featured_play_list_outlined),
            selectedIcon: Icon(Icons.featured_play_list),
            label: 'Feed',
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
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
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
    try {
      final client = StreamChat.of(context).client;
      return StreamBuilder<int>(
        stream: client.state.totalUnreadCountStream,
        builder: (context, snapshot) {
          final unreadCount = snapshot.data ?? client.state.totalUnreadCount;

          if (unreadCount == 0) {
            return Icon(selected ? Icons.people : Icons.people_outlined);
          }

          return Badge(
            backgroundColor: const Color(0xFF25D366), // WhatsApp green
            label: Text(
              unreadCount > 99 ? '99+' : unreadCount.toString(),
            ),
            child: Icon(selected ? Icons.people : Icons.people_outlined),
          );
        },
      );
    } catch (_) {
      return Icon(selected ? Icons.people : Icons.people_outlined);
    }
  }
}

