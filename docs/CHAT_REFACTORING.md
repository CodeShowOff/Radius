# Chat System Refactoring

## Overview
This document describes the refactored chat system that unifies chat functionality between the GuessMe game and Connections features while maintaining their distinct behaviors.

## Architecture

### Shared Components

#### 1. ChatConfig (`chat/domain/entities/chat_config.dart`)
Configuration class that controls chat behavior and UI:
- **Display Mode**: Anonymous (GuessMe) vs Identified (Connections)
- **Features**: Media attachments, typing indicators, read receipts
- **Lifecycle**: Time-limited vs persistent

#### 2. SharedMessagesList (`chat/presentation/widgets/shared_messages_list.dart`)
Unified message list widget that adapts based on configuration:
- Displays messages with appropriate styling (anonymous/identified)
- Handles empty states, typing indicators, date separators
- Supports message grouping and pagination

#### 3. SharedChatInput (`chat/presentation/widgets/shared_chat_input.dart`)
Configurable input widget:
- Simple text-only input for GuessMe
- Full-featured input with media for Connections
- Respects enabled/disabled states

#### 4. GuessmeMessageAdapter (`chat/data/adapters/guessme_message_adapter.dart`)
Adapter pattern to convert GuessMe messages to standard Message format:
- Enables code reuse across features
- Maintains type safety
- Handles system messages appropriately

## GuessMe Flow

### 1. Anonymous Chat Phase
- Users chat anonymously (no names/photos shown)
- 1-hour time limit enforced via BLoC timer
- Text-only messages

### 2. Guess Check
- User initiates guess check
- Other user confirms/denies
- If correct → Connection Prompt phase

### 3. Connection Prompt Phase
- Both users see prompt asking if they want to connect
- Session state: `awaitingConnectionConfirmations = true`
- Each user responds independently

### 4. Conversion to Permanent Connection
**If both users agree:**
1. `GuessmeService.convertToConnection()` is called
2. Creates bidirectional Connection records
3. Creates persistent Conversation document
4. Updates both users' stats
5. Returns conversation ID
6. UI redirects to new persistent chat

**If either declines or timeout:**
- Session ends normally
- Chat is discarded
- No connection created

## Data Flow

### GuessMe → Connection Conversion

```
GuessMe Session (temporary)
    ↓
Both users agree
    ↓
convertToConnection()
    ├── Create Connection records (bidirectional)
    ├── Create Conversation document
    └── Return conversationId
    ↓
Navigate to permanent chat
```

### Firestore Collections

#### During GuessMe:
- `guess_me_sessions/{sessionId}` - Game state
- `guess_me_messages/{messageId}` - Temporary messages

#### After Conversion:
- `connections/{userId}_{otherUserId}` - Connection record (2 docs)
- `conversations/{conversationId}` - Permanent conversation
- Future messages go to `conversations/{conversationId}/messages/`

## Key Design Decisions

### 1. Adapter Pattern for Messages
Rather than modifying the Message entity, we use an adapter to convert GuessMe messages. This:
- Preserves type safety
- Avoids coupling between features
- Enables independent evolution

### 2. Configuration Over Inheritance
`ChatConfig` uses composition to configure behavior rather than creating separate widget hierarchies:
- Easier to maintain
- Less code duplication
- More flexible

### 3. Idempotent Conversion
`convertToConnection()` is idempotent:
- Checks if conversation already exists
- Safe to retry on failure
- Prevents duplicate connections

### 4. Existing Chat Unaffected
Connections chat continues using its own `_MessagesList`:
- No risk of regression
- Independent evolution paths
- Clean separation of concerns

## Error Handling

### Connection Conversion
- Validates session exists and has both players
- Validates mutual consent confirmed
- Checks user profiles exist
- Handles race conditions via idempotency
- Logs all failures for debugging

### UI Layer
- Displays error messages via SnackBar
- Falls back gracefully on conversion failure
- Provides clear user feedback

## Testing Considerations

### Unit Tests Needed
- [ ] GuessmeMessageAdapter conversion logic
- [ ] ChatConfig factory methods
- [ ] convertToConnection() edge cases

### Integration Tests Needed
- [ ] Full GuessMe → Connection flow
- [ ] Both users accept connection
- [ ] One user declines
- [ ] Session timeout during connection prompt
- [ ] Concurrent conversion attempts

### Manual Test Scenarios
1. Complete game with mutual connection
2. Complete game with declined connection
3. Game timeout before guess
4. Game timeout during connection prompt
5. Network failure during conversion
6. Existing connection between users

## Migration Impact

### Breaking Changes
**None** - This is a refactoring that maintains all existing behavior.

### New Capabilities
- GuessMe chat now uses proven, tested chat components
- Easier to add features to GuessMe chat in future
- Consistent UX between anonymous and identified chats

## Performance Considerations

- Message adapter creates new Message objects (minimal overhead)
- Conversion process batches writes where possible
- Idempotent conversion prevents duplicate work
- Firestore queries use existing indexes

## Future Enhancements

### Potential Improvements
1. **Message Transfer**: Copy GuessMe messages to permanent conversation
2. **Connection Source Tracking**: Show which connections came from GuessMe
3. **Stats Dashboard**: Show GuessMe → Connection conversion rate
4. **Replay Protection**: Prevent users from gaming the system
5. **Cool-down Period**: Prevent spam matching

### Extensibility
The shared chat components can be extended for:
- Group chats
- Broadcast messages
- Temporary event-based chats
- Other game modes
