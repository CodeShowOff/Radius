/// Firestore database service interface.
/// 
/// Abstracts Firestore SDK for easier testing and potential migration.
/// Implementation will be added when Firebase is configured.
abstract class IFirestoreService {
  /// Get a document by path.
  Future<Map<String, dynamic>?> getDocument(String path);
  
  /// Set/update a document.
  Future<void> setDocument({
    required String path,
    required Map<String, dynamic> data,
    bool merge = true,
  });
  
  /// Delete a document.
  Future<void> deleteDocument(String path);
  
  /// Query a collection.
  Future<List<Map<String, dynamic>>> queryCollection({
    required String path,
    List<QueryConstraint>? constraints,
    int? limit,
  });
  
  /// Stream a document.
  Stream<Map<String, dynamic>?> documentStream(String path);
  
  /// Stream a collection.
  Stream<List<Map<String, dynamic>>> collectionStream({
    required String path,
    List<QueryConstraint>? constraints,
  });
  
  /// Batch write operations.
  Future<void> batchWrite(List<BatchOperation> operations);
}

/// Query constraint for Firestore queries.
class QueryConstraint {
  final String field;
  final QueryOperator operator;
  final dynamic value;

  const QueryConstraint({
    required this.field,
    required this.operator,
    required this.value,
  });
}

/// Query operators.
enum QueryOperator {
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
}

/// Batch operation types.
abstract class BatchOperation {
  final String path;
  const BatchOperation(this.path);
}

class BatchSet extends BatchOperation {
  final Map<String, dynamic> data;
  final bool merge;
  const BatchSet(super.path, this.data, {this.merge = true});
}

class BatchUpdate extends BatchOperation {
  final Map<String, dynamic> data;
  const BatchUpdate(super.path, this.data);
}

class BatchDelete extends BatchOperation {
  const BatchDelete(super.path);
}
