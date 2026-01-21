/// Configuration for shared chat UI components.
/// 
/// This allows the same chat widget to be used for both:
/// - Connections (persistent, shows profiles)
/// - Guess Me (temporary, anonymous)
class ChatConfig {
  /// Display mode for the chat.
  final ChatDisplayMode displayMode;

  /// Whether to show media attachment buttons.
  final bool enableMediaAttachments;

  /// Whether to show typing indicators.
  final bool showTypingIndicator;

  /// Whether to show read receipts.
  final bool showReadReceipts;

  /// Custom placeholder text for message input.
  final String? inputPlaceholder;

  /// Whether this is a time-limited chat.
  final bool isTimeLimited;

  /// Optional expiration time for time-limited chats.
  final DateTime? expiresAt;

  const ChatConfig({
    this.displayMode = ChatDisplayMode.identified,
    this.enableMediaAttachments = true,
    this.showTypingIndicator = true,
    this.showReadReceipts = true,
    this.inputPlaceholder,
    this.isTimeLimited = false,
    this.expiresAt,
  });

  /// Create config for Connections chat (persistent, identified).
  factory ChatConfig.connections() {
    return const ChatConfig(
      displayMode: ChatDisplayMode.identified,
      enableMediaAttachments: true,
      showTypingIndicator: true,
      showReadReceipts: true,
      isTimeLimited: false,
    );
  }

  /// Create config for Guess Me chat (temporary, anonymous).
  factory ChatConfig.guessMe({DateTime? expiresAt}) {
    return ChatConfig(
      displayMode: ChatDisplayMode.anonymous,
      enableMediaAttachments: false,
      showTypingIndicator: false,
      showReadReceipts: false,
      inputPlaceholder: 'Type a message...',
      isTimeLimited: true,
      expiresAt: expiresAt,
    );
  }

  ChatConfig copyWith({
    ChatDisplayMode? displayMode,
    bool? enableMediaAttachments,
    bool? showTypingIndicator,
    bool? showReadReceipts,
    String? inputPlaceholder,
    bool? isTimeLimited,
    DateTime? expiresAt,
  }) {
    return ChatConfig(
      displayMode: displayMode ?? this.displayMode,
      enableMediaAttachments: enableMediaAttachments ?? this.enableMediaAttachments,
      showTypingIndicator: showTypingIndicator ?? this.showTypingIndicator,
      showReadReceipts: showReadReceipts ?? this.showReadReceipts,
      inputPlaceholder: inputPlaceholder ?? this.inputPlaceholder,
      isTimeLimited: isTimeLimited ?? this.isTimeLimited,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }
}

/// How chat participants are displayed.
enum ChatDisplayMode {
  /// Show real names and profile photos (Connections).
  identified,

  /// Hide names and photos, show anonymous avatars (Guess Me).
  anonymous,
}
