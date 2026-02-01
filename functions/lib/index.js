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
exports.expireOldHelpRequests = exports.onHelpRequestAssigned = exports.onHelpRequestCreated = exports.cleanupOldGroupJoinRequests = exports.cleanupOldConnectionRequests = exports.cleanupExpiredGuessMeSessions = exports.onConnectionRequestAccepted = exports.onGroupJoinRequestNotification = exports.onConnectionRequestReceived = exports.onGroupMessageNotification = exports.onMessageSent = void 0;
const firestore_1 = require("firebase-functions/v2/firestore");
const scheduler_1 = require("firebase-functions/v2/scheduler");
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
 * Send push notification when a new group message is sent.
 * Notifies all active group members except the sender.
 * Groups notifications together per group on Android (tag) and iOS (threadId).
 */
exports.onGroupMessageNotification = (0, firestore_1.onDocumentCreated)("location_groups/{groupId}/messages/{messageId}", async (event) => {
    const message = event.data?.data();
    if (!message)
        return;
    const groupId = event.params.groupId;
    const senderId = message.senderId;
    const senderName = message.senderName || "Someone";
    const messageText = message.text || "Sent a message";
    // Skip system messages
    if (message.type === "system") {
        firebase_functions_1.logger.log("Skipping notification for system message");
        return null;
    }
    // Get group info
    const groupDoc = await admin
        .firestore()
        .collection("location_groups")
        .doc(groupId)
        .get();
    if (!groupDoc.exists) {
        firebase_functions_1.logger.log("Group not found");
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
        firebase_functions_1.logger.log("No active members found");
        return null;
    }
    // Collect all tokens from all members (except sender)
    const allTokens = [];
    const tokenToUserMap = new Map();
    for (const memberDoc of membersSnapshot.docs) {
        const memberData = memberDoc.data();
        const memberUserId = memberData.userId;
        // Skip the sender
        if (memberUserId === senderId)
            continue;
        // Get user's FCM tokens
        const userDoc = await admin
            .firestore()
            .collection("users")
            .doc(memberUserId)
            .get();
        if (!userDoc.exists)
            continue;
        const userData = userDoc.data();
        const fcmTokens = userData?.fcmTokens || {};
        const tokens = Object.keys(fcmTokens);
        for (const token of tokens) {
            allTokens.push(token);
            tokenToUserMap.set(token, memberUserId);
        }
    }
    if (allTokens.length === 0) {
        firebase_functions_1.logger.log("No FCM tokens for any group members");
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
        firebase_functions_1.logger.log(`Group notification: ${response.successCount} sent, ` +
            `${response.failureCount} failed to ${allTokens.length} tokens`);
        // Remove invalid tokens
        if (response.failureCount > 0) {
            const invalidTokensByUser = new Map();
            response.responses.forEach((resp, idx) => {
                if (!resp.success) {
                    const token = allTokens[idx];
                    const userId = tokenToUserMap.get(token);
                    if (userId) {
                        if (!invalidTokensByUser.has(userId)) {
                            invalidTokensByUser.set(userId, []);
                        }
                        invalidTokensByUser.get(userId).push(token);
                    }
                }
            });
            // Remove invalid tokens for each user
            for (const [userId, tokens] of invalidTokensByUser) {
                const updates = {};
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
    }
    catch (error) {
        firebase_functions_1.logger.error("Error sending group notification:", error);
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
/**
 * Send push notification to group admins when someone requests to join.
 * Only applies to private groups (requestToJoin visibility).
 */
exports.onGroupJoinRequestNotification = (0, firestore_1.onDocumentCreated)("location_groups/{groupId}/join_requests/{requestId}", async (event) => {
    const request = event.data?.data();
    if (!request)
        return;
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
        firebase_functions_1.logger.log("Group not found");
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
        firebase_functions_1.logger.log("No active admins found");
        return null;
    }
    // Collect all admin tokens
    const allTokens = [];
    const tokenToUserMap = new Map();
    for (const adminDoc of adminsSnapshot.docs) {
        const adminData = adminDoc.data();
        const adminUserId = adminData.userId;
        // Get admin's FCM tokens
        const userDoc = await admin
            .firestore()
            .collection("users")
            .doc(adminUserId)
            .get();
        if (!userDoc.exists)
            continue;
        const userData = userDoc.data();
        const fcmTokens = userData?.fcmTokens || {};
        const tokens = Object.keys(fcmTokens);
        for (const token of tokens) {
            allTokens.push(token);
            tokenToUserMap.set(token, adminUserId);
        }
    }
    if (allTokens.length === 0) {
        firebase_functions_1.logger.log("No FCM tokens for any admins");
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
        firebase_functions_1.logger.log(`Join request notification: ${response.successCount} sent, ` +
            `${response.failureCount} failed`);
        // Remove invalid tokens
        if (response.failureCount > 0) {
            const invalidTokensByUser = new Map();
            response.responses.forEach((resp, idx) => {
                if (!resp.success) {
                    const token = allTokens[idx];
                    const userId = tokenToUserMap.get(token);
                    if (userId) {
                        if (!invalidTokensByUser.has(userId)) {
                            invalidTokensByUser.set(userId, []);
                        }
                        invalidTokensByUser.get(userId).push(token);
                    }
                }
            });
            // Remove invalid tokens for each user
            for (const [userId, tokens] of invalidTokensByUser) {
                const updates = {};
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
    }
    catch (error) {
        firebase_functions_1.logger.error("Error sending join request notification:", error);
        return null;
    }
});
/**
 * Send push notification when connection request is accepted.
 * Notifies the original sender.
 */
exports.onConnectionRequestAccepted = (0, firestore_1.onDocumentUpdated)("connection_requests/{requestId}", async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after)
        return null;
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
        firebase_functions_1.logger.log("Sender not found");
        return null;
    }
    const senderData = senderDoc.data();
    const fcmTokens = senderData?.fcmTokens || {};
    const tokens = Object.keys(fcmTokens);
    if (tokens.length === 0) {
        firebase_functions_1.logger.log("No FCM tokens for sender");
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
        firebase_functions_1.logger.log(`Connection accepted notification: ${response.successCount} ` +
            `sent, ${response.failureCount} failed`);
        // Remove invalid tokens
        if (response.failureCount > 0) {
            const invalidTokens = [];
            response.responses.forEach((resp, idx) => {
                if (!resp.success) {
                    invalidTokens.push(tokens[idx]);
                }
            });
            if (invalidTokens.length > 0) {
                const updates = {};
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
    }
    catch (error) {
        firebase_functions_1.logger.error("Error sending connection accepted notification:", error);
        return null;
    }
});
/**
 * Scheduled function to clean up expired GuessMe sessions.
 * Runs daily at 2:00 AM UTC. Deletes sessions older than 7 days.
 */
exports.cleanupExpiredGuessMeSessions = (0, scheduler_1.onSchedule)({
    schedule: "0 2 * * *", // Daily at 2 AM UTC
    timeZone: "UTC",
}, async () => {
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
            firebase_functions_1.logger.log("No expired GuessMe sessions to clean up");
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
        firebase_functions_1.logger.log(`Cleaned up ${totalDeleted} expired GuessMe sessions`);
    }
    catch (error) {
        firebase_functions_1.logger.error("Error cleaning up GuessMe sessions:", error);
    }
});
/**
 * Scheduled function to clean up old connection requests.
 * Runs daily at 2:30 AM UTC.
 * Deletes rejected/cancelled requests older than 30 days.
 * Deletes pending requests older than 90 days.
 */
exports.cleanupOldConnectionRequests = (0, scheduler_1.onSchedule)({
    schedule: "30 2 * * *", // Daily at 2:30 AM UTC
    timeZone: "UTC",
}, async () => {
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
            firebase_functions_1.logger.log("No old connection requests to clean up");
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
        firebase_functions_1.logger.log(`Cleaned up ${totalDeleted} old connection requests`);
    }
    catch (error) {
        firebase_functions_1.logger.error("Error cleaning up connection requests:", error);
    }
});
/**
 * Scheduled function to clean up old group join requests.
 * Runs daily at 3:00 AM UTC.
 * Deletes rejected requests older than 30 days.
 * Deletes pending requests older than 60 days.
 */
exports.cleanupOldGroupJoinRequests = (0, scheduler_1.onSchedule)({
    schedule: "0 3 * * *", // Daily at 3 AM UTC
    timeZone: "UTC",
}, async () => {
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
            firebase_functions_1.logger.log("No groups found");
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
        firebase_functions_1.logger.log(`Cleaned up ${totalDeleted} old group join requests`);
    }
    catch (error) {
        firebase_functions_1.logger.error("Error cleaning up group join requests:", error);
    }
});
// ============================================================================
// NEARBY HELP FUNCTIONS
// ============================================================================
/**
 * Calculate distance between two points using Haversine formula.
 * Returns distance in meters.
 */
function calculateDistance(lat1, lon1, lat2, lon2) {
    const R = 6371000; // Earth's radius in meters
    const dLat = ((lat2 - lat1) * Math.PI) / 180;
    const dLon = ((lon2 - lon1) * Math.PI) / 180;
    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
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
function getApproximateDistance(distanceMeters) {
    if (distanceMeters < 50)
        return "Very close (~50m)";
    if (distanceMeters < 100)
        return "Nearby (~100m)";
    if (distanceMeters < 250)
        return "Within 250m";
    if (distanceMeters < 500)
        return "Within 500m";
    if (distanceMeters < 1000)
        return "Within 1km";
    return "Over 1km away";
}
/**
 * Send push notification when a new help request is created.
 * Notifies nearby users who have help alerts enabled.
 */
exports.onHelpRequestCreated = (0, firestore_1.onDocumentCreated)("help_requests/{requestId}", async (event) => {
    const helpRequest = event.data?.data();
    if (!helpRequest)
        return;
    const requestId = event.params.requestId;
    const seekerId = helpRequest.seekerUserId;
    const radiusMeters = helpRequest.radius || 100;
    const seekerLat = helpRequest.latitude;
    const seekerLon = helpRequest.longitude;
    const topic = helpRequest.topic || "General help";
    firebase_functions_1.logger.log(`New help request created: ${requestId} with radius ${radiusMeters}m`);
    try {
        // Get all users with help alerts enabled
        const usersSnapshot = await admin
            .firestore()
            .collection("users")
            .get();
        const tokensToNotify = [];
        for (const userDoc of usersSnapshot.docs) {
            const userId = userDoc.id;
            // Skip the seeker themselves
            if (userId === seekerId)
                continue;
            const userData = userDoc.data();
            // Check if user has opted in for help alerts
            const helpSettings = userData?.nearbyHelpSettings;
            if (helpSettings?.receiveHelpAlerts === false)
                continue;
            // Check if user has FCM tokens
            const fcmTokens = userData?.fcmTokens || {};
            const tokens = Object.keys(fcmTokens);
            if (tokens.length === 0)
                continue;
            // Get user's locations (home/work)
            const locationsSnapshot = await admin
                .firestore()
                .collection("users")
                .doc(userId)
                .collection("locations")
                .get();
            // Check each location for proximity
            for (const locationDoc of locationsSnapshot.docs) {
                const location = locationDoc.data();
                // Skip if this location is not active for help alerts
                if (location.isActive === false)
                    continue;
                const userLat = location.latitude;
                const userLon = location.longitude;
                if (userLat == null || userLon == null)
                    continue;
                const distance = calculateDistance(seekerLat, seekerLon, userLat, userLon);
                // Check if within radius
                if (distance <= radiusMeters) {
                    // Add all tokens for this user
                    for (const token of tokens) {
                        tokensToNotify.push({ token, userId, distance });
                    }
                    // Only count user once (break after first matching location)
                    break;
                }
            }
        }
        if (tokensToNotify.length === 0) {
            firebase_functions_1.logger.log("No nearby users found for help request");
            return null;
        }
        firebase_functions_1.logger.log(`Found ${tokensToNotify.length} tokens to notify`);
        // Get seeker's name
        const seekerDoc = await admin
            .firestore()
            .collection("users")
            .doc(seekerId)
            .get();
        const seekerName = seekerDoc.data()?.displayName || "Someone nearby";
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
                firebase_functions_1.logger.log(`User ${userId}: Sent ${response.successCount}, Failed ${response.failureCount}`);
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
                            .doc(userId)
                            .update(updates);
                    }
                }
            }
            catch (error) {
                firebase_functions_1.logger.error(`Error sending to user ${userId}:`, error);
            }
        }
        // Update the request with notification count
        await admin
            .firestore()
            .collection("help_requests")
            .doc(requestId)
            .update({
            notifiedUsersCount: uniqueUsers.length,
            notifiedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return { notifiedUsers: uniqueUsers.length };
    }
    catch (error) {
        firebase_functions_1.logger.error("Error in onHelpRequestCreated:", error);
        return null;
    }
});
/**
 * Send push notification when a helper is assigned to a request.
 * Notifies the seeker that help is on the way.
 */
exports.onHelpRequestAssigned = (0, firestore_1.onDocumentUpdated)("help_requests/{requestId}", async (event) => {
    const beforeData = event.data?.before.data();
    const afterData = event.data?.after.data();
    if (!beforeData || !afterData)
        return;
    // Check if status changed to IN_PROGRESS (helper assigned)
    if (beforeData.status !== "IN_PROGRESS" && afterData.status === "IN_PROGRESS") {
        const requestId = event.params.requestId;
        const seekerId = afterData.seekerId;
        const helperId = afterData.helperId;
        if (!helperId) {
            firebase_functions_1.logger.log("No helper ID in assigned request");
            return null;
        }
        firebase_functions_1.logger.log(`Help request ${requestId} assigned to helper ${helperId}`);
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
                firebase_functions_1.logger.log("Seeker not found");
                return null;
            }
            const seekerData = seekerDoc.data();
            const fcmTokens = seekerData?.fcmTokens || {};
            const tokens = Object.keys(fcmTokens);
            if (tokens.length === 0) {
                firebase_functions_1.logger.log("No FCM tokens for seeker");
                return null;
            }
            const payload = {
                notification: {
                    title: "✅ Help is on the way!",
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
            firebase_functions_1.logger.log(`Seeker notification: Sent ${response.successCount}, Failed ${response.failureCount}`);
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
                        .doc(seekerId)
                        .update(updates);
                }
            }
            return response;
        }
        catch (error) {
            firebase_functions_1.logger.error("Error in onHelpRequestAssigned:", error);
            return null;
        }
    }
    // Check if status changed to RESOLVED (help completed)
    if (beforeData.status !== "RESOLVED" && afterData.status === "RESOLVED") {
        const requestId = event.params.requestId;
        const seekerId = afterData.seekerId;
        const helperId = afterData.helperId;
        const completedBy = afterData.completedBy;
        firebase_functions_1.logger.log(`Help request ${requestId} completed by ${completedBy}`);
        try {
            // Notify the other party
            const notifyUserId = completedBy === seekerId ? helperId : seekerId;
            if (!notifyUserId) {
                firebase_functions_1.logger.log("No user to notify");
                return null;
            }
            const userDoc = await admin
                .firestore()
                .collection("users")
                .doc(notifyUserId)
                .get();
            if (!userDoc.exists) {
                firebase_functions_1.logger.log("User to notify not found");
                return null;
            }
            const userData = userDoc.data();
            const fcmTokens = userData?.fcmTokens || {};
            const tokens = Object.keys(fcmTokens);
            if (tokens.length === 0) {
                firebase_functions_1.logger.log("No FCM tokens for user to notify");
                return null;
            }
            const isSeeker = notifyUserId === seekerId;
            const payload = {
                notification: {
                    title: "🎉 Help Request Completed",
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
            firebase_functions_1.logger.log(`Completion notification: Sent ${response.successCount}, Failed ${response.failureCount}`);
            return response;
        }
        catch (error) {
            firebase_functions_1.logger.error("Error sending completion notification:", error);
            return null;
        }
    }
    // Check if status changed to CANCELLED
    if (beforeData.status !== "CANCELLED" && afterData.status === "CANCELLED") {
        const requestId = event.params.requestId;
        const helperId = afterData.helperId;
        const cancelledBy = afterData.cancelledBy;
        // Only notify helper if request was assigned and cancelled by seeker
        if (!helperId || cancelledBy === helperId) {
            return null;
        }
        firebase_functions_1.logger.log(`Help request ${requestId} cancelled, notifying helper`);
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
        }
        catch (error) {
            firebase_functions_1.logger.error("Error sending cancellation notification:", error);
            return null;
        }
    }
    return null;
});
/**
 * Scheduled function to expire old help requests.
 * Runs every 15 minutes to check for requests older than 1 hour.
 */
exports.expireOldHelpRequests = (0, scheduler_1.onSchedule)("every 15 minutes", async () => {
    const oneHourAgo = admin.firestore.Timestamp.fromDate(new Date(Date.now() - 60 * 60 * 1000));
    firebase_functions_1.logger.log("Checking for expired help requests...");
    try {
        // Find open requests older than 1 hour
        const expiredRequests = await admin
            .firestore()
            .collection("help_requests")
            .where("status", "==", "OPEN")
            .where("createdAt", "<", oneHourAgo)
            .get();
        if (expiredRequests.empty) {
            firebase_functions_1.logger.log("No expired requests found");
            return;
        }
        firebase_functions_1.logger.log(`Found ${expiredRequests.size} expired requests`);
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
            const seekerId = request.seekerId;
            try {
                const seekerDoc = await admin
                    .firestore()
                    .collection("users")
                    .doc(seekerId)
                    .get();
                if (!seekerDoc.exists)
                    continue;
                const seekerData = seekerDoc.data();
                const fcmTokens = seekerData?.fcmTokens || {};
                const tokens = Object.keys(fcmTokens);
                if (tokens.length === 0)
                    continue;
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
            }
            catch (error) {
                firebase_functions_1.logger.error(`Error notifying seeker ${seekerId}:`, error);
            }
        }
        firebase_functions_1.logger.log(`Expired ${expiredRequests.size} help requests`);
    }
    catch (error) {
        firebase_functions_1.logger.error("Error expiring help requests:", error);
    }
});
//# sourceMappingURL=index.js.map