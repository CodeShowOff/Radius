import {onDocumentCreated} from "firebase-functions/v2/firestore";
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
export const onGroupMessageSent = onDocumentCreated(
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
        `Group notification: ${response.successCount} sent, ${response.failureCount} failed to ${allTokens.length} tokens`
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
 * Update unread counts for group members when a new group message is sent.
 * This runs server-side to bypass client permission restrictions.
 */
export const onGroupMessageSent = onDocumentCreated(
  "location_groups/{groupId}/messages/{messageId}",
  async (event) => {
    const message = event.data?.data();
    if (!message) return;

    const groupId = event.params.groupId;
    const senderId = message.senderId;
    const isSystemMessage = message.senderId === "system";

    // Skip unread count updates for system messages
    if (isSystemMessage) {
      logger.log("Skipping unread count update for system message");
      return null;
    }

    try {
      // Get all active members except the sender
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

      // Update unread counts in batch
      const batch = admin.firestore().batch();
      let updateCount = 0;

      membersSnapshot.forEach((memberDoc) => {
        const memberData = memberDoc.data();
        const memberUserId = memberData.userId;

        // Skip the sender - their count is already reset by client
        if (memberUserId === senderId) {
          return;
        }

        // Increment unread count for other members
        batch.set(
          memberDoc.ref,
          {
            unreadCount: admin.firestore.FieldValue.increment(1),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          {merge: true}
        );
        updateCount++;
      });

      if (updateCount > 0) {
        await batch.commit();
        logger.log(Updated unread counts for  members in group );
      }

      return null;
    } catch (error) {
      logger.error("Error updating group unread counts:", error);
      return null;
    }
  }
);
