import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../bloc/video_chat_lobby_bloc.dart';
import '../widgets/age_gate_view.dart';
import '../widgets/headphones_advisory_view.dart';
import '../widgets/profile_prompt_view.dart';
import '../widgets/profile_setup_view.dart';
import '../widgets/video_lobby_ready_view.dart';

/// Main entry page for the Random Video Chat feature.
///
/// Orchestrates the multi-step onboarding flow:
/// 1. Age gate (18+ confirmation) — first time only
/// 2. Headphones advisory — every session (unless permanently dismissed)
/// 3. Profile setup (new user) / Profile modify prompt (returning user)
/// 4. Ready → show matching lobby
class VideoChatLobbyPage extends StatefulWidget {
  const VideoChatLobbyPage({super.key});

  @override
  State<VideoChatLobbyPage> createState() => _VideoChatLobbyPageState();
}

class _VideoChatLobbyPageState extends State<VideoChatLobbyPage> {
  @override
  void initState() {
    super.initState();
    _enterLobby();
  }

  void _enterLobby() {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      context.read<VideoChatLobbyBloc>().add(
            VideoChatLobbyEntered(userId: authState.user.id),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocBuilder<VideoChatLobbyBloc, VideoChatLobbyState>(
        builder: (context, state) {
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _buildContent(context, state),
          );
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, VideoChatLobbyState state) {
    return switch (state) {
      VideoChatLobbyInitial() => _buildLoading(),
      VideoChatLobbyLoading() => _buildLoading(),
      VideoChatLobbyAgeGate() => AgeGateView(
          key: const ValueKey('age_gate'),
          onConfirmed: () {
            context
                .read<VideoChatLobbyBloc>()
                .add(const VideoChatAgeVerified());
          },
          onBack: () => Navigator.of(context).pop(),
        ),
      VideoChatLobbyHeadphonesAdvisory() => HeadphonesAdvisoryView(
          key: const ValueKey('headphones'),
          onDismissed: (permanently) {
            context.read<VideoChatLobbyBloc>().add(
                  VideoChatHeadphonesDismissed(permanently: permanently),
                );
          },
        ),
      VideoChatLobbyProfileSetup(:final existingProfile, :final isFirstTime) =>
        ProfileSetupView(
          key: const ValueKey('profile_setup'),
          existingProfile: existingProfile,
          isFirstTime: isFirstTime,
          onSave: (name, photoPath) {
            context.read<VideoChatLobbyBloc>().add(
                  VideoChatProfileSaved(
                    displayName: name,
                    photoFilePath: photoPath,
                  ),
                );
          },
          onRemovePhoto: () {
            context
                .read<VideoChatLobbyBloc>()
                .add(const VideoChatProfilePhotoRemoved());
          },
        ),
      VideoChatLobbyProfilePrompt(:final existingProfile) =>
        ProfilePromptView(
          key: const ValueKey('profile_prompt'),
          profile: existingProfile,
          onModify: () {
            context.read<VideoChatLobbyBloc>().add(
                  const VideoChatProfileModifyRequested(),
                );
          },
          onContinue: () {
            context
                .read<VideoChatLobbyBloc>()
                .add(const VideoChatProfileSkipped());
          },
        ),
      VideoChatLobbySavingProfile() => _buildSaving(),
      VideoChatLobbyReady(:final profile) => VideoLobbyReadyView(
          key: const ValueKey('ready'),
          profile: profile,
        ),
      VideoChatLobbyError(:final message) => _buildError(message),
    };
  }

  Widget _buildLoading() {
    return const Center(
      key: ValueKey('loading'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Setting up Video Chat...'),
        ],
      ),
    );
  }

  Widget _buildSaving() {
    return Center(
      key: const ValueKey('saving'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Saving your profile...',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      key: const ValueKey('error'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: AppTheme.errorColor),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _enterLobby,
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}
