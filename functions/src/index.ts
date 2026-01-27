import {onDocumentCreated, onDocumentUpdated} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import {logger} from "firebase-functions";

admin.initializeApp();

/**
 * Send push notification when a new message is sent.
 */
export const onMessageSent = onDocumentCreated(
  "conversations/{conversationId}/messages/{messageId}",
  async (event) => {
    const message = event.data?.data();
    if (!message) return;

    const conversationId = event.params.conversationId;

    // Get conversation to find recipient
    const conversationDoc = await admin
      .firestore()
      .collection("conversations")
      .doc(conversationId)
      .get();

    if (!conversationDoc.exists) {
      logger.log("Conversation not found");
      return null;
    }

    const conversation = conversationDoc.data();
    if (!conversation) return null;

    const senderId = message.senderId;
    const participantIds = conversation.participantIds as string[];
    const recipientId = participantIds.find((id: string) => id !== senderId);

    if (!recipientId) {
      logger.log("Recipient not found");
      return null;
    }

    // Get sender info
    const senderName =
      conversation.participants?.[senderId]?.displayName || "Someone";

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
    const payload = {
      notification: {
        title: senderName,
        body: message.text || "Sent a message",
      },
      data: {
        conversationId: conversationId,
        senderId: senderId,
        type: "message",
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
 * Send push notification when a new group message is sent.
 * Notifies all active group members except the sender.
 * Groups notifications together per group on Android (tag) and iOS (threadId).
 */
export const onGroupMessageNotification = onDocumentCreated(
  "location_groups/{groupId}/messages/{messageId}",
  async (event) => {
    const message = event.data?.data();
    if (!message) return;

    const groupId = event.params.groupId;
    const senderId = message.senderId as string;
    const senderName = message.senderName || "Someone";
    const messageText = message.text || "Sent a message";

    // Skip system messages
    if (message.type === "system") {
      logger.log("Skipping notification for system message");
      return null;
    }

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

    // Get all active members except sender
    const membersSnapshot = await admin
      .firestore()
      .collection("location_groups")
      .doc(groupId)
      .collection("members")
      .where("status", "==", "active")
      .get();

    if (membersSnapshot.empty) {
      logger.log("No active members found");
      return null;
    }

    // Collect all tokens from all members (except sender)
    const allTokens: string[] = [];
    const tokenToUserMap: Map<string, string> = new Map();

    for (const memberDoc of membersSnapshot.docs) {
      const memberData = memberDoc.data();
      const memberUserId = memberData.userId as string;

      // Skip the sender
      if (memberUserId === senderId) continue;

      // Get user's FCM tokens
      const userDoc = await admin
        .firestore()
        .collection("users")
        .doc(memberUserId)
        .get();

      if (!userDoc.exists) continue;

      const userData = userDoc.data();
      const fcmTokens = userData?.fcmTokens || {};
      const tokens = Object.keys(fcmTokens);

      for (const token of tokens) {
        allTokens.push(token);
        tokenToUserMap.set(token, memberUserId);
      }
    }

    if (allTokens.length === 0) {
      logger.log("No FCM tokens for any group members");
      return null;
    }

    // Prepare notification
    const payload = {
      notification: {
        title: `${groupName}`,
        body: `${senderName}: ${messageText.substring(0, 100)}`,
      },
      data: {
        groupId: groupId,
        senderId: senderId,
        type: "group_message",
      },
    };

    // Send to all members' devices
    try {
      const response = await admin.messaging().sendEachForMulticast({
        tokens: allTokens,
        notification: payload.notification,
        data: payload.data,
        android: {
          priority: "high",
          notification: {
            channelId: "radius_messages",
            priority: "high",
            sound: "default",
            defaultSound: true,
            tag: `group_${groupId}`, // Group notifications together
          },
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              badge: 1,
              threadId: `group_${groupId}`, // Group notifications together on iOS
            },
          },
        },
      });

      logger.log(
        `Group notification: ${response.successCount} sent, ` +
        `${response.failureCount} failed to ${allTokens.length} tokens`
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
            updates[`fcmTokens.${token}`] = admin.firestore.FieldValue.delete();
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
      logger.error("Error sending group notification:", error);
      return null;
    }
  }
);

/**
 * Send push notification when a connection request is received.
 */
export const onConnectionRequestReceived = onDocumentCreated(
  "connection_requests/{requestId}",
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
  "location_groups/{groupId}/join_requests/{requestId}",
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
      notification: {
        title: `${groupName} - Join Request`,
        body: body,
      },
      data: {
        groupId: groupId,
        requestId: event.params.requestId,
        requesterId: requesterId,
        type: "group_join_request",
      },
    };

    // Send to all admins' devices
    try {
      const response = await admin.messaging().sendEachForMulticast({
        tokens: allTokens,
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
 * Send push notification when connection request is accepted.
 * Notifies the original sender.
 */
export const onConnectionRequestAccepted = onDocumentUpdated(
  "connection_requests/{requestId}",
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
 * Scheduled function to clean up expired GuessMe sessions.
 * Runs daily at 2:00 AM UTC. Deletes sessions older than 7 days.
 */
export const cleanupExpiredGuessMeSessions = onSchedule(
  {
    schedule: "0 2 * * *", // Daily at 2 AM UTC
    timeZone: "UTC",
  },
  async () => {
    const sevenDaysAgo = new Date();
    sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);

    try {
      // Find expired sessions
      const expiredSessions = await admin
        .firestore()
        .collection("guess_me_sessions")
        .where("createdAt", "<", sevenDaysAgo)
        .get();

      if (expiredSessions.empty) {
        logger.log("No expired GuessMe sessions to clean up");
        return;
      }

      // Delete in batches
      const batchSize = 500;
      let batch = admin.firestore().batch();
      let count = 0;
      let totalDeleted = 0;

      for (const doc of expiredSessions.docs) {
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
        `Cleaned up ${totalDeleted} expired GuessMe sessions`
      );
    } catch (error) {
      logger.error("Error cleaning up GuessMe sessions:", error);
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
