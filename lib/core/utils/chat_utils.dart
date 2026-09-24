/// Utility functions for chat.
class ChatUtils {
  /// Creates a deterministic channel ID for a 1-to-1 chat.
  static String getDirectMessageChannelId(String userId1, String userId2) {
    final list = [userId1, userId2]..sort();
    // Append _v2 to bypass any previously corrupted channels that were created
    // without both members before the recent fix.
    return '${list[0]}_${list[1]}_v2';
  }
}
