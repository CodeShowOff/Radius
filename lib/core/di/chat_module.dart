import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:injectable/injectable.dart';
import 'package:logger/logger.dart';

import '../../features/chat/data/chat_cache_service.dart';
import '../../features/chat/data/chat_service.dart';
import '../../features/chat/data/media_upload_service.dart';
import '../../features/chat/presentation/bloc/chat_bloc.dart';
import '../../features/chat/presentation/bloc/conversations_bloc.dart';

/// Module for providing chat dependencies.
@module
abstract class ChatModule {
  @lazySingleton
  ChatService chatService(FirebaseFirestore firestore, Logger logger) =>
      ChatService(firestore: firestore, logger: logger);

  @lazySingleton
  MediaUploadService mediaUploadService(
          FirebaseStorage storage, Logger logger) =>
      MediaUploadService(storage: storage, logger: logger);

  /// ChatBloc is a factory — each chat screen gets its own instance.
  /// This eliminates race conditions when switching between conversations.
  /// Instant display is still provided by the singleton ChatCacheService.
  @injectable
  ChatBloc chatBloc(
          ChatService chatService, 
          MediaUploadService mediaUploadService,
          ChatCacheService cacheService) =>
      ChatBloc(
        chatService: chatService,
        mediaUploadService: mediaUploadService,
        cacheService: cacheService,
      );

  @lazySingleton
  ConversationsBloc conversationsBloc(ChatService chatService) =>
      ConversationsBloc(chatService: chatService);
}
