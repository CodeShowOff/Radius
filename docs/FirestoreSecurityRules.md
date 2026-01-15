# Firestore Security Rules Documentation

This document explains the security rules for the Radius app and their limitations.

## Overview

The security rules protect user data across several collections:
- **User profiles** - Personal data and settings
- **Proximity/Nearby** - Location and discovery data
- **Connections** - Friend relationships
- **Chat** - Conversations and messages

---

## Rule Explanations

### 1. Helper Functions

| Function | Purpose |
|----------|---------|
| `isAuthenticated()` | Verifies user has valid Firebase Auth token |
| `isOwner(userId)` | Checks if authenticated user owns the resource |
| `isBlocked(userId, byUserId)` | Checks if one user blocked another |
| `hasBlockRelationship()` | Checks if either user blocked the other |
| `areConnected()` | Verifies two users have accepted connection |
| `canSendRequest()` | Enforces rate limiting (10/hour, 30/day) |

### 2. User Profiles (`/users/{userId}`)

```
READ:  Own profile always OR (authenticated + not blocked + profile visible)
CREATE: Owner only, must include email/createdAt
UPDATE: Owner only, cannot change email/createdAt/uid
DELETE: Owner only
```

**Why these rules:**
- Users always see their own data
- Others can see profiles unless blocked or set to private
- Immutable fields (email, createdAt) prevent tampering

### 3. Proximity & Nearby (`/ble_id_mappings`, `/proximityBeacons`, `/encounters`)

```
BLE Mappings:
  READ:   Any authenticated user (required for proximity discovery)
  WRITE:  Owner only

Proximity Beacons:
  READ:   Any authenticated user
  WRITE:  Owner only, must include userId/location/timestamp

Encounters:
  READ:   Participants only
  CREATE: Participants only, exactly 2 users
  UPDATE/DELETE: Denied (immutable records)
```

**Why these rules:**
- BLE mappings must be readable for proximity detection to work
- Beacons are public by design (how users are discovered)
- Encounters are audit records - cannot be modified

### 4. Connections (`/connections`, `/connection_requests`)

```
Connections:
  READ:   Participants only
  CREATE: Participant + status='connected' + not blocked
  UPDATE: Participants only, cannot change users/createdAt
  DELETE: Either participant

Connection Requests:
  READ:   Sender or receiver only
  CREATE: Sender + rate limited + not blocked + status='pending'
  UPDATE: Receiver can accept/reject, sender can cancel
  DELETE: Sender (if cancelled) or receiver (if rejected)
```

**Why these rules:**
- Only involved parties see connection data
- Rate limiting prevents spam (10/hour, 30/day)
- Blocking prevents unwanted contact
- Cannot change participants after creation

### 5. Chat (`/conversations`, `/messages`, `/typing`)

```
Conversations:
  READ:   Participants only
  CREATE: Participant + 2 users + users are connected + not blocked
  UPDATE: Participants only, cannot change participantIds/createdAt
  DELETE: Either participant

Messages:
  READ:   Conversation participants only
  CREATE: Participant + sender is auth user + max 5000 chars
  UPDATE: Sender can edit, recipient can only mark read/delivered
  DELETE: Sender only

Typing:
  READ:   Conversation participants only
  WRITE:  Own typing status only
```

**Why these rules:**
- Chat requires existing connection (prevents random messages)
- Only sender can edit/delete their messages
- Recipients can only update read status
- 5000 char limit prevents abuse

### 6. Reports (`/reports`)

```
READ:   Own reports only
CREATE: Authenticated + cannot report self + required fields
UPDATE/DELETE: Denied (admin only)
```

**Why these rules:**
- Users can report bad actors
- Reports are immutable to preserve evidence
- Only admins (via Admin SDK) can process reports

---

## Limitations & Workarounds

### Limitation 1: Nearby User Profile Access
**Problem:** Rules cannot verify if users are truly "nearby" - this requires geospatial calculations that Firestore rules can't perform.

**Workaround:** 
- BLE mappings and beacons are public to authenticated users
- Client-side filters by distance
- Server-side verification via Cloud Functions for sensitive operations

### Limitation 2: Complex Queries
**Problem:** Firestore rules evaluate per-document, not per-query. Can't restrict "list all users where X".

**Workaround:**
- Use compound queries on client
- Implement Cloud Functions for complex filtering
- Denormalize data into user-specific subcollections

### Limitation 3: Rate Limiting Accuracy
**Problem:** Rate limit checks require reading another document (2 reads per operation), increasing costs.

**Workaround:**
- Rate limits stored in user subcollection
- Cloud Functions can implement more sophisticated rate limiting
- Consider Firebase App Check for additional abuse prevention

### Limitation 4: Atomic Connection Creation
**Problem:** Creating a connection requires checking multiple conditions across documents.

**Workaround:**
- Use Cloud Functions for connection acceptance (transaction)
- Client creates connection doc, function validates and finalizes
- Rules provide defense-in-depth

### Limitation 5: No Server-Side Message Filtering
**Problem:** Cannot filter messages by content in rules (e.g., profanity filter).

**Workaround:**
- Use Cloud Functions with `onWrite` trigger
- Implement moderation service
- Client-side filtering as first line

### Limitation 6: Document Size Validation
**Problem:** Cannot check total document size, only individual field sizes.

**Workaround:**
- Set individual field limits (e.g., 5000 chars for messages)
- Use Cloud Functions to validate complex documents
- Client-side validation before write

---

## Recommended Cloud Functions

To complement these rules, implement these Cloud Functions:

```typescript
// 1. Connection acceptance (atomic creation)
exports.acceptConnection = functions.https.onCall(async (data, context) => {
  // Validate, create connection, update request in transaction
});

// 2. Message moderation
exports.moderateMessage = functions.firestore
  .document('conversations/{convId}/messages/{msgId}')
  .onCreate(async (snap, context) => {
    // Check for prohibited content
  });

// 3. Cleanup on user delete
exports.cleanupUserData = functions.auth.user().onDelete(async (user) => {
  // Remove user's data from all collections
});

// 4. Rate limit reset
exports.resetRateLimits = functions.pubsub
  .schedule('every 1 hours')
  .onRun(async (context) => {
    // Reset hourly counters
  });
```

---

## Testing Rules

Test your rules using the Firebase Emulator:

```bash
# Start emulator
firebase emulators:start

# Run security rules tests
firebase emulators:exec "npm test"
```

Example test structure:

```javascript
const { assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');

describe('Chat Rules', () => {
  it('allows participants to read messages', async () => {
    // Setup: Create conversation with user1 and user2
    // Test: user1 reads messages - should succeed
    // Test: user3 reads messages - should fail
  });
});
```

---

## Deployment

```bash
# Deploy rules only
firebase deploy --only firestore:rules

# Deploy with emulator test
firebase emulators:exec "npm test" && firebase deploy --only firestore:rules
```

---

## Security Checklist

- [x] All collections require authentication
- [x] Users can only read their own private data
- [x] Blocked users cannot interact
- [x] Connection required for chat
- [x] Rate limiting on connection requests
- [x] Immutable fields protected
- [x] Message size limited
- [x] Reports are immutable
- [ ] Add Firebase App Check for device verification
- [ ] Implement Cloud Functions for complex validation
- [ ] Add message content moderation
