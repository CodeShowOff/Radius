import 'package:injectable/injectable.dart';
import 'package:stream_chat_flutter/stream_chat_flutter.dart';

@module
abstract class StreamChatModule {
  @lazySingleton
  StreamChatClient get streamChatClient {
    // Replace with the actual Stream API Key during initialization
    // We instantiate it here so it can be injected globally.
    // The key can be loaded from environment variables if needed.
    return StreamChatClient(
      '9x8t84er452n',
      logLevel: Level.INFO,
    );
  }
}
