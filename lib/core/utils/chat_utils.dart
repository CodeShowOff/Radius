/// Utility functions for chat.
class ChatUtils {
  /// Creates a deterministic channel ID for a 1-to-1 chat.
  static String getDirectMessageChannelId(String userId1, String userId2) {
    final list = [userId1, userId2]..sort();
    return '${list[0]}_${list[1]}';
  }
}
