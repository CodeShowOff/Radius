import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/widgets/cached_avatar.dart';
import '../bloc/nearby_group_bloc.dart';

class NearbyGroupDetailPage extends StatefulWidget {
  final String groupId;

  const NearbyGroupDetailPage({super.key, required this.groupId});

  @override
  State<NearbyGroupDetailPage> createState() => _NearbyGroupDetailPageState();
}

class _NearbyGroupDetailPageState extends State<NearbyGroupDetailPage> {
  @override
  void initState() {
    super.initState();
    context.read<NearbyGroupBloc>().add(LoadNearbyGroupDetails(widget.groupId));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Group Info')),
      body: BlocBuilder<NearbyGroupBloc, NearbyGroupState>(
        builder: (context, state) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final group = state.selectedGroup;
          if (group == null) {
            return const Center(child: Text('Group not found'));
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: CachedAvatar(
                  imageUrl: group.creatorPhotoUrl,
                  name: group.name,
                  radius: 48,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                group.name,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              if (group.description != null && group.description!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  group.description!,
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 32),
              Text(
                'Members (${state.groupMembers.length})',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...state.groupMembers.map((member) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CachedAvatar(
                      imageUrl: member.photoUrl,
                      name: member.displayName ?? member.username,
                      radius: 20,
                    ),
                    title: Text(member.displayName ?? member.username),
                    subtitle: Text(member.id == group.creatorId ? 'Creator' : 'Member'),
                  )),
            ],
          );
        },
      ),
    );
  }
}
