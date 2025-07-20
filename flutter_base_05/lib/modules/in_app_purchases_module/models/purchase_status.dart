/// Enum representing different purchase statuses
enum PurchaseStatus {
  pending,
  processing,
  completed,
  failed,
  cancelled,
  refunded,
  expired,
  unknown;

  /// Convert status to string for API communication
  String get apiValue {
    switch (this) {
      case PurchaseStatus.pending:
        return 'pending';
      case PurchaseStatus.processing:
        return 'processing';
      case PurchaseStatus.completed:
        return 'completed';
      case PurchaseStatus.failed:
        return 'failed';
      case PurchaseStatus.cancelled:
        return 'cancelled';
      case PurchaseStatus.refunded:
        return 'refunded';
      case PurchaseStatus.expired:
        return 'expired';
      case PurchaseStatus.unknown:
        return 'unknown';
    }
  }

  /// Convert string to status from API
  static PurchaseStatus fromApiValue(String value) {
    switch (value.toLowerCase()) {
      case 'pending':
        return PurchaseStatus.pending;
      case 'processing':
        return PurchaseStatus.processing;
      case 'completed':
        return PurchaseStatus.completed;
      case 'failed':
        return PurchaseStatus.failed;
      case 'cancelled':
        return PurchaseStatus.cancelled;
      case 'refunded':
        return PurchaseStatus.refunded;
      case 'expired':
        return PurchaseStatus.expired;
      default:
        return PurchaseStatus.unknown;
    }
  }

  /// Get user-friendly status message
  String get displayMessage {
    switch (this) {
      case PurchaseStatus.pending:
        return 'Purchase is pending';
      case PurchaseStatus.processing:
        return 'Processing your purchase...';
      case PurchaseStatus.completed:
        return 'Purchase completed successfully';
      case PurchaseStatus.failed:
        return 'Purchase failed';
      case PurchaseStatus.cancelled:
        return 'Purchase was cancelled';
      case PurchaseStatus.refunded:
        return 'Purchase was refunded';
      case PurchaseStatus.expired:
        return 'Purchase has expired';
      case PurchaseStatus.unknown:
        return 'Unknown purchase status';
    }
  }

  /// Check if status indicates success
  bool get isSuccess => this == PurchaseStatus.completed;

  /// Check if status indicates failure
  bool get isFailure => this == PurchaseStatus.failed || this == PurchaseStatus.cancelled;

  /// Check if status is in progress
  bool get isInProgress => this == PurchaseStatus.pending || this == PurchaseStatus.processing;
} 