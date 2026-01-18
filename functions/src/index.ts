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
