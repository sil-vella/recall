/// class CreditBucket - Provides core functionality
///
/// Provides core functionality
///
/// Example:
/// ```dart
/// final creditbucket = CreditBucket();
/// ```
///
class CreditBucket {
  final String id;
  final String userId;
  final double balance;
  final double lockedAmount;
  final DateTime createdAt;
  final DateTime updatedAt;

  CreditBucket({
    required this.id,
    required this.userId,
    required this.balance,
    required this.lockedAmount,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CreditBucket.fromJson(Map<String, dynamic> json) {
    return CreditBucket(
      id: json['id'] as String,
      userId: json['userId'] as String,
      balance: (json['balance'] as num).toDouble(),
      lockedAmount: (json['lockedAmount'] as num).toDouble(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'balance': balance,
      'lockedAmount': lockedAmount,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
} 