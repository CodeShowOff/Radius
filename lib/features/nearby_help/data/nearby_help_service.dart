import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:logger/logger.dart';

import '../domain/entities/help_radius.dart';
import '../domain/entities/help_request.dart';
import '../domain/entities/help_request_status.dart';
import 'models/help_request_model.dart';

/// Result type for nearby help operations.
sealed class NearbyHelpResult<T> {
  const NearbyHelpResult();
}

class NearbyHelpSuccess<T> extends NearbyHelpResult<T> {
  final T data;
  const NearbyHelpSuccess(this.data);
}

class NearbyHelpFailure<T> extends NearbyHelpResult<T> {
  final String message;
  final NearbyHelpErrorType type;
  const NearbyHelpFailure(this.message, this.type);
}

enum NearbyHelpErrorType {
  /// Request not found
  notFound,

  /// Request already has a helper assigned
  alreadyAssigned,

  /// User is not authorized for this action
  unauthorized,

  /// Rate limit exceeded
  rateLimitExceeded,

  /// Request has expired
  expired,

  /// Network error
  networkError,

  /// Unknown error
  unknown,
}

/// Service for managing nearby help requests via Firestore.
///
/// Implements:
/// - Help request creation and management
/// - Atomic helper assignment (prevents race conditions)
/// - Geospatial queries for nearby users
/// - Real-time request status updates
/// - Rate limiting for spam prevention
///
/// Firestore Collections:
/// - `help_requests` - Active and historical help requests
/// - `users/{userId}/locations` - Saved user locations (home/work)
/// - `users/{userId}` - nearbyHelpSettings field for opt-in/opt-out
class NearbyHelpService {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final Logger _logger;

  // Collection references
  late final CollectionReference<Map<String, dynamic>> _helpRequestsRef;

  // Rate limit: max requests per hour per user
  static const int _maxRequestsPerHour = 5;

  // Request expiration time in minutes
  static const int _requestExpirationMinutes = 30;

  NearbyHelpService({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    Logger? logger,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance,
        _logger = logger ?? Logger() {
    _helpRequestsRef = _firestore.collection('help_requests');
  }

  // ==================== HELP REQUEST CREATION ====================

  /// Creates a new help request.
  ///
  /// Validates:
  /// - User is not rate limited
  /// - User doesn't have an active request already
  Future<NearbyHelpResult<HelpRequest>> createHelpRequest({
    required String seekerUserId,
    required String seekerName,
    String? seekerPhotoUrl,
    required double latitude,
    required double longitude,
    required HelpRadius radius,
    String? topic,
  }) async {
    try {
      // Check rate limit
      final rateLimitResult = await _checkRateLimit(seekerUserId);
      if (rateLimitResult != null) {
        return rateLimitResult;
      }

      // Check for existing active request
      final existingRequest = await _getActiveRequestForUser(seekerUserId);
      if (existingRequest != null) {
        return const NearbyHelpFailure(
          'You already have an active help request',
          NearbyHelpErrorType.rateLimitExceeded,
        );
      }

      final now = DateTime.now();
      final expiresAt = now.add(const Duration(minutes: _requestExpirationMinutes));
      final geoHash = _generateGeoHash(latitude, longitude);

      final requestModel = HelpRequestModel(
        id: '', // Will be set by Firestore
        seekerUserId: seekerUserId,
        seekerName: seekerName,
        seekerPhotoUrl: seekerPhotoUrl,
        latitude: latitude,
        longitude: longitude,
        radius: radius,
        topic: topic,
        status: HelpRequestStatus.open,
        createdAt: now,
        expiresAt: expiresAt,
        updatedAt: now,
        geoHash: geoHash,
      );

      // Create the request document
      final docRef = await _helpRequestsRef.add(requestModel.toFirestoreCreate());

      // Return the created request with the generated ID
      final createdRequest = HelpRequestModel(
        id: docRef.id,
        seekerUserId: seekerUserId,
        seekerName: seekerName,
        seekerPhotoUrl: seekerPhotoUrl,
        latitude: latitude,
        longitude: longitude,
        radius: radius,
        topic: topic,
        status: HelpRequestStatus.open,
        createdAt: now,
        expiresAt: expiresAt,
        updatedAt: now,
        geoHash: geoHash,
      );

      _logger.i('Created help request: ${docRef.id}');
      return NearbyHelpSuccess(createdRequest);
    } catch (e, stack) {
      _logger.e('Error creating help request', error: e, stackTrace: stack);
      return NearbyHelpFailure(
        'Failed to create help request: $e',
        NearbyHelpErrorType.unknown,
      );
    }
  }

  // ==================== HELPER ASSIGNMENT (ATOMIC) ====================

  /// Attempts to assign a helper to a request using atomic transaction.
  ///
  /// This prevents race conditions where multiple helpers try to accept
  /// the same request simultaneously. Only one will succeed.
  Future<NearbyHelpResult<HelpRequest>> acceptHelpRequest({
    required String requestId,
    required String helperUserId,
    required String helperName,
    String? helperPhotoUrl,
  }) async {
    try {
      return await _firestore.runTransaction<NearbyHelpResult<HelpRequest>>((transaction) async {
        // Get the current request state
        final docRef = _helpRequestsRef.doc(requestId);
        final snapshot = await transaction.get(docRef);

        if (!snapshot.exists) {
          return const NearbyHelpFailure(
            'Help request not found',
            NearbyHelpErrorType.notFound,
          );
        }

        final request = HelpRequestModel.fromFirestore(snapshot);

        // Check if request is still open
        if (request.status != HelpRequestStatus.open) {
          return const NearbyHelpFailure(
            'This request is already being handled by another helper',
            NearbyHelpErrorType.alreadyAssigned,
          );
        }

        // Check if request has expired
        if (DateTime.now().isAfter(request.expiresAt)) {
          // Mark as expired
          transaction.update(docRef, {
            'status': HelpRequestStatus.expired.value,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          return const NearbyHelpFailure(
            'This request has expired',
            NearbyHelpErrorType.expired,
          );
        }

        // Check that helper is not the seeker
        if (request.seekerUserId == helperUserId) {
          return const NearbyHelpFailure(
            'You cannot help your own request',
            NearbyHelpErrorType.unauthorized,
          );
        }

        // Atomically assign the helper
        transaction.update(docRef, {
          'helperUserId': helperUserId,
          'helperName': helperName,
          'helperPhotoUrl': helperPhotoUrl,
          'status': HelpRequestStatus.inProgress.value,
          'assignedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        _logger.i('Helper $helperUserId assigned to request $requestId');

        // Return updated request
        return NearbyHelpSuccess(request.copyWith(
          helperUserId: helperUserId,
          helperName: helperName,
          helperPhotoUrl: helperPhotoUrl,
          status: HelpRequestStatus.inProgress,
          assignedAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));
      });
    } catch (e, stack) {
      _logger.e('Error accepting help request', error: e, stackTrace: stack);
      return NearbyHelpFailure(
        'Failed to accept request: $e',
        NearbyHelpErrorType.unknown,
      );
    }
  }

  // ==================== STATUS UPDATES ====================

  /// Marks the helper as "on the way".
  Future<NearbyHelpResult<void>> markOnTheWay(String requestId, String helperUserId) async {
    try {
      final docRef = _helpRequestsRef.doc(requestId);
      final doc = await docRef.get();

      if (!doc.exists) {
        return const NearbyHelpFailure('Request not found', NearbyHelpErrorType.notFound);
      }

      final request = HelpRequestModel.fromFirestore(doc);

      if (request.helperUserId != helperUserId) {
        return const NearbyHelpFailure(
          'Only the assigned helper can update this request',
          NearbyHelpErrorType.unauthorized,
        );
      }

      await docRef.update({
        'helperOnTheWay': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return const NearbyHelpSuccess(null);
    } catch (e, stack) {
      _logger.e('Error marking on the way', error: e, stackTrace: stack);
      return NearbyHelpFailure('Failed to update: $e', NearbyHelpErrorType.unknown);
    }
  }

  /// Marks the help as completed.
  Future<NearbyHelpResult<void>> markCompleted(String requestId, String userId) async {
    try {
      final docRef = _helpRequestsRef.doc(requestId);
      final doc = await docRef.get();

      if (!doc.exists) {
        return const NearbyHelpFailure('Request not found', NearbyHelpErrorType.notFound);
      }

      final request = HelpRequestModel.fromFirestore(doc);

      // Only the seeker can mark as completed
      if (request.seekerUserId != userId) {
        return const NearbyHelpFailure(
          'Only the help seeker can mark this request as completed',
          NearbyHelpErrorType.unauthorized,
        );
      }

      await docRef.update({
        'status': HelpRequestStatus.resolved.value,
        'resolvedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'completedBy': userId,
      });

      _logger.i('Help request $requestId marked as completed');
      return const NearbyHelpSuccess(null);
    } catch (e, stack) {
      _logger.e('Error marking completed', error: e, stackTrace: stack);
      return NearbyHelpFailure('Failed to complete: $e', NearbyHelpErrorType.unknown);
    }
  }

  /// Cancels a help request (seeker only).
  Future<NearbyHelpResult<void>> cancelRequest(String requestId, String seekerUserId) async {
    try {
      final docRef = _helpRequestsRef.doc(requestId);
      final doc = await docRef.get();

      if (!doc.exists) {
        return const NearbyHelpFailure('Request not found', NearbyHelpErrorType.notFound);
      }

      final request = HelpRequestModel.fromFirestore(doc);

      if (request.seekerUserId != seekerUserId) {
        return const NearbyHelpFailure(
          'Only the seeker can cancel this request',
          NearbyHelpErrorType.unauthorized,
        );
      }

      await docRef.update({
        'status': HelpRequestStatus.cancelled.value,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _logger.i('Help request $requestId cancelled');
      return const NearbyHelpSuccess(null);
    } catch (e, stack) {
      _logger.e('Error cancelling request', error: e, stackTrace: stack);
      return NearbyHelpFailure('Failed to cancel: $e', NearbyHelpErrorType.unknown);
    }
  }

  // ==================== QUERIES ====================

  /// Gets a help request by ID.
  Future<HelpRequest?> getHelpRequest(String requestId) async {
    try {
      final doc = await _helpRequestsRef.doc(requestId).get();
      if (!doc.exists) return null;
      return HelpRequestModel.fromFirestore(doc);
    } catch (e, stack) {
      _logger.e('Error getting help request', error: e, stackTrace: stack);
      return null;
    }
  }

  /// Streams a help request for real-time updates.
  Stream<HelpRequest?> streamHelpRequest(String requestId) {
    return _helpRequestsRef.doc(requestId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return HelpRequestModel.fromFirestore(doc);
    });
  }

  /// Gets the active help request for a user (as seeker).
  Future<HelpRequest?> getActiveRequestForSeeker(String userId) async {
    return _getActiveRequestForUser(userId);
  }

  /// Streams active help requests where user is the seeker.
  Stream<List<HelpRequest>> streamSeekerRequests(String userId) {
    // Note: whereIn requires a composite index with the orderBy field
    // We query without orderBy and sort in memory for simplicity
    return _helpRequestsRef
        .where('seekerUserId', isEqualTo: userId)
        .where('status', whereIn: ['OPEN', 'IN_PROGRESS'])
        .snapshots()
        .map((snapshot) {
          final requests = snapshot.docs
              .map((doc) => HelpRequestModel.fromFirestore(doc))
              .toList();
          // Sort in memory by createdAt descending
          requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return requests;
        });
  }

  /// Streams active help requests where user is the helper.
  Stream<List<HelpRequest>> streamHelperRequests(String userId) {
    return _helpRequestsRef
        .where('helperUserId', isEqualTo: userId)
        .where('status', isEqualTo: 'IN_PROGRESS')
        .snapshots()
        .map((snapshot) {
          final requests = snapshot.docs
              .map((doc) => HelpRequestModel.fromFirestore(doc))
              .toList();
          // Sort in memory by assignedAt descending
          requests.sort((a, b) {
            final aAssigned = a.assignedAt ?? a.createdAt;
            final bAssigned = b.assignedAt ?? b.createdAt;
            return bAssigned.compareTo(aAssigned);
          });
          return requests;
        });
  }

  /// Streams open help requests that the user can potentially help with.
  ///
  /// Only returns requests where [userId] is in the server-populated
  /// `notifiedUserIds` array. This means only users the Cloud Function
  /// verified as nearby (via `onHelpRequestCreated`) can discover requests
  /// through browsing — exact GPS coordinates are never broadcast to all
  /// authenticated users.
  ///
  /// Additional client-side filters:
  /// - Excludes the user's own requests (safety net)
  /// - Excludes expired requests
  Stream<List<HelpRequest>> streamOpenHelpRequests(String userId) {
    return _helpRequestsRef
        .where('status', isEqualTo: 'OPEN')
        .where('notifiedUserIds', arrayContains: userId)
        .snapshots()
        .map((snapshot) {
          final now = DateTime.now();
          final requests = snapshot.docs
              .map((doc) => HelpRequestModel.fromFirestore(doc))
              .where((request) =>
                  request.seekerUserId != userId &&
                  now.isBefore(request.expiresAt))
              .toList();
          // Sort by createdAt descending (most recent first)
          requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return requests;
        });
  }

  /// Gets all open help requests that the user might be able to help with.
  ///
  /// Scoped to requests where [userId] appears in `notifiedUserIds`
  /// (server-side proximity verification).
  Future<List<HelpRequest>> getOpenHelpRequests(String userId) async {
    try {
      final snapshot = await _helpRequestsRef
          .where('status', isEqualTo: 'OPEN')
          .where('notifiedUserIds', arrayContains: userId)
          .get();

      final now = DateTime.now();
      final requests = snapshot.docs
          .map((doc) => HelpRequestModel.fromFirestore(doc))
          .where((request) =>
              request.seekerUserId != userId &&
              now.isBefore(request.expiresAt))
          .toList();

      // Sort by createdAt descending
      requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return requests;
    } catch (e, stack) {
      _logger.e('Error getting open help requests', error: e, stackTrace: stack);
      return [];
    }
  }

  /// Finds nearby users who can help based on their saved locations.
  ///
  /// Calls a server-side Cloud Function to perform the proximity query.
  /// The server does all distance filtering — no other users' GPS coordinates
  /// are ever sent to the client. Only matching user IDs are returned.
  Future<List<String>> findNearbyHelpers({
    required double latitude,
    required double longitude,
    required HelpRadius radius,
    required String excludeUserId,
  }) async {
    try {
      final callable = _functions.httpsCallable(
        'findNearbyHelpers',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );

      final result = await callable.call<Map<String, dynamic>>({
        'latitude': latitude,
        'longitude': longitude,
        'radiusMeters': radius.meters,
      });

      final data = result.data;
      final userIds =
          (data['userIds'] as List<dynamic>?)?.cast<String>() ?? [];

      _logger.i('Found ${userIds.length} nearby helpers (server-side)');
      return userIds;
    } catch (e, stack) {
      _logger.e('Error finding nearby helpers', error: e, stackTrace: stack);
      return [];
    }
  }

  /// Gets the count of successfully completed help requests where the user was the helper.
  Future<int> getHelpsDoneCount(String userId) async {
    try {
      final result = await _helpRequestsRef
          .where('helperUserId', isEqualTo: userId)
          .where('status', isEqualTo: 'RESOLVED')
          .count()
          .get();

      return result.count ?? 0;
    } catch (e, stack) {
      _logger.e('Error getting helps done count', error: e, stackTrace: stack);
      return 0;
    }
  }

  /// Streams the count of successfully completed help requests where the user was the helper.
  Stream<int> streamHelpsDoneCount(String userId) {
    return _helpRequestsRef
        .where('helperUserId', isEqualTo: userId)
        .where('status', isEqualTo: 'RESOLVED')
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  // ==================== HELPER METHODS ====================

  /// Checks rate limit for creating help requests.
  Future<NearbyHelpFailure<HelpRequest>?> _checkRateLimit(String userId) async {
    try {
      final oneHourAgo = DateTime.now().subtract(const Duration(hours: 1));

      final recentRequests = await _helpRequestsRef
          .where('seekerUserId', isEqualTo: userId)
          .where('createdAt', isGreaterThan: Timestamp.fromDate(oneHourAgo))
          .count()
          .get();

      if ((recentRequests.count ?? 0) >= _maxRequestsPerHour) {
        return const NearbyHelpFailure(
          'You have reached the maximum number of help requests per hour',
          NearbyHelpErrorType.rateLimitExceeded,
        );
      }

      return null;
    } catch (e) {
      _logger.e('Error checking rate limit', error: e);
      return null; // Allow the request if rate limit check fails
    }
  }

  /// Gets the active help request for a user (as seeker).
  Future<HelpRequest?> _getActiveRequestForUser(String userId) async {
    try {
      final snapshot = await _helpRequestsRef
          .where('seekerUserId', isEqualTo: userId)
          .where('status', whereIn: ['OPEN', 'IN_PROGRESS'])
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) return null;
      return HelpRequestModel.fromFirestore(snapshot.docs.first);
    } catch (e) {
      _logger.e('Error getting active request', error: e);
      return null;
    }
  }

  /// Generates a simple geohash for the given coordinates.
  /// This is a simplified version for basic geospatial queries.
  String _generateGeoHash(double latitude, double longitude) {
    // Simple geohash based on truncated coordinates
    // For production, consider using a proper geohash library
    final latPart = ((latitude + 90) * 1000).toInt().toString().padLeft(6, '0');
    final lonPart = ((longitude + 180) * 1000).toInt().toString().padLeft(6, '0');
    return '$latPart$lonPart';
  }

  /// Calculates approximate distance for display (before helper accepts).
  /// Returns a human-readable string like "~50m" or "~100m".
  String getApproximateDistance(double distance) {
    if (distance < 50) return '~50m';
    if (distance < 100) return '~100m';
    if (distance < 250) return '~250m';
    if (distance < 500) return '~500m';
    if (distance < 1000) return '~1km';
    if (distance < 2000) return '~2km';
    return '>2km';
  }
}
