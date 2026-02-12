import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/services/cloudinary_service.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../profile/presentation/bloc/profile_bloc.dart';
import '../../domain/entities/location_group.dart';
import '../../domain/entities/group_membership.dart';
import '../bloc/location_group_bloc.dart';

/// Page showing group details, members, and join/leave options.
class GroupDetailPage extends StatefulWidget {
  final String groupId;

  const GroupDetailPage({
    super.key,
    required this.groupId,
  });

  @override
  State<GroupDetailPage> createState() => _GroupDetailPageState();
}

class _GroupDetailPageState extends State<GroupDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _imagePicker = ImagePicker();
  final _cloudinaryService = CloudinaryService();
  bool _hasShownPendingNotification = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadGroupDetails();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadGroupDetails() {
    final authState = context.read<AuthBloc>().state;
    final userId = authState is AuthAuthenticated ? authState.user.id : null;

    context.read<LocationGroupBloc>().add(LoadGroupDetails(
          groupId: widget.groupId,
          currentUserId: userId,
        ));
  }

  void _joinGroup() {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to join groups')),
      );
      return;
    }

    final state = context.read<LocationGroupBloc>().state;
    final group = state.currentGroup;
    if (group == null) return;

    // Get latest profile info if available
    String? userName = authState.user.displayName;
    String? userPhotoUrl = authState.user.avatarUrl;
    
    try {
      final profileState = context.read<ProfileBloc>().state;
      if (profileState is ProfileLoaded) {
        if (profileState.profile.name.isNotEmpty) {
          userName = profileState.profile.name;
        }
        if (profileState.profile.photoUrl != null && 
            profileState.profile.photoUrl!.isNotEmpty) {
          userPhotoUrl = profileState.profile.photoUrl;
        }
      }
    } catch (_) {
      // ProfileBloc might not be available, use auth data as fallback
    }

    if (group.isPublic) {
      context.read<LocationGroupBloc>().add(JoinPublicGroup(
            groupId: widget.groupId,
            userId: authState.user.id,
            userName: userName,
            userPhotoUrl: userPhotoUrl,
          ));
    } else {
      _showRequestDialog(authState, userName, userPhotoUrl);
    }
  }

  void _showRequestDialog(AuthAuthenticated authState, String? userName, String? userPhotoUrl) {
    final messageController = TextEditingController();
    // Capture the bloc before showing dialog to ensure it's accessible
    final bloc = context.read<LocationGroupBloc>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Request to Join'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This group requires admin approval. You can include a message with your request.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: messageController,
              decoration: const InputDecoration(
                labelText: 'Message (optional)',
                hintText: 'Introduce yourself...',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              maxLength: 200,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              bloc.add(RequestToJoinGroup(
                    groupId: widget.groupId,
                    userId: authState.user.id,
                    userName: userName,
                    userPhotoUrl: userPhotoUrl,
                    message: messageController.text.trim().isEmpty
                        ? null
                        : messageController.text.trim(),
                  ));
            },
            child: const Text('Send Request'),
          ),
        ],
      ),
    );
  }

  void _leaveGroup() {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;
    
    // Capture the bloc before showing dialog to ensure it's accessible
    final bloc = context.read<LocationGroupBloc>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave Group'),
        content: const Text('Are you sure you want to leave this group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              bloc.add(LeaveGroup(
                    groupId: widget.groupId,
                    userId: authState.user.id,
                  ));
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
  }

  void _showDeleteGroupDialog() {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;

    // Verify user is admin
    final state = context.read<LocationGroupBloc>().state;
    if (!state.isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only admins can delete groups')),
      );
      return;
    }
    
    // Capture the bloc before showing dialog to ensure it's accessible
    final bloc = context.read<LocationGroupBloc>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Group'),
        content: const Text(
          'Are you sure you want to permanently delete this group? This action cannot be undone and will remove all messages and member data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              bloc.add(DeleteGroup(
                    groupId: widget.groupId,
                    adminUserId: authState.user.id,
                  ));
              // Navigation will happen in listener after successful deletion
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showGroupSettings() {
    final state = context.read<LocationGroupBloc>().state;
    final group = state.currentGroup;
    if (group == null) return;

    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;

    // Verify user is admin
    if (!state.isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only admins can modify group settings')),
      );
      return;
    }
    
    // Capture the bloc before showing dialog to ensure it's accessible
    final bloc = context.read<LocationGroupBloc>();

    final nameController = TextEditingController(text: group.name);
    final descriptionController = TextEditingController(text: group.description);
    GroupVisibility selectedVisibility = group.visibility;
    String? avatarUrl = group.avatarUrl;
    bool isUploading = false;

    Future<void> pickAndUploadImage(StateSetter setState) async {
      final pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (pickedFile == null) return;

      // Check mounted BEFORE setState
      if (!mounted) return;
      setState(() => isUploading = true);

      try {
        final url = await _cloudinaryService.uploadImage(
          File(pickedFile.path),
          folder: 'radius/groups',
          tags: {'group_avatar': 'true'},
        );

        // Check mounted BEFORE setState
        if (!mounted) return;
        setState(() {
          avatarUrl = url;
          isUploading = false;
        });
      } catch (e) {
        // Check mounted BEFORE setState and showing snackbar
        if (!mounted) return;
        setState(() => isUploading = false);
        
        if (!mounted) return;
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to upload image: $e')),
          );
        }
      }
    }

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Group Settings'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      backgroundImage:
                          avatarUrl != null ? NetworkImage(avatarUrl!) : null,
                      child: avatarUrl == null
                          ? Text(
                              group.name.isNotEmpty
                                  ? group.name[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: isUploading
                            ? null
                            : () => pickAndUploadImage(setState),
                        icon: isUploading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.photo_camera),
                        label: Text(isUploading ? 'Uploading...' : 'Change Photo'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Group Name',
                    border: OutlineInputBorder(),
                  ),
                  maxLength: 50,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                  maxLength: 200,
                ),
                const SizedBox(height: 16),
                const Text('Privacy', style: TextStyle(fontWeight: FontWeight.bold)),
                RadioGroup<GroupVisibility>(
                  groupValue: selectedVisibility,
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => selectedVisibility = value);
                  },
                  child: const Column(
                    children: [
                      RadioListTile<GroupVisibility>(
                        title: Text('Public'),
                        subtitle: Text('Anyone can join'),
                        value: GroupVisibility.public,
                      ),
                      RadioListTile<GroupVisibility>(
                        title: Text('Request to Join'),
                        subtitle: Text('Admins approve members'),
                        value: GroupVisibility.requestToJoin,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                bloc.add(UpdateGroupSettings(
                      groupId: widget.groupId,
                      adminUserId: authState.user.id,
                      name: nameController.text.trim(),
                      description: descriptionController.text.trim(),
                      visibility: selectedVisibility,
                      avatarUrl: avatarUrl != group.avatarUrl ? avatarUrl : null,
                    ));
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocConsumer<LocationGroupBloc, LocationGroupState>(
      listener: (context, state) {
        // Handle successful group deletion
        if (state.groupDeleted) {
          // Clear the flag first
          context.read<LocationGroupBloc>().add(const ClearGroupDeletionFlag());
          
          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Group deleted successfully'),
              backgroundColor: theme.colorScheme.primary,
            ),
          );
          
          // Navigate to my groups page
          context.go(Routes.myGroups);
          return;
        }
        
        if (state.hasError && state.errorMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.errorMessage!),
              backgroundColor: theme.colorScheme.error,
            ),
          );
          context.read<LocationGroupBloc>().add(const ClearGroupError());
        }

        // Show success message when join request is sent
        // Note: We check status to show this only once when request is sent
        if (state.status == GroupBlocStatus.loaded && 
            state.hasPendingRequest && 
            !state.isMember &&
            !_hasShownPendingNotification) {
          _hasShownPendingNotification = true;
          
          // Delay to ensure it shows after navigation/UI updates
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Join request sent! You\'ll be notified when approved.'),
                  backgroundColor: theme.colorScheme.primary,
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          });
        }
        
        // Reset flag if no longer pending (approved or rejected)
        if (!state.hasPendingRequest) {
          _hasShownPendingNotification = false;
        }
      },
      builder: (context, state) {
        final group = state.currentGroup;

        // Handle null group first: show loading for initial/loading, otherwise not found
        if (group == null) {
          final isLoading = state.status == GroupBlocStatus.initial ||
              state.status == GroupBlocStatus.loading;
          if (isLoading) {
            return Scaffold(
              appBar: AppBar(),
              body: const Center(child: CircularProgressIndicator()),
            );
          }
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  const Text('Group not found'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => context.pop(),
                    child: const Text('Go Back'),
                  ),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          body: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              return [
                _buildSliverAppBar(theme, group, state),
              ];
            },
            body: Column(
              children: [
                // Tab bar
                TabBar(
                  controller: _tabController,
                  tabs: [
                    const Tab(
                      text: 'About',
                      icon: Icon(Icons.info_outline),
                    ),
                    Tab(
                      text: 'Members (${group.memberCount})',
                      icon: const Icon(Icons.people_outline),
                    ),
                  ],
                ),

                // Tab content
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildAboutTab(theme, group, state),
                      _buildMembersTab(theme, state),
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: _buildBottomBar(theme, group, state),
        );
      },
    );
  }

  SliverAppBar _buildSliverAppBar(
    ThemeData theme,
    LocationGroup group,
    LocationGroupState state,
  ) {
    return SliverAppBar(
      expandedHeight: 200,
      pinned: true,
      actions: [
        if (state.isAdmin)
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'settings':
                  _showGroupSettings();
                  break;
                case 'requests':
                  _showJoinRequests();
                  break;
                case 'delete':
                  _showDeleteGroupDialog();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  leading: Icon(Icons.settings),
                  title: Text('Group Settings'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (group.requiresApproval)
                PopupMenuItem(
                  value: 'requests',
                  child: ListTile(
                    leading: Badge(
                      isLabelVisible: state.joinRequests.isNotEmpty,
                      label: Text(state.joinRequests.length.toString()),
                      child: const Icon(Icons.person_add),
                    ),
                    title: const Text('Join Requests'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              const PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline, color: Colors.red),
                  title: Text('Delete Group', style: TextStyle(color: Colors.red)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        title: Text(
          group.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.primaryContainer,
                theme.colorScheme.secondaryContainer,
              ],
            ),
          ),
          child: Center(
            child: CircleAvatar(
              radius: 40,
              backgroundColor: theme.colorScheme.surface,
              backgroundImage: group.avatarUrl != null
                  ? NetworkImage(group.avatarUrl!)
                  : null,
              child: group.avatarUrl == null
                  ? Text(
                      group.name.isNotEmpty ? group.name[0].toUpperCase() : '?',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAboutTab(
    ThemeData theme,
    LocationGroup group,
    LocationGroupState state,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Location
          Card(
            child: ListTile(
              leading: Icon(
                Icons.location_on,
                color: theme.colorScheme.primary,
              ),
              title: Text(group.stateName),
              subtitle: Text(group.countryName),
            ),
          ),

          const SizedBox(height: 16),

          // Description
          if (group.description != null && group.description!.isNotEmpty) ...[
            Text(
              'About',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              group.description!,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
          ],

          // Stats
          Text(
            'Group Info',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),

          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    group.isPublic ? Icons.public : Icons.lock_outline,
                    color: theme.colorScheme.secondary,
                  ),
                  title: Text(group.isPublic ? 'Open Group' : 'Approval Required'),
                  subtitle: Text(
                    group.isPublic
                        ? 'Anyone can join this group'
                        : 'Admins approve new members',
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(
                    Icons.calendar_today,
                    color: theme.colorScheme.tertiary,
                  ),
                  title: const Text('Created'),
                  subtitle: Text(_formatDate(group.createdAt)),
                ),
                if (group.createdByUserName != null) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(
                      Icons.person,
                      color: theme.colorScheme.primary,
                    ),
                    title: const Text('Created by'),
                    subtitle: Text(group.createdByUserName!),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMembersTab(ThemeData theme, LocationGroupState state) {
    if (state.groupMembers.isEmpty) {
      return Center(
        child: Text(
          'No members yet',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: state.groupMembers.length,
      itemBuilder: (context, index) {
        final member = state.groupMembers[index];
        return _MemberTile(
          member: member,
          isCurrentUser: _isCurrentUser(member.userId),
          canManage: state.isAdmin && !_isCurrentUser(member.userId),
          onPromote: () => _promoteMember(member),
          onRemove: () => _removeMember(member),
        );
      },
    );
  }

  bool _isCurrentUser(String userId) {
    final authState = context.read<AuthBloc>().state;
    return authState is AuthAuthenticated && authState.user.id == userId;
  }

  void _promoteMember(GroupMembership member) {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;
    
    // Capture the bloc before showing dialog to ensure it's accessible
    final bloc = context.read<LocationGroupBloc>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Promote to Admin'),
        content: Text(
          'Make ${member.userName ?? 'this user'} an admin? They will be able to manage members and group settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              bloc.add(PromoteToAdmin(
                    groupId: widget.groupId,
                    targetUserId: member.userId,
                    adminUserId: authState.user.id,
                  ));
            },
            child: const Text('Promote'),
          ),
        ],
      ),
    );
  }

  void _removeMember(GroupMembership member) {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;
    
    // Capture the bloc before showing dialog to ensure it's accessible
    final bloc = context.read<LocationGroupBloc>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text(
          'Remove ${member.userName ?? 'this user'} from the group?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              bloc.add(RemoveMember(
                    groupId: widget.groupId,
                    targetUserId: member.userId,
                    adminUserId: authState.user.id,
                  ));
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  void _showJoinRequests() {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;

    // Verify user is admin
    final state = context.read<LocationGroupBloc>().state;
    if (!state.isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only admins can view join requests')),
      );
      return;
    }

    // Capture bloc reference before showing modal
    final locationGroupBloc = context.read<LocationGroupBloc>();

    // Load join requests
    locationGroupBloc.add(
      LoadJoinRequests(groupId: widget.groupId),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (modalContext) => BlocProvider.value(
        value: locationGroupBloc,
        child: BlocBuilder<LocationGroupBloc, LocationGroupState>(
          builder: (builderContext, state) {
          return DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.3,
            maxChildSize: 0.9,
            expand: false,
            builder: (context, scrollController) {
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Text(
                          'Join Requests',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: state.joinRequests.isEmpty
                        ? Center(
                            child: Text(
                              'No pending requests',
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: Theme.of(context).colorScheme.outline,
                                  ),
                            ),
                          )
                        : ListView.builder(
                            controller: scrollController,
                            itemCount: state.joinRequests.length,
                            itemBuilder: (context, index) {
                              final request = state.joinRequests[index];
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundImage: request.userPhotoUrl != null
                                      ? NetworkImage(request.userPhotoUrl!)
                                      : null,
                                  child: request.userPhotoUrl == null
                                      ? Text(
                                          (request.userName ?? '?')[0].toUpperCase(),
                                        )
                                      : null,
                                ),
                                title: Text(request.userName ?? 'Unknown User'),
                                subtitle: request.message != null
                                    ? Text(
                                        request.message!,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      )
                                    : null,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      onPressed: () {
                                        context.read<LocationGroupBloc>().add(
                                              RejectJoinRequest(
                                                groupId: widget.groupId,
                                                requestUserId: request.userId,
                                                adminUserId: authState.user.id,
                                              ),
                                            );
                                      },
                                      icon: const Icon(Icons.close),
                                      color: Theme.of(context).colorScheme.error,
                                    ),
                                    IconButton(
                                      onPressed: () {
                                        context.read<LocationGroupBloc>().add(
                                              ApproveJoinRequest(
                                                groupId: widget.groupId,
                                                requestUserId: request.userId,
                                                adminUserId: authState.user.id,
                                              ),
                                            );
                                      },
                                      icon: const Icon(Icons.check),
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          );
        },
        ),
      ),
    );
  }

  Widget _buildBottomBar(
    ThemeData theme,
    LocationGroup group,
    LocationGroupState state,
  ) {
    // ========================================================================
    // SECURITY: Show loading indicator during any membership state transition
    // This prevents showing wrong buttons during membership check/join/leave
    // ========================================================================
    if (state.status == GroupBlocStatus.loading || 
        state.status == GroupBlocStatus.joining ||
        state.status == GroupBlocStatus.leaving) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.tonal(
            onPressed: null,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text('Loading...'),
              ],
            ),
          ),
        ),
      );
    }

    if (state.isMember) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => context.push(
                    Routes.locationGroupChatWith(group.id),
                  ),
                  icon: const Icon(Icons.chat),
                  label: const Text('Open Chat'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: _leaveGroup,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  foregroundColor: theme.colorScheme.error,
                ),
                child: const Text('Leave'),
              ),
            ],
          ),
        ),
      );
    }

    if (state.hasPendingRequest) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.tonal(
            onPressed: null,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('Request Pending'),
          ),
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton.icon(
          onPressed: state.isLoading ? null : _joinGroup,
          icon: Icon(group.isPublic ? Icons.group_add : Icons.person_add),
          label: Text(group.isPublic ? 'Join Group' : 'Request to Join'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _MemberTile extends StatelessWidget {
  final GroupMembership member;
  final bool isCurrentUser;
  final bool canManage;
  final VoidCallback? onPromote;
  final VoidCallback? onRemove;

  const _MemberTile({
    required this.member,
    required this.isCurrentUser,
    required this.canManage,
    this.onPromote,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Prefer up-to-date profile info for the current user
    String displayName = member.userName ?? 'Unknown User';
    String? photoUrl = member.userPhotoUrl;

    if (isCurrentUser) {
      try {
        final profileState = context.read<ProfileBloc>().state;
        if (profileState is ProfileLoaded) {
          if (profileState.profile.name.isNotEmpty) {
            displayName = profileState.profile.name;
          }
          if (profileState.profile.photoUrl != null &&
              profileState.profile.photoUrl!.isNotEmpty) {
            photoUrl = profileState.profile.photoUrl;
          }
        }
      } catch (_) {
        // ProfileBloc might not be available; fall back to membership data
      }
    }

    return ListTile(
      onTap: !isCurrentUser
          ? () => context.push(
                Routes.userProfileWith(member.userId),
                extra: {
                  'displayName': displayName,
                  'photoUrl': photoUrl,
                },
              )
          : null,
      leading: CircleAvatar(
        backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
        child: photoUrl == null
            ? Text(
                (displayName.isNotEmpty ? displayName[0] : '?').toUpperCase(),
              )
            : null,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              displayName,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isCurrentUser) ...[
            const SizedBox(width: 8),
            Text(
              '(You)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ],
      ),
      subtitle: member.isAdmin
          ? Text(
              'Admin',
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            )
          : null,
      trailing: canManage
          ? PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'promote':
                    onPromote?.call();
                    break;
                  case 'remove':
                    onRemove?.call();
                    break;
                }
              },
              itemBuilder: (context) => [
                if (!member.isAdmin)
                  const PopupMenuItem(
                    value: 'promote',
                    child: Text('Make Admin'),
                  ),
                PopupMenuItem(
                  value: 'remove',
                  child: Text(
                    'Remove',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ],
            )
          : null,
    );
  }
}
