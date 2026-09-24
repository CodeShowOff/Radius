import {
  onDocumentCreated, onDocumentDeleted, onDocumentUpdated,
  onSchedule, onCall, HttpsError, logger
} from "./mock";
import * as admin from "firebase-admin";
import { StreamChat } from "stream-chat";

// =============================================================================
// STREAM CHAT - Token Generation
// =============================================================================

export const getStreamToken = onCall(
  {
    enforceAppCheck: false,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be authenticated");
    }

    const apiKey = process.env.STREAM_API_KEY;
    const apiSecret = process.env.STREAM_API_SECRET;

    if (!apiKey || !apiSecret) {
      logger.error("Stream API keys are missing in environment variables.");
      throw new HttpsError("internal", "Stream API keys are missing.");
    }

    try {
      const serverClient = StreamChat.getInstance(apiKey, apiSecret);
      const token = serverClient.createToken(request.auth.uid);
      return { token };
    } catch (error) {
      logger.error("Error generating Stream token:", error);
      throw new HttpsError("internal", "Failed to generate Stream token");
    }
  }
);

// =============================================================================
// STREAM CHAT - Group Membership Sync
// =============================================================================

const syncStreamChannelMembership = async (groupId: string, userId: string, action: "add" | "remove") => {
  const apiKey = process.env.STREAM_API_KEY;
  const apiSecret = process.env.STREAM_API_SECRET;
  if (!apiKey || !apiSecret) {
    logger.error("Stream API keys missing");
    return;
  }
  
  try {
    const serverClient = StreamChat.getInstance(apiKey, apiSecret);
    const channel = serverClient.channel("messaging", groupId);
    
    if (action === "add") {
      // Create channel if it doesn't exist, then add member
      await channel.create();
      await channel.addMembers([userId]);
      logger.log(`Added user ${userId} to Stream channel ${groupId}`);
    } else {
      await channel.removeMembers([userId]);
      logger.log(`Removed user ${userId} from Stream channel ${groupId}`);
    }
  } catch (error) {
    logger.error(`Error syncing membership for ${groupId} (user: ${userId}, action: ${action}):`, error);
  }
};

export const onLocationGroupMemberAdded = onDocumentCreated(
  { document: "location_groups/{groupId}/members/{userId}", region: "asia-south1" },
  async (event) => syncStreamChannelMembership(event.params.groupId, event.params.userId, "add")
);
export const onLocationGroupMemberRemoved = onDocumentDeleted(
  { document: "location_groups/{groupId}/members/{userId}", region: "asia-south1" },
  async (event) => syncStreamChannelMembership(event.params.groupId, event.params.userId, "remove")
);

export const onNearbyGroupMemberAdded = onDocumentCreated(
  { document: "nearby_groups/{groupId}/members/{userId}", region: "asia-south1" },
  async (event) => syncStreamChannelMembership(event.params.groupId, event.params.userId, "add")
);
export const onNearbyGroupMemberRemoved = onDocumentDeleted(
  { document: "nearby_groups/{groupId}/members/{userId}", region: "asia-south1" },
  async (event) => syncStreamChannelMembership(event.params.groupId, event.params.userId, "remove")
);

export const onRandomGroupMemberAdded = onDocumentCreated(
  { document: "random_groups/{groupId}/members/{userId}", region: "asia-south1" },
  async (event) => syncStreamChannelMembership(event.params.groupId, event.params.userId, "add")
);
export const onRandomGroupMemberRemoved = onDocumentDeleted(
  { document: "random_groups/{groupId}/members/{userId}", region: "asia-south1" },
  async (event) => syncStreamChannelMembership(event.params.groupId, event.params.userId, "remove")
);
// =============================================================================
// RANDOM CHAT - Server-Side Suggestion Generation
// =============================================================================

/**
 * Callable Cloud Function that generates daily random chat suggestions.
 *
 * Moves suggestion generation server-side for:
 * - Security: clients can't scrape the entire profiles collection
 * - Performance: Admin SDK has no billing per-read overhead for batch reads
 * - Integrity: selection logic can't be manipulated by modified clients
 *
 * The function:
 * 1. Checks for cached suggestions in the user's profile (returns early if valid)
 * 2. Queries visible profiles in batches (limit 100 per batch, up to 5 batches)
 * 3. Filters out ineligible users (self, saturated, already connected)
 * 4. Applies gender priority logic (opposite gender first)
 * 5. Selects up to 10 users and caches the result
 * 6. Returns the selected user IDs
 *
 * @param data.gender - Optional gender of the calling user for priority matching
 * @returns {suggestedIds: string[], dateKey: string}
 */
export const generateRandomChatSuggestions = onCall(
  {
    // Enforce authentication
    enforceAppCheck: false, // Set to true if App Check is enforced
  },
  async (request) => {
    // 1. Auth check
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be authenticated");
    }

    const currentUserId = request.auth.uid;
    const currentUserGender = (request.data?.gender as string) || null;
    const db = admin.firestore();

    const MAX_DAILY_USERS = 10;
    const BATCH_SIZE = 100;
    const MAX_BATCHES = 5;
    const TARGET_ELIGIBLE = 20;
    const MAX_DAILY_RECEIVED_REQUESTS = 10;

    // Date key in yyyy-MM-dd format (UTC)
    const now = new Date();
    const dateKey = `${now.getFullYear()}-` +
      `${String(now.getMonth() + 1).padStart(2, "0")}-` +
      `${String(now.getDate()).padStart(2, "0")}`;

    try {
      // 2. Check for cached suggestions in user's profile
      const profileDoc = await db.collection("profiles").doc(currentUserId).get();

      if (profileDoc.exists) {
        const profileData = profileDoc.data()!;
        const cachedDate = profileData.randomChatSuggestionsDate as string | undefined;
        const cachedIds = (profileData.randomChatSuggestionIds as string[]) || [];

        if (cachedDate === dateKey && cachedIds.length > 0) {
          logger.log(`Returning ${cachedIds.length} cached suggestions for ${currentUserId}`);
          return {suggestedIds: cachedIds, dateKey};
        }
      }

      // 3. Fetch ineligible user IDs (small, targeted queries)
      const dailyDocPath = `random_chat_daily/${dateKey}`;

      const [saturatedSnapshot, connectedSnapshot] = await Promise.all([
        db.collection(`${dailyDocPath}/user_stats`)
          .where("receivedRequestCount", ">=", MAX_DAILY_RECEIVED_REQUESTS)
          .get(),
        db.collection(`${dailyDocPath}/user_stats`)
          .where("hasActiveConnection", "==", true)
          .get(),
      ]);

      const excludeIds = new Set<string>();
      excludeIds.add(currentUserId);
      saturatedSnapshot.docs.forEach((doc) => excludeIds.add(doc.id));
      connectedSnapshot.docs.forEach((doc) => excludeIds.add(doc.id));

      logger.log(`Exclude set: ${excludeIds.size} IDs ` +
        `(saturated=${saturatedSnapshot.size}, connected=${connectedSnapshot.size})`);

      // 4. Batched profile fetching with isVisible=true and pagination
      interface EligibleUser {
        id: string;
        gender?: string;
      }

      const eligibleUsers: EligibleUser[] = [];
      let lastDoc: admin.firestore.QueryDocumentSnapshot | null = null;
      let totalFetched = 0;

      for (let batch = 0; batch < MAX_BATCHES; batch++) {
        let query: admin.firestore.Query = db.collection("profiles")
          .where("isVisible", "==", true)
          .limit(BATCH_SIZE);

        if (lastDoc) {
          query = query.startAfter(lastDoc);
        }

        const snapshot = await query.get();
        totalFetched += snapshot.size;

        for (const doc of snapshot.docs) {
          if (!excludeIds.has(doc.id)) {
            eligibleUsers.push({
              id: doc.id,
              gender: doc.data().gender as string | undefined,
            });
          }
        }

        logger.log(`Batch ${batch + 1}: fetched ${snapshot.size}, ` +
          `total eligible ${eligibleUsers.length}`);

        if (eligibleUsers.length >= TARGET_ELIGIBLE || snapshot.size < BATCH_SIZE) {
          break;
        }

        lastDoc = snapshot.docs[snapshot.docs.length - 1];
      }

      logger.log(`Batched fetch complete: ${totalFetched} docs read, ` +
        `${eligibleUsers.length} eligible profiles`);

      if (eligibleUsers.length === 0) {
        // Cache empty result
        await db.collection("profiles").doc(currentUserId).update({
          randomChatSuggestionIds: [],
          randomChatSuggestionsDate: dateKey,
        });
        await db.collection(`${dailyDocPath}/suggestions`).doc(currentUserId).set({
          suggestedUserIds: [],
          generatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return {suggestedIds: [], dateKey};
      }

      // 5. Apply gender priority logic
      let selectedUsers: EligibleUser[];

      if (currentUserGender) {
        const oppositeGender = getOppositeGender(currentUserGender);

        const oppositeGenderUsers = eligibleUsers.filter((u) =>
          u.gender?.toLowerCase() === oppositeGender.toLowerCase()
        );
        const otherUsers = eligibleUsers.filter((u) =>
          !u.gender || u.gender.toLowerCase() !== oppositeGender.toLowerCase()
        );

        // Shuffle both arrays
        shuffleArray(oppositeGenderUsers);
        shuffleArray(otherUsers);

        // Take opposite gender first, fill remaining with others
        selectedUsers = oppositeGenderUsers.slice(0, MAX_DAILY_USERS);
        if (selectedUsers.length < MAX_DAILY_USERS) {
          const remaining = MAX_DAILY_USERS - selectedUsers.length;
          selectedUsers.push(...otherUsers.slice(0, remaining));
        }
      } else {
        // No gender set - random selection
        shuffleArray(eligibleUsers);
        selectedUsers = eligibleUsers.slice(0, MAX_DAILY_USERS);
      }

      const suggestedIds = selectedUsers.map((u) => u.id);

      logger.log(`Generated ${suggestedIds.length} suggestions for ${currentUserId}: ` +
        `${suggestedIds.join(", ")}`);

      // 6. Cache in user's profile and daily subcollection
      await Promise.all([
        db.collection("profiles").doc(currentUserId).update({
          randomChatSuggestionIds: suggestedIds,
          randomChatSuggestionsDate: dateKey,
        }),
        db.collection(`${dailyDocPath}/suggestions`).doc(currentUserId).set({
          suggestedUserIds: suggestedIds,
          generatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }),
      ]);

      return {suggestedIds, dateKey};
    } catch (error) {
      logger.error("Error generating random chat suggestions:", error);
      throw new HttpsError("internal", "Failed to generate suggestions");
    }
  }
);

/** Fisher-Yates shuffle (in-place). */
function shuffleArray<T>(array: T[]): void {
  for (let i = array.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [array[i], array[j]] = [array[j], array[i]];
  }
}

/** Returns the opposite gender string. */
function getOppositeGender(gender: string): string {
  switch (gender.toLowerCase()) {
  case "male": return "female";
  case "female": return "male";
  default: return ""; // non-binary or other - no priority
  }
}

/**
 * Send push notification when a connection request is received.
 */
export const onConnectionRequestReceived = onDocumentCreated(
  {
    document: "connection_requests/{requestId}",
    region: "asia-south1",
  },
  async (event) => {
    const request = event.data?.data();
    if (!request) return;

    const recipientId = request.receiverId;
    const senderId = request.senderId;
    const senderName = request.senderDisplayName || "Someone";

    // Get recipient's FCM tokens
    const userDoc = await admin
      .firestore()
      .collection("users")
      .doc(recipientId)
      .get();

    if (!userDoc.exists) {
      logger.log("User not found");
      return null;
    }

    const userData = userDoc.data();
    const fcmTokens = userData?.fcmTokens || {};
    const tokens = Object.keys(fcmTokens);

    if (tokens.length === 0) {
      logger.log("No FCM tokens for user");
      return null;
    }

    // Prepare notification
    const body = request.message
      ? `${senderName}: ${request.message}`
      : `${senderName} wants to connect with you`;

    const payload = {
      notification: {
        title: "New Connection Request",
        body: body,
      },
      data: {
        requestId: event.params.requestId,
        senderId: senderId,
        type: "connection_request",
      },
    };

    // Send to all user's devices
    try {
      const response = await admin.messaging().sendEachForMulticast({
        tokens: tokens,
        notification: payload.notification,
        data: payload.data,
        android: {
          priority: "high",
          notification: {
            channelId: "radius_messages",
            priority: "high",
            sound: "default",
            defaultSound: true,
          },
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              badge: 1,
            },
          },
        },
      });

      logger.log(
        `Sent ${response.successCount} notifications, ${response.failureCount} failures`
      );

      // Remove invalid tokens
      if (response.failureCount > 0) {
        const tokensToRemove: string[] = [];
        response.responses.forEach((resp, idx) => {
          if (!resp.success) {
            tokensToRemove.push(tokens[idx]);
          }
        });

        if (tokensToRemove.length > 0) {
          const updates: Record<string, admin.firestore.FieldValue> = {};
          tokensToRemove.forEach((token) => {
            updates[`fcmTokens.${token}`] = admin.firestore.FieldValue.delete();
          });
          await admin
            .firestore()
            .collection("users")
            .doc(recipientId)
            .update(updates);
        }
      }

      return response;
    } catch (error) {
      logger.error("Error sending notification:", error);
      return null;
    }
  }
);
/**
 * Send push notification to group admins when someone requests to join.
 * Only applies to private groups (requestToJoin visibility).
 */
export const onGroupJoinRequestNotification = onDocumentCreated(
  {
    document: "location_groups/{groupId}/join_requests/{requestId}",
    region: "asia-south1",
  },
  async (event) => {
    const request = event.data?.data();
    if (!request) return;

    const groupId = event.params.groupId;
    const requesterId = request.userId;
    const requesterName = request.userName || "Someone";
    const message = request.message;

    // Get group info
    const groupDoc = await admin
      .firestore()
      .collection("location_groups")
      .doc(groupId)
      .get();

    if (!groupDoc.exists) {
      logger.log("Group not found");
      return null;
    }

    const groupData = groupDoc.data();
    const groupName = groupData?.name || "Group";

    // Get all admin members
    const adminsSnapshot = await admin
      .firestore()
      .collection("location_groups")
      .doc(groupId)
      .collection("members")
      .where("role", "==", "admin")
      .where("status", "==", "active")
      .get();

    if (adminsSnapshot.empty) {
      logger.log("No active admins found");
      return null;
    }

    // Collect all admin tokens
    const allTokens: string[] = [];
    const tokenToUserMap: Map<string, string> = new Map();

    for (const adminDoc of adminsSnapshot.docs) {
      const adminData = adminDoc.data();
      const adminUserId = adminData.userId as string;

      // Get admin's FCM tokens
      const userDoc = await admin
        .firestore()
        .collection("users")
        .doc(adminUserId)
        .get();

      if (!userDoc.exists) continue;

      const userData = userDoc.data();
      const fcmTokens = userData?.fcmTokens || {};
      const tokens = Object.keys(fcmTokens);

      for (const token of tokens) {
        allTokens.push(token);
        tokenToUserMap.set(token, adminUserId);
      }
    }

    if (allTokens.length === 0) {
      logger.log("No FCM tokens for any admins");
      return null;
    }

    // Prepare notification
    const body = message
      ? `${requesterName}: ${message}`
      : `${requesterName} wants to join`;

    const payload = {
      data: {
        groupId: groupId,
        requestId: event.params.requestId,
        requesterId: requesterId,
        type: "group_join_request",
        title: `${groupName} - Join Request`,
        body: body,
      },
    };

    // Send to all admins' devices
    // NOTE: Silent data-only message - no push notification banner for join requests
    // Only updates badge count to avoid notification overload from many join requests
    try {
      const response = await admin.messaging().sendEachForMulticast({
        tokens: allTokens,
        data: payload.data,
        android: {
          priority: "high",
        },
        apns: {
          payload: {
            aps: {
              badge: 1,
              contentAvailable: true,
            },
          },
        },
      });

      logger.log(
        `Join request notification: ${response.successCount} sent, ` +
        `${response.failureCount} failed`
      );

      // Remove invalid tokens
      if (response.failureCount > 0) {
        const invalidTokensByUser: Map<string, string[]> = new Map();

        response.responses.forEach((resp, idx) => {
          if (!resp.success) {
            const token = allTokens[idx];
            const userId = tokenToUserMap.get(token);
            if (userId) {
              if (!invalidTokensByUser.has(userId)) {
                invalidTokensByUser.set(userId, []);
              }
              invalidTokensByUser.get(userId)!.push(token);
            }
          }
        });

        // Remove invalid tokens for each user
        for (const [userId, tokens] of invalidTokensByUser) {
          const updates: Record<string, admin.firestore.FieldValue> = {};
          tokens.forEach((token) => {
            updates[`fcmTokens.${token}`] =
              admin.firestore.FieldValue.delete();
          });
          await admin
            .firestore()
            .collection("users")
            .doc(userId)
            .update(updates);
        }
      }

      return response;
    } catch (error) {
      logger.error("Error sending join request notification:", error);
      return null;
    }
  }
);

/**
 * Send push notification when a user requests to join a random group.
 * Notifies all admins of the group.
 */
export const onRandomGroupJoinRequestNotification = onDocumentCreated(
  {
    document: "random_groups/{groupId}/join_requests/{requestId}",
    region: "asia-south1",
  },
  async (event) => {
    const request = event.data?.data();
    if (!request) return;

    const groupId = event.params.groupId;
    const requesterId = request.requesterId;
    const requesterName = request.requesterUsername || "Someone";
    const message = request.message;

    // Get group info
    const groupDoc = await admin
      .firestore()
      .collection("random_groups")
      .doc(groupId)
      .get();

    if (!groupDoc.exists) {
      logger.log("Random group not found");
      return null;
    }

    const groupData = groupDoc.data();
    const groupName = groupData?.name || "Group";
    const adminIds = (groupData?.adminIds || []) as string[];

    if (adminIds.length === 0) {
      logger.log("No admins found for random group");
      return null;
    }

    // Collect all admin tokens
    const allTokens: string[] = [];
    const tokenToUserMap: Map<string, string> = new Map();

    for (const adminUserId of adminIds) {
      // Get admin's FCM tokens
      const userDoc = await admin
        .firestore()
        .collection("users")
        .doc(adminUserId)
        .get();

      if (!userDoc.exists) continue;

      const userData = userDoc.data();
      const fcmTokens = userData?.fcmTokens || {};
      const tokens = Object.keys(fcmTokens);

      for (const token of tokens) {
        allTokens.push(token);
        tokenToUserMap.set(token, adminUserId);
      }
    }

    if (allTokens.length === 0) {
      logger.log("No FCM tokens for any admins in random group");
      return null;
    }

    // Prepare notification
    const body = message
      ? `${requesterName}: ${message}`
      : `${requesterName} wants to join`;

    const payload = {
      data: {
        groupId: groupId,
        requestId: event.params.requestId,
        requesterId: requesterId,
        type: "random_group_join_request",
        title: `${groupName} - Join Request`,
        body: body,
      },
    };

    // Send to all admins' devices
    // NOTE: Silent data-only message - no push notification banner for join requests
    // Only updates badge count to avoid notification overload from many join requests
    try {
      const response = await admin.messaging().sendEachForMulticast({
        tokens: allTokens,
        data: payload.data,
        android: {
          priority: "high",
        },
        apns: {
          payload: {
            aps: {
              badge: 1,
              contentAvailable: true,
            },
          },
        },
      });

      logger.log(
        `Random group join request notification: ${response.successCount} sent, ` +
        `${response.failureCount} failed`
      );

      // Remove invalid tokens
      if (response.failureCount > 0) {
        const invalidTokensByUser: Map<string, string[]> = new Map();

        response.responses.forEach((resp, idx) => {
          if (!resp.success) {
            const token = allTokens[idx];
            const userId = tokenToUserMap.get(token);
            if (userId) {
              if (!invalidTokensByUser.has(userId)) {
                invalidTokensByUser.set(userId, []);
              }
              invalidTokensByUser.get(userId)!.push(token);
            }
          }
        });

        // Remove invalid tokens for each user
        for (const [userId, tokens] of invalidTokensByUser) {
          const updates: Record<string, admin.firestore.FieldValue> = {};
          tokens.forEach((token) => {
            updates[`fcmTokens.${token}`] =
              admin.firestore.FieldValue.delete();
          });
          await admin
            .firestore()
            .collection("users")
            .doc(userId)
            .update(updates);
        }
      }

      return response;
    } catch (error) {
      logger.error("Error sending random group join request notification:", error);
      return null;
    }
  }
);

/**
 * Send push notification when connection request is accepted.
 * Notifies the original sender.
 */
export const onConnectionRequestAccepted = onDocumentUpdated(
  {
    document: "connection_requests/{requestId}",
    region: "asia-south1",
  },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();

    if (!before || !after) return null;

    // Only trigger when status changes from pending to accepted
    if (before.status !== "pending" || after.status !== "accepted") {
      return null;
    }

    const senderId = after.senderId;
    const accepterName = after.receiverName || "Someone";

    // Get sender's FCM tokens
    const senderDoc = await admin
      .firestore()
      .collection("users")
      .doc(senderId)
      .get();

    if (!senderDoc.exists) {
      logger.log("Sender not found");
      return null;
    }

    const senderData = senderDoc.data();
    const fcmTokens = senderData?.fcmTokens || {};
    const tokens = Object.keys(fcmTokens);

    if (tokens.length === 0) {
      logger.log("No FCM tokens for sender");
      return null;
    }

    // Prepare notification
    const payload = {
      notification: {
        title: "Connection Request Accepted",
        body: `${accepterName} accepted your connection request`,
      },
      data: {
        senderId: senderId,
        receiverId: after.receiverId,
        type: "connection_accepted",
      },
    };

    // Send notification
    try {
      const response = await admin.messaging().sendEachForMulticast({
        tokens: tokens,
        notification: payload.notification,
        data: payload.data,
        android: {
          priority: "high",
          notification: {
            channelId: "radius_messages",
            priority: "high",
            sound: "default",
            defaultSound: true,
          },
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              badge: 1,
            },
          },
        },
      });

      logger.log(
        `Connection accepted notification: ${response.successCount} ` +
        `sent, ${response.failureCount} failed`
      );

      // Remove invalid tokens
      if (response.failureCount > 0) {
        const invalidTokens: string[] = [];
        response.responses.forEach((resp, idx) => {
          if (!resp.success) {
            invalidTokens.push(tokens[idx]);
          }
        });

        if (invalidTokens.length > 0) {
          const updates: Record<string, admin.firestore.FieldValue> = {};
          invalidTokens.forEach((token) => {
            updates[`fcmTokens.${token}`] =
              admin.firestore.FieldValue.delete();
          });
          await admin
            .firestore()
            .collection("users")
            .doc(senderId)
            .update(updates);
        }
      }

      return response;
    } catch (error) {
      logger.error("Error sending connection accepted notification:", error);
      return null;
    }
  }
);

/**
 * Scheduled function to clean up old connection requests.
 * Runs daily at 2:30 AM UTC.
 * Deletes rejected/cancelled requests older than 30 days.
 * Deletes pending requests older than 90 days.
 */
export const cleanupOldConnectionRequests = onSchedule(
  {
    schedule: "30 2 * * *", // Daily at 2:30 AM UTC
    timeZone: "UTC",
  },
  async () => {
    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

    const ninetyDaysAgo = new Date();
    ninetyDaysAgo.setDate(ninetyDaysAgo.getDate() - 90);

    let totalDeleted = 0;

    try {
      // Clean up rejected/cancelled requests older than 30 days
      const oldRejected = await admin
        .firestore()
        .collection("connection_requests")
        .where("status", "in", ["rejected", "cancelled"])
        .where("updatedAt", "<", thirtyDaysAgo)
        .get();

      // Clean up pending requests older than 90 days
      const oldPending = await admin
        .firestore()
        .collection("connection_requests")
        .where("status", "==", "pending")
        .where("createdAt", "<", ninetyDaysAgo)
        .get();

      const allDocs = [...oldRejected.docs, ...oldPending.docs];

      if (allDocs.length === 0) {
        logger.log("No old connection requests to clean up");
        return;
      }

      // Delete in batches
      const batchSize = 500;
      let batch = admin.firestore().batch();
      let count = 0;

      for (const doc of allDocs) {
        batch.delete(doc.ref);
        count++;
        totalDeleted++;

        if (count === batchSize) {
          await batch.commit();
          batch = admin.firestore().batch();
          count = 0;
        }
      }

      // Commit remaining
      if (count > 0) {
        await batch.commit();
      }

      logger.log(
        `Cleaned up ${totalDeleted} old connection requests`
      );
    } catch (error) {
      logger.error("Error cleaning up connection requests:", error);
    }
  }
);

/**
 * Scheduled function to clean up old group join requests.
 * Runs daily at 3:00 AM UTC.
 * Deletes rejected requests older than 30 days.
 * Deletes pending requests older than 60 days.
 */
export const cleanupOldGroupJoinRequests = onSchedule(
  {
    schedule: "0 3 * * *", // Daily at 3 AM UTC
    timeZone: "UTC",
  },
  async () => {
    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

    const sixtyDaysAgo = new Date();
    sixtyDaysAgo.setDate(sixtyDaysAgo.getDate() - 60);

    let totalDeleted = 0;

    try {
      // Get all groups
      const groupsSnapshot = await admin
        .firestore()
        .collection("location_groups")
        .get();

      if (groupsSnapshot.empty) {
        logger.log("No groups found");
        return;
      }

      // Process each group's join requests
      for (const groupDoc of groupsSnapshot.docs) {
        const groupId = groupDoc.id;

        // Clean up rejected requests older than 30 days
        const oldRejected = await admin
          .firestore()
          .collection("location_groups")
          .doc(groupId)
          .collection("join_requests")
          .where("status", "==", "rejected")
          .where("updatedAt", "<", thirtyDaysAgo)
          .get();

        // Clean up pending requests older than 60 days
        const oldPending = await admin
          .firestore()
          .collection("location_groups")
          .doc(groupId)
          .collection("join_requests")
          .where("status", "==", "pending")
          .where("createdAt", "<", sixtyDaysAgo)
          .get();

        const allDocs = [...oldRejected.docs, ...oldPending.docs];

        if (allDocs.length > 0) {
          // Delete in batches
          const batchSize = 500;
          let batch = admin.firestore().batch();
          let count = 0;

          for (const doc of allDocs) {
            batch.delete(doc.ref);
            count++;
            totalDeleted++;

            if (count === batchSize) {
              await batch.commit();
              batch = admin.firestore().batch();
              count = 0;
            }
          }

          // Commit remaining
          if (count > 0) {
            await batch.commit();
          }
        }
      }

      logger.log(
        `Cleaned up ${totalDeleted} old group join requests`
      );
    } catch (error) {
      logger.error("Error cleaning up group join requests:", error);
    }
  }
);

// ============================================================================
// NEARBY HELP FUNCTIONS
// ============================================================================

/**
 * Callable Cloud Function that finds nearby helpers server-side.
 *
 * This replaces the client-side findNearbyHelpers() that would leak all
 * opted-in users' home/work GPS coordinates. Distance filtering now happens
 * entirely on the server — the client never sees other users' coordinates.
 *
 * @param data.latitude - Seeker's latitude
 * @param data.longitude - Seeker's longitude
 * @param data.radiusMeters - Search radius in meters (must be one of 50, 100, 500, 1000, 2000)
 * @returns {userIds: string[]} - IDs of nearby users (no location data)
 */
export const findNearbyHelpers = onCall(
  {
    enforceAppCheck: false,
  },
  async (request) => {
    // 1. Auth check
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be authenticated");
    }

    const currentUserId = request.auth.uid;
    const latitude = request.data?.latitude as number | undefined;
    const longitude = request.data?.longitude as number | undefined;
    const radiusMeters = request.data?.radiusMeters as number | undefined;

    // 2. Validate inputs
    if (latitude == null || longitude == null || radiusMeters == null) {
      throw new HttpsError(
        "invalid-argument",
        "latitude, longitude, and radiusMeters are required"
      );
    }

    if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
      throw new HttpsError("invalid-argument", "Invalid coordinates");
    }

    const allowedRadii = [50, 100, 500, 1000, 2000];
    if (!allowedRadii.includes(radiusMeters)) {
      throw new HttpsError(
        "invalid-argument",
        `radiusMeters must be one of: ${allowedRadii.join(", ")}`
      );
    }

    const db = admin.firestore();

    try {
      // 3. Query all users (Admin SDK bypasses security rules)
      const usersSnapshot = await db.collection("users").get();

      const nearbyUserIds: string[] = [];

      for (const userDoc of usersSnapshot.docs) {
        const userId = userDoc.id;

        // Skip the requesting user
        if (userId === currentUserId) continue;

        const userData = userDoc.data();

        // Check opt-out: only skip if explicitly set to false
        const helpSettings = userData?.nearbyHelpSettings;
        if (helpSettings?.receiveHelpAlerts === false) {
          continue;
        }

        // Get user's saved locations
        const locationsSnapshot = await db
          .collection("users")
          .doc(userId)
          .collection("locations")
          .where("isActive", "!=", false)
          .get();

        if (locationsSnapshot.empty) continue;

        // Check each location for proximity
        for (const locationDoc of locationsSnapshot.docs) {
          const location = locationDoc.data();
          const userLat = location.latitude;
          const userLon = location.longitude;

          if (userLat == null || userLon == null) continue;

          const distance = calculateDistance(latitude, longitude, userLat, userLon);

          if (distance <= radiusMeters) {
            nearbyUserIds.push(userId);
            break; // User matched, no need to check other locations
          }
        }
      }

      logger.log(
        `findNearbyHelpers: found ${nearbyUserIds.length} nearby users ` +
        `within ${radiusMeters}m for user ${currentUserId}`
      );

      return {userIds: nearbyUserIds};
    } catch (error) {
      logger.error("Error in findNearbyHelpers:", error);
      throw new HttpsError("internal", "Failed to find nearby helpers");
    }
  }
);

/**
 * Calculate distance between two points using Haversine formula.
 * Returns distance in meters.
 */
function calculateDistance(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number
): number {
  const R = 6371000; // Earth's radius in meters
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLon = ((lon2 - lon1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

/**
 * Get approximate distance string for privacy (before helper accepts).
 */
function getApproximateDistance(distanceMeters: number): string {
  if (distanceMeters < 50) return "Very close (~50m)";
  if (distanceMeters < 100) return "Nearby (~100m)";
  if (distanceMeters < 250) return "Within 250m";
  if (distanceMeters < 500) return "Within 500m";
  if (distanceMeters < 1000) return "Within 1km";
  if (distanceMeters < 2000) return "Within 2km";
  return "Over 2km away";
}

/**
 * Send push notification when a new help request is created.
 * Notifies nearby users who have help alerts enabled.
 * 
 * CRITICAL FIX: The previous query used "!=" which excluded users without the field.
 * Now we query ALL users who have saved locations and check settings manually.
 * Users default to receiving alerts unless they explicitly opted out.
 */
export const onHelpRequestCreated = onDocumentCreated(
  {
    document: "help_requests/{requestId}",
    region: "asia-south1",
  },
  async (event) => {
    const helpRequest = event.data?.data();
    if (!helpRequest) return;

    const requestId = event.params.requestId;
    const seekerId = helpRequest.seekerUserId;
    const radiusMeters = helpRequest.radius || 100;
    const seekerLat = helpRequest.latitude;
    const seekerLon = helpRequest.longitude;
    const topic = helpRequest.topic || "General help";

    logger.log(`New help request created: ${requestId} with radius ${radiusMeters}m`);
    logger.log(`Seeker location: lat=${seekerLat}, lon=${seekerLon}`);

    try {
      // CRITICAL FIX: Query ALL users with FCM tokens instead of filtering by settings.
      // The previous query with "!=" excluded users who never set nearbyHelpSettings,
      // which means new users with default settings (receiveHelpAlerts=true) were missed.
      // 
      // Now we get all users and filter in code, which ensures:
      // 1. Users who never set settings (default to true) are included
      // 2. Users who explicitly set receiveHelpAlerts=true are included
      // 3. Only users who explicitly set receiveHelpAlerts=false are excluded
      const usersSnapshot = await admin
        .firestore()
        .collection("users")
        .get();

      const tokensToNotify: {token: string; userId: string; distance: number}[] = [];
      let usersChecked = 0;
      let usersWithLocations = 0;
      let usersWithTokens = 0;
      let usersOptedOut = 0;

      for (const userDoc of usersSnapshot.docs) {
        const userId = userDoc.id;
        usersChecked++;
        
        // Skip the seeker themselves
        if (userId === seekerId) continue;

        const userData = userDoc.data();

        // CRITICAL FIX: Check if user has EXPLICITLY opted out of help alerts.
        // Default behavior: if nearbyHelpSettings doesn't exist OR receiveHelpAlerts
        // is undefined/null, the user SHOULD receive alerts (opt-out model, not opt-in).
        const helpSettings = userData?.nearbyHelpSettings;
        if (helpSettings?.receiveHelpAlerts === false) {
          usersOptedOut++;
          logger.log(`User ${userId} explicitly opted out of help alerts`);
          continue;
        }
        
        // Check if user has FCM tokens
        const fcmTokens = userData?.fcmTokens || {};
        const tokens = Object.keys(fcmTokens);
        if (tokens.length === 0) {
          continue;
        }
        usersWithTokens++;

        // Get user's locations (home/work)
        const locationsSnapshot = await admin
          .firestore()
          .collection("users")
          .doc(userId)
          .collection("locations")
          .get();

        if (locationsSnapshot.empty) {
          continue;
        }
        usersWithLocations++;

        // Check each location for proximity
        let userMatched = false;
        for (const locationDoc of locationsSnapshot.docs) {
          const location = locationDoc.data();
          
          // CRITICAL FIX: Only skip if isActive is EXPLICITLY false.
          // If isActive is undefined/null/true, include this location.
          // Previous code: `if (location.isActive === false)` was correct,
          // but we need to also handle missing isActive field gracefully.
          if (location.isActive === false) {
            logger.log(`User ${userId} location ${locationDoc.id} is inactive, skipping`);
            continue;
          }

          const userLat = location.latitude;
          const userLon = location.longitude;
          
          if (userLat == null || userLon == null) {
            logger.log(`User ${userId} location ${locationDoc.id} has invalid coords`);
            continue;
          }

          const distance = calculateDistance(seekerLat, seekerLon, userLat, userLon);
          
          logger.log(
            `User ${userId} location ${locationDoc.id}: ` +
            `distance=${distance.toFixed(2)}m, radius=${radiusMeters}m`
          );

          // Check if within radius
          if (distance <= radiusMeters) {
            // Add all tokens for this user
            for (const token of tokens) {
              tokensToNotify.push({token, userId, distance});
            }
            userMatched = true;
            logger.log(`User ${userId} is within radius! Adding ${tokens.length} token(s)`);
            // Only count user once (break after first matching location)
            break;
          }
        }
        
        if (!userMatched) {
          logger.log(`User ${userId} has locations but none within ${radiusMeters}m radius`);
        }
      }

      logger.log(
        `Stats: checked=${usersChecked}, withTokens=${usersWithTokens}, ` +
        `withLocations=${usersWithLocations}, optedOut=${usersOptedOut}`
      );

      if (tokensToNotify.length === 0) {
        logger.log("No nearby users found for help request - this could indicate:");
        logger.log("1. No users have saved locations within the radius");
        logger.log("2. All nearby users have opted out of help alerts");
        logger.log("3. Nearby users don't have FCM tokens (not logged in)");
        return null;
      }

      const uniqueUserCount = [...new Set(tokensToNotify.map(t => t.userId))].length;
      logger.log(
        `Found ${tokensToNotify.length} tokens to notify from ` +
        `${uniqueUserCount} users`
      );

      // Get seeker's name - prefer the name stored in the request, fallback to user document
      let seekerName = helpRequest.seekerName;
      if (!seekerName) {
        const seekerDoc = await admin
          .firestore()
          .collection("users")
          .doc(seekerId)
          .get();
        seekerName = seekerDoc.data()?.displayName || "Someone nearby";
      }

      // Group tokens by user and send with approximate distance
      const uniqueUsers = [...new Set(tokensToNotify.map(t => t.userId))];
      
      for (const userId of uniqueUsers) {
        const userTokens = tokensToNotify.filter(t => t.userId === userId);
        const minDistance = Math.min(...userTokens.map(t => t.distance));
        const approximateDistance = getApproximateDistance(minDistance);

        const payload = {
          notification: {
            title: "🆘 Nearby Help Request",
            body: `${seekerName} needs help with: ${topic}. ${approximateDistance}`,
          },
          data: {
            type: "nearby_help_request",
            requestId: requestId,
            seekerId: seekerId,
            topic: topic,
            approximateDistance: approximateDistance,
          },
        };

        const tokens = userTokens.map(t => t.token);

        try {
          const response = await admin.messaging().sendEachForMulticast({
            tokens: tokens,
            notification: payload.notification,
            data: payload.data,
            android: {
              priority: "high",
              notification: {
                channelId: "radius_nearby_help",
                priority: "high",
                sound: "default",
                defaultSound: true,
                tag: `nearby_help_${requestId}`, // Group notifications
              },
            },
            apns: {
              payload: {
                aps: {
                  sound: "default",
                  badge: 1,
                  threadId: "nearby_help",
                },
              },
            },
          });

          logger.log(
            `User ${userId}: Sent ${response.successCount}, Failed ${response.failureCount}`
          );

          // Remove invalid tokens
          if (response.failureCount > 0) {
            const tokensToRemove: string[] = [];
            response.responses.forEach((resp, idx) => {
              if (!resp.success) {
                tokensToRemove.push(tokens[idx]);
              }
            });

            if (tokensToRemove.length > 0) {
              const updates: Record<string, admin.firestore.FieldValue> = {};
              tokensToRemove.forEach((token) => {
                updates[`fcmTokens.${token}`] = admin.firestore.FieldValue.delete();
              });
              await admin
                .firestore()
                .collection("users")
                .doc(userId)
                .update(updates);
            }
          }
        } catch (error) {
          logger.error(`Error sending to user ${userId}:`, error);
        }
      }

      // Update the request with notification count and notified user IDs.
      // notifiedUserIds is used by client queries to scope request visibility:
      // only server-verified nearby users can discover this request via browsing.
      await admin
        .firestore()
        .collection("help_requests")
        .doc(requestId)
        .update({
          notifiedUserIds: uniqueUsers,
          notifiedUsersCount: uniqueUsers.length,
          notifiedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

      return {notifiedUsers: uniqueUsers.length};
    } catch (error) {
      logger.error("Error in onHelpRequestCreated:", error);
      return null;
    }
  }
);

/**
 * Send push notification when a helper is assigned to a request.
 * Notifies the seeker that help is on the way.
 */
export const onHelpRequestAssigned = onDocumentUpdated(
  {
    document: "help_requests/{requestId}",
    region: "asia-south1",
  },
  async (event) => {
    const beforeData = event.data?.before.data();
    const afterData = event.data?.after.data();
    
    if (!beforeData || !afterData) return;

    // Check if status changed to IN_PROGRESS (helper assigned)
    if (beforeData.status !== "IN_PROGRESS" && afterData.status === "IN_PROGRESS") {
      const requestId = event.params.requestId;
      const seekerId = afterData.seekerUserId;
      const helperId = afterData.helperUserId;

      if (!helperId) {
        logger.log("No helper ID in assigned request");
        return null;
      }

      logger.log(`Help request ${requestId} assigned to helper ${helperId}`);

      try {
        // Get helper's name
        const helperDoc = await admin
          .firestore()
          .collection("users")
          .doc(helperId)
          .get();
        const helperName = helperDoc.data()?.displayName || "A helper";

        // Get seeker's FCM tokens
        const seekerDoc = await admin
          .firestore()
          .collection("users")
          .doc(seekerId)
          .get();

        if (!seekerDoc.exists) {
          logger.log("Seeker not found");
          return null;
        }

        const seekerData = seekerDoc.data();
        const fcmTokens = seekerData?.fcmTokens || {};
        const tokens = Object.keys(fcmTokens);

        if (tokens.length === 0) {
          logger.log("No FCM tokens for seeker");
          return null;
        }

        const payload = {
          notification: {
            title: "Help is on the way!",
            body: `${helperName} is coming to help you`,
          },
          data: {
            type: "nearby_help_assigned",
            requestId: requestId,
            helperId: helperId,
            helperName: helperName,
          },
        };

        const response = await admin.messaging().sendEachForMulticast({
          tokens: tokens,
          notification: payload.notification,
          data: payload.data,
          android: {
            priority: "high",
            notification: {
              channelId: "radius_nearby_help",
              priority: "high",
              sound: "default",
              defaultSound: true,
            },
          },
          apns: {
            payload: {
              aps: {
                sound: "default",
                badge: 1,
              },
            },
          },
        });

        logger.log(
          `Seeker notification: Sent ${response.successCount}, Failed ${response.failureCount}`
        );

        // Remove invalid tokens
        if (response.failureCount > 0) {
          const tokensToRemove: string[] = [];
          response.responses.forEach((resp, idx) => {
            if (!resp.success) {
              tokensToRemove.push(tokens[idx]);
            }
          });

          if (tokensToRemove.length > 0) {
            const updates: Record<string, admin.firestore.FieldValue> = {};
            tokensToRemove.forEach((token) => {
              updates[`fcmTokens.${token}`] = admin.firestore.FieldValue.delete();
            });
            await admin
              .firestore()
              .collection("users")
              .doc(seekerId)
              .update(updates);
          }
        }

        return response;
      } catch (error) {
        logger.error("Error in onHelpRequestAssigned:", error);
        return null;
      }
    }

    // Check if status changed to RESOLVED (help completed)
    if (beforeData.status !== "RESOLVED" && afterData.status === "RESOLVED") {
      const requestId = event.params.requestId;
      const seekerId = afterData.seekerUserId;
      const helperId = afterData.helperUserId;
      const completedBy = afterData.completedBy;

      logger.log(`Help request ${requestId} completed by ${completedBy}`);

      try {
        // Notify the other party
        const notifyUserId = completedBy === seekerId ? helperId : seekerId;
        
        if (!notifyUserId) {
          logger.log("No user to notify");
          return null;
        }

        const userDoc = await admin
          .firestore()
          .collection("users")
          .doc(notifyUserId)
          .get();

        if (!userDoc.exists) {
          logger.log("User to notify not found");
          return null;
        }

        const userData = userDoc.data();
        const fcmTokens = userData?.fcmTokens || {};
        const tokens = Object.keys(fcmTokens);

        if (tokens.length === 0) {
          logger.log("No FCM tokens for user to notify");
          return null;
        }

        const isSeeker = notifyUserId === seekerId;
        const payload = {
          notification: {
            title: "Help Request Completed",
            body: isSeeker 
              ? "Your helper marked the request as completed"
              : "The requester confirmed help was received",
          },
          data: {
            type: "nearby_help_completed",
            requestId: requestId,
          },
        };

        const response = await admin.messaging().sendEachForMulticast({
          tokens: tokens,
          notification: payload.notification,
          data: payload.data,
          android: {
            priority: "high",
            notification: {
              channelId: "radius_nearby_help",
              priority: "default",
              sound: "default",
            },
          },
          apns: {
            payload: {
              aps: {
                sound: "default",
              },
            },
          },
        });

        logger.log(
          `Completion notification: Sent ${response.successCount}, Failed ${response.failureCount}`
        );

        return response;
      } catch (error) {
        logger.error("Error sending completion notification:", error);
        return null;
      }
    }

    // Check if status changed to CANCELLED
    if (beforeData.status !== "CANCELLED" && afterData.status === "CANCELLED") {
      const requestId = event.params.requestId;
      const helperId = afterData.helperUserId;
      const cancelledBy = afterData.cancelledBy;

      // Only notify helper if request was assigned and cancelled by seeker
      if (!helperId || cancelledBy === helperId) {
        return null;
      }

      logger.log(`Help request ${requestId} cancelled, notifying helper`);

      try {
        const helperDoc = await admin
          .firestore()
          .collection("users")
          .doc(helperId)
          .get();

        if (!helperDoc.exists) {
          return null;
        }

        const helperData = helperDoc.data();
        const fcmTokens = helperData?.fcmTokens || {};
        const tokens = Object.keys(fcmTokens);

        if (tokens.length === 0) {
          return null;
        }

        const payload = {
          notification: {
            title: "Help Request Cancelled",
            body: "The requester cancelled their help request",
          },
          data: {
            type: "nearby_help_cancelled",
            requestId: requestId,
          },
        };

        const response = await admin.messaging().sendEachForMulticast({
          tokens: tokens,
          notification: payload.notification,
          data: payload.data,
          android: {
            priority: "high",
            notification: {
              channelId: "radius_nearby_help",
              priority: "default",
            },
          },
          apns: {
            payload: {
              aps: {
                sound: "default",
              },
            },
          },
        });

        return response;
      } catch (error) {
        logger.error("Error sending cancellation notification:", error);
        return null;
      }
    }

    return null;
  }
);

/**
 * Scheduled function to expire old help requests.
 * Runs every 10 minutes to check for requests that have passed their expiresAt time.
 */
export const expireOldHelpRequests = onSchedule(
  "every 10 minutes",
  async () => {
    const now = admin.firestore.Timestamp.now();

    logger.log("Checking for expired help requests...");

    try {
      // Find open requests that have passed their expiration time
      const expiredRequests = await admin
        .firestore()
        .collection("help_requests")
        .where("status", "==", "OPEN")
        .where("expiresAt", "<", now)
        .get();

      if (expiredRequests.empty) {
        logger.log("No expired requests found");
        return;
      }

      logger.log(`Found ${expiredRequests.size} expired requests`);

      // Update each to EXPIRED status
      const batch = admin.firestore().batch();
      expiredRequests.docs.forEach((doc) => {
        batch.update(doc.ref, {
          status: "EXPIRED",
          expiredAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      });

      await batch.commit();

      // Notify seekers about expiration
      for (const doc of expiredRequests.docs) {
        const request = doc.data();
        const seekerId = request.seekerUserId;

        try {
          const seekerDoc = await admin
            .firestore()
            .collection("users")
            .doc(seekerId)
            .get();

          if (!seekerDoc.exists) continue;

          const seekerData = seekerDoc.data();
          const fcmTokens = seekerData?.fcmTokens || {};
          const tokens = Object.keys(fcmTokens);

          if (tokens.length === 0) continue;

          await admin.messaging().sendEachForMulticast({
            tokens: tokens,
            notification: {
              title: "Help Request Expired",
              body: "Your help request has expired. You can create a new one if needed.",
            },
            data: {
              type: "nearby_help_expired",
              requestId: doc.id,
            },
            android: {
              notification: {
                channelId: "radius_nearby_help",
              },
            },
          });
        } catch (error) {
          logger.error(`Error notifying seeker ${seekerId}:`, error);
        }
      }

      logger.log(`Expired ${expiredRequests.size} help requests`);
    } catch (error) {
      logger.error("Error expiring help requests:", error);
    }
  }
);

// =============================================================================
// RANDOM CHAT - Daily Reset & Cleanup
// =============================================================================

/**
 * Scheduled function that runs at midnight every day to clean up
 * yesterday's random chat data.
 *
 * This ensures:
 * - All active connections are removed
 * - All pending requests are expired
 * - Daily received/sent request counts are reset
 * - Suggested user lists are cleared
 *
 * We keep old date data for 2 days as a safety buffer, then delete.
 */
export const randomChatDailyReset = onSchedule(
  {
    schedule: "0 0 * * *", // Every day at midnight (UTC)
    timeZone: "UTC",
    retryCount: 3,
  },
  async () => {
    logger.log("Running Random Chat daily reset...");

    const db = admin.firestore();

    try {
      // Calculate date keys
      const now = new Date();
      // Clean up data from 2 days ago (keep yesterday for safety)
      const twoDaysAgo = new Date(now);
      twoDaysAgo.setDate(twoDaysAgo.getDate() - 2);

      const oldDateKey = `${twoDaysAgo.getFullYear()}-` +
        `${String(twoDaysAgo.getMonth() + 1).padStart(2, "0")}-` +
        `${String(twoDaysAgo.getDate()).padStart(2, "0")}`;

      logger.log(`Cleaning up random chat data for date: ${oldDateKey}`);

      const dailyDocRef = db.collection("random_chat_daily").doc(oldDateKey);

      // Delete all subcollections
      const subcollections = ["suggestions", "requests", "connections", "user_stats"];

      for (const subcol of subcollections) {
        const colRef = dailyDocRef.collection(subcol);
        let deleted = 0;

        // Delete in batches of 500
        let snapshot = await colRef.limit(500).get();

        while (!snapshot.empty) {
          const batch = db.batch();
          snapshot.docs.forEach((doc) => {
            batch.delete(doc.ref);
          });
          await batch.commit();
          deleted += snapshot.size;
          snapshot = await colRef.limit(500).get();
        }

        logger.log(`Deleted ${deleted} docs from ${subcol} for ${oldDateKey}`);
      }

      // Also expire any pending requests from yesterday that weren't handled
      const yesterday = new Date(now);
      yesterday.setDate(yesterday.getDate() - 1);
      const yesterdayKey = `${yesterday.getFullYear()}-` +
        `${String(yesterday.getMonth() + 1).padStart(2, "0")}-` +
        `${String(yesterday.getDate()).padStart(2, "0")}`;

      const yesterdayRequests = await db
        .collection("random_chat_daily")
        .doc(yesterdayKey)
        .collection("requests")
        .where("status", "==", "pending")
        .get();

      if (!yesterdayRequests.empty) {
        // Chunk into batches of 500 (Firestore batch limit)
        const docs = yesterdayRequests.docs;
        for (let i = 0; i < docs.length; i += 500) {
          const chunk = docs.slice(i, i + 500);
          const batch = db.batch();
          chunk.forEach((doc) => {
            batch.update(doc.ref, {status: "expired"});
          });
          await batch.commit();
        }
        logger.log(`Expired ${yesterdayRequests.size} pending requests from ${yesterdayKey}`);
      }

      logger.log("Random Chat daily reset complete");
    } catch (error) {
      logger.error("Error in Random Chat daily reset:", error);
    }
  }
);

/**
 * Cloud Function triggered when a random chat request is created.
 * Sends a push notification to the receiver.
 */
export const onRandomChatRequestCreated = onDocumentCreated(
  {
    document: "random_chat_daily/{dateKey}/requests/{requestId}",
    region: "asia-south1",
  },
  async (event) => {
    const request = event.data?.data();
    if (!request) return;

    const receiverId = request.receiverId as string;
    const senderName = request.senderDisplayName as string || "Someone";

    try {
      // Get receiver's FCM tokens
      const userDoc = await admin
        .firestore()
        .collection("users")
        .doc(receiverId)
        .get();

      if (!userDoc.exists) return;

      const userData = userDoc.data();
      const fcmTokens = userData?.fcmTokens || {};
      const tokens = Object.keys(fcmTokens);

      if (tokens.length === 0) return;

      await admin.messaging().sendEachForMulticast({
        tokens: tokens,
        notification: {
          title: "New Random Chat Request",
          body: `${senderName} wants to chat with you!`,
        },
        data: {
          type: "random_chat_request",
          requestId: event.params.requestId,
          senderId: request.senderId as string,
        },
        android: {
          priority: "high",
          notification: {
            channelId: "radius_random_chat",
            priority: "high",
            sound: "default",
            tag: `random_chat_${request.senderId}`,
          },
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              badge: 1,
            },
          },
        },
      });

      logger.log(`Sent random chat request notification to ${receiverId}`);
    } catch (error) {
      logger.error("Error sending random chat notification:", error);
    }
  }
);

/**
 * Cloud Function triggered when a random chat request is accepted.
 * Notifies the sender that their request was accepted.
 */
export const onRandomChatRequestAccepted = onDocumentUpdated(
  {
    document: "random_chat_daily/{dateKey}/requests/{requestId}",
    region: "asia-south1",
  },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();

    if (!before || !after) return;

    // Only trigger on status change to 'accepted'
    if (before.status === after.status || after.status !== "accepted") return;

    const senderId = after.senderId as string;
    const receiverName = after.receiverDisplayName as string || "Someone";

    try {
      const userDoc = await admin
        .firestore()
        .collection("users")
        .doc(senderId)
        .get();

      if (!userDoc.exists) return;

      const userData = userDoc.data();
      const fcmTokens = userData?.fcmTokens || {};
      const tokens = Object.keys(fcmTokens);

      if (tokens.length === 0) return;

      await admin.messaging().sendEachForMulticast({
        tokens: tokens,
        notification: {
          title: "Request Accepted!",
          body: `${receiverName} accepted your Random Chat request!`,
        },
        data: {
          type: "random_chat_accepted",
          requestId: event.params.requestId,
          receiverId: after.receiverId as string,
        },
        android: {
          priority: "high",
          notification: {
            channelId: "radius_random_chat",
            priority: "high",
            sound: "default",
            tag: `random_chat_accepted_${after.receiverId}`,
          },
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              badge: 1,
            },
          },
        },
      });

      logger.log(`Sent random chat acceptance notification to ${senderId}`);
    } catch (error) {
      logger.error("Error sending acceptance notification:", error);
    }
  }
);

/**
 * Cloud Function triggered when a random chat connection is created.
 *
 * Expires ALL other pending requests involving either connected user.
 * This is the authoritative server-side cleanup — the client can only
 * expire its own requests (Firestore rules), so this function handles
 * the other user's pending requests as well.
 */
export const onRandomChatConnectionCreated = onDocumentCreated(
  {
    document: "random_chat_daily/{dateKey}/connections/{connectionId}",
    region: "asia-south1",
  },
  async (event) => {
    const connection = event.data?.data();
    if (!connection) return;

    const dateKey = event.params.dateKey;
    const user1Id = connection.user1Id as string;
    const user2Id = connection.user2Id as string;

    const db = admin.firestore();

    try {
      for (const userId of [user1Id, user2Id]) {
        // Expire pending requests TO this user
        const toSnap = await db
          .collection("random_chat_daily")
          .doc(dateKey)
          .collection("requests")
          .where("receiverId", "==", userId)
          .where("status", "==", "pending")
          .get();

        for (let i = 0; i < toSnap.docs.length; i += 500) {
          const chunk = toSnap.docs.slice(i, i + 500);
          const batch = db.batch();
          chunk.forEach((doc) => {
            batch.update(doc.ref, {
              status: "expired",
              respondedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          });
          await batch.commit();
        }

        // Expire pending requests FROM this user
        const fromSnap = await db
          .collection("random_chat_daily")
          .doc(dateKey)
          .collection("requests")
          .where("senderId", "==", userId)
          .where("status", "==", "pending")
          .get();

        for (let i = 0; i < fromSnap.docs.length; i += 500) {
          const chunk = fromSnap.docs.slice(i, i + 500);
          const batch = db.batch();
          chunk.forEach((doc) => {
            batch.update(doc.ref, {
              status: "expired",
              respondedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          });
          await batch.commit();
        }
      }

      logger.log(`Expired pending requests for connected users ${user1Id} & ${user2Id}`);
    } catch (error) {
      logger.error("Error expiring requests after connection created:", error);
    }
  }
);

// =============================================================================
// AUTO-ASSIGN DISCOVERY USERNAME ON SIGNUP
// =============================================================================

/**
 * Generates a valid discovery username from a display name.
 * Rules: lowercase, [a-z0-9._], 3-30 chars, no leading/trailing/consecutive dots or underscores.
 */
function generateBaseUsername(displayName: string | undefined | null): string {
  if (!displayName || displayName.trim().length === 0) {
    return "user";
  }

  let base = displayName
    .toLowerCase()
    .trim()
    .replace(/[\s-]+/g, ".")
    .replace(/[^a-z0-9._]/g, "")
    .replace(/\.{2,}/g, ".")
    .replace(/_{2,}/g, "_")
    .replace(/^[._]+/, "")
    .replace(/[._]+$/, "");

  if (base.length < 3) {
    base = base.length === 0 ? "user" : base + "0".repeat(3 - base.length);
  }

  // Truncate to leave room for suffix (max 24 chars base, 6 for suffix)
  if (base.length > 24) {
    base = base.substring(0, 24).replace(/[._]+$/, "");
  }

  return base;
}

/**
 * Firestore trigger: auto-assigns a discovery username when a new user document
 * is created in the `users` collection (i.e., on signup).
 *
 * Instagram-inspired approach:
 * - Derives username from displayName (e.g. "John Smith" → "john.smith")
 * - If taken, appends a random 4-digit suffix (e.g. "john.smith4827")
 * - Tries up to 10 suffixes, then falls back to "user.<first8charsOfUid>"
 * - Uses a batched write (index + user + profile) — fast, no deadlocks
 * - Runs async after signup, doesn't block the client
 */
export const onUserCreatedAssignDiscoveryUsername = onDocumentCreated(
  {
    document: "users/{userId}",
    region: "asia-south1",
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const userId = event.params.userId;
    const data = snapshot.data();

    // Skip if already has a discovery username
    if (data.discoveryUsername &&
        typeof data.discoveryUsername === "string" &&
        data.discoveryUsername.length > 0) {
      logger.log(`User ${userId} already has username: ` +
        `${data.discoveryUsername}`);
      return;
    }

    const db = admin.firestore();
    const displayName = data.displayName as string | undefined;
    const baseUsername = generateBaseUsername(displayName);

    try {
      let finalUsername: string | null = null;

      // Try the base username first, then append random suffixes
      const candidates: string[] = [baseUsername];
      for (let i = 0; i < 10; i++) {
        const suffix = Math.floor(Math.random() * 9000 + 1000);
        candidates.push(`${baseUsername}${suffix}`);
      }

      for (const candidate of candidates) {
        const indexDoc = await db.collection("discovery_usernames").doc(candidate).get();
        if (!indexDoc.exists) {
          finalUsername = candidate;
          break;
        }
      }

      if (!finalUsername) {
        // Fallback: uid-based username (guaranteed unique)
        finalUsername = `user.${userId.substring(0, 8).toLowerCase()}`;
      }

      // Batched write: index entry + user doc + profile doc
      const batch = db.batch();

      batch.set(db.collection("discovery_usernames").doc(finalUsername), {
        userId: userId,
        claimedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      batch.set(
        db.collection("users").doc(userId),
        {discoveryUsername: finalUsername},
        {merge: true},
      );

      batch.set(
        db.collection("profiles").doc(userId),
        {discoveryUsername: finalUsername},
        {merge: true},
      );

      await batch.commit();
      logger.log(`Auto-assigned @${finalUsername} to new user ${userId}`);
    } catch (error) {
      logger.error(`Failed to assign discovery username for user ${userId}:`, error);
    }
  }
);

// =============================================================================
// CONNECTION STATUS CHANGE — Sync other user's connectionCount
// =============================================================================

/**
 * Firestore trigger that keeps `profiles/{userId}.connectionCount` in sync
 * when a connection status changes.
 *
 * The client only updates its OWN profile (allowed by security rules).
 * This trigger updates the OTHER user's profile via the Admin SDK.
 *
 * Transitions handled:
 *   connected → disconnected  →  decrement other user
 *   connected → blocked       →  decrement other user
 *   !connected → connected    →  increment other user (the request sender)
 */
export const onConnectionStatusChanged = onDocumentUpdated(
  {
    document: "connections/{connectionId}",
    region: "asia-south1",
  },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after) return;

    const oldStatus = before.status as string;
    const newStatus = after.status as string;
    if (oldStatus === newStatus) return;

    const userId1 = after.userId1 as string;
    const userId2 = after.userId2 as string;
    const db = admin.firestore();
    const profilesRef = db.collection("profiles");

    try {
      if (oldStatus === "connected" && newStatus === "disconnected") {
        // Remove: no updatedBy field, so update both users.
        // The client already did its own -1, but in a separate write that
        // may or may not have committed yet. Using the trigger for BOTH
        // ensures consistency even if the client write fails.
        // To avoid double-decrement on the actor, the client-side code
        // should be removed in favour of this trigger. For backwards
        // compatibility we accept a possible ±1 transient discrepancy.
        const batch = db.batch();
        for (const uid of [userId1, userId2]) {
          batch.set(profilesRef.doc(uid),
            {connectionCount: admin.firestore.FieldValue.increment(-1)},
            {merge: true});
        }
        await batch.commit();
        logger.log(
          `Decremented connectionCount for ${userId1} & ${userId2}`);
      } else if (oldStatus === "connected" && newStatus === "blocked") {
        // Block: blockedBy tells us who acted (they already updated their own)
        const blockedBy = after.blockedBy as string | undefined;
        const otherUser = blockedBy === userId1 ? userId2 : userId1;
        await profilesRef.doc(otherUser).set(
          {connectionCount: admin.firestore.FieldValue.increment(-1)},
          {merge: true});
        logger.log(
          `Decremented connectionCount for ${otherUser} (blocked)`);
      } else if (newStatus === "connected" && oldStatus !== "connected") {
        // Accept: the receiver accepted, client already updated their own.
        // initiatedBy = the sender, who needs their count incremented.
        const initiatedBy = after.initiatedBy as string | undefined;
        if (initiatedBy) {
          await profilesRef.doc(initiatedBy).set(
            {connectionCount: admin.firestore.FieldValue.increment(1)},
            {merge: true});
          logger.log(
            `Incremented connectionCount for ${initiatedBy} (accepted)`);
        }
      }
    } catch (error) {
      logger.error("Error updating connectionCount:", error);
    }
  }
);

// =============================================================================
// CONNECTION CREATED — Increment sender's connectionCount
// =============================================================================

/**
 * Firestore trigger that increments the sender's `profiles/{userId}.connectionCount`
 * when a new connection document is created with status "connected".
 *
 * The client increments the acceptor's count directly. This trigger handles
 * the sender (initiatedBy), whose profile the client cannot write to due to
 * security rules.
 *
 * This is needed because `onDocumentUpdated` does not fire on document
 * creation — only on subsequent updates.
 */
export const onConnectionCreated = onDocumentCreated(
  {
    document: "connections/{connectionId}",
    region: "asia-south1",
  },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const status = data.status as string;
    if (status !== "connected") return;

    const initiatedBy = data.initiatedBy as string | undefined;
    if (!initiatedBy) return;

    const db = admin.firestore();
    try {
      await db.collection("profiles").doc(initiatedBy).set(
        {connectionCount: admin.firestore.FieldValue.increment(1)},
        {merge: true}
      );
      logger.log(
        `Incremented connectionCount for ${initiatedBy} (new connection created)`
      );
    } catch (error) {
      logger.error("Error updating connectionCount on connection created:", error);
    }
  }
);

// =============================================================================
// PROFILE UPDATE - Propagate displayName/photoUrl to conversations
// =============================================================================

/**
 * Cloud Function triggered when a user document is updated.
 *
 * When displayName or photoUrl changes, propagates the update to:
 * 1. All conversation documents (participantInfo & participantNames)
 * 2. Location group member docs (userName & userPhotoUrl)
 * 3. Nearby group member docs (displayName & photoUrl)
 * 4. Random group member docs (displayName & photoUrl)
 *
 * This keeps all denormalized user info in sync across the app.
 * Historical messages are intentionally NOT updated (showing the name
 * at send time is standard chat behavior).
 */
export const onUserProfileUpdated = onDocumentUpdated(
  {
    document: "users/{userId}",
    region: "asia-south1",
  },
  async (event) => {
    const userId = event.params.userId;
    const before = event.data?.before.data();
    const after = event.data?.after.data();

    if (!before || !after) return;

    const oldDisplayName = before.displayName as string | undefined;
    const newDisplayName = after.displayName as string | undefined;
    const oldPhotoUrl = before.photoUrl as string | undefined;
    const newPhotoUrl = after.photoUrl as string | undefined;

    // Only proceed if displayName or photoUrl actually changed
    if (oldDisplayName === newDisplayName && oldPhotoUrl === newPhotoUrl) {
      return;
    }

    const nameChanged = oldDisplayName !== newDisplayName && !!newDisplayName;
    const photoChanged = oldPhotoUrl !== newPhotoUrl;

    logger.log(
      `Profile updated for ${userId}: ` +
      `name: "${oldDisplayName}" → "${newDisplayName}", ` +
      `photo: "${oldPhotoUrl}" → "${newPhotoUrl}"`
    );

    const db = admin.firestore();
    const BATCH_LIMIT = 500;
    let batch = db.batch();
    let operationCount = 0;

    /** Commits the current batch if it has operations, and resets it. */
    const flushBatch = async () => {
      if (operationCount > 0) {
        await batch.commit();
        batch = db.batch();
        operationCount = 0;
      }
    };

    /** Adds an update to the batch and flushes if the limit is reached. */
    const addToBatch = async (
      ref: admin.firestore.DocumentReference,
      data: Record<string, string | null>
    ) => {
      batch.update(ref, data);
      operationCount++;
      if (operationCount >= BATCH_LIMIT) {
        await flushBatch();
      }
    };

    try {
      // --- 1. Update conversations (1:1 chats) ---
      const conversationsSnapshot = await db
        .collection("conversations")
        .where("participantIds", "array-contains", userId)
        .select()
        .get();

      for (const doc of conversationsSnapshot.docs) {
        const updateData: Record<string, string | null> = {};
        if (nameChanged) {
          updateData[`participantInfo.${userId}.displayName`] = newDisplayName!;
          updateData[`participantNames.${userId}`] = newDisplayName!;
        }
        if (photoChanged) {
          updateData[`participantInfo.${userId}.photoUrl`] = newPhotoUrl ?? null;
        }
        if (Object.keys(updateData).length > 0) {
          await addToBatch(doc.ref, updateData);
        }
      }

      // --- 2. Update group member docs across all group types ---
      // Uses collectionGroup query (indexed on members.userId COLLECTION_GROUP)
      // to find all member docs for this user in one query.
      // Location groups use: userName, userPhotoUrl
      // Nearby/Random groups use: displayName, photoUrl
      const groupMembersSnapshot = await db
        .collectionGroup("members")
        .where("userId", "==", userId)
        .get();

      for (const doc of groupMembersSnapshot.docs) {
        const parentCollection = doc.ref.parent.parent?.parent.id;
        const updateData: Record<string, string | null> = {};

        if (parentCollection === "location_groups") {
          if (nameChanged) updateData["userName"] = newDisplayName!;
          if (photoChanged) updateData["userPhotoUrl"] = newPhotoUrl ?? null;
        } else if (parentCollection === "nearby_groups" ||
                   parentCollection === "random_groups") {
          if (nameChanged) updateData["displayName"] = newDisplayName!;
          if (photoChanged) updateData["photoUrl"] = newPhotoUrl ?? null;
        } else {
          continue; // Skip unrelated "members" subcollections
        }

        if (Object.keys(updateData).length > 0) {
          await addToBatch(doc.ref, updateData);
        }
      }

      // Flush any remaining operations
      await flushBatch();

      logger.log(
        `Profile propagation complete for ${userId}: ` +
        `${conversationsSnapshot.size} conversations, ` +
        `${groupMembersSnapshot.size} group memberships`
      );
    } catch (error) {
      logger.error(
        `Error propagating profile update for ${userId}:`, error
      );
    }
  }
);

// =============================================================================
// POSTS — Sync authorConnections when connection status changes
// =============================================================================

/**
 * When a connection status changes, update the `authorConnections` array
 * on all "connections" visibility posts by the affected users.
 *
 * - connected → add the other user to authorConnections on all
 *   connections-only posts by each user.
 * - disconnected/blocked → remove the other user from authorConnections
 *   on all connections-only posts by each user.
 *
 * Uses batched writes (max 500 per batch).
 */
export const onPostConnectionSync = onDocumentUpdated(
  {
    document: "connections/{connectionId}",
    region: "asia-south1",
  },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after) return;

    const oldStatus = before.status as string;
    const newStatus = after.status as string;
    if (oldStatus === newStatus) return;

    const userId1 = after.userId1 as string;
    const userId2 = after.userId2 as string;
    const db = admin.firestore();

    const BATCH_LIMIT = 500;
    let batch = db.batch();
    let operationCount = 0;

    const flushBatch = async () => {
      if (operationCount > 0) {
        await batch.commit();
        batch = db.batch();
        operationCount = 0;
      }
    };

    try {
      if (newStatus === "connected" && oldStatus !== "connected") {
        // New connection: add each user to the other's connections-only posts
        // User1's connections-only posts → add userId2
        const user1Posts = await db
          .collection("posts")
          .where("authorId", "==", userId1)
          .where("visibility", "==", "connections")
          .select()
          .get();

        for (const doc of user1Posts.docs) {
          batch.update(doc.ref, {
            authorConnections: admin.firestore.FieldValue.arrayUnion(userId2),
          });
          operationCount++;
          if (operationCount >= BATCH_LIMIT) {
            await flushBatch();
          }
        }

        // User2's connections-only posts → add userId1
        const user2Posts = await db
          .collection("posts")
          .where("authorId", "==", userId2)
          .where("visibility", "==", "connections")
          .select()
          .get();

        for (const doc of user2Posts.docs) {
          batch.update(doc.ref, {
            authorConnections: admin.firestore.FieldValue.arrayUnion(userId1),
          });
          operationCount++;
          if (operationCount >= BATCH_LIMIT) {
            await flushBatch();
          }
        }

        await flushBatch();
        logger.log(
          "Post authorConnections synced (connected): " +
          `${user1Posts.size} posts for ${userId1}, ` +
          `${user2Posts.size} posts for ${userId2}`
        );
      } else if (
        oldStatus === "connected" &&
        (newStatus === "disconnected" || newStatus === "blocked")
      ) {
        // Disconnected/blocked: remove each user from the other's posts
        const user1Posts = await db
          .collection("posts")
          .where("authorId", "==", userId1)
          .where("visibility", "==", "connections")
          .select()
          .get();

        for (const doc of user1Posts.docs) {
          batch.update(doc.ref, {
            authorConnections: admin.firestore.FieldValue.arrayRemove(userId2),
          });
          operationCount++;
          if (operationCount >= BATCH_LIMIT) {
            await flushBatch();
          }
        }

        const user2Posts = await db
          .collection("posts")
          .where("authorId", "==", userId2)
          .where("visibility", "==", "connections")
          .select()
          .get();

        for (const doc of user2Posts.docs) {
          batch.update(doc.ref, {
            authorConnections: admin.firestore.FieldValue.arrayRemove(userId1),
          });
          operationCount++;
          if (operationCount >= BATCH_LIMIT) {
            await flushBatch();
          }
        }

        await flushBatch();
        logger.log(
          `Post authorConnections synced (${newStatus}): ` +
          `${user1Posts.size} posts for ${userId1}, ` +
          `${user2Posts.size} posts for ${userId2}`
        );
      }
    } catch (error) {
      logger.error("Error syncing post authorConnections:", error);
    }
  }
);

// =============================================================================
// POSTS — Cleanup Storage files when a post is deleted
// =============================================================================

/**
 * Firestore trigger that cleans up Firebase Storage files when a post
 * document is deleted. Reads the `mediaItems` array from the deleted
 * snapshot and deletes each `storagePath`.
 */
export const cleanupDeletedPostMedia = onDocumentDeleted(
  {
    document: "posts/{postId}",
    region: "asia-south1",
  },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const mediaItems = data.mediaItems as Array<Record<string, unknown>> | undefined;
    if (!mediaItems || mediaItems.length === 0) {
      logger.log(`Post ${event.params.postId} deleted — no media to clean up`);
      return;
    }

    const bucket = admin.storage().bucket();
    let deleted = 0;
    let failed = 0;

    for (const item of mediaItems) {
      const storagePath = item.storagePath as string | undefined;
      if (!storagePath) continue;

      try {
        await bucket.file(storagePath).delete();
        deleted++;
      } catch (err: unknown) {
        // File may already be deleted — log and continue
        const errorMessage = err instanceof Error ? err.message : String(err);
        logger.warn(
          `Failed to delete ${storagePath}: ${errorMessage}`
        );
        failed++;
      }

      // Also try to delete the thumbnail if it's a video
      const thumbnailUrl = item.thumbnailUrl as string | undefined;
      const type = item.type as string | undefined;
      if (type === "video" && thumbnailUrl) {
        // Thumbnail storagePath follows the pattern:
        // post_media/thumbnails/{authorId}/{postId}/{uuid}.jpg
        // Derive from the video storagePath:
        // post_media/videos/{authorId}/{postId}/{uuid}.mp4
        //  → post_media/thumbnails/{authorId}/{postId}/{uuid}.jpg
        const thumbPath = storagePath
          .replace("/videos/", "/thumbnails/")
          .replace(/\.[^.]+$/, ".jpg");
        try {
          await bucket.file(thumbPath).delete();
          deleted++;
        } catch {
          // Thumbnail may not exist or already deleted — ignore
        }
      }
    }

    logger.log(
      `Post ${event.params.postId} media cleanup: ` +
      `${deleted} deleted, ${failed} failed`
    );
  }
);

// =============================================================================
// POSTS — Sync denormalized author info when profile changes
// =============================================================================

/**
 * When a user's profile (displayName or photoUrl) changes, update all
 * posts authored by that user to keep the denormalized `authorName`
 * and `authorPhotoUrl` fields in sync.
 *
 * This is a separate trigger from `onUserProfileUpdated` because it
 * targets the `posts` collection specifically. It fires on the same
 * `users/{userId}` document update.
 */
export const syncPostAuthorProfile = onDocumentUpdated(
  {
    document: "users/{userId}",
    region: "asia-south1",
  },
  async (event) => {
    const userId = event.params.userId;
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;

    const oldDisplayName = before.displayName as string | undefined;
    const newDisplayName = after.displayName as string | undefined;
    const oldPhotoUrl = before.photoUrl as string | undefined;
    const newPhotoUrl = after.photoUrl as string | undefined;

    // Only proceed if displayName or photoUrl actually changed
    if (oldDisplayName === newDisplayName && oldPhotoUrl === newPhotoUrl) {
      return;
    }

    const nameChanged = oldDisplayName !== newDisplayName && !!newDisplayName;
    const photoChanged = oldPhotoUrl !== newPhotoUrl;

    if (!nameChanged && !photoChanged) return;

    const db = admin.firestore();

    try {
      const postsSnapshot = await db
        .collection("posts")
        .where("authorId", "==", userId)
        .select()
        .get();

      if (postsSnapshot.empty) {
        logger.log(`No posts to update for user ${userId}`);
        return;
      }

      const BATCH_LIMIT = 500;
      let batch = db.batch();
      let operationCount = 0;

      for (const doc of postsSnapshot.docs) {
        const updateData: Record<string, string | null> = {};
        if (nameChanged) updateData["authorName"] = newDisplayName!;
        if (photoChanged) updateData["authorPhotoUrl"] = newPhotoUrl ?? null;

        batch.update(doc.ref, updateData);
        operationCount++;

        if (operationCount >= BATCH_LIMIT) {
          await batch.commit();
          batch = db.batch();
          operationCount = 0;
        }
      }

      if (operationCount > 0) {
        await batch.commit();
      }

      logger.log(
        `Synced author info on ${postsSnapshot.size} posts for user ${userId}`
      );
    } catch (error) {
      logger.error(
        `Error syncing post author profile for ${userId}:`, error
      );
    }
  }
);

// =============================================================================
// POST LIKES & COMMENTS — Counter Maintenance
// =============================================================================

/**
 * Increments likeCount on the parent post when a like document is created.
 *
 * Trigger: posts/{postId}/likes/{userId} — onCreate
 */
// =============================================================================
// GLOBAL POSTS — Trending Score & Counter Maintenance
// =============================================================================

/**
 * Initializes the trendingScore on a global post when it is created.
 *
 * Trigger: posts/{postId} — onCreate
 */
export const onPostCreated = onDocumentCreated(
  "posts/{postId}",
  async (event) => {
    const postId = event.params.postId;
    const postData = event.data?.data();
    if (!postData) return;

    const createdAt = postData.createdAt as admin.firestore.Timestamp;
    const likes = postData.likeCount || 0;
    const comments = postData.commentCount || 0;
    
    // If createdAt is missing, we can't calculate a score
    if (!createdAt) return;

    // Uses the same gravity-based trending algorithm
    const trendingScore = calculateTrendingScore(createdAt, likes + (comments * 2));

    try {
      await admin.firestore().collection("posts").doc(postId).update({
        trendingScore: trendingScore,
      });
      logger.log(`Initialized trendingScore for post ${postId}`);
    } catch (error) {
      logger.error(`Error initializing trendingScore for post ${postId}:`, error);
    }
  }
);

/**
 * Increments likeCount and updates trendingScore on the parent post when a like is created.
 *
 * Trigger: posts/{postId}/likes/{userId} — onCreate
 */
export const onPostLikeCreated = onDocumentCreated(
  "posts/{postId}/likes/{userId}",
  async (event) => {
    const postId = event.params.postId;
    const db = admin.firestore();

    const postRef = db.collection("posts").doc(postId);

    try {
      await db.runTransaction(async (transaction) => {
        const postDoc = await transaction.get(postRef);
        if (!postDoc.exists) return;

        const data = postDoc.data()!;
        const createdAt = data.createdAt as admin.firestore.Timestamp;
        if (!createdAt) return;

        const newLikes = (data.likeCount || 0) + 1;
        const comments = data.commentCount || 0;
        const newScore = calculateTrendingScore(createdAt, newLikes + (comments * 2));

        transaction.update(postRef, {
          likeCount: newLikes,
          trendingScore: newScore,
        });
      });
      logger.log(`Incremented likeCount & updated trendingScore on post ${postId}`);
    } catch (error) {
      logger.error(`Error incrementing likeCount on post ${postId}:`, error);
    }
  }
);

/**
 * Decrements likeCount and updates trendingScore on the parent post when a like is deleted.
 *
 * Trigger: posts/{postId}/likes/{userId} — onDelete
 */
export const onPostLikeDeleted = onDocumentDeleted(
  "posts/{postId}/likes/{userId}",
  async (event) => {
    const postId = event.params.postId;
    const db = admin.firestore();

    const postRef = db.collection("posts").doc(postId);

    try {
      await db.runTransaction(async (transaction) => {
        const postDoc = await transaction.get(postRef);
        if (!postDoc.exists) return;

        const data = postDoc.data()!;
        const createdAt = data.createdAt as admin.firestore.Timestamp;
        if (!createdAt) return;

        const newLikes = Math.max(0, (data.likeCount || 0) - 1);
        const comments = data.commentCount || 0;
        const newScore = calculateTrendingScore(createdAt, newLikes + (comments * 2));

        transaction.update(postRef, {
          likeCount: newLikes,
          trendingScore: newScore,
        });
      });
      logger.log(`Decremented likeCount & updated trendingScore on post ${postId}`);
    } catch (error) {
      logger.error(`Error decrementing likeCount on post ${postId}:`, error);
    }
  }
);

/**
 * Increments commentCount and updates trendingScore on the parent post when a comment is created.
 *
 * Trigger: posts/{postId}/comments/{commentId} — onCreate
 */
export const onPostCommentCreated = onDocumentCreated(
  "posts/{postId}/comments/{commentId}",
  async (event) => {
    const postId = event.params.postId;
    const db = admin.firestore();

    const postRef = db.collection("posts").doc(postId);

    try {
      await db.runTransaction(async (transaction) => {
        const postDoc = await transaction.get(postRef);
        if (!postDoc.exists) return;

        const data = postDoc.data()!;
        const createdAt = data.createdAt as admin.firestore.Timestamp;
        if (!createdAt) return;

        const likes = data.likeCount || 0;
        const newComments = (data.commentCount || 0) + 1;
        const newScore = calculateTrendingScore(createdAt, likes + (newComments * 2));

        transaction.update(postRef, {
          commentCount: newComments,
          trendingScore: newScore,
        });
      });
      logger.log(`Incremented commentCount & updated trendingScore on post ${postId}`);
    } catch (error) {
      logger.error(`Error incrementing commentCount on post ${postId}:`, error);
    }
  }
);

/**
 * Decrements commentCount and updates trendingScore on the parent post when a comment is deleted.
 *
 * Trigger: posts/{postId}/comments/{commentId} — onDelete
 */
export const onPostCommentDeleted = onDocumentDeleted(
  "posts/{postId}/comments/{commentId}",
  async (event) => {
    const postId = event.params.postId;
    const db = admin.firestore();

    const postRef = db.collection("posts").doc(postId);

    try {
      await db.runTransaction(async (transaction) => {
        const postDoc = await transaction.get(postRef);
        if (!postDoc.exists) return;

        const data = postDoc.data()!;
        const createdAt = data.createdAt as admin.firestore.Timestamp;
        if (!createdAt) return;

        const likes = data.likeCount || 0;
        const newComments = Math.max(0, (data.commentCount || 0) - 1);
        const newScore = calculateTrendingScore(createdAt, likes + (newComments * 2));

        transaction.update(postRef, {
          commentCount: newComments,
          trendingScore: newScore,
        });
      });
      logger.log(`Decremented commentCount & updated trendingScore on post ${postId}`);
    } catch (error) {
      logger.error(`Error decrementing commentCount on post ${postId}:`, error);
    }
  }
);

// =============================================================================
// LOCAL NEWS POSTS — Like & Comment Counter Maintenance
// =============================================================================

/**
 * Calculates the trending score for a local news post using a gravity-based algorithm.
 * 45000 seconds = 12.5 hours. A post needs 10x more interactions to match a post that is 12.5 hours newer.
 */
function calculateTrendingScore(createdAt: admin.firestore.Timestamp, engagementScore: number): number {
  const interactionScore = Math.log10(Math.max(1, engagementScore));
  const epochSeconds = 1704067200; // Jan 1 2024
  const timeScore = (createdAt.seconds - epochSeconds) / 45000;
  return interactionScore + timeScore;
}

/**
 * Initializes the trendingScore on a local news post when it is created.
 *
 * Trigger: local_news_posts/{postId} — onCreate
 */
export const onLocalNewsPostCreated = onDocumentCreated(
  "local_news_posts/{postId}",
  async (event) => {
    const postId = event.params.postId;
    const postData = event.data?.data();
    if (!postData) return;

    const createdAt = postData.createdAt as admin.firestore.Timestamp;
    const engagementScore = postData.engagementScore || 0;
    
    // If createdAt is missing, we can't calculate a score
    if (!createdAt) return;

    const trendingScore = calculateTrendingScore(createdAt, engagementScore);

    const db = admin.firestore();
    try {
      await db.collection("local_news_posts").doc(postId).update({
        trendingScore: trendingScore,
      });
      logger.log(`Initialized trendingScore=${trendingScore} for local news post ${postId}`);
    } catch (error) {
      logger.error(`Error initializing trendingScore for local news post ${postId}:`, error);
    }
  }
);

/**
 * The Feed API (Reels)
 *
 * Endpoint: /api/getReelsFeed
 * Ranks videos based on engagementScore rather than chronologically.
 */
export const getReelsFeed = onCall({}, async (request: any) => {
  const data = request.data || {};
  const city = data.city;
  const country = data.country;
  const limit = data.limit || 10;

  if (!city || !country) {
    throw new Error('City and Country are required to fetch the Reels feed.');
  }

  const db = admin.firestore();
  
  // The Feed Engine Algorithm
  // Query all reels for the specified location, and rank them natively by their engagementScore.
  try {
    const snapshot = await db.collection("local_news_posts")
      .where("postType", "==", "reel")
      .where("city", "==", city)
      .where("country", "==", country)
      .orderBy("trendingScore", "desc")
      .limit(limit)
      .get();

    const reels = snapshot.docs.map(doc => {
      const docData = doc.data();
      // Ensure timestamps are correctly converted if necessary for the client, 
      // but typically the client parses the raw JSON if sent via REST.
      return {
        id: doc.id,
        ...docData,
      };
    });

    return reels;
  } catch (error) {
    logger.error("Error generating reels feed:", error);
    throw new Error('Failed to generate reels feed.');
  }
});

/**
 * The Feed API (Standard Local Posts)
 *
 * Endpoint: /api/getLocalNewsFeed
 * Ranks text/image local posts based on engagementScore rather than chronologically.
 */
export const getLocalNewsFeed = onCall({}, async (request: any) => {
  const data = request.data || {};
  const city = data.city;
  const country = data.country;
  const limit = data.limit || 20;

  if (!city || !country) {
    throw new Error('City and Country are required to fetch the local news feed.');
  }

  const db = admin.firestore();
  
  try {
    const snapshot = await db.collection("local_news_posts")
      .where("postType", "==", "post")
      .where("city", "==", city)
      .where("country", "==", country)
      .orderBy("trendingScore", "desc")
      .limit(limit)
      .get();

    const posts = snapshot.docs.map(doc => {
      const docData = doc.data();
      return {
        id: doc.id,
        ...docData,
      };
    });

    return posts;
  } catch (error) {
    logger.error("Error generating local news feed:", error);
    throw new Error('Failed to generate local news feed.');
  }
});

// =============================================================================
// PEOPLE YOU MAY KNOW - Suggested Connections Algorithm
// =============================================================================

/**
 * Algorithm for suggesting new connections ("People You May Know").
 * 
 * Ranks users based on:
 * 1. Location Proximity (Same city/country)
 * 2. Mutual Connections (Friends of friends)
 * 3. Not currently connected and no pending requests.
 */
export const getSuggestedConnections = onCall({
  enforceAppCheck: false,
}, async (request: any) => {
  const data = request.data || {};
  const currentUserId = request.auth?.uid || data.userId;
  
  if (!currentUserId) {
    throw new HttpsError("unauthenticated", "Must provide userId or be authenticated");
  }

  const limitCount = data.limit || 15;
  const db = admin.firestore();

  try {
    // 1. Get current user profile for location info
    const currentUserDoc = await db.collection("profiles").doc(currentUserId).get();
    const currentUserData = currentUserDoc.data() || {};
    const city = currentUserData.city || "";
    const country = currentUserData.country || "";

    // 2. Get current user's active connections to filter them out and find mutuals
    const connectionsSnapshot = await db.collection("connections")
      .where("participants", "array-contains", currentUserId)
      .get();
    
    const existingConnectionIds = new Set<string>();
    existingConnectionIds.add(currentUserId); // Don't suggest self

    // Build a map of our friends' connections to calculate mutuals
    const mutualCandidates = new Map<string, number>();

    for (const doc of connectionsSnapshot.docs) {
      const data = doc.data();
      const otherId = data.userId1 === currentUserId ? data.userId2 : data.userId1;
      existingConnectionIds.add(otherId);
      
      // Look up friends of this friend to find mutuals
      const friendsOfFriend = await db.collection("connections")
        .where("participants", "array-contains", otherId)
        .limit(20) // Cap to avoid massive queries
        .get();
        
      for (const fof of friendsOfFriend.docs) {
        const fofData = fof.data();
        const mutualId = fofData.userId1 === otherId ? fofData.userId2 : fofData.userId1;
        if (mutualId !== currentUserId) {
          mutualCandidates.set(mutualId, (mutualCandidates.get(mutualId) || 0) + 1);
        }
      }
    }

    // 3. Get pending sent/received requests to filter them out
    const sentReqs = await db.collection("connection_requests")
      .where("senderId", "==", currentUserId)
      .where("status", "==", "pending")
      .get();
    sentReqs.forEach(doc => existingConnectionIds.add(doc.data().receiverId));

    const receivedReqs = await db.collection("connection_requests")
      .where("receiverId", "==", currentUserId)
      .where("status", "==", "pending")
      .get();
    receivedReqs.forEach(doc => existingConnectionIds.add(doc.data().senderId));

    // 4. Fetch random users in the same location to fill out suggestions
    let locationUsers: any[] = [];
    if (city && country) {
      const locSnapshot = await db.collection("profiles")
        .where("country", "==", country)
        .where("city", "==", city)
        .limit(50)
        .get();
        
      locationUsers = locSnapshot.docs
        .filter(doc => !existingConnectionIds.has(doc.id))
        .map(doc => ({ id: doc.id, ...doc.data() }));
    }

    // 5. If we need more, fetch a few random recent profiles
    let generalUsers: any[] = [];
    if (locationUsers.length < limitCount) {
      const genSnapshot = await db.collection("profiles")
        .orderBy("lastActiveAt", "desc")
        .limit(30)
        .get();
        
      generalUsers = genSnapshot.docs
        .filter(doc => !existingConnectionIds.has(doc.id))
        .map(doc => ({ id: doc.id, ...doc.data() }));
    }

    // Combine and deduplicate candidates
    const allCandidates = new Map<string, any>();
    locationUsers.forEach(u => allCandidates.set(u.id, u));
    generalUsers.forEach(u => allCandidates.set(u.id, u));

    // Calculate score for each candidate
    const scoredCandidates = Array.from(allCandidates.values()).map(user => {
      let score = 0;
      let reason = "Suggested for you";
      
      const mutualCount = mutualCandidates.get(user.id) || 0;
      if (mutualCount > 0) {
        score += mutualCount * 20; // 20 pts per mutual connection
        reason = `${mutualCount} mutual connection${mutualCount > 1 ? 's' : ''}`;
      } else if (user.city === city && user.country === country) {
        score += 10;
        reason = `Near you in ${city}`;
      } else if (user.country === country) {
        score += 5;
        reason = `From ${country}`;
      }
      
      return {
        ...user,
        algorithmScore: score,
        suggestionReason: reason
      };
    });

    // Sort by score descending
    scoredCandidates.sort((a, b) => b.algorithmScore - a.algorithmScore);

    // Return top N
    return scoredCandidates.slice(0, limitCount).map(user => ({
      userId: user.id,
      displayName: user.displayName || user.name || 'User',
      photoUrl: user.photoUrl || user.avatarUrl || null,
      bio: user.bio || '',
      discoveryUsername: user.discoveryUsername || '',
      reason: user.suggestionReason
    }));

  } catch (error) {
    logger.error("Error generating suggested connections:", error);
    throw new HttpsError("internal", "Failed to generate suggestions.");
  }
});

/**
 * Increments likeCount and updates trendingScore on the parent local news post when a like is created.
 *
 * Trigger: local_news_posts/{postId}/likes/{userId} — onCreate
 */
export const onLocalNewsLikeCreated = onDocumentCreated(
  "local_news_posts/{postId}/likes/{userId}",
  async (event) => {
    const postId = event.params.postId;
    const db = admin.firestore();
    const postRef = db.collection("local_news_posts").doc(postId);

    try {
      await db.runTransaction(async (transaction) => {
        const postDoc = await transaction.get(postRef);
        if (!postDoc.exists) return;

        const data = postDoc.data()!;
        const newLikes = (data.likeCount || 0) + 1;
        
        transaction.update(postRef, {
          likeCount: newLikes,
        });
      });
      logger.log(`Incremented likeCount on local news post ${postId}`);
    } catch (error) {
      logger.error(`Error incrementing likeCount on local news post ${postId}:`, error);
    }
  }
);

/**
 * Decrements likeCount and updates trendingScore on the parent local news post when a like is deleted.
 *
 * Trigger: local_news_posts/{postId}/likes/{userId} — onDelete
 */
export const onLocalNewsLikeDeleted = onDocumentDeleted(
  "local_news_posts/{postId}/likes/{userId}",
  async (event) => {
    const postId = event.params.postId;
    const db = admin.firestore();
    const postRef = db.collection("local_news_posts").doc(postId);

    try {
      await db.runTransaction(async (transaction) => {
        const postDoc = await transaction.get(postRef);
        if (!postDoc.exists) return;

        const data = postDoc.data()!;
        const newLikes = Math.max(0, (data.likeCount || 0) - 1);
        
        transaction.update(postRef, {
          likeCount: newLikes,
        });
      });
      logger.log(`Decremented likeCount on local news post ${postId}`);
    } catch (error) {
      logger.error(`Error decrementing likeCount on local news post ${postId}:`, error);
    }
  }
);

/**
 * Increments commentCount and updates trendingScore on the parent local news post when a comment is created.
 *
 * Trigger: local_news_posts/{postId}/comments/{commentId} — onCreate
 */
export const onLocalNewsCommentCreated = onDocumentCreated(
  "local_news_posts/{postId}/comments/{commentId}",
  async (event) => {
    const postId = event.params.postId;
    const db = admin.firestore();
    const postRef = db.collection("local_news_posts").doc(postId);

    try {
      await db.runTransaction(async (transaction) => {
        const postDoc = await transaction.get(postRef);
        if (!postDoc.exists) return;

        const data = postDoc.data()!;
        const newComments = (data.commentCount || 0) + 1;
        
        transaction.update(postRef, {
          commentCount: newComments,
        });
      });
      logger.log(`Incremented commentCount on local news post ${postId}`);
    } catch (error) {
      logger.error(`Error incrementing commentCount on local news post ${postId}:`, error);
    }
  }
);

/**
 * Decrements commentCount and updates trendingScore on the parent local news post when a comment is deleted.
 *
 * Trigger: local_news_posts/{postId}/comments/{commentId} — onDelete
 */
export const onLocalNewsCommentDeleted = onDocumentDeleted(
  "local_news_posts/{postId}/comments/{commentId}",
  async (event) => {
    const postId = event.params.postId;
    const db = admin.firestore();
    const postRef = db.collection("local_news_posts").doc(postId);

    try {
      await db.runTransaction(async (transaction) => {
        const postDoc = await transaction.get(postRef);
        if (!postDoc.exists) return;

        const data = postDoc.data()!;
        const newComments = Math.max(0, (data.commentCount || 0) - 1);
        
        transaction.update(postRef, {
          commentCount: newComments,
        });
      });
      logger.log(`Decremented commentCount on local news post ${postId}`);
    } catch (error) {
      logger.error(`Error decrementing commentCount on local news post ${postId}:`, error);
    }
  }
);

/**
 * Cleans up Firebase Storage media when a local news post is deleted.
 *
 * Trigger: local_news_posts/{postId} — onDelete
 *
 * Storage path pattern: local_news_media/{images|videos|thumbnails}/{authorId}/{postId}/
 */
export const onLocalNewsPostDeleted = onDocumentDeleted(
  "local_news_posts/{postId}",
  async (event) => {
    const postId = event.params.postId;
    const postData = event.data?.data();

    if (!postData) return;

    const authorId = postData.authorId as string;
    const mediaItems = (postData.mediaItems || []) as Array<Record<string, unknown>>;

    if (mediaItems.length === 0) {
      logger.log(`No media to clean up for local news post ${postId}`);
      return;
    }

    const bucket = admin.storage().bucket();
    const prefixes = [
      `local_news_media/images/${authorId}/${postId}/`,
      `local_news_media/videos/${authorId}/${postId}/`,
      `local_news_media/thumbnails/${authorId}/${postId}/`,
    ];

    let totalDeleted = 0;

    for (const prefix of prefixes) {
      try {
        const [files] = await bucket.getFiles({prefix});
        for (const file of files) {
          await file.delete();
          totalDeleted++;
        }
      } catch (error) {
        logger.error(`Error deleting files at ${prefix}:`, error);
      }
    }

    // Also delete likes and comments subcollections
    const db = admin.firestore();
    const subcollections = ["likes", "comments"];

    for (const subcol of subcollections) {
      try {
        let snapshot = await db
          .collection("local_news_posts")
          .doc(postId)
          .collection(subcol)
          .limit(500)
          .get();

        while (!snapshot.empty) {
          const batch = db.batch();
          snapshot.docs.forEach((doc) => batch.delete(doc.ref));
          await batch.commit();

          snapshot = await db
            .collection("local_news_posts")
            .doc(postId)
            .collection(subcol)
            .limit(500)
            .get();
        }
      } catch (error) {
        logger.error(`Error deleting ${subcol} subcollection for post ${postId}:`, error);
      }
    }

    logger.log(
      `Cleaned up ${totalDeleted} media files and subcollections ` +
      `for local news post ${postId}`
    );
  }
);
