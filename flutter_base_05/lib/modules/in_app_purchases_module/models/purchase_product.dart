/// Model representing a purchaseable product
class PurchaseProduct {
  final String id;
  final String title;
  final String description;
  final double price;
  final String currencyCode;
  final String productType; // 'consumable', 'non_consumable', 'subscription'
  final Map<String, dynamic>? metadata;

  PurchaseProduct({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    required this.currencyCode,
    required this.productType,
    this.metadata,
  });

  factory PurchaseProduct.fromJson(Map<String, dynamic> json) {
    return PurchaseProduct(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      price: (json['price'] ?? 0.0).toDouble(),
      currencyCode: json['currency_code'] ?? 'USD',
      productType: json['product_type'] ?? 'non_consumable',
      metadata: json['metadata'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'price': price,
      'currency_code': currencyCode,
      'product_type': productType,
      'metadata': metadata,
    };
  }

  @override
  String toString() {
    return 'PurchaseProduct(id: $id, title: $title, price: $price $currencyCode)';
  }
} 