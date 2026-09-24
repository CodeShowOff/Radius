import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';

import '../models/post_model.dart';

/// Service for Firestore operations on the posts collection.
///
/// Firestore Collections:
/// - `posts` â€” User posts with text, media, and visibility settings
class PostService {
  final FirebaseFirestore _firestore;
  final Logger _logger;

  late final CollectionReference<Map<String, dynamic>> _postsRef;

  PostService({
    FirebaseFirestore? firestore,
    Logger? logger,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _logger = logger ?? Logger() {
    _postsRef = _firestore.collection('posts');
  }

  /// Creates a new post and returns the created document.
  Future<PostModel> createPost(PostModel post) async {
    try {
      final docRef = _postsRef.doc();
      final data = post.toFirestore();
      await docRef.set(data);

      // Return with the generated ID
      final doc = await docRef.get();
      return PostModel.fromFirestore(doc);
    } catch (e, stack) {
      _logger.e('Error creating post', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Counts posts created by [authorId] since the start of today (UTC).
  /// Used for daily rate limiting.
  Future<int> countTodayPostsByAuthor(String authorId) async {
    try {
      final now = DateTime.now().toUtc();
      final startOfDay = DateTime.utc(now.year, now.month, now.day);

      final snapshot = await _postsRef
          .where('authorId', isEqualTo: authorId)
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .count()
          .get();

      return snapshot.count ?? 0;
    } catch (e, stack) {
      _logger.e('Error counting today posts for $authorId',
          error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Gets a single post by ID.
  Future<PostModel?> getPost(String postId) async {
    try {
      final doc = await _postsRef.doc(postId).get();
      if (!doc.exists) return null;
      return PostModel.fromFirestore(doc);
    } catch (e, stack) {
      _logger.e('Error getting post $postId', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Deletes a post.
  Future<void> deletePost(String postId) async {
    try {
      await _postsRef.doc(postId).delete();
    } catch (e, stack) {
      _logger.e('Error deleting post $postId', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Updates specific fields of a post.
  Future<void> updatePost(String postId, Map<String, dynamic> data) async {
    try {
      await _postsRef.doc(postId).update(data);
    } catch (e, stack) {
      _logger.e('Error updating post $postId', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Gets posts by a specific author, ordered by creation time.
  ///
  /// When [viewerUserId] equals [authorId] (own profile), a single query is
  /// used because Firestore rules allow reading all own posts.
  ///
  /// When [includeConnectionsVisibility] is true and the viewer is someone
  /// else, two parallel queries are run to satisfy Firestore security rules:
  ///   1. Public posts by the author
  ///   2. Connections-only posts where the viewer is in authorConnections
  ///
  /// When [includeConnectionsVisibility] is false, only public posts are returned.
  Future<List<PostModel>> getPostsByAuthor({
    required String authorId,
    bool includeConnectionsVisibility = false,
    String? viewerUserId,
    int limit = 10,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      // Own profile â€” single query is allowed by Firestore rules
      // (authorId == request.auth.uid satisfies the read rule)
      if (viewerUserId != null && viewerUserId == authorId) {
        Query<Map<String, dynamic>> query = _postsRef
            .where('authorId', isEqualTo: authorId)
            .orderBy('trendingScore', descending: true)
            .limit(limit);
        if (startAfter != null) {
          query = query.startAfterDocument(startAfter);
        }
        final snapshot = await query.get();
        return snapshot.docs
            .map((doc) => PostModel.fromFirestore(doc))
            .toList();
      }

      // Connected viewer â€” two parallel queries to satisfy Firestore rules:
      //   Query 1: visibility == 'public'  →  rule condition 1
      //   Query 2: arrayContains viewer    →  rule condition 3
      if (includeConnectionsVisibility && viewerUserId != null) {
        Query<Map<String, dynamic>> publicQuery = _postsRef
            .where('authorId', isEqualTo: authorId)
            .where('visibility', isEqualTo: 'public')
            .orderBy('trendingScore', descending: true)
            .limit(limit);

        Query<Map<String, dynamic>> connectionsQuery = _postsRef
            .where('authorId', isEqualTo: authorId)
            .where('authorConnections', arrayContains: viewerUserId)
            .orderBy('trendingScore', descending: true)
            .limit(limit);

        if (startAfter != null) {
          publicQuery = publicQuery.startAfterDocument(startAfter);
          connectionsQuery = connectionsQuery.startAfterDocument(startAfter);
        }

        final results = await Future.wait([
          publicQuery.get(),
          connectionsQuery.get(),
        ]);

        // Merge & deduplicate
        final postMap = <String, PostModel>{};
        for (final doc in results[0].docs) {
          final post = PostModel.fromFirestore(doc);
          postMap[post.id] = post;
        }
        for (final doc in results[1].docs) {
          final post = PostModel.fromFirestore(doc);
          postMap[post.id] = post;
        }

        final merged = postMap.values.toList()
          ..sort((a, b) => b.trendingScore.compareTo(a.trendingScore));

        return merged.take(limit).toList();
      }

      // Non-connected viewer â€” public only
      Query<Map<String, dynamic>> query = _postsRef
          .where('authorId', isEqualTo: authorId)
          .where('visibility', isEqualTo: 'public')
          .orderBy('trendingScore', descending: true)
          .limit(limit);

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      final snapshot = await query.get();
      return snapshot.docs.map((doc) => PostModel.fromFirestore(doc)).toList();
    } catch (e, stack) {
      _logger.e('Error getting posts for author $authorId',
          error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Gets public posts from a batch of author IDs.
  /// Firestore `whereIn` supports max 30 values per query.
  Future<List<PostModel>> getPublicPostsByAuthors({
    required List<String> authorIds,
    int limit = 10,
    DocumentSnapshot? startAfter,
  }) async {
    if (authorIds.isEmpty) return [];

    try {
      // Batch authorIds into groups of 30 (Firestore whereIn limit)
      final batches = <List<String>>[];
      for (var i = 0; i < authorIds.length; i += 30) {
        batches.add(authorIds.sublist(
          i,
          i + 30 > authorIds.length ? authorIds.length : i + 30,
        ));
      }

      final allPosts = <PostModel>[];

      for (final batch in batches) {
        Query<Map<String, dynamic>> query = _postsRef
            .where('authorId', whereIn: batch)
            .where('visibility', isEqualTo: 'public')
            .orderBy('trendingScore', descending: true)
            .limit(limit);

        if (startAfter != null) {
          query = query.startAfterDocument(startAfter);
        }

        final snapshot = await query.get();
        allPosts.addAll(
          snapshot.docs.map((doc) => PostModel.fromFirestore(doc)),
        );
      }

      return allPosts;
    } catch (e, stack) {
      _logger.e('Error getting public posts by authors',
          error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Gets connections-only posts visible to a specific user.
  /// Uses the `authorConnections` array with `arrayContains`.
  Future<List<PostModel>> getConnectionsPostsForUser({
    required String userId,
    int limit = 10,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _postsRef
          .where('visibility', isEqualTo: 'connections')
          .where('authorConnections', arrayContains: userId)
          .orderBy('trendingScore', descending: true)
          .limit(limit);

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      final snapshot = await query.get();
      return snapshot.docs.map((doc) => PostModel.fromFirestore(doc)).toList();
    } catch (e, stack) {
      _logger.e('Error getting connections posts for user $userId',
          error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Streams real-time updates for a single post.
  Stream<PostModel?> postStream(String postId) {
    return _postsRef.doc(postId).snapshots().map((doc) {
      if (!doc.exists) return null;
      try {
        return PostModel.fromFirestore(doc);
      } catch (e) {
        _logger.e('Error parsing post stream for $postId', error: e);
        return null;
      }
    });
  }
}
