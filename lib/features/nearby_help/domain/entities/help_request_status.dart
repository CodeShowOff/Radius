/// Status of a help request.
enum HelpRequestStatus {
  /// Request is open and waiting for helpers.
  open,

  /// A helper has accepted and is on the way.
  inProgress,

  /// Help has been completed.
  resolved,

  /// Request was cancelled by the seeker.
  cancelled,

  /// Request expired without being accepted.
  expired,
}

/// Extension to convert status to/from string for Firestore.
extension HelpRequestStatusX on HelpRequestStatus {
  String get value {
    switch (this) {
      case HelpRequestStatus.open:
        return 'OPEN';
      case HelpRequestStatus.inProgress:
        return 'IN_PROGRESS';
      case HelpRequestStatus.resolved:
        return 'RESOLVED';
      case HelpRequestStatus.cancelled:
        return 'CANCELLED';
      case HelpRequestStatus.expired:
        return 'EXPIRED';
    }
  }

  static HelpRequestStatus fromString(String value) {
    switch (value.toUpperCase()) {
      case 'OPEN':
        return HelpRequestStatus.open;
      case 'IN_PROGRESS':
        return HelpRequestStatus.inProgress;
      case 'RESOLVED':
        return HelpRequestStatus.resolved;
      case 'CANCELLED':
        return HelpRequestStatus.cancelled;
      case 'EXPIRED':
        return HelpRequestStatus.expired;
      default:
        return HelpRequestStatus.open;
    }
  }
}
