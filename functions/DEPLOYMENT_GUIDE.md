# Firebase Cloud Functions Deployment Guide

## Overview
This project now includes 6 Firebase Cloud Functions to handle notifications and automated cleanup tasks.

## Functions Summary

### 1. **onMessageSent** (1-to-1 Chat Notifications)
- **Trigger**: When a new message is created in `chats/{chatId}/messages/{messageId}`
- **Purpose**: Send push notification to recipient in 1-to-1 chats
- **Data**: Includes sender name, message preview, chat ID

### 2. **onGroupMessageNotification** (Group Chat Notifications)
- **Trigger**: When a new message is created in `location_groups/{groupId}/messages/{messageId}`
- **Purpose**: Send push notification to all active group members (except sender)
- **Data**: Includes group name, sender name, message preview, group ID

### 3. **onConnectionRequestReceived** (Connection Request Notifications)
- **Trigger**: When a new connection request is created in `connection_requests/{requestId}`
- **Purpose**: Notify recipient when someone sends a connection request
- **Data**: Includes sender name, request ID

### 4. **onGroupJoinRequestNotification** (Join Request Notifications) ✨ NEW
- **Trigger**: When a join request is created in `location_groups/{groupId}/join_requests/{requestId}`
- **Purpose**: Notify all group admins when someone requests to join a private group
- **Data**: Includes group name, requester name, optional message, group ID, request ID

### 5. **onConnectionRequestAccepted** (Acceptance Notifications) ✨ NEW
- **Trigger**: When a connection request status changes from "pending" to "accepted"
- **Purpose**: Notify the original sender when their connection request is accepted
- **Data**: Includes accepter name, user IDs

### 6. **cleanupExpiredGuessMeSessions** (Scheduled Cleanup) ✨ NEW
- **Schedule**: Daily at 2:00 AM UTC (`0 2 * * *`)
- **Purpose**: Delete GuessMe sessions older than 7 days
- **Collection**: `guess_me_sessions`

### 7. **cleanupOldConnectionRequests** (Scheduled Cleanup) ✨ NEW
- **Schedule**: Daily at 2:30 AM UTC (`30 2 * * *`)
- **Purpose**: 
  - Delete rejected/cancelled connection requests older than 30 days
  - Delete pending connection requests older than 90 days
- **Collection**: `connection_requests`

### 8. **cleanupOldGroupJoinRequests** (Scheduled Cleanup) ✨ NEW
- **Schedule**: Daily at 3:00 AM UTC (`0 3 * * *`)
- **Purpose**:
  - Delete rejected join requests older than 30 days
  - Delete pending join requests older than 60 days
- **Collection**: `location_groups/{groupId}/join_requests`

## Deployment Steps

### Prerequisites
1. Firebase CLI installed: `npm install -g firebase-tools`
2. Logged in to Firebase: `firebase login`
3. Correct Firebase project selected

### Deploy All Functions
```bash
cd functions
npm run build
firebase deploy --only functions
```

### Deploy Specific Functions
```bash
# Deploy only notification functions
firebase deploy --only functions:onGroupJoinRequestNotification,functions:onConnectionRequestAccepted

# Deploy only cleanup functions
firebase deploy --only functions:cleanupExpiredGuessMeSessions,functions:cleanupOldConnectionRequests,functions:cleanupOldGroupJoinRequests
```

### Verify Current Project
```bash
firebase projects:list
firebase use  # Shows current project
```

### Switch Project (if needed)
```bash
firebase use <project-id>
```

## Post-Deployment Verification

### Check Function Deployment
```bash
firebase functions:list
```

### View Function Logs
```bash
# Real-time logs
firebase functions:log

# Specific function logs
firebase functions:log --only onGroupJoinRequestNotification
```

### Test Scheduled Functions Manually
You can trigger scheduled functions manually in the Firebase Console:
1. Go to Firebase Console → Functions
2. Find the scheduled function
3. Click on the three dots → "Execute now"

## Important Notes

### FCM Token Management
All notification functions automatically:
- Clean up invalid FCM tokens when notifications fail
- Support multi-device notifications (one user can have multiple tokens)
- Use proper notification channels for Android (`radius_messages`)

### Scheduled Functions
- Run automatically at specified times (UTC timezone)
- Use batch operations to handle large datasets efficiently (500 documents per batch)
- Log the number of documents deleted for monitoring

### Firestore Indexes
Some queries may require composite indexes. If deployment shows index creation links, click them to create the required indexes.

### Costs
- **Notification functions**: Triggered per document creation/update
- **Scheduled functions**: Run once per day, minimal cost
- Monitor usage in Firebase Console → Usage and Billing

## Troubleshooting

### Build Errors
```bash
cd functions
npm run lint  # Check for linting errors
npm run build # Check for TypeScript errors
```

### Deployment Errors
- Ensure you're on the correct project
- Check that `firebase.json` is properly configured
- Verify Node.js version matches `engines` in `package.json` (18)

### Function Not Triggering
1. Check Firebase Console → Functions → Logs for errors
2. Verify the document path matches the trigger path exactly
3. Ensure Firestore rules allow the operations
4. For scheduled functions, check the execution history in the console

## Monitoring

### View Metrics
- Firebase Console → Functions → Dashboard
- Shows invocations, errors, and execution time

### Set Up Alerts
- Firebase Console → Functions → Health tab
- Configure alerts for high error rates or failures

## Rollback (if needed)
```bash
# List previous deployments
firebase functions:log --only <function-name>

# Delete a specific function
firebase functions:delete <function-name>
```

## Next Steps After Deployment

1. ✅ Test notification delivery with real devices
2. ✅ Monitor function logs for the first 24 hours
3. ✅ Verify scheduled functions run at expected times
4. ✅ Check Firestore for proper data cleanup
5. ✅ Monitor Firebase usage/costs

---
**Last Updated**: Functions deployed with 6 cloud functions (3 notifications + 3 scheduled cleanups)
