import '../../domain/entities/message.dart';
import '../../../guess_me/domain/entities/guess_me_session.dart';

/// Adapter to convert GuessMe messages to the unified Message format.
/// 
/// This allows GuessMe messages to be displayed using the same chat UI
/// components as regular Connection messages.
/// 
/// IMPORTANT: Handles system messages, guess check messages, and regular chat.
class GuessmeMessageAdapter {
  /// Converts a GuessmeMessage to a Message entity for display.
  /// 
  /// Handles all message types:
  /// - Regular chat messages (from players)
  /// - System messages (game events, shown as 'system')
  /// - Guess check messages (special formatting)
  static Message toMessage(GuessmeMessage guessmeMessage) {
    // System and guess check messages should show for both players
    // Use a special marker to identify them
    final senderId = _getSenderId(guessmeMessage);

    return Message(
      id: guessmeMessage.id,
      conversationId: guessmeMessage.sessionId,
      senderId: senderId,
      text: guessmeMessage.text,
      sentAt: guessmeMessage.sentAt,
      type: MessageType.text,
      status: MessageStatus.sent,
      // GuessMe messages don't have delivery/read tracking
      deliveredAt: null,
      readAt: null,
    );
  }

  /// Determines the sender ID for proper message display.
  static String _getSenderId(GuessmeMessage message) {
    // System messages: show as system (centered, special styling)
    if (message.type == GuessmeMessageType.system) {
      return 'system';
    }
    
    // Guess check messages: show as system (centered, special styling)
    if (message.type == GuessmeMessageType.guessCheck) {
      return 'guesscheck_system';
    }
    
    // Regular messages: show as sent by player
    return message.senderId;
  }

  /// Converts a list of GuessmeMessages to Messages.
  static List<Message> toMessages(List<GuessmeMessage> guessmeMessages) {
    return guessmeMessages.map(toMessage).toList();
  }
}
