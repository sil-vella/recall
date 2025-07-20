/// Model representing a purchase receipt for verification
class PurchaseReceipt {
  final String purchaseId;
  final String productId;
  final String platform; // 'google_play', 'app_store', 'stripe'
  final String receiptData;
  final String? transactionId;
  final DateTime purchaseDate;
  final bool isVerified;
  final Map<String, dynamic>? verificationData;

  PurchaseReceipt({
    required this.purchaseId,
    required this.productId,
    required this.platform,
    required this.receiptData,
    this.transactionId,
    required this.purchaseDate,
    this.isVerified = false,
    this.verificationData,
  });

  factory PurchaseReceipt.fromJson(Map<String, dynamic> json) {
    return PurchaseReceipt(
      purchaseId: json['purchase_id'] ?? '',
      productId: json['product_id'] ?? '',
      platform: json['platform'] ?? '',
      receiptData: json['receipt_data'] ?? '',
      transactionId: json['transaction_id'],
      purchaseDate: DateTime.parse(json['purchase_date'] ?? DateTime.now().toIso8601String()),
      isVerified: json['is_verified'] ?? false,
      verificationData: json['verification_data'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'purchase_id': purchaseId,
      'product_id': productId,
      'platform': platform,
      'receipt_data': receiptData,
      'transaction_id': transactionId,
      'purchase_date': purchaseDate.toIso8601String(),
      'is_verified': isVerified,
      'verification_data': verificationData,
    };
  }

  @override
  String toString() {
    return 'PurchaseReceipt(purchaseId: $purchaseId, productId: $productId, platform: $platform, verified: $isVerified)';
  }
} 