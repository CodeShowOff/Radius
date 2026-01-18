/// Chat feature barrel file.
///
/// Export all chat-related classes for easy importing.
library;

// Domain entities
export 'domain/entities/message.dart';
export 'domain/entities/conversation.dart';

// Data models
export 'data/models/message_model.dart';
export 'data/models/conversation_model.dart';

// Services
export 'data/chat_service.dart';
export 'data/media_upload_service.dart';

// BLoC
export 'presentation/bloc/chat_bloc.dart';
export 'presentation/bloc/conversations_bloc.dart';

// Screens
export 'presentation/screens/chat_screen.dart';
export 'presentation/screens/conversations_screen.dart';

// Widgets
export 'presentation/widgets/message_bubble.dart';
export 'presentation/widgets/chat_input.dart';
export 'presentation/widgets/media_message_content.dart';
export 'presentation/widgets/voice_recorder_widget.dart';
