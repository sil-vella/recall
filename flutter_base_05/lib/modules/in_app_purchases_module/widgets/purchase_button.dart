import 'package:flutter/material.dart';
import '../models/purchase_product.dart';

/// Widget for handling purchase actions
class PurchaseButton extends StatefulWidget {
  final PurchaseProduct product;
  final VoidCallback onPurchase;

  const PurchaseButton({
    Key? key,
    required this.product,
    required this.onPurchase,
  }) : super(key: key);

  @override
  State<PurchaseButton> createState() => _PurchaseButtonState();
}

class _PurchaseButtonState extends State<PurchaseButton> {
  bool _isLoading = false;

  /// Handle purchase button tap
  Future<void> _handlePurchase() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      widget.onPurchase();
    } catch (e) {
      // Error handling is done in the parent widget
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: _isLoading ? null : _handlePurchase,
      style: ElevatedButton.styleFrom(
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: _isLoading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.shopping_cart,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  _getButtonText(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
    );
  }

  /// Get appropriate button text based on product type
  String _getButtonText() {
    switch (widget.product.productType) {
      case 'subscription':
        return 'Subscribe';
      case 'consumable':
        return 'Buy';
      case 'non_consumable':
        return 'Purchase';
      default:
        return 'Buy';
    }
  }
} 