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
exports.onRandomChatConnectionCreated = exports.onRandomChatRequestAccepted = exports.onRandomChatRequestCreated = exports.randomChatDailyReset = exports.expireOldHelpRequests = exports.onHelpRequestAssigned = exports.onHelpRequestCreated = exports.cleanupOldGroupJoinRequests = exports.cleanupOldConnectionRequests = exports.onConnectionRequestAccepted = exports.onRandomGroupJoinRequestNotification = exports.onGroupJoinRequestNotification = exports.onConnectionRequestReceived = exports.onRandomGroupMessageNotification = exports.onNearbyGroupMessageNotification = exports.onGroupMessageNotification = exports.onMessageSent = exports.generateRandomChatSuggestions = void 0;
const firestore_1 = require("firebase-functions/v2/firestore");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const firebase_functions_1 = require("firebase-functions");
admin.initializeApp();
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
exports.generateRandomChatSuggestions = (0, https_1.onCall)({
    // Enforce authentication
    enforceAppCheck: false, // Set to true if App Check is enforced
}, async (request) => {
    // 1. Auth check
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Must be authenticated");
    }
    const currentUserId = request.auth.uid;
    const currentUserGender = request.data?.gender || null;
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
            const profileData = profileDoc.data();
            const cachedDate = profileData.randomChatSuggestionsDate;
            const cachedIds = profileData.randomChatSuggestionIds || [];
            if (cachedDate === dateKey && cachedIds.length > 0) {
                firebase_functions_1.logger.log(`Returning ${cachedIds.length} cached suggestions for ${currentUserId}`);
                return { suggestedIds: cachedIds, dateKey };
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
        const excludeIds = new Set();
        excludeIds.add(currentUserId);
        saturatedSnapshot.docs.forEach((doc) => excludeIds.add(doc.id));
        connectedSnapshot.docs.forEach((doc) => excludeIds.add(doc.id));
        firebase_functions_1.logger.log(`Exclude set: ${excludeIds.size} IDs ` +
            `(saturated=${saturatedSnapshot.size}, connected=${connectedSnapshot.size})`);
        const eligibleUsers = [];
        let lastDoc = null;
        let totalFetched = 0;
        for (let batch = 0; batch < MAX_BATCHES; batch++) {
            let query = db.collection("profiles")
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
                        gender: doc.data().gender,
                    });
                }
            }
            firebase_functions_1.logger.log(`Batch ${batch + 1}: fetched ${snapshot.size}, ` +
                `total eligible ${eligibleUsers.length}`);
            if (eligibleUsers.length >= TARGET_ELIGIBLE || snapshot.size < BATCH_SIZE) {
                break;
            }
            lastDoc = snapshot.docs[snapshot.docs.length - 1];
        }
        firebase_functions_1.logger.log(`Batched fetch complete: ${totalFetched} docs read, ` +
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
            return { suggestedIds: [], dateKey };
        }
        // 5. Apply gender priority logic
        let selectedUsers;
        if (currentUserGender) {
            const oppositeGender = getOppositeGender(currentUserGender);
            const oppositeGenderUsers = eligibleUsers.filter((u) => u.gender?.toLowerCase() === oppositeGender.toLowerCase());
            const otherUsers = eligibleUsers.filter((u) => !u.gender || u.gender.toLowerCase() !== oppositeGender.toLowerCase());
            // Shuffle both arrays
            shuffleArray(oppositeGenderUsers);
            shuffleArray(otherUsers);
            // Take opposite gender first, fill remaining with others
            selectedUsers = oppositeGenderUsers.slice(0, MAX_DAILY_USERS);
            if (selectedUsers.length < MAX_DAILY_USERS) {
                const remaining = MAX_DAILY_USERS - selectedUsers.length;
                selectedUsers.push(...otherUsers.slice(0, remaining));
            }
        }
        else {
            // No gender set - random selection
            shuffleArray(eligibleUsers);
            selectedUsers = eligibleUsers.slice(0, MAX_DAILY_USERS);
        }
        const suggestedIds = selectedUsers.map((u) => u.id);
        firebase_functions_1.logger.log(`Generated ${suggestedIds.length} suggestions for ${currentUserId}: ` +
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
        return { suggestedIds, dateKey };
    }
    catch (error) {
        firebase_functions_1.logger.error("Error generating random chat suggestions:", error);
        throw new https_1.HttpsError("internal", "Failed to generate suggestions");
    }
});
/** Fisher-Yates shuffle (in-place). */
function shuffleArray(array) {
    for (let i = array.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [array[i], array[j]] = [array[j], array[i]];
    }
}
/** Returns the opposite gender string. */
function getOppositeGender(gender) {
    switch (gender.toLowerCase()) {
        case "male": return "female";
        case "female": return "male";
        default: return ""; // non-binary or other - no priority
    }
}
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
    // Get sender info from participantInfo (Flutter app stores it here)
    // Fallback to fetching from users collection if not found
    let senderName = conversation.participantInfo?.[senderId]?.displayName;
    if (!senderName) {
        // Try to get name from users collection as fallback
        const senderDoc = await admin
            .firestore()
            .collection("users")
            .doc(senderId)
            .get();
        if (senderDoc.exists) {
            const senderData = senderDoc.data();
            senderName = senderData?.displayName || senderData?.username || "Someone";
        }
        else {
            senderName = "Someone";
        }
    }
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
    // Check notification preferences
    const notifPrefs = userData?.notificationPreferences;
    if (notifPrefs?.directMessages === false) {
        firebase_functions_1.logger.log(`Skipping notification for ${recipientId}: direct messages disabled`);
        return null;
    }
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
                    // Group notifications from same sender together to avoid flooding
                    tag: `chat_${senderId}`,
                },
            },
            apns: {
                payload: {
                    aps: {
                        sound: "default",
                        badge: 1,
                        // Group notifications from same sender together on iOS
                        threadId: `chat_${senderId}`,
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
        // Check notification preferences
        const notifPrefs = userData?.notificationPreferences;
        if (notifPrefs?.locationGroups === false) {
            firebase_functions_1.logger.log(`Skipping notification for ${memberUserId}: location groups disabled`);
            continue;
        }
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
 * Send push notification when a new nearby group message is sent.
 * Notifies all members except the sender.
 * Similar to location groups but for Bluetooth-based nearby groups.
 */
exports.onNearbyGroupMessageNotification = (0, firestore_1.onDocumentCreated)("nearby_groups/{groupId}/messages/{messageId}", async (event) => {
    const message = event.data?.data();
    if (!message)
        return;
    const groupId = event.params.groupId;
    const senderId = message.senderId;
    const senderName = message.senderName || "Someone";
    const messageText = message.text || "Sent a message";
    // Skip system messages
    if (message.type === "system") {
        firebase_functions_1.logger.log("Skipping notification for system message in nearby group");
        return null;
    }
    // Get group info
    const groupDoc = await admin
        .firestore()
        .collection("nearby_groups")
        .doc(groupId)
        .get();
    if (!groupDoc.exists) {
        firebase_functions_1.logger.log("Nearby group not found");
        return null;
    }
    const groupData = groupDoc.data();
    const groupName = groupData?.name || "Nearby Group";
    // Get all members except sender
    const membersSnapshot = await admin
        .firestore()
        .collection("nearby_groups")
        .doc(groupId)
        .collection("members")
        .get();
    if (membersSnapshot.empty) {
        firebase_functions_1.logger.log("No members found in nearby group");
        return null;
    }
    // Collect all tokens from all members (except sender)
    const allTokens = [];
    const tokenToUserMap = new Map();
    for (const memberDoc of membersSnapshot.docs) {
        // const memberData = memberDoc.data();
        const memberUserId = memberDoc.id; // Document ID is the user ID
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
        // Check notification preferences
        const notifPrefs = userData?.notificationPreferences;
        if (notifPrefs?.nearbyGroups === false) {
            firebase_functions_1.logger.log(`Skipping notification for ${memberUserId}: nearby groups disabled`);
            continue;
        }
        const fcmTokens = userData?.fcmTokens || {};
        const tokens = Object.keys(fcmTokens);
        for (const token of tokens) {
            allTokens.push(token);
            tokenToUserMap.set(token, memberUserId);
        }
    }
    if (allTokens.length === 0) {
        firebase_functions_1.logger.log("No FCM tokens for any nearby group members");
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
            type: "nearby_group_message",
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
                    tag: `nearby_group_${groupId}`, // Group notifications together
                },
            },
            apns: {
                payload: {
                    aps: {
                        sound: "default",
                        badge: 1,
                        threadId: `nearby_group_${groupId}`, // Group notifications together on iOS
                    },
                },
            },
        });
        firebase_functions_1.logger.log(`Nearby group notification: ${response.successCount} sent, ` +
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
        firebase_functions_1.logger.error("Error sending nearby group notification:", error);
        return null;
    }
});
/**
 * Send push notification when a new random group message is sent.
 * Notifies all members except the sender.
 * Random groups are internet-based, admin-approved communities.
 */
exports.onRandomGroupMessageNotification = (0, firestore_1.onDocumentCreated)("random_groups/{groupId}/messages/{messageId}", async (event) => {
    const message = event.data?.data();
    if (!message)
        return;
    const groupId = event.params.groupId;
    const senderId = message.senderId;
    const senderName = message.senderName || message.senderUsername || "Someone";
    const messageText = message.text || "Sent a message";
    // Skip system messages
    if (message.type === "system") {
        firebase_functions_1.logger.log("Skipping notification for system message in random group");
        return null;
    }
    // Get group info
    const groupDoc = await admin
        .firestore()
        .collection("random_groups")
        .doc(groupId)
        .get();
    if (!groupDoc.exists) {
        firebase_functions_1.logger.log("Random group not found");
        return null;
    }
    const groupData = groupDoc.data();
    const groupName = groupData?.name || "Random Group";
    // Get all members (stored in subcollection)
    const membersSnapshot = await admin
        .firestore()
        .collection("random_groups")
        .doc(groupId)
        .collection("members")
        .get();
    if (membersSnapshot.empty) {
        firebase_functions_1.logger.log("No members found in random group");
        return null;
    }
    // Collect all tokens from all members (except sender)
    const allTokens = [];
    const tokenToUserMap = new Map();
    for (const memberDoc of membersSnapshot.docs) {
        const memberUserId = memberDoc.id; // Document ID is the user ID
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
        // Check notification preferences
        const notifPrefs = userData?.notificationPreferences;
        if (notifPrefs?.randomGroups === false) {
            firebase_functions_1.logger.log(`Skipping notification for ${memberUserId}: random groups disabled`);
            continue;
        }
        const fcmTokens = userData?.fcmTokens || {};
        const tokens = Object.keys(fcmTokens);
        for (const token of tokens) {
            allTokens.push(token);
            tokenToUserMap.set(token, memberUserId);
        }
    }
    if (allTokens.length === 0) {
        firebase_functions_1.logger.log("No FCM tokens for any random group members");
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
            type: "random_group_message",
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
                    tag: `random_group_${groupId}`, // Group notifications together
                },
            },
            apns: {
                payload: {
                    aps: {
                        sound: "default",
                        badge: 1,
                        threadId: `random_group_${groupId}`, // Group notifications together on iOS
                    },
                },
            },
        });
        firebase_functions_1.logger.log(`Random group notification: ${response.successCount} sent, ` +
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
        firebase_functions_1.logger.error("Error sending random group notification:", error);
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
 * Send push notification when a user requests to join a random group.
 * Notifies all admins of the group.
 */
exports.onRandomGroupJoinRequestNotification = (0, firestore_1.onDocumentCreated)("random_groups/{groupId}/join_requests/{requestId}", async (event) => {
    const request = event.data?.data();
    if (!request)
        return;
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
        firebase_functions_1.logger.log("Random group not found");
        return null;
    }
    const groupData = groupDoc.data();
    const groupName = groupData?.name || "Group";
    const adminIds = (groupData?.adminIds || []);
    if (adminIds.length === 0) {
        firebase_functions_1.logger.log("No admins found for random group");
        return null;
    }
    // Collect all admin tokens
    const allTokens = [];
    const tokenToUserMap = new Map();
    for (const adminUserId of adminIds) {
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
        firebase_functions_1.logger.log("No FCM tokens for any admins in random group");
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
        firebase_functions_1.logger.log(`Random group join request notification: ${response.successCount} sent, ` +
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
        firebase_functions_1.logger.error("Error sending random group join request notification:", error);
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
    if (distanceMeters < 2000)
        return "Within 2km";
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
    firebase_functions_1.logger.log(`Seeker location: lat=${seekerLat}, lon=${seekerLon}`);
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
        const tokensToNotify = [];
        let usersChecked = 0;
        let usersWithLocations = 0;
        let usersWithTokens = 0;
        let usersOptedOut = 0;
        for (const userDoc of usersSnapshot.docs) {
            const userId = userDoc.id;
            usersChecked++;
            // Skip the seeker themselves
            if (userId === seekerId)
                continue;
            const userData = userDoc.data();
            // CRITICAL FIX: Check if user has EXPLICITLY opted out of help alerts.
            // Default behavior: if nearbyHelpSettings doesn't exist OR receiveHelpAlerts
            // is undefined/null, the user SHOULD receive alerts (opt-out model, not opt-in).
            const helpSettings = userData?.nearbyHelpSettings;
            if (helpSettings?.receiveHelpAlerts === false) {
                usersOptedOut++;
                firebase_functions_1.logger.log(`User ${userId} explicitly opted out of help alerts`);
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
                    firebase_functions_1.logger.log(`User ${userId} location ${locationDoc.id} is inactive, skipping`);
                    continue;
                }
                const userLat = location.latitude;
                const userLon = location.longitude;
                if (userLat == null || userLon == null) {
                    firebase_functions_1.logger.log(`User ${userId} location ${locationDoc.id} has invalid coords`);
                    continue;
                }
                const distance = calculateDistance(seekerLat, seekerLon, userLat, userLon);
                firebase_functions_1.logger.log(`User ${userId} location ${locationDoc.id}: ` +
                    `distance=${distance.toFixed(2)}m, radius=${radiusMeters}m`);
                // Check if within radius
                if (distance <= radiusMeters) {
                    // Add all tokens for this user
                    for (const token of tokens) {
                        tokensToNotify.push({ token, userId, distance });
                    }
                    userMatched = true;
                    firebase_functions_1.logger.log(`User ${userId} is within radius! Adding ${tokens.length} token(s)`);
                    // Only count user once (break after first matching location)
                    break;
                }
            }
            if (!userMatched) {
                firebase_functions_1.logger.log(`User ${userId} has locations but none within ${radiusMeters}m radius`);
            }
        }
        firebase_functions_1.logger.log(`Stats: checked=${usersChecked}, withTokens=${usersWithTokens}, ` +
            `withLocations=${usersWithLocations}, optedOut=${usersOptedOut}`);
        if (tokensToNotify.length === 0) {
            firebase_functions_1.logger.log("No nearby users found for help request - this could indicate:");
            firebase_functions_1.logger.log("1. No users have saved locations within the radius");
            firebase_functions_1.logger.log("2. All nearby users have opted out of help alerts");
            firebase_functions_1.logger.log("3. Nearby users don't have FCM tokens (not logged in)");
            return null;
        }
        const uniqueUserCount = [...new Set(tokensToNotify.map(t => t.userId))].length;
        firebase_functions_1.logger.log(`Found ${tokensToNotify.length} tokens to notify from ` +
            `${uniqueUserCount} users`);
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
        const seekerId = afterData.seekerUserId;
        const helperId = afterData.helperUserId;
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
        const seekerId = afterData.seekerUserId;
        const helperId = afterData.helperUserId;
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
        const helperId = afterData.helperUserId;
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
 * Runs every 10 minutes to check for requests that have passed their expiresAt time.
 */
exports.expireOldHelpRequests = (0, scheduler_1.onSchedule)("every 10 minutes", async () => {
    const now = admin.firestore.Timestamp.now();
    firebase_functions_1.logger.log("Checking for expired help requests...");
    try {
        // Find open requests that have passed their expiration time
        const expiredRequests = await admin
            .firestore()
            .collection("help_requests")
            .where("status", "==", "OPEN")
            .where("expiresAt", "<", now)
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
            const seekerId = request.seekerUserId;
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
exports.randomChatDailyReset = (0, scheduler_1.onSchedule)({
    schedule: "0 0 * * *", // Every day at midnight (UTC)
    timeZone: "UTC",
    retryCount: 3,
}, async () => {
    firebase_functions_1.logger.log("Running Random Chat daily reset...");
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
        firebase_functions_1.logger.log(`Cleaning up random chat data for date: ${oldDateKey}`);
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
            firebase_functions_1.logger.log(`Deleted ${deleted} docs from ${subcol} for ${oldDateKey}`);
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
                    batch.update(doc.ref, { status: "expired" });
                });
                await batch.commit();
            }
            firebase_functions_1.logger.log(`Expired ${yesterdayRequests.size} pending requests from ${yesterdayKey}`);
        }
        firebase_functions_1.logger.log("Random Chat daily reset complete");
    }
    catch (error) {
        firebase_functions_1.logger.error("Error in Random Chat daily reset:", error);
    }
});
/**
 * Cloud Function triggered when a random chat request is created.
 * Sends a push notification to the receiver.
 */
exports.onRandomChatRequestCreated = (0, firestore_1.onDocumentCreated)("random_chat_daily/{dateKey}/requests/{requestId}", async (event) => {
    const request = event.data?.data();
    if (!request)
        return;
    const receiverId = request.receiverId;
    const senderName = request.senderDisplayName || "Someone";
    try {
        // Get receiver's FCM tokens
        const userDoc = await admin
            .firestore()
            .collection("users")
            .doc(receiverId)
            .get();
        if (!userDoc.exists)
            return;
        const userData = userDoc.data();
        const fcmTokens = userData?.fcmTokens || {};
        const tokens = Object.keys(fcmTokens);
        if (tokens.length === 0)
            return;
        await admin.messaging().sendEachForMulticast({
            tokens: tokens,
            notification: {
                title: "New Random Chat Request",
                body: `${senderName} wants to chat with you!`,
            },
            data: {
                type: "random_chat_request",
                requestId: event.params.requestId,
                senderId: request.senderId,
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
        firebase_functions_1.logger.log(`Sent random chat request notification to ${receiverId}`);
    }
    catch (error) {
        firebase_functions_1.logger.error("Error sending random chat notification:", error);
    }
});
/**
 * Cloud Function triggered when a random chat request is accepted.
 * Notifies the sender that their request was accepted.
 */
exports.onRandomChatRequestAccepted = (0, firestore_1.onDocumentUpdated)("random_chat_daily/{dateKey}/requests/{requestId}", async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after)
        return;
    // Only trigger on status change to 'accepted'
    if (before.status === after.status || after.status !== "accepted")
        return;
    const senderId = after.senderId;
    const receiverName = after.receiverDisplayName || "Someone";
    try {
        const userDoc = await admin
            .firestore()
            .collection("users")
            .doc(senderId)
            .get();
        if (!userDoc.exists)
            return;
        const userData = userDoc.data();
        const fcmTokens = userData?.fcmTokens || {};
        const tokens = Object.keys(fcmTokens);
        if (tokens.length === 0)
            return;
        await admin.messaging().sendEachForMulticast({
            tokens: tokens,
            notification: {
                title: "Request Accepted!",
                body: `${receiverName} accepted your Random Chat request!`,
            },
            data: {
                type: "random_chat_accepted",
                requestId: event.params.requestId,
                receiverId: after.receiverId,
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
        firebase_functions_1.logger.log(`Sent random chat acceptance notification to ${senderId}`);
    }
    catch (error) {
        firebase_functions_1.logger.error("Error sending acceptance notification:", error);
    }
});
/**
 * Cloud Function triggered when a random chat connection is created.
 *
 * Expires ALL other pending requests involving either connected user.
 * This is the authoritative server-side cleanup — the client can only
 * expire its own requests (Firestore rules), so this function handles
 * the other user's pending requests as well.
 */
exports.onRandomChatConnectionCreated = (0, firestore_1.onDocumentCreated)("random_chat_daily/{dateKey}/connections/{connectionId}", async (event) => {
    const connection = event.data?.data();
    if (!connection)
        return;
    const dateKey = event.params.dateKey;
    const user1Id = connection.user1Id;
    const user2Id = connection.user2Id;
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
        firebase_functions_1.logger.log(`Expired pending requests for connected users ${user1Id} & ${user2Id}`);
    }
    catch (error) {
        firebase_functions_1.logger.error("Error expiring requests after connection created:", error);
    }
});
//# sourceMappingURL=index.js.map