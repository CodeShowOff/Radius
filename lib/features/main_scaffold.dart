import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../core/router/routes.dart';
import 'chat/presentation/bloc/conversations_bloc.dart';
import 'location_groups/presentation/bloc/location_group_bloc.dart';

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
      return 0;
    } else if (location.startsWith('/connections')) {
      return 1;
    } else if (location.startsWith('/my-groups')) {
      return 2;
    }
    return 0;
  }

  void _onItemTapped(int index) {
    switch (index) {
      case 0:
        context.go(Routes.home);
        break;
      case 1:
        context.go(Routes.connections);
        break;
      case 2:
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
      buildWhen: (previous, current) => previous.totalUnreadCount != current.totalUnreadCount,
      builder: (context, state) {
        final unreadCount = state.totalUnreadCount;
        
        if (unreadCount == 0) {
          return Icon(selected ? Icons.people : Icons.people_outlined);
        }
        
        return Badge(
          label: Text(unreadCount > 99 ? '99+' : unreadCount.toString()),
          child: Icon(selected ? Icons.people : Icons.people_outlined),
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
