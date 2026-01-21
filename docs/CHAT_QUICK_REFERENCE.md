# Quick Reference: Chat System Refactoring

## What Changed?

### GuessMe Game
**Before:** Had its own duplicate chat rendering code  
**After:** Uses shared chat components with anonymous configuration

### Connections
**Before/After:** No changes - still uses its own dedicated chat implementation

## How to Use Shared Components

### For Anonymous Chat (like GuessMe)
```dart
// 1. Create config
final config = ChatConfig.guessMe(
  expiresAt: expiresAt, // Optional expiration time
);

// 2. Convert messages
final messages = GuessmeMessageAdapter.toMessages(guessmeMessages);

// 3. Display messages
SharedMessagesList(
  messages: messages,
  currentUserId: userId,
  config: config,
  scrollController: scrollController,
)

// 4. Handle input
SharedChatInput(
  config: config,
  onSend: (text) => sendMessage(text),
  enabled: true,
)
```

### For Identified Chat (like Connections)
```dart
// 1. Create config
final config = ChatConfig.connections();

// 2. Display messages (already using Message type)
SharedMessagesList(
  messages: messages,
  currentUserId: userId,
  config: config,
  otherUserName: name,
  otherUserPhotoUrl: photoUrl,
  scrollController: scrollController,
)

// 3. Handle input with media support
SharedChatInput(
  config: config,
  onSend: (text) => sendMessage(text),
  onImageSelected: (file) => sendImage(file),
  onDocumentSelected: (file) => sendDocument(file),
  onVoiceRecorded: (file, duration) => sendVoice(file, duration),
  enabled: true,
)
```

## Configuration Options

### ChatDisplayMode
- `anonymous`: Hides names/photos, shows "?" avatar
- `identified`: Shows real names and profile photos

### ChatConfig Properties
- `displayMode`: How participants are shown
- `enableMediaAttachments`: Show media buttons?
- `showTypingIndicator`: Show typing status?
- `showReadReceipts`: Show read status?
- `inputPlaceholder`: Custom input text
- `isTimeLimited`: Has expiration?
- `expiresAt`: When chat expires

## Conversion Flow

### When Both Users Agree to Connect:

```dart
// In GuessMe BLoC
final conversationId = await _service.convertToConnection(
  sessionId: sessionId,
);

// In UI (automatically handled)
if (conversationId != null) {
  // Navigate to permanent chat
  context.push(Routes.chatWith(conversationId), extra: {...});
}
```

### What Gets Created:
1. **Connection Record** (2 docs, one per user)
   - `connections/{user1Id}_{user2Id}`
   - `connections/{user2Id}_{user1Id}`

2. **Conversation Document**
   - `conversations/{deterministic_id}`
   - ID format: `{smallerId}_{largerId}` (sorted)

3. **Stats Update**
   - Both users' `correctGuesses` increment
   - Streaks updated

## File Locations

### New Shared Components
- `lib/features/chat/domain/entities/chat_config.dart`
- `lib/features/chat/presentation/widgets/shared_messages_list.dart`
- `lib/features/chat/presentation/widgets/shared_chat_input.dart`
- `lib/features/chat/data/adapters/guessme_message_adapter.dart`

### Modified Files
- `lib/features/guess_me/presentation/pages/guess_me_game_page.dart` (refactored)
- `lib/features/guess_me/presentation/bloc/guess_me_bloc.dart` (conversion logic)
- `lib/features/guess_me/presentation/bloc/guess_me_state.dart` (added conversationId)
- `lib/features/guess_me/data/guess_me_service.dart` (conversion methods)
- `lib/features/chat/chat.dart` (exports updated)

### Documentation
- `docs/CHAT_REFACTORING.md` (full architecture)
- `docs/CHAT_REFACTORING_SUMMARY.md` (implementation summary)

## Key Methods

### GuessmeService
```dart
// Convert session to permanent connection
Future<String?> convertToConnection({required String sessionId})

// Handle connection confirmation
Future<ConnectionConfirmationResult> respondToConnectionPrompt({
  required String sessionId,
  required String userId,
  required bool wantsToConnect,
})
```

### GuessmeMessageAdapter
```dart
// Convert single message
static Message toMessage(GuessmeMessage guessmeMessage)

// Convert message list
static List<Message> toMessages(List<GuessmeMessage> guessmeMessages)
```

## Common Issues

### Problem: Messages not showing
**Solution**: Ensure you're using `GuessmeMessageAdapter.toMessages()` to convert

### Problem: Media buttons showing in GuessMe
**Solution**: Use `ChatConfig.guessMe()` which sets `enableMediaAttachments: false`

### Problem: Names showing in anonymous mode
**Solution**: Set `displayMode: ChatDisplayMode.anonymous` in config

### Problem: Conversion fails silently
**Solution**: Check logs - method returns `null` on failure with detailed logging

## Testing Checklist

- [ ] GuessMe chat displays anonymously
- [ ] Connections chat shows names/photos
- [ ] GuessMe timer counts down
- [ ] Both users receive connection prompt
- [ ] Accepting creates connection
- [ ] Declining ends game properly
- [ ] Navigation to permanent chat works
- [ ] Original connections chat unchanged
- [ ] Media uploads work in connections
- [ ] No media buttons in GuessMe

## Migration Notes

### Breaking Changes
**None** - This is a pure refactoring with added functionality

### Behavioral Changes
- GuessMe game end now offers "Go to Chat" button if both connected
- Navigation automatically redirects to new permanent chat

### Performance Impact
- Minimal: Message adapter creates lightweight wrappers
- Conversion: One-time cost, creates 3 documents
- No impact on existing connections chat

## Support

For questions or issues:
1. Check `docs/CHAT_REFACTORING.md` for architecture details
2. Review inline code documentation
3. Check Firebase logs for conversion failures
4. Verify user profiles exist before conversion
