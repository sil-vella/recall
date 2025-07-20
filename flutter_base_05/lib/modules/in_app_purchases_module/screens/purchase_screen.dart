import 'package:flutter/material.dart';
import '../../../core/managers/module_manager.dart';
import '../../../tools/logging/logger.dart';
import '../models/purchase_product.dart';
import '../services/platform_purchase_service.dart';
import '../widgets/product_card.dart';

/// Screen for displaying and handling in-app purchases
class PurchaseScreen extends StatefulWidget {
  const PurchaseScreen({Key? key}) : super(key: key);

  @override
  State<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends State<PurchaseScreen> {
  static final Logger _log = Logger();
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
      _log.info('✅ Purchase service initialized');
    } catch (e) {
      _log.error('❌ Error initializing purchase service: $e');
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

      // Example product IDs - replace with your actual product IDs
      final productIds = [
        'premium_feature_1',
        'premium_feature_2',
        'subscription_monthly',
        'subscription_yearly',
      ];

      final products = await _purchaseService.loadProducts(productIds);
      
      setState(() {
        _products = products;
        _isLoading = false;
      });

      _log.info('✅ Loaded ${products.length} products');
    } catch (e) {
      _log.error('❌ Error loading products: $e');
      setState(() {
        _error = 'Failed to load products: $e';
        _isLoading = false;
      });
    }
  }

  /// Handle product purchase
  Future<void> _purchaseProduct(PurchaseProduct product) async {
    try {
      _log.info('💳 Starting purchase for: ${product.title}');
      
      final result = await _purchaseService.purchaseProduct(product);
      
      if (result['success'] == true) {
        _log.info('✅ Purchase initiated successfully');
        _showSuccessMessage('Purchase initiated successfully');
      } else {
        _log.error('❌ Purchase failed: ${result['error']}');
        _showErrorMessage('Purchase failed: ${result['error']}');
      }
    } catch (e) {
      _log.error('❌ Error purchasing product: $e');
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('In-App Purchases'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadProducts,
            tooltip: 'Refresh products',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  /// Build the main body content
  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
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
      return Center(
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
      return const Center(
        child: Column(
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