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
  /// Throws [FormatException] if required fields are missing.
  factory ConnectionModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;

    if (data == null) {
      throw FormatException('Connection document ${doc.id} has no data');
    }

    final userId1 = data['userId1'] as String?;
    final userId2 = data['userId2'] as String?;
    final statusStr = data['status'] as String?;
    final connectedAt = data['connectedAt'] as Timestamp?;
    final updatedAt = data['updatedAt'] as Timestamp?;
    final initiatedBy = data['initiatedBy'] as String?;

    if (userId1 == null ||
        userId2 == null ||
        statusStr == null ||
        connectedAt == null ||
        updatedAt == null ||
        initiatedBy == null) {
      throw FormatException(
        'Connection document ${doc.id} missing required fields: '
        'userId1=$userId1, userId2=$userId2, status=$statusStr, '
        'connectedAt=$connectedAt, updatedAt=$updatedAt, initiatedBy=$initiatedBy',
      );
    }

    return ConnectionModel(
      id: doc.id,
      userId1: userId1,
      userId2: userId2,
      status: _parseStatus(statusStr),
      connectedAt: connectedAt.toDate(),
      updatedAt: updatedAt.toDate(),
      initiatedBy: initiatedBy,
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
