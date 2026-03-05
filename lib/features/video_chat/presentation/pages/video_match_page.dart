import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/video_chat_profile.dart';
import '../bloc/video_match_bloc.dart';

/// Full-screen page shown while searching for a random video partner.
///
/// Displays a pulsing animation and elapsed time. When a match is found,
/// it automatically navigates to the [VideoCallPage] (as caller) or
/// waits for the incoming call (as receiver).
class VideoMatchPage extends StatelessWidget {
  final VideoChatProfile profile;

  const VideoMatchPage({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) {
        final bloc = getIt<VideoMatchBloc>();
        bloc.add(VideoMatchStarted(profile: profile));
        return bloc;
      },
      child: _VideoMatchContent(profile: profile),
    );
  }
}

class _VideoMatchContent extends StatelessWidget {
  final VideoChatProfile profile;

  const _VideoMatchContent({required this.profile});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          context.read<VideoMatchBloc>().add(const VideoMatchCancelled());
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        body: BlocConsumer<VideoMatchBloc, VideoMatchState>(
          listener: (context, state) {
            if (state is VideoMatchFound) {
              _onMatchFound(context, state);
            } else if (state is VideoMatchError) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.message)),
              );
              Navigator.of(context).pop();
            }
          },
          builder: (context, state) {
            return switch (state) {
              VideoMatchSearching(:final elapsed) =>
                _SearchingView(elapsed: elapsed, profile: profile),
              VideoMatchFound() => _MatchFoundView(state: state),
              _ => _SearchingView(
                  elapsed: Duration.zero, profile: profile),
            };
          },
        ),
      ),
    );
  }

  void _onMatchFound(BuildContext context, VideoMatchFound state) {
    if (state.callRole == 'caller') {
      // We initiate the call — navigate to call page.
      // The VideoCallBloc on the call page will handle creating the
      // offer. We pass the matched user info via the route.
      _navigateToCall(context, state);
    } else {
      // We are the receiver — the other user will create the call doc.
      // We need to listen for an incoming call and then navigate.
      // For simplicity, navigate to call page immediately — the
      // VideoCallBloc will handle the incoming flow.
      _navigateToCall(context, state);
    }
  }

  void _navigateToCall(BuildContext context, VideoMatchFound state) {
    // Navigate to the call page and pass all match info via extra.
    // The BlocProvider in the router will create the VideoCallBloc,
    // set the profile, and dispatch the appropriate event (caller
    // or receiver) — ensuring no state transitions are missed.
    context.pushReplacement(
      Routes.videoCall,
      extra: {
        'profile': profile,
        'matchedUserId': state.matchedUserId,
        'matchedName': state.matchedName,
        'matchedPhotoUrl': state.matchedPhotoUrl,
        'callRole': state.callRole,
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Searching Animation View
// ════════════════════════════════════════════════════════════════════════════

class _SearchingView extends StatefulWidget {
  final Duration elapsed;
  final VideoChatProfile profile;

  const _SearchingView({required this.elapsed, required this.profile});

  @override
  State<_SearchingView> createState() => _SearchingViewState();
}

class _SearchingViewState extends State<_SearchingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          children: [
            const Spacer(flex: 2),

            // Pulsing video icon
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _pulseAnimation.value,
                  child: child,
                );
              },
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppTheme.primaryGradient,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.3),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.videocam_rounded,
                  size: 56,
                  color: Colors.white,
                ),
              ),
            ),

            const SizedBox(height: 40),

            Text(
              'Searching...',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 12),

            Text(
              'Looking for someone to chat with.\nThis may take a moment.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: isDark ? Colors.white70 : Colors.black54,
                height: 1.5,
              ),
            ),

            const SizedBox(height: 24),

            // Elapsed time
            Text(
              _formatDuration(widget.elapsed),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),

            const Spacer(flex: 2),

            // Cancel button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: OutlinedButton.icon(
                onPressed: () {
                  context
                      .read<VideoMatchBloc>()
                      .add(const VideoMatchCancelled());
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.close, size: 22),
                label: const Text(
                  'Cancel',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  side: BorderSide(color: theme.colorScheme.error),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),

            const Spacer(flex: 1),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Match Found Transition View
// ════════════════════════════════════════════════════════════════════════════

class _MatchFoundView extends StatelessWidget {
  final VideoMatchFound state;

  const _MatchFoundView({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppTheme.primaryGradient,
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 44,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Match Found!',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Connecting with ${state.matchedName}...',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.brightness == Brightness.dark
                  ? Colors.white70
                  : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}
