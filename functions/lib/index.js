"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.onConnectionRequestReceived = exports.onMessageSent = void 0;
const firestore_1 = require("firebase-functions/v2/firestore");
const admin = __importStar(require("firebase-admin"));
const firebase_functions_1 = require("firebase-functions");
admin.initializeApp();
/**
 * Send push notification when a new message is sent.
 */
exports.onMessageSent = (0, firestore_1.onDocumentCreated)("conversations/{conversationId}/messages/{messageId}", async (event) => {
    const message = event.data?.data();
    if (!message)
        return;
    const conversationId = event.params.conversationId;
    // Get conversation to find recipient
    const conversationDoc = await admin
        .firestore()
        .collection("conversations")
        .doc(conversationId)
        .get();
    if (!conversationDoc.exists) {
        firebase_functions_1.logger.log("Conversation not found");
        return null;
    }
    const conversation = conversationDoc.data();
    if (!conversation)
        return null;
    const senderId = message.senderId;
    const participantIds = conversation.participantIds;
    const recipientId = participantIds.find((id) => id !== senderId);
    if (!recipientId) {
        firebase_functions_1.logger.log("Recipient not found");
        return null;
    }
    // Get sender info
    const senderName = conversation.participants?.[senderId]?.displayName || "Someone";
    // Get recipient's FCM tokens
    const userDoc = await admin
        .firestore()
        .collection("users")
        .doc(recipientId)
        .get();
    if (!userDoc.exists) {
        firebase_functions_1.logger.log("User not found");
        return null;
    }
    const userData = userDoc.data();
    const fcmTokens = userData?.fcmTokens || {};
    const tokens = Object.keys(fcmTokens);
    if (tokens.length === 0) {
        firebase_functions_1.logger.log("No FCM tokens for user");
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
        firebase_functions_1.logger.log(`Sent ${response.successCount} notifications, ${response.failureCount} failures`);
        // Remove invalid tokens
        if (response.failureCount > 0) {
            const tokensToRemove = [];
            response.responses.forEach((resp, idx) => {
                if (!resp.success) {
                    tokensToRemove.push(tokens[idx]);
                }
            });
            if (tokensToRemove.length > 0) {
                const updates = {};
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
    }
    catch (error) {
        firebase_functions_1.logger.error("Error sending notification:", error);
        return null;
    }
});
/**
 * Send push notification when a connection request is received.
 */
exports.onConnectionRequestReceived = (0, firestore_1.onDocumentCreated)("connection_requests/{requestId}", async (event) => {
    const request = event.data?.data();
    if (!request)
        return;
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
        firebase_functions_1.logger.log("User not found");
        return null;
    }
    const userData = userDoc.data();
    const fcmTokens = userData?.fcmTokens || {};
    const tokens = Object.keys(fcmTokens);
    if (tokens.length === 0) {
        firebase_functions_1.logger.log("No FCM tokens for user");
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
        firebase_functions_1.logger.log(`Sent ${response.successCount} notifications, ${response.failureCount} failures`);
        // Remove invalid tokens
        if (response.failureCount > 0) {
            const tokensToRemove = [];
            response.responses.forEach((resp, idx) => {
                if (!resp.success) {
                    tokensToRemove.push(tokens[idx]);
                }
            });
            if (tokensToRemove.length > 0) {
                const updates = {};
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
    }
    catch (error) {
        firebase_functions_1.logger.error("Error sending notification:", error);
        return null;
    }
});
//# sourceMappingURL=index.js.map