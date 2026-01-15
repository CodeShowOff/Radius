# Connection System Architecture

## Overview
The connection system enables users to connect with each other through a request-based mutual consent flow. It includes spam prevention, rate limiting, and blocking functionality.

## Firestore Schema

### Collections

#### `connections/{connectionId}`
Stores mutual connections between users.

```
connectionId: {
  userId1: string,        // Alphabetically smaller user ID
  userId2: string,        // Alphabetically larger user ID
  status: string,         // 'connected' | 'blocked' | 'disconnected'
  connectedAt: timestamp,
  updatedAt: timestamp,
  initiatedBy: string,    // User ID who sent original request
  blockedBy: string?,     // User ID who blocked (if status='blocked')
  canMessage: boolean,
  shareLocation: boolean,
  users: [string, string] // Array for querying (denormalized)
}
```

**Connection ID Format:** `{userId1}_{userId2}` where userId1 < userId2 (alphabetically sorted)

#### `connection_requests/{requestId}`
Stores connection requests (pending and historical).

```
requestId: {
  senderId: string,
  receiverId: string,
  status: string,         // 'pending' | 'accepted' | 'rejected' | 'cancelled' | 'expired'
  sentAt: timestamp,
  respondedAt: timestamp?,
  expiresAt: timestamp,   // 7 days from sentAt
  message: string?,       // Optional message
  source: string?,        // 'nearby' | 'search' | 'profile'
  senderDisplayName: string?,
  senderPhotoUrl: string?,
  receiverDisplayName: string?,
  receiverPhotoUrl: string?
}
```

#### `users/{userId}/rate_limits/connection_requests`
Tracks rate limits per user.

```
{
  hourlyCount: number,
  hourlyResetAt: timestamp,
  dailyCount: number,
  dailyResetAt: timestamp,
  lastRequestAt: timestamp
}
```

#### `users/{userId}/blocked_users/{blockedUserId}`
Stores blocked user relationships.

```
{
  blockedAt: timestamp
}
```

### Indexes Required

Create these composite indexes in Firebase Console:

1. **Received requests inbox:**
   - Collection: `connection_requests`
   - Fields: `receiverId` (Ascending), `status` (Ascending), `sentAt` (Descending)

2. **Sent requests:**
   - Collection: `connection_requests`
   - Fields: `senderId` (Ascending), `status` (Ascending), `sentAt` (Descending)

3. **User connections:**
   - Collection: `connections`
   - Fields: `users` (Array Contains), `status` (Ascending), `connectedAt` (Descending)

4. **Duplicate request check:**
   - Collection: `connection_requests`
   - Fields: `senderId` (Ascending), `receiverId` (Ascending), `sentAt` (Descending)

## Connection Flow

### Sending a Request
1. User taps "Connect" on a nearby user or profile
2. App validates:
   - Not self-request
   - Not already connected
   - No pending request exists
   - Not blocked by recipient
   - Rate limits not exceeded (10/hour, 30/day)
   - Cooldown period respected (24h after rejection)
3. Request created with `status: 'pending'`
4. Expires after 7 days if no response

### Accepting a Request
1. Recipient taps "Accept" on received request
2. Transaction:
   - Request status → `accepted`
   - New connection document created
3. Both users now connected

### Rejecting a Request
1. Recipient taps "Decline" on received request
2. Request status → `rejected`
3. Sender cannot send another request for 24 hours

### Cancelling a Request
1. Sender can cancel pending requests
2. Request status → `cancelled`

## Spam Prevention

### Rate Limiting
- **Hourly limit:** 10 requests per hour
- **Daily limit:** 30 requests per day
- Counters reset automatically

### Cooldown Periods
- **Rejection cooldown:** 24 hours before can send to same user again
- **Same user cooldown:** 24 hours between requests to same user

### Request Expiration
- Requests expire after 7 days
- Expired requests cannot be accepted/rejected

## Security Rules

See `firestore.rules` for complete security rules including:
- Authentication requirements
- Participant-only access
- Rate limit enforcement
- Block list checking
- Status transition validation

## Connection States

```dart
enum ConnectionState {
  notConnected,     // No connection or request
  requestSent,      // Current user sent pending request
  requestReceived,  // Current user received pending request
  connected,        // Users are connected
  blocked,          // One user blocked the other
}
```

## UI Components

### ConnectionButton
Adaptive button that shows:
- "Connect" → When not connected
- "Pending" → When request sent
- Accept/Decline → When request received
- "Connected" → When connected
- "Blocked" → When blocked

### ConnectionRequestCard
Card showing request details with:
- User avatar and name
- Optional message
- Source indicator
- Time ago
- Accept/Decline or Cancel buttons

### ConnectionRequestsScreen
Tabbed screen with:
- Received requests tab (with badge count)
- Sent requests tab

### ConnectionsListScreen
List of user's connections with:
- User info
- Connection date
- Menu (Message, Remove, Block)

## Best Practices

1. **Always check connection state** before showing Connect button
2. **Use transactions** for accept/reject to ensure consistency
3. **Denormalize user info** in requests for fast UI rendering
4. **Listen to streams** for real-time updates
5. **Handle errors gracefully** with user-friendly messages
6. **Show loading states** during async operations

## Error Handling

```dart
enum ConnectionErrorType {
  rateLimitExceeded,
  alreadyConnected,
  alreadyPending,
  selfRequest,
  blockedUser,
  requestNotFound,
  unauthorized,
  cooldownActive,
  networkError,
  unknown,
}
```

Each error type has a user-friendly message for display.
