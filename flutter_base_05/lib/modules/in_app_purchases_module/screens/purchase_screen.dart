import 'package:flutter/material.dart';
import '../../../core/00_base/screen_base.dart';
import '../../../core/managers/module_manager.dart';
import '../models/purchase_product.dart';
import '../services/platform_purchase_service.dart';
import '../widgets/product_card.dart';

/// Screen for displaying and handling in-app purchases
class PurchaseScreen extends BaseScreen {
  const PurchaseScreen({Key? key}) : super(key: key);

  @override
  String computeTitle(BuildContext context) => 'In-App Purchases';

  @override
  BaseScreenState<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends BaseScreenState<PurchaseScreen> {
  late PlatformPurchaseService _purchaseService;
  List<PurchaseProduct> _products = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializePurchaseService();
    _loadProducts();
  }

  /// Initialize the purchase service
  Future<void> _initializePurchaseService() async {
    try {
      _purchaseService = PlatformPurchaseService();
      // Get ModuleManager from the current context or a global instance
      final moduleManager = ModuleManager();
      await _purchaseService.initialize(moduleManager);
      // log.info('✅ Purchase service initialized'); // Removed unused import
    } catch (e) {
      // log.error('❌ Error initializing purchase service: $e'); // Removed unused import
      setState(() {
        _error = 'Failed to initialize purchase service: $e';
      });
    }
  }

  /// Load available products
  Future<void> _loadProducts() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      // Load products from backend API with automatic sync if needed
      final products = await _purchaseService.loadProductsWithSync();
      
      // Also load native products for purchase flow
      final productIds = products.map((p) => p.id).toList();
      if (productIds.isNotEmpty) {
        await _purchaseService.loadNativeProducts(productIds);
      }
      
      setState(() {
        _products = products;
        _isLoading = false;
      });

      // log.info('✅ Loaded ${products.length} products'); // Removed unused import
    } catch (e) {
      // log.error('❌ Error loading products: $e'); // Removed unused import
      setState(() {
        _error = 'Failed to load products: $e';
        _isLoading = false;
      });
    }
  }

  /// Handle product purchase
  Future<void> _purchaseProduct(PurchaseProduct product) async {
    try {
      // log.info('💳 Starting purchase for: ${product.title}'); // Removed unused import
      
      final result = await _purchaseService.purchaseProduct(product);
      
      if (result['success'] == true) {
        // log.info('✅ Purchase initiated successfully'); // Removed unused import
        _showSuccessMessage('Purchase initiated successfully');
      } else {
        // log.error('❌ Purchase failed: ${result['error']}'); // Removed unused import
        _showErrorMessage('Purchase failed: ${result['error']}');
      }
    } catch (e) {
      // log.error('❌ Error purchasing product: $e'); // Removed unused import
      _showErrorMessage('Purchase error: $e');
    }
  }

  /// Show success message
  void _showSuccessMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Show error message
  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  @override
  Widget buildContent(BuildContext context) {
    if (_isLoading) {
      return buildContentCard(
        context,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading products...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return buildContentCard(
        context,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            Text(
              'Error',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadProducts,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_products.isEmpty) {
      return buildContentCard(
        context,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.shopping_cart_outlined,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text(
              'No products available',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadProducts,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _products.length,
        itemBuilder: (context, index) {
          final product = _products[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: ProductCard(
              product: product,
              onPurchase: () => _purchaseProduct(product),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _purchaseService.dispose();
    super.dispose();
  }
} 