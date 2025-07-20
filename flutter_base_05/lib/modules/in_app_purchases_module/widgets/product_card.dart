import 'package:flutter/material.dart';
import '../models/purchase_product.dart';
import 'purchase_button.dart';

/// Widget for displaying a product card
class ProductCard extends StatelessWidget {
  final PurchaseProduct product;
  final VoidCallback onPurchase;

  const ProductCard({
    Key? key,
    required this.product,
    required this.onPurchase,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        product.description,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getProductTypeColor(),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _getProductTypeLabel(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Price',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                    Text(
                      '${product.price.toStringAsFixed(2)} ${product.currencyCode}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                  ],
                ),
                PurchaseButton(
                  product: product,
                  onPurchase: onPurchase,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Get color for product type badge
  Color _getProductTypeColor() {
    switch (product.productType) {
      case 'subscription':
        return Colors.blue;
      case 'consumable':
        return Colors.green;
      case 'non_consumable':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  /// Get label for product type badge
  String _getProductTypeLabel() {
    switch (product.productType) {
      case 'subscription':
        return 'SUBSCRIPTION';
      case 'consumable':
        return 'CONSUMABLE';
      case 'non_consumable':
        return 'FEATURE';
      default:
        return 'UNKNOWN';
    }
  }
} 