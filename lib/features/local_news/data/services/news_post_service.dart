import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../../core/constants/env.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';

import '../models/news_post_model.dart';

/// Service for Firestore operations on the local news posts collection.
///
/// Firestore Collection: `local_news_posts`
///
/// Posts are queried by `country` + `city` for location-based feeds,
/// ordered by `createdAt` descending.
class NewsPostService {
  final FirebaseFirestore _firestore;
  final Logger _logger;

  late final CollectionReference<Map<String, dynamic>> _postsRef;

  /// Default page size for feed queries.
  static const int defaultPageSize = 20;

  NewsPostService({
    FirebaseFirestore? firestore,
    Logger? logger,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _logger = logger ?? Logger() {
    _postsRef = _firestore.collection('local_news_posts');
  }

  // ==================== CRUD ====================

  /// Creates a new local news post and returns it with the generated ID.
  Future<NewsPostModel> createPost(NewsPostModel post) async {
    try {
      final docRef = _postsRef.doc();
      final data = post.toFirestore();
      await docRef.set(data);

      final doc = await docRef.get();
      return NewsPostModel.fromFirestore(doc);
    } catch (e, stack) {
      _logger.e('Error creating local news post', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Counts news posts (both 'post' and 'reel') created by [authorId]
  /// since the start of today (UTC). Used for daily rate limiting.
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
      _logger.e('Error counting today news posts for $authorId',
          error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Gets a single post by ID.
  Future<NewsPostModel?> getPost(String postId) async {
    try {
      final doc = await _postsRef.doc(postId).get();
      if (!doc.exists) return null;
      return NewsPostModel.fromFirestore(doc);
    } catch (e, stack) {
      _logger.e('Error getting local news post $postId',
          error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Deletes a post.
  Future<void> deletePost(String postId) async {
    try {
      await _postsRef.doc(postId).delete();
    } catch (e, stack) {
      _logger.e('Error deleting local news post $postId',
          error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Updates specific fields of a post.
  Future<void> updatePost(String postId, Map<String, dynamic> data) async {
    try {
      await _postsRef.doc(postId).update(data);
    } catch (e, stack) {
      _logger.e('Error updating local news post $postId',
          error: e, stackTrace: stack);
      rethrow;
    }
  }

  // ==================== FEED QUERIES ====================

  /// Watches the news feed for a specific city, ordered by creation time.
  ///
  /// Primary query: all posts in the same `country` + `city`.
  /// Requires composite index: country ASC, city ASC, createdAt DESC.
  Stream<List<NewsPostModel>> watchNewsFeed({
    required String country,
    required String city,
    int limit = defaultPageSize,
  }) {
    return _postsRef
        .where('country', isEqualTo: country)
        .where('city', isEqualTo: city)
        .where('postType', isEqualTo: 'post')
        .orderBy('trendingScore', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        try {
          return NewsPostModel.fromFirestore(doc);
        } catch (e) {
          _logger.e('Error parsing news post ${doc.id}', error: e);
          return null;
        }
      }).whereType<NewsPostModel>().toList();
    });
  }

  /// Fetches a page of news posts for a city (for pagination).
  Future<List<NewsPostModel>> getNewsFeed({
    required String country,
    required String city,
    int limit = defaultPageSize,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      final client = HttpClient();
      final request = await client.postUrl(Uri.parse('${Env.backendUrl}/getLocalNewsFeed'));
      request.headers.contentType = ContentType.json;
      
      final requestBody = jsonEncode({
        'data': {
          'country': country,
          'city': city,
          'limit': limit,
          if (startAfter != null) 'startAfter': startAfter.id,
        }
      });
      
      request.write(requestBody);
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      
      if (response.statusCode != 200) {
        throw Exception('API Error: $responseBody');
      }

      final jsonResponse = jsonDecode(responseBody);
      final rawData = jsonResponse['data'] as List<dynamic>? ?? [];

      return rawData.map((item) {
        final map = item as Map<String, dynamic>;
        final id = map['id'] as String;
        return NewsPostModel.fromMap(map, id);
      }).toList();
    } catch (e, stack) {
      _logger.e('Error fetching news feed from API for $city, $country',
          error: e, stackTrace: stack);
      rethrow;
    }
  }

  // ==================== REELS FEED QUERIES ====================

  /// Default page size for reels feed (smaller than posts since videos are heavier).
  static const int defaultReelsPageSize = 10;

  /// Watches the reels feed for a specific city, ordered by creation time.
  ///
  /// Only returns posts with `postType == 'reel'`.
  /// Requires composite index: country ASC, city ASC, postType ASC, createdAt DESC.
  Stream<List<NewsPostModel>> watchReelsFeed({
    required String country,
    required String city,
    int limit = defaultReelsPageSize,
  }) {
    return _postsRef
        .where('country', isEqualTo: country)
        .where('city', isEqualTo: city)
        .where('postType', isEqualTo: 'reel')
        .orderBy('trendingScore', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        try {
          return NewsPostModel.fromFirestore(doc);
        } catch (e) {
          _logger.e('Error parsing reel ${doc.id}', error: e);
          return null;
        }
      }).whereType<NewsPostModel>().toList();
    });
  }

  /// Fetches a page of reels for a city (for pagination).
  ///
  /// Only returns posts with `postType == 'reel'`.
  /// Requires composite index: country ASC, city ASC, postType ASC, createdAt DESC.
  Future<List<NewsPostModel>> getReelsFeed({
    required String country,
    required String city,
    int limit = defaultReelsPageSize,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      final client = HttpClient();
      // Use 192.168.13.105 to reach the local machine from a real device
      final request = await client.postUrl(Uri.parse('${Env.backendUrl}/getReelsFeed'));
      request.headers.contentType = ContentType.json;
      
      final requestBody = jsonEncode({
        'data': {
          'country': country,
          'city': city,
          'limit': limit,
          if (startAfter != null) 'startAfter': startAfter.id,
        }
      });
      
      request.write(requestBody);
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      
      if (response.statusCode != 200) {
        throw Exception('API Error: $responseBody');
      }

      final jsonResponse = jsonDecode(responseBody);
      final rawData = jsonResponse['data'] as List<dynamic>? ?? [];

      return rawData.map((item) {
        final map = item as Map<String, dynamic>;
        final id = map['id'] as String;
        return NewsPostModel.fromMap(map, id);
      }).toList();
    } catch (e, stack) {
      _logger.e('Error fetching reels feed from API for $city, $country',
          error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Gets posts by a specific author, ordered by creation time.
  Future<List<NewsPostModel>> getPostsByAuthor({
    required String authorId,
    int limit = defaultPageSize,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _postsRef
          .where('authorId', isEqualTo: authorId)
          .orderBy('createdAt', descending: true)
          .limit(limit);

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      final snapshot = await query.get();
      return snapshot.docs
          .map((doc) => NewsPostModel.fromFirestore(doc))
          .toList();
    } catch (e, stack) {
      _logger.e('Error getting news posts for author $authorId',
          error: e, stackTrace: stack);
      rethrow;
    }
  }

  // ==================== REAL-TIME ====================

  /// Streams real-time updates for a single post.
  Stream<NewsPostModel?> postStream(String postId) {
    return _postsRef.doc(postId).snapshots().map((doc) {
      if (!doc.exists) return null;
      try {
        return NewsPostModel.fromFirestore(doc);
      } catch (e) {
        _logger.e('Error parsing news post stream for $postId', error: e);
        return null;
      }
    });
  }
}
