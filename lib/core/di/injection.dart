import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:injectable/injectable.dart';

import '../services/bluetooth/bluetooth_service.dart';
import '../services/firebase/profile_service.dart';
import '../services/firebase/username_service.dart';
import '../services/firebase/discovery_username_service.dart';
import '../services/presence/presence_service.dart';
import '../services/realtime/realtime_connection_service.dart';
import '../services/realtime/realtime_data_manager.dart';
import '../../features/auth/presentation/bloc/auth_bloc.dart';
import '../../features/posts/data/services/post_service.dart';
import '../../features/posts/data/services/post_media_service.dart';
import '../../features/posts/data/services/media_optimizer.dart';
import '../../features/posts/data/services/post_interaction_service.dart';
import '../../features/posts/data/repositories/post_repository_impl.dart';
import '../../features/posts/data/repositories/post_interaction_repository_impl.dart';
import '../../features/posts/domain/repositories/i_post_repository.dart';
import '../../features/posts/domain/repositories/i_post_interaction_repository.dart';
import '../../features/posts/presentation/bloc/create_post_bloc.dart';
import '../../features/posts/presentation/bloc/post_feed_bloc.dart';
import '../../features/posts/presentation/bloc/user_posts_bloc.dart';
import '../../features/chat/data/chat_cache_service.dart';
import '../../features/chat/data/chat_preload_service.dart';
import '../../features/chat/data/chat_service.dart';
import '../../features/chat/presentation/bloc/conversations_bloc.dart';
import '../../features/connections/data/connection_service.dart';
import '../../features/connections/presentation/bloc/connection_bloc.dart';
import '../../features/connections/presentation/bloc/discovery_bloc.dart';
import '../../features/location_groups/data/group_chat_cache_service.dart';
import '../../features/location_groups/data/group_chat_preload_service.dart';
import '../../features/location_groups/data/group_chat_service.dart';
import '../../features/location_groups/data/group_media_upload_service.dart';
import '../../features/location_groups/data/location_data_service.dart';
import '../../features/location_groups/data/location_group_service.dart';
import '../../features/location_groups/presentation/bloc/group_chat_bloc.dart';
import '../../features/location_groups/presentation/bloc/location_group_bloc.dart';
import '../../features/nearby_groups/data/nearby_group_chat_cache_service.dart';
import '../../features/nearby_groups/data/nearby_group_chat_service.dart';
import '../../features/nearby_groups/data/nearby_group_service.dart';
import '../../features/nearby_groups/presentation/bloc/nearby_group_bloc.dart';
import '../../features/nearby_groups/presentation/bloc/nearby_group_chat_bloc.dart';
import '../../features/nearby_help/data/nearby_help_service.dart';
import '../../features/nearby_help/data/user_location_service.dart';
import '../../features/nearby_help/presentation/bloc/nearby_help_bloc.dart';
import '../../features/random_chat/data/random_chat_cache_service.dart';
import '../../features/random_chat/data/random_chat_service.dart';
import '../../features/random_chat/presentation/bloc/random_chat_bloc.dart';
import '../../features/random_groups/data/random_group_chat_cache_service.dart';
import '../../features/random_groups/data/random_group_chat_preload_service.dart';
import '../../features/random_groups/data/random_group_chat_service.dart';
import '../../features/random_groups/data/random_group_service.dart';
import '../../features/random_groups/presentation/bloc/random_group_bloc.dart';
import '../../features/random_groups/presentation/bloc/random_group_chat_bloc.dart';
import '../../features/profile/data/repositories/profile_repository_impl.dart';
import '../../features/profile/domain/repositories/i_profile_repository.dart';
import '../../features/profile/presentation/bloc/profile_bloc.dart';
import '../../features/proximity/presentation/bloc/nearby_users_bloc.dart';
import '../../features/proximity/proximity_service.dart';
import '../../features/video_chat/data/video_call_service.dart';
import '../../features/video_chat/data/video_chat_profile_service.dart';
import '../../features/video_chat/data/video_chat_settings_service.dart';
import '../../features/video_chat/data/video_match_service.dart';
import '../../features/video_chat/data/webrtc_service.dart';
import '../../features/video_chat/presentation/bloc/video_call_bloc.dart';
import '../../features/video_chat/presentation/bloc/video_chat_lobby_bloc.dart';
import '../../features/video_chat/presentation/bloc/video_match_bloc.dart';
import '../../features/local_news/data/services/geocoding_service.dart';
import '../../features/local_news/data/services/news_interaction_service.dart';
import '../../features/local_news/data/services/news_location_service.dart';
import '../../features/local_news/data/services/news_media_service.dart';
import '../../features/local_news/data/services/news_post_service.dart';
import '../../features/local_news/data/repositories/news_interaction_repository_impl.dart';
import '../../features/local_news/data/repositories/news_post_repository_impl.dart';
import '../../features/local_news/domain/repositories/i_news_interaction_repository.dart';
import '../../features/local_news/domain/repositories/i_news_post_repository.dart';
import '../../features/local_news/presentation/bloc/create_news_post_bloc.dart';
import '../../features/local_news/presentation/bloc/news_feed_bloc.dart';
import '../../features/local_news/presentation/bloc/news_location_bloc.dart';
import '../../features/local_news/presentation/bloc/reels_feed_bloc.dart';
import '../settings/app_settings_store.dart';
import '../theme/theme_cubit.dart';

import 'injection.config.dart';

final getIt = GetIt.instance;

@InjectableInit(
  initializerName: 'init',
  preferRelativeImports: true,
  asExtension: true,
)
Future<void> configureDependencies() {
  // ---------------------------------------------------------------------------
  // Manual registrations
  //
  // This project uses a mix of `injectable`-generated registrations plus
  // plain Dart classes (no @injectable annotations). Those plain classes must
  // be registered here to avoid runtime "not registered inside GetIt" errors.
  // ---------------------------------------------------------------------------

  // RouteObserver for detecting route changes
  if (!getIt.isRegistered<RouteObserver<PageRoute>>()) {
    getIt.registerLazySingleton<RouteObserver<PageRoute>>(() => RouteObserver<PageRoute>());
  }

  if (!getIt.isRegistered<ProfileService>()) {
    getIt.registerLazySingleton<ProfileService>(() => ProfileService());
  }

  if (!getIt.isRegistered<UsernameService>()) {
    getIt.registerLazySingleton<UsernameService>(() => UsernameService());
  }

  if (!getIt.isRegistered<BluetoothService>()) {
    getIt.registerLazySingleton<BluetoothService>(() => BluetoothService());
  }

  if (!getIt.isRegistered<ProximityService>()) {
    getIt.registerLazySingleton<ProximityService>(
      () => ProximityService(
        bluetoothService: getIt<BluetoothService>(),
        usernameService: getIt<UsernameService>(),
        settingsStore: getIt<AppSettingsStore>(),
      ),
    );
  }

  if (!getIt.isRegistered<ConnectionService>()) {
    getIt.registerLazySingleton<ConnectionService>(() => ConnectionService());
  }

  // Discovery username service for username-based user search
  if (!getIt.isRegistered<DiscoveryUsernameService>()) {
    getIt.registerLazySingleton<DiscoveryUsernameService>(
      () => DiscoveryUsernameService(),
    );
  }

  // Real-time connection monitoring service
  if (!getIt.isRegistered<RealtimeConnectionService>()) {
    getIt.registerLazySingleton<RealtimeConnectionService>(
      () => RealtimeConnectionService(),
    );
  }

  // Presence service for online/offline tracking via Firebase RTDB
  if (!getIt.isRegistered<PresenceService>()) {
    getIt.registerLazySingleton<PresenceService>(
      () => PresenceService(),
    );
  }

  if (!getIt.isRegistered<IProfileRepository>()) {
    getIt.registerLazySingleton<IProfileRepository>(
      () => ProfileRepositoryImpl(profileService: getIt<ProfileService>()),
    );
  }

  // Posts feature
  if (!getIt.isRegistered<PostService>()) {
    getIt.registerLazySingleton<PostService>(() => PostService());
  }

  if (!getIt.isRegistered<PostMediaService>()) {
    getIt.registerLazySingleton<PostMediaService>(() => PostMediaService());
  }

  if (!getIt.isRegistered<MediaOptimizer>()) {
    getIt.registerLazySingleton<MediaOptimizer>(() => MediaOptimizer());
  }

  if (!getIt.isRegistered<IPostRepository>()) {
    getIt.registerLazySingleton<IPostRepository>(
      () => PostRepositoryImpl(postService: getIt<PostService>()),
    );
  }

  // Post interactions (likes & comments)
  if (!getIt.isRegistered<PostInteractionService>()) {
    getIt.registerLazySingleton<PostInteractionService>(
      () => PostInteractionService(),
    );
  }

  if (!getIt.isRegistered<IPostInteractionRepository>()) {
    getIt.registerLazySingleton<IPostInteractionRepository>(
      () => PostInteractionRepositoryImpl(
        service: getIt<PostInteractionService>(),
      ),
    );
  }

  // CreatePostBloc — factory (new instance per create-post page)
  if (!getIt.isRegistered<CreatePostBloc>()) {
    getIt.registerFactory<CreatePostBloc>(
      () => CreatePostBloc(
        postRepository: getIt<IPostRepository>(),
        mediaService: getIt<PostMediaService>(),
        mediaOptimizer: getIt<MediaOptimizer>(),
        postService: getIt<PostService>(),
      ),
    );
  }

  // PostFeedBloc — factory (new instance per feed page visit)
  if (!getIt.isRegistered<PostFeedBloc>()) {
    getIt.registerFactory<PostFeedBloc>(
      () => PostFeedBloc(
        postRepository: getIt<IPostRepository>(),
      ),
    );
  }

  // UserPostsBloc — factory (new instance per profile page)
  if (!getIt.isRegistered<UserPostsBloc>()) {
    getIt.registerFactory<UserPostsBloc>(
      () => UserPostsBloc(
        postRepository: getIt<IPostRepository>(),
      ),
    );
  }

  // App settings (Hive-backed when available)
  if (!getIt.isRegistered<AppSettingsStore>()) {
    getIt.registerLazySingleton<AppSettingsStore>(
      () {
        Box<dynamic>? box;
        if (getIt.isRegistered<Box<dynamic>>(instanceName: 'radius_settings')) {
          box = getIt<Box<dynamic>>(instanceName: 'radius_settings');
        }
        return AppSettingsStore(box: box);
      },
    );
  }

  if (!getIt.isRegistered<ThemeCubit>()) {
    getIt.registerLazySingleton<ThemeCubit>(
      () => ThemeCubit(settings: getIt<AppSettingsStore>()),
    );
  }

  // App-wide BLoCs - these must be singletons to maintain persistent real-time streams
  if (!getIt.isRegistered<AuthBloc>()) {
    getIt.registerFactory<AuthBloc>(
      () => AuthBloc(authRepository: getIt()),
    );
  }

  if (!getIt.isRegistered<ConnectionBloc>()) {
    getIt.registerLazySingleton<ConnectionBloc>(
      () => ConnectionBloc(connectionService: getIt()),
    );
  }

  // Discovery BLoC for username-based user search and connection requests
  if (!getIt.isRegistered<DiscoveryBloc>()) {
    getIt.registerLazySingleton<DiscoveryBloc>(
      () => DiscoveryBloc(
        discoveryService: getIt<DiscoveryUsernameService>(),
        connectionService: getIt<ConnectionService>(),
      ),
    );
  }

  if (!getIt.isRegistered<ProfileBloc>()) {
    getIt.registerLazySingleton<ProfileBloc>(
      () => ProfileBloc(profileRepository: getIt()),
    );
  }

  if (!getIt.isRegistered<NearbyUsersBloc>()) {
    getIt.registerFactory<NearbyUsersBloc>(
      () => NearbyUsersBloc(proximityService: getIt()),
    );
  }

  // Location Groups feature
  if (!getIt.isRegistered<LocationDataService>()) {
    getIt.registerLazySingleton<LocationDataService>(() => LocationDataService());
  }

  if (!getIt.isRegistered<LocationGroupService>()) {
    getIt.registerLazySingleton<LocationGroupService>(() => LocationGroupService());
  }

  if (!getIt.isRegistered<GroupChatService>()) {
    getIt.registerLazySingleton<GroupChatService>(() => GroupChatService());
  }

  // Chat cache services - global in-memory caches for instant chat loading
  // NOTE: ChatCacheService is registered via injection.config.dart (ChatModule)
  // with proper Logger injection. Do NOT register it here to avoid duplicates.

  if (!getIt.isRegistered<GroupChatCacheService>()) {
    getIt.registerLazySingleton<GroupChatCacheService>(() => GroupChatCacheService());
  }

  // ChatPreloadService - preloads recent/unread chats on app startup
  // Must be registered before RealTimeDataManager but after getIt.init() for ChatService
  // Registration moved below getIt.init() to ensure ChatService is available

  if (!getIt.isRegistered<GroupMediaUploadService>()) {
    getIt.registerLazySingleton<GroupMediaUploadService>(() => GroupMediaUploadService());
  }

  if (!getIt.isRegistered<LocationGroupBloc>()) {
    getIt.registerLazySingleton<LocationGroupBloc>(
      () => LocationGroupBloc(
        groupService: getIt<LocationGroupService>(),
      ),
    );
  }

  if (!getIt.isRegistered<GroupChatBloc>()) {
    getIt.registerFactory<GroupChatBloc>(
      () => GroupChatBloc(
        chatService: getIt<GroupChatService>(),
        cacheService: getIt<GroupChatCacheService>(),
        mediaUploadService: getIt<GroupMediaUploadService>(),
      ),
    );
  }

  // Nearby Groups feature - Bluetooth-based proximity groups
  if (!getIt.isRegistered<NearbyGroupService>()) {
    getIt.registerLazySingleton<NearbyGroupService>(() => NearbyGroupService());
  }

  if (!getIt.isRegistered<NearbyGroupChatService>()) {
    getIt.registerLazySingleton<NearbyGroupChatService>(() => NearbyGroupChatService());
  }

  if (!getIt.isRegistered<NearbyGroupChatCacheService>()) {
    getIt.registerLazySingleton<NearbyGroupChatCacheService>(() => NearbyGroupChatCacheService());
  }

  if (!getIt.isRegistered<NearbyGroupBloc>()) {
    getIt.registerLazySingleton<NearbyGroupBloc>(
      () => NearbyGroupBloc(
        groupService: getIt<NearbyGroupService>(),
        proximityService: getIt<ProximityService>(),
        bluetoothService: getIt<BluetoothService>(),
      ),
    );
  }

  if (!getIt.isRegistered<NearbyGroupChatBloc>()) {
    getIt.registerFactory<NearbyGroupChatBloc>(
      () => NearbyGroupChatBloc(
        chatService: getIt<NearbyGroupChatService>(),
        cacheService: getIt<NearbyGroupChatCacheService>(),
      ),
    );
  }

  // Random Groups feature - Admin-approved internet-based groups
  if (!getIt.isRegistered<RandomGroupService>()) {
    getIt.registerLazySingleton<RandomGroupService>(() => RandomGroupService());
  }

  if (!getIt.isRegistered<RandomGroupChatService>()) {
    getIt.registerLazySingleton<RandomGroupChatService>(() => RandomGroupChatService());
  }

  if (!getIt.isRegistered<RandomGroupChatCacheService>()) {
    getIt.registerLazySingleton<RandomGroupChatCacheService>(() => RandomGroupChatCacheService());
  }

  if (!getIt.isRegistered<RandomGroupBloc>()) {
    getIt.registerLazySingleton<RandomGroupBloc>(
      () => RandomGroupBloc(
        groupService: getIt<RandomGroupService>(),
        chatService: getIt<RandomGroupChatService>(),
      ),
    );
  }

  if (!getIt.isRegistered<RandomGroupChatBloc>()) {
    getIt.registerFactory<RandomGroupChatBloc>(
      () => RandomGroupChatBloc(
        chatService: getIt<RandomGroupChatService>(),
        cacheService: getIt<RandomGroupChatCacheService>(),
        mediaUploadService: getIt<GroupMediaUploadService>(),
      ),
    );
  }

  // Nearby Help feature
  if (!getIt.isRegistered<NearbyHelpService>()) {
    getIt.registerLazySingleton<NearbyHelpService>(() => NearbyHelpService());
  }

  if (!getIt.isRegistered<UserLocationService>()) {
    getIt.registerLazySingleton<UserLocationService>(() => UserLocationService());
  }

  if (!getIt.isRegistered<NearbyHelpBloc>()) {
    getIt.registerLazySingleton<NearbyHelpBloc>(
      () => NearbyHelpBloc(
        helpService: getIt<NearbyHelpService>(),
        locationService: getIt<UserLocationService>(),
      ),
    );
  }

  // Random Chat feature - daily random user discovery & chat
  if (!getIt.isRegistered<RandomChatService>()) {
    getIt.registerLazySingleton<RandomChatService>(() => RandomChatService());
  }

  if (!getIt.isRegistered<RandomChatCacheService>()) {
    getIt.registerLazySingleton<RandomChatCacheService>(() => RandomChatCacheService());
  }

  if (!getIt.isRegistered<RandomChatBloc>()) {
    getIt.registerLazySingleton<RandomChatBloc>(
      () => RandomChatBloc(
        service: getIt<RandomChatService>(),
        cacheService: getIt<RandomChatCacheService>(),
      ),
    );
  }

  // Video Chat feature — anonymous random video calling
  if (!getIt.isRegistered<VideoChatProfileService>()) {
    getIt.registerLazySingleton<VideoChatProfileService>(
      () => VideoChatProfileService(),
    );
  }

  if (!getIt.isRegistered<VideoChatSettingsService>()) {
    getIt.registerLazySingleton<VideoChatSettingsService>(
      () => VideoChatSettingsService(),
    );
  }

  if (!getIt.isRegistered<VideoCallService>()) {
    getIt.registerLazySingleton<VideoCallService>(
      () => VideoCallService(),
    );
  }

  if (!getIt.isRegistered<VideoMatchService>()) {
    getIt.registerLazySingleton<VideoMatchService>(
      () => VideoMatchService(),
    );
  }

  // WebRtcService is per-call (factory) — each call gets a fresh instance
  if (!getIt.isRegistered<WebRtcService>()) {
    getIt.registerFactory<WebRtcService>(
      () => WebRtcService(),
    );
  }

  if (!getIt.isRegistered<VideoChatLobbyBloc>()) {
    getIt.registerFactory<VideoChatLobbyBloc>(
      () => VideoChatLobbyBloc(
        profileService: getIt<VideoChatProfileService>(),
        settingsService: getIt<VideoChatSettingsService>(),
      ),
    );
  }

  if (!getIt.isRegistered<VideoCallBloc>()) {
    getIt.registerFactory<VideoCallBloc>(
      () => VideoCallBloc(
        callService: getIt<VideoCallService>(),
        webRtcService: getIt<WebRtcService>(),
      ),
    );
  }

  if (!getIt.isRegistered<VideoMatchBloc>()) {
    getIt.registerFactory<VideoMatchBloc>(
      () => VideoMatchBloc(
        matchService: getIt<VideoMatchService>(),
      ),
    );
  }

  // Local News feature
  if (!getIt.isRegistered<GeocodingService>()) {
    getIt.registerLazySingleton<GeocodingService>(() => GeocodingService());
  }
  if (!getIt.isRegistered<NewsLocationService>()) {
    getIt.registerLazySingleton<NewsLocationService>(
      () => NewsLocationService(),
    );
  }
  if (!getIt.isRegistered<NewsPostService>()) {
    getIt.registerLazySingleton<NewsPostService>(() => NewsPostService());
  }
  if (!getIt.isRegistered<NewsMediaService>()) {
    getIt.registerLazySingleton<NewsMediaService>(() => NewsMediaService());
  }
  if (!getIt.isRegistered<NewsInteractionService>()) {
    getIt.registerLazySingleton<NewsInteractionService>(() => NewsInteractionService());
  }
  if (!getIt.isRegistered<INewsPostRepository>()) {
    getIt.registerLazySingleton<INewsPostRepository>(
      () => NewsPostRepositoryImpl(postService: getIt<NewsPostService>()),
    );
  }
  if (!getIt.isRegistered<INewsInteractionRepository>()) {
    getIt.registerLazySingleton<INewsInteractionRepository>(
      () => NewsInteractionRepositoryImpl(service: getIt<NewsInteractionService>()),
    );
  }
  if (!getIt.isRegistered<NewsLocationBloc>()) {
    getIt.registerLazySingleton<NewsLocationBloc>(
      () => NewsLocationBloc(locationService: getIt<NewsLocationService>()),
    );
  }
  if (!getIt.isRegistered<NewsFeedBloc>()) {
    getIt.registerFactory<NewsFeedBloc>(
      () => NewsFeedBloc(repository: getIt<INewsPostRepository>()),
    );
  }
  if (!getIt.isRegistered<ReelsFeedBloc>()) {
    getIt.registerFactory<ReelsFeedBloc>(
      () => ReelsFeedBloc(repository: getIt<INewsPostRepository>()),
    );
  }
  if (!getIt.isRegistered<CreateNewsPostBloc>()) {
    getIt.registerFactory<CreateNewsPostBloc>(
      () => CreateNewsPostBloc(
        repository: getIt<INewsPostRepository>(),
        mediaService: getIt<NewsMediaService>(),
        locationService: getIt<NewsLocationService>(),
        mediaOptimizer: getIt<MediaOptimizer>(),
        newsPostService: getIt<NewsPostService>(),
      ),
    );
  }

  // Run generated registrations last so modules can override defaults if needed.
  getIt.init();

  // ChatPreloadService - preloads recent/unread chats on app startup for instant loading
  // Must be registered after getIt.init() to ensure ChatService and ConversationsBloc are available
  if (!getIt.isRegistered<ChatPreloadService>()) {
    getIt.registerLazySingleton<ChatPreloadService>(
      () => ChatPreloadService(
        chatService: getIt<ChatService>(),
        cacheService: getIt<ChatCacheService>(),
        conversationsBloc: getIt<ConversationsBloc>(),
      ),
    );
  }

  // GroupChatPreloadService - preloads recent group chat messages on app startup
  // Eliminates the "No messages yet" flash when opening group chats
  if (!getIt.isRegistered<GroupChatPreloadService>()) {
    getIt.registerLazySingleton<GroupChatPreloadService>(
      () => GroupChatPreloadService(
        chatService: getIt<GroupChatService>(),
        cacheService: getIt<GroupChatCacheService>(),
        locationGroupBloc: getIt<LocationGroupBloc>(),
      ),
    );
  }

  // RandomGroupChatPreloadService - preloads recent random group chat messages on app startup
  // Eliminates the "No messages yet" flash when opening random group chats
  if (!getIt.isRegistered<RandomGroupChatPreloadService>()) {
    getIt.registerLazySingleton<RandomGroupChatPreloadService>(
      () => RandomGroupChatPreloadService(
        chatService: getIt<RandomGroupChatService>(),
        cacheService: getIt<RandomGroupChatCacheService>(),
        randomGroupBloc: getIt<RandomGroupBloc>(),
      ),
    );
  }

  // Register RealTimeDataManager after all BLoCs are registered
  // This needs to be registered after getIt.init() so that ConversationsBloc is available
  if (!getIt.isRegistered<RealTimeDataManager>()) {
    getIt.registerLazySingleton<RealTimeDataManager>(
      () => RealTimeDataManager(
        connectionService: getIt<RealtimeConnectionService>(),
        presenceService: getIt<PresenceService>(),
        chatPreloadService: getIt<ChatPreloadService>(),
        groupChatPreloadService: getIt<GroupChatPreloadService>(),
        randomGroupChatPreloadService: getIt<RandomGroupChatPreloadService>(),
        connectionBloc: getIt<ConnectionBloc>(),
        discoveryBloc: getIt<DiscoveryBloc>(),
        conversationsBloc: getIt<ConversationsBloc>(),
        locationGroupBloc: getIt<LocationGroupBloc>(),
        nearbyGroupBloc: getIt<NearbyGroupBloc>(),
        randomGroupBloc: getIt<RandomGroupBloc>(),
        profileBloc: getIt<ProfileBloc>(),
      ),
    );
  }

  return Future.value();
}
