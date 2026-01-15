import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/connection.dart';

/// Firestore model for Connection entity.
/// 
/// Firestore Schema:
/// ```
/// connections/{connectionId}
///   - userId1: string (alphabetically smaller)
///   - userId2: string (alphabetically larger)
///   - status: string ('connected', 'blocked', 'disconnected')
///   - connectedAt: timestamp
///   - updatedAt: timestamp
///   - initiatedBy: string (userId)
///   - blockedBy: string? (userId)
///   - canMessage: boolean
///   - shareLocation: boolean
/// ```
class ConnectionModel extends Connection {
  const ConnectionModel({
    required super.id,
    required super.userId1,
    required super.userId2,
    required super.status,
    required super.connectedAt,
    required super.updatedAt,
    required super.initiatedBy,
    super.blockedBy,
    super.canMessage,
    super.shareLocation,
  });

  /// Creates model from Firestore document.
  factory ConnectionModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return ConnectionModel(
      id: doc.id,
      userId1: data['userId1'] as String,
      userId2: data['userId2'] as String,
      status: _parseStatus(data['status'] as String),
      connectedAt: (data['connectedAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
      initiatedBy: data['initiatedBy'] as String,
      blockedBy: data['blockedBy'] as String?,
      canMessage: data['canMessage'] as bool? ?? true,
      shareLocation: data['shareLocation'] as bool? ?? false,
    );
  }

  /// Creates model from Connection entity.
  factory ConnectionModel.fromEntity(Connection connection) {
    return ConnectionModel(
      id: connection.id,
      userId1: connection.userId1,
      userId2: connection.userId2,
      status: connection.status,
      connectedAt: connection.connectedAt,
      updatedAt: connection.updatedAt,
      initiatedBy: connection.initiatedBy,
      blockedBy: connection.blockedBy,
      canMessage: connection.canMessage,
      shareLocation: connection.shareLocation,
    );
  }

  /// Converts to Firestore document data.
  Map<String, dynamic> toFirestore() {
    return {
      'userId1': userId1,
      'userId2': userId2,
      'status': status.name,
      'connectedAt': Timestamp.fromDate(connectedAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'initiatedBy': initiatedBy,
      'blockedBy': blockedBy,
      'canMessage': canMessage,
      'shareLocation': shareLocation,
      // Denormalized for queries
      'users': [userId1, userId2],
    };
  }

  /// Converts to Connection entity.
  Connection toEntity() {
    return Connection(
      id: id,
      userId1: userId1,
      userId2: userId2,
      status: status,
      connectedAt: connectedAt,
      updatedAt: updatedAt,
      initiatedBy: initiatedBy,
      blockedBy: blockedBy,
      canMessage: canMessage,
      shareLocation: shareLocation,
    );
  }

  static ConnectionStatus _parseStatus(String status) {
    return ConnectionStatus.values.firstWhere(
      (e) => e.name == status,
      orElse: () => ConnectionStatus.disconnected,
    );
  }
}
