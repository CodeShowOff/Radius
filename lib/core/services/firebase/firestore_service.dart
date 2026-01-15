import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:injectable/injectable.dart';

import '../../error/exceptions.dart';

/// Firestore database service implementation.
///
/// Provides a clean abstraction over Cloud Firestore operations.
/// Handles CRUD operations, queries, and real-time streams.
@lazySingleton
class FirestoreService {
  final FirebaseFirestore _firestore;

  FirestoreService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Gets the Firestore instance for advanced operations.
  FirebaseFirestore get instance => _firestore;

  // ===========================================================================
  // DOCUMENT OPERATIONS
  // ===========================================================================

  /// Get a document by its path.
  ///
  /// Returns null if document doesn't exist.
  /// Path format: 'collection/documentId' or 'collection/doc/subcollection/doc'
  Future<Map<String, dynamic>?> getDocument(String path) async {
    try {
      final doc = await _firestore.doc(path).get();
      if (!doc.exists) return null;
      return _addIdToData(doc);
    } on FirebaseException catch (e) {
      throw _mapFirestoreException(e);
    }
  }

  /// Set a document at the specified path.
  ///
  /// If [merge] is true, data will be merged with existing document.
  /// If [merge] is false, existing document will be overwritten.
  Future<void> setDocument({
    required String path,
    required Map<String, dynamic> data,
    bool merge = true,
  }) async {
    try {
      await _firestore.doc(path).set(data, SetOptions(merge: merge));
    } on FirebaseException catch (e) {
      throw _mapFirestoreException(e);
    }
  }

  /// Update specific fields in a document.
  ///
  /// Document must exist, otherwise throws an exception.
  Future<void> updateDocument({
    required String path,
    required Map<String, dynamic> data,
  }) async {
    try {
      await _firestore.doc(path).update(data);
    } on FirebaseException catch (e) {
      throw _mapFirestoreException(e);
    }
  }

  /// Delete a document by its path.
  Future<void> deleteDocument(String path) async {
    try {
      await _firestore.doc(path).delete();
    } on FirebaseException catch (e) {
      throw _mapFirestoreException(e);
    }
  }

  /// Check if a document exists.
  Future<bool> documentExists(String path) async {
    try {
      final doc = await _firestore.doc(path).get();
      return doc.exists;
    } on FirebaseException catch (e) {
      throw _mapFirestoreException(e);
    }
  }

  // ===========================================================================
  // COLLECTION OPERATIONS
  // ===========================================================================

  /// Add a new document to a collection with auto-generated ID.
  ///
  /// Returns the generated document ID.
  Future<String> addDocument({
    required String collectionPath,
    required Map<String, dynamic> data,
  }) async {
    try {
      final docRef = await _firestore.collection(collectionPath).add(data);
      return docRef.id;
    } on FirebaseException catch (e) {
      throw _mapFirestoreException(e);
    }
  }

  /// Query documents in a collection.
  ///
  /// Supports filtering, ordering, and limiting results.
  Future<List<Map<String, dynamic>>> queryCollection({
    required String path,
    List<QueryFilter>? filters,
    List<QueryOrderBy>? orderBy,
    int? limit,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _firestore.collection(path);

      // Apply filters
      if (filters != null) {
        for (final filter in filters) {
          query = _applyFilter(query, filter);
        }
      }

      // Apply ordering
      if (orderBy != null) {
        for (final order in orderBy) {
          query = query.orderBy(order.field, descending: order.descending);
        }
      }

      // Apply pagination
      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      // Apply limit
      if (limit != null) {
        query = query.limit(limit);
      }

      final snapshot = await query.get();
      return snapshot.docs.map(_addIdToData).toList();
    } on FirebaseException catch (e) {
      throw _mapFirestoreException(e);
    }
  }

  /// Get all documents in a collection.
  Future<List<Map<String, dynamic>>> getCollection(String path) async {
    return queryCollection(path: path);
  }

  // ===========================================================================
  // REAL-TIME STREAMS
  // ===========================================================================

  /// Stream a single document.
  ///
  /// Emits null if document doesn't exist.
  Stream<Map<String, dynamic>?> documentStream(String path) {
    return _firestore.doc(path).snapshots().map((doc) {
      if (!doc.exists) return null;
      return _addIdToData(doc);
    });
  }

  /// Stream a collection with optional filtering.
  Stream<List<Map<String, dynamic>>> collectionStream({
    required String path,
    List<QueryFilter>? filters,
    List<QueryOrderBy>? orderBy,
    int? limit,
  }) {
    Query<Map<String, dynamic>> query = _firestore.collection(path);

    // Apply filters
    if (filters != null) {
      for (final filter in filters) {
        query = _applyFilter(query, filter);
      }
    }

    // Apply ordering
    if (orderBy != null) {
      for (final order in orderBy) {
        query = query.orderBy(order.field, descending: order.descending);
      }
    }

    // Apply limit
    if (limit != null) {
      query = query.limit(limit);
    }

    return query.snapshots().map(
          (snapshot) => snapshot.docs.map(_addIdToData).toList(),
        );
  }

  // ===========================================================================
  // BATCH OPERATIONS
  // ===========================================================================

  /// Execute multiple write operations atomically.
  ///
  /// All operations succeed or fail together.
  Future<void> batchWrite(List<BatchOperation> operations) async {
    if (operations.isEmpty) return;
    if (operations.length > 500) {
      throw const DatabaseException(
        message: 'Batch operations limited to 500 writes',
        code: 'batch-limit-exceeded',
      );
    }

    try {
      final batch = _firestore.batch();

      for (final operation in operations) {
        final docRef = _firestore.doc(operation.path);

        switch (operation) {
          case BatchSet op:
            batch.set(docRef, op.data, SetOptions(merge: op.merge));
          case BatchUpdate op:
            batch.update(docRef, op.data);
          case BatchDelete _:
            batch.delete(docRef);
        }
      }

      await batch.commit();
    } on FirebaseException catch (e) {
      throw _mapFirestoreException(e);
    }
  }

  // ===========================================================================
  // TRANSACTION OPERATIONS
  // ===========================================================================

  /// Run a transaction for atomic read-write operations.
  ///
  /// The [transactionHandler] receives a transaction object and must
  /// return the result of the transaction.
  Future<T> runTransaction<T>(
    Future<T> Function(Transaction transaction) transactionHandler,
  ) async {
    try {
      return await _firestore.runTransaction(transactionHandler);
    } on FirebaseException catch (e) {
      throw _mapFirestoreException(e);
    }
  }

  /// Get a document within a transaction.
  Future<Map<String, dynamic>?> getDocumentInTransaction(
    Transaction transaction,
    String path,
  ) async {
    final doc = await transaction.get(_firestore.doc(path));
    if (!doc.exists) return null;
    return _addIdToData(doc);
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  /// Generate a new document ID without creating the document.
  String generateDocumentId(String collectionPath) {
    return _firestore.collection(collectionPath).doc().id;
  }

  /// Get a document reference.
  DocumentReference<Map<String, dynamic>> docRef(String path) {
    return _firestore.doc(path);
  }

  /// Get a collection reference.
  CollectionReference<Map<String, dynamic>> collectionRef(String path) {
    return _firestore.collection(path);
  }

  /// Server timestamp placeholder for use in document data.
  static FieldValue get serverTimestamp => FieldValue.serverTimestamp();

  /// Array union operation for adding elements to an array field.
  static FieldValue arrayUnion(List<dynamic> elements) =>
      FieldValue.arrayUnion(elements);

  /// Array remove operation for removing elements from an array field.
  static FieldValue arrayRemove(List<dynamic> elements) =>
      FieldValue.arrayRemove(elements);

  /// Increment operation for numeric fields.
  static FieldValue increment(num value) => FieldValue.increment(value);

  /// Delete field operation.
  static FieldValue get deleteField => FieldValue.delete();

  // ===========================================================================
  // PRIVATE HELPERS
  // ===========================================================================

  /// Adds document ID to the data map.
  Map<String, dynamic> _addIdToData(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return {
      'id': doc.id,
      ...data,
    };
  }

  /// Applies a filter to a query.
  Query<Map<String, dynamic>> _applyFilter(
    Query<Map<String, dynamic>> query,
    QueryFilter filter,
  ) {
    switch (filter.operator) {
      case FilterOperator.equalTo:
        return query.where(filter.field, isEqualTo: filter.value);
      case FilterOperator.notEqualTo:
        return query.where(filter.field, isNotEqualTo: filter.value);
      case FilterOperator.lessThan:
        return query.where(filter.field, isLessThan: filter.value);
      case FilterOperator.lessThanOrEqualTo:
        return query.where(filter.field, isLessThanOrEqualTo: filter.value);
      case FilterOperator.greaterThan:
        return query.where(filter.field, isGreaterThan: filter.value);
      case FilterOperator.greaterThanOrEqualTo:
        return query.where(filter.field, isGreaterThanOrEqualTo: filter.value);
      case FilterOperator.arrayContains:
        return query.where(filter.field, arrayContains: filter.value);
      case FilterOperator.arrayContainsAny:
        return query.where(filter.field, arrayContainsAny: filter.value as List);
      case FilterOperator.whereIn:
        return query.where(filter.field, whereIn: filter.value as List);
      case FilterOperator.whereNotIn:
        return query.where(filter.field, whereNotIn: filter.value as List);
      case FilterOperator.isNull:
        return query.where(filter.field, isNull: filter.value as bool);
    }
  }

  /// Maps Firestore exceptions to our custom DatabaseException.
  DatabaseException _mapFirestoreException(FirebaseException e) {
    String message;
    switch (e.code) {
      case 'permission-denied':
        message = 'Permission denied. Please check your authentication.';
        break;
      case 'not-found':
        message = 'Document not found';
        break;
      case 'already-exists':
        message = 'Document already exists';
        break;
      case 'resource-exhausted':
        message = 'Quota exceeded. Please try again later.';
        break;
      case 'unavailable':
        message = 'Service temporarily unavailable';
        break;
      case 'cancelled':
        message = 'Operation was cancelled';
        break;
      default:
        message = e.message ?? 'Database error occurred';
    }

    return DatabaseException(
      message: message,
      code: e.code,
      originalError: e,
    );
  }
}

// ===========================================================================
// QUERY HELPERS
// ===========================================================================

/// Filter for Firestore queries.
class QueryFilter {
  final String field;
  final FilterOperator operator;
  final dynamic value;

  const QueryFilter({
    required this.field,
    required this.operator,
    required this.value,
  });

  /// Convenience constructor for equality filter.
  const QueryFilter.equals(this.field, this.value)
      : operator = FilterOperator.equalTo;

  /// Convenience constructor for array contains filter.
  const QueryFilter.arrayContains(this.field, this.value)
      : operator = FilterOperator.arrayContains;
}

/// Filter operators for Firestore queries.
enum FilterOperator {
  equalTo,
  notEqualTo,
  lessThan,
  lessThanOrEqualTo,
  greaterThan,
  greaterThanOrEqualTo,
  arrayContains,
  arrayContainsAny,
  whereIn,
  whereNotIn,
  isNull,
}

/// Order by clause for Firestore queries.
class QueryOrderBy {
  final String field;
  final bool descending;

  const QueryOrderBy(this.field, {this.descending = false});
}

// ===========================================================================
// BATCH OPERATION TYPES
// ===========================================================================

/// Base class for batch operations.
sealed class BatchOperation {
  final String path;
  const BatchOperation(this.path);
}

/// Set operation for batch writes.
class BatchSet extends BatchOperation {
  final Map<String, dynamic> data;
  final bool merge;

  const BatchSet(super.path, this.data, {this.merge = true});
}

/// Update operation for batch writes.
class BatchUpdate extends BatchOperation {
  final Map<String, dynamic> data;

  const BatchUpdate(super.path, this.data);
}

/// Delete operation for batch writes.
class BatchDelete extends BatchOperation {
  const BatchDelete(super.path);
}
