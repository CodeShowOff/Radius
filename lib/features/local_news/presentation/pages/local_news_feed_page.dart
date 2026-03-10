import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/router/routes.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/news_location.dart';
import '../../domain/repositories/i_news_interaction_repository.dart';
import '../bloc/news_feed_bloc.dart';
import '../bloc/news_interaction_cubit.dart';
import '../bloc/news_location_bloc.dart';
import '../bloc/reels_feed_bloc.dart';
import '../widgets/manual_location_picker.dart';
import '../widgets/news_post_card.dart';
import '../widgets/reels_feed_view.dart';

/// Main news feed page showing location-scoped news posts.
///
/// On first open, checks for a saved location. If none is found,
/// displays a location setup flow (GPS or manual search). Once a
/// location is set, shows the feed with posts filtered by that location.
class LocalNewsFeedPage extends StatefulWidget {
  const LocalNewsFeedPage({super.key});

  @override
  State<LocalNewsFeedPage> createState() => _LocalNewsFeedPageState();
}

class _LocalNewsFeedPageState extends State<LocalNewsFeedPage>
    with TickerProviderStateMixin {
  final _scrollController = ScrollController();
  late final TabController _tabController;

  /// Whether the manual search picker is shown (within setup flow).
  bool _showManualSearch = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);

    // Check for saved location after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLocation();
    });
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _scrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    // Rebuild so the FAB reflects the current tab.
    // Guard with indexIsChanging to avoid double rebuild during animation.
    if (!_tabController.indexIsChanging) {
      setState(() {});
    }
  }

  /// Gets the current user's ID from AuthBloc, or empty string if not signed in.
  String get _userId {
    final authState = context.read<AuthBloc>().state;
    return authState is AuthAuthenticated ? authState.user.id : '';
  }

  /// Checks whether the user already has a saved location.
  /// If the bloc is still in initial state, dispatches the check event.
  /// If a location is already ready, loads the feed directly.
  void _checkLocation() {
    final locState = context.read<NewsLocationBloc>().state;
    if (locState.status == NewsLocationStatus.initial) {
      final uid = _userId;
      if (uid.isNotEmpty) {
        context.read<NewsLocationBloc>().add(
              NewsLocationCheckRequested(userId: uid),
            );
      }
    } else if (locState.hasLocation) {
      _loadFeed(locState.location!);
    }
  }

  void _loadFeed(NewsLocation location) {
    context.read<NewsFeedBloc>().add(NewsFeedLoadRequested(
          country: location.country,
          city: location.city,
        ));
    context.read<ReelsFeedBloc>().add(ReelsFeedLoadRequested(
          country: location.country,
          city: location.city,
        ));
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;

    if (currentScroll >= maxScroll * 0.7) {
      final state = context.read<NewsFeedBloc>().state;
      if (state.hasMore && !state.isLoadingMore) {
        context.read<NewsFeedBloc>().add(const NewsFeedLoadMore());
      }
    }
  }

  Future<void> _onRefresh() async {
    context.read<NewsFeedBloc>().add(const NewsFeedRefreshRequested());
    await context.read<NewsFeedBloc>().stream.first;
  }

  void _confirmDelete(BuildContext context, String postId) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Post?'),
        content: const Text(
          'This post will be permanently deleted. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              context.read<NewsFeedBloc>().add(NewsFeedPostDeleted(postId));
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<NewsLocationBloc, NewsLocationState>(
      listener: (context, locationState) {
        if (locationState.status == NewsLocationStatus.ready &&
            locationState.location != null) {
          _loadFeed(locationState.location!);
          setState(() => _showManualSearch = false);
        }
      },
      builder: (context, locationState) {
        if (locationState.hasLocation) {
          return _buildFeedScaffold(context, locationState);
        }
        return _buildSetupScaffold(context, locationState);
      },
    );
  }

  // ─── Feed scaffold (location is ready) ─────────────────────────────

  Widget _buildFeedScaffold(
      BuildContext context, NewsLocationState locationState) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            const Text('Local'),
            Text(
              locationState.location!.shortDisplayString,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_location_alt_outlined),
            tooltip: 'Change Location',
            onPressed: () {
              context.read<NewsLocationBloc>().add(
                    const NewsLocationChangeRequested(),
                  );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'News'),
            Tab(text: 'Reels'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (_tabController.index == 1) {
            context.push(Routes.localNewsCreateReel);
          } else {
            context.push(Routes.localNewsCreate);
          }
        },
        tooltip: _tabController.index == 1 ? 'Create Reel' : 'Post News',
        child: const Icon(Icons.add),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _NewsFeedTab(
            scrollController: _scrollController,
            onRefresh: _onRefresh,
            onConfirmDelete: _confirmDelete,
          ),
          const ReelsFeedView(),
        ],
      ),
    );
  }

  // ─── Setup scaffold (location not yet configured) ──────────────────

  Widget _buildSetupScaffold(
      BuildContext context, NewsLocationState locationState) {
    return Scaffold(
      appBar: AppBar(title: const Text('Local News')),
      body: SafeArea(
        child: _buildSetupBody(context, locationState),
      ),
    );
  }

  Widget _buildSetupBody(
      BuildContext context, NewsLocationState locationState) {
    return switch (locationState.status) {
      NewsLocationStatus.initial || NewsLocationStatus.loading =>
        const _CheckingLocationView(),
      NewsLocationStatus.needsSetup => _showManualSearch
          ? _ManualSearchView(
              onBack: () => setState(() => _showManualSearch = false),
            )
          : _SetupChoiceView(
              onManualTap: () => setState(() => _showManualSearch = true),
            ),
      NewsLocationStatus.detecting => const _DetectingGpsView(),
      NewsLocationStatus.detected => _ConfirmLocationView(
          location: locationState.location!,
          userId: _userId,
        ),
      NewsLocationStatus.saving => const _SavingLocationView(),
      NewsLocationStatus.error => _SetupErrorView(
          message: locationState.errorMessage ?? 'An unknown error occurred.',
          onManualTap: () => setState(() => _showManualSearch = true),
        ),
      NewsLocationStatus.ready =>
        const _CheckingLocationView(), // brief flash before rebuild
    };
  }
}

// ---------------------------------------------------------------------------
// Checking / Loading location indicator
// ---------------------------------------------------------------------------
class _CheckingLocationView extends StatelessWidget {
  const _CheckingLocationView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Checking location...'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Setup Choice — GPS vs Manual Search
// ---------------------------------------------------------------------------
class _SetupChoiceView extends StatelessWidget {
  final VoidCallback onManualTap;

  const _SetupChoiceView({required this.onManualTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.location_on_outlined,
            size: 72,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            'Set Your Location',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'To show you local news and updates from your area, '
            'we need to know your location. You can change this anytime.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),

          // GPS option
          _SetupOptionCard(
            icon: Icons.my_location,
            title: 'Use GPS',
            subtitle: 'Automatically detect your location',
            recommended: true,
            onTap: () {
              context.read<NewsLocationBloc>().add(
                    const NewsLocationGpsRequested(),
                  );
            },
          ),
          const SizedBox(height: 16),

          // Manual pick option
          _SetupOptionCard(
            icon: Icons.list_alt,
            title: 'Pick Manually',
            subtitle: 'Select your country and city',
            onTap: onManualTap,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Setup option card
// ---------------------------------------------------------------------------
class _SetupOptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool recommended;
  final VoidCallback onTap;

  const _SetupOptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.recommended = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: recommended ? 2 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: recommended
              ? theme.colorScheme.primary
              : theme.colorScheme.outline,
          width: recommended ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(icon, size: 32, color: theme.colorScheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (recommended) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Recommended',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// GPS detecting view
// ---------------------------------------------------------------------------
class _DetectingGpsView extends StatelessWidget {
  const _DetectingGpsView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(
            'Detecting your location...',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'This may take a moment.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Confirm detected / selected location
// ---------------------------------------------------------------------------
class _ConfirmLocationView extends StatelessWidget {
  final NewsLocation location;
  final String userId;

  const _ConfirmLocationView({
    required this.location,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 72,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            'Location Found',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'You will see news from:',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // Location display card
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(
                    Icons.location_on,
                    color: theme.colorScheme.primary,
                    size: 28,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    location.displayString,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    location.country,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (location.source == LocationSource.gps) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.gps_fixed,
                          size: 14,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Detected via GPS',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

          const Spacer(),

          // Confirm button
          FilledButton.icon(
            onPressed: () {
              context.read<NewsLocationBloc>().add(
                    NewsLocationSaveRequested(userId: userId),
                  );
            },
            icon: const Icon(Icons.check),
            label: const Text('Confirm Location'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Choose different location
          OutlinedButton(
            onPressed: () {
              context.read<NewsLocationBloc>().add(
                    const NewsLocationChangeRequested(),
                  );
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Choose Different Location'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Saving location indicator
// ---------------------------------------------------------------------------
class _SavingLocationView extends StatelessWidget {
  const _SavingLocationView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Saving your location...'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error view (setup context)
// ---------------------------------------------------------------------------
class _SetupErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onManualTap;

  const _SetupErrorView({
    required this.message,
    required this.onManualTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.error_outline,
            size: 72,
            color: theme.colorScheme.error,
          ),
          const SizedBox(height: 24),
          Text(
            'Something went wrong',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: () {
              context.read<NewsLocationBloc>().add(
                    const NewsLocationGpsRequested(),
                  );
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Try GPS Again'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onManualTap,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Search Location Manually'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Manual search view — wraps ManualLocationPicker
// ---------------------------------------------------------------------------
class _ManualSearchView extends StatelessWidget {
  final VoidCallback onBack;

  const _ManualSearchView({required this.onBack});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
              ),
              const SizedBox(width: 8),
              Text(
                'Select Location',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Pick your country and city from the list below.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          ManualLocationPicker(
            onLocationSelected: (country, city) {
              context.read<NewsLocationBloc>().add(
                    NewsLocationManualSelected(
                      city: city,
                      country: country,
                    ),
                  );
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// News Feed tab content (extracted from the original body)
// ---------------------------------------------------------------------------
class _NewsFeedTab extends StatelessWidget {
  final ScrollController scrollController;
  final Future<void> Function() onRefresh;
  final void Function(BuildContext, String) onConfirmDelete;

  const _NewsFeedTab({
    required this.scrollController,
    required this.onRefresh,
    required this.onConfirmDelete,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NewsFeedBloc, NewsFeedState>(
      builder: (context, state) {
        if (state.status == NewsFeedStatus.initial ||
            state.status == NewsFeedStatus.loading) {
          return _buildLoadingView();
        }

        if (state.status == NewsFeedStatus.error && state.posts.isEmpty) {
          return _ErrorView(
            message: state.errorMessage ?? 'Failed to load news',
            onRetry: () {
              final loc = context.read<NewsLocationBloc>().state.location;
              if (loc != null) {
                context.read<NewsFeedBloc>().add(NewsFeedLoadRequested(
                      country: loc.country,
                      city: loc.city,
                    ));
              }
            },
          );
        }

        if (state.posts.isEmpty) {
          return _EmptyFeedView(locationLabel: state.locationLabel);
        }

        return _buildFeedList(context, state);
      },
    );
  }

  Widget _buildLoadingView() {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      children: const [
        _NewsCardSkeleton(),
        _NewsCardSkeleton(),
        _NewsCardSkeleton(),
      ],
    );
  }

  Widget _buildFeedList(BuildContext context, NewsFeedState state) {
    final authState = context.read<AuthBloc>().state;
    final currentUserId =
        authState is AuthAuthenticated ? authState.user.id : '';

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        controller: scrollController,
        itemCount: state.posts.length + (state.isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= state.posts.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final post = state.posts[index];
          final isOwn = post.authorId == currentUserId;

          return BlocProvider(
            create: (_) => NewsInteractionCubit(
              repository: getIt<INewsInteractionRepository>(),
            )..loadInteractionInfo(
                postId: post.id,
                userId: currentUserId,
                initialLikeCount: post.likeCount,
                initialCommentCount: post.commentCount,
              ),
            child: NewsPostCard(
              post: post,
              isOwnPost: isOwn,
              onDelete: isOwn
                  ? () => onConfirmDelete(context, post.id)
                  : null,
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty feed view
// ---------------------------------------------------------------------------
class _EmptyFeedView extends StatelessWidget {
  final String locationLabel;

  const _EmptyFeedView({required this.locationLabel});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.newspaper_outlined,
              size: 64,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No local news yet',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              locationLabel.isNotEmpty
                  ? 'There are no news posts in $locationLabel yet.\nBe the first to post!'
                  : 'Be the first to post news in your area!',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.push(Routes.localNewsCreate),
              icon: const Icon(Icons.add),
              label: const Text('Post News'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error view
// ---------------------------------------------------------------------------
class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Simple loading skeleton for news cards
// ---------------------------------------------------------------------------
class _NewsCardSkeleton extends StatelessWidget {
  const _NewsCardSkeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.surfaceContainerHighest;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header skeleton
            Row(
              children: [
                CircleAvatar(radius: 20, backgroundColor: color),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 120,
                      height: 14,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 80,
                      height: 10,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Media skeleton
            Container(
              width: double.infinity,
              height: 200,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 12),
            // Text skeleton
            Container(
              width: double.infinity,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: 200,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
