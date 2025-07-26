import 'dart:async';
import 'dart:io';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../../../core/managers/state_manager.dart';
import '../../../core/managers/module_manager.dart';
import '../../../modules/connections_api_module/connections_api_module.dart';
import '../../../tools/logging/logger.dart';
import '../models/purchase_product.dart';
import '../models/purchase_status.dart' as app_purchase_status;
import '../models/purchase_receipt.dart';
import 'purchase_verification_service.dart';

/// Service for handling platform-specific in-app purchases
class PlatformPurchaseService {
  static final Logger _log = Logger();
  static final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  
  late PurchaseVerificationService _verificationService;
  late ConnectionsApiModule _apiModule;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  List<ProductDetails> _nativeProducts = [];
  List<PurchaseProduct> _backendProducts = [];
  bool _isAvailable = false;
  bool _isInitialized = false;

  /// Initialize the purchase service
  Future<void> initialize(ModuleManager moduleManager) async {
    try {
      _log.info('🔧 Initializing PlatformPurchaseService...');
      
      // Get existing ConnectionsApiModule from ModuleManager
      final apiModule = moduleManager.getModuleByType<ConnectionsApiModule>();
      if (apiModule != null) {
        _apiModule = apiModule;
      } else {
        throw Exception('ConnectionsApiModule not found in ModuleManager');
      }
      
      // Check if in-app purchases are available
      _isAvailable = await _inAppPurchase.isAvailable();
      _log.info('📱 In-app purchases available: $_isAvailable');
      
      if (_isAvailable) {
        // Listen to purchase updates
        _subscription = _inAppPurchase.purchaseStream.listen(
          _onPurchaseUpdate,
          onDone: () => _log.info('✅ Purchase stream completed'),
          onError: (error) => _log.error('❌ Purchase stream error: $error'),
        );
        
        _verificationService = PurchaseVerificationService();
        await _verificationService.initialize(moduleManager);
        
        _isInitialized = true;
        _log.info('✅ PlatformPurchaseService initialized successfully');
      } else {
        _log.warning('⚠️ In-app purchases not available on this device');
      }
    } catch (e) {
      _log.error('❌ Error initializing PlatformPurchaseService: $e');
      rethrow;
    }
  }

  /// Load available products from backend API
  Future<List<PurchaseProduct>> loadProducts(List<String> productIds) async {
    try {
      _log.info('🛍 Loading products from backend API...');
      
      // Check if we have cached products in StateManager
      final cachedProducts = StateManager().getModuleState<Map<String, dynamic>>("in_app_purchases");
      if (cachedProducts != null && cachedProducts['products'] != null) {
        final lastSync = cachedProducts['lastProductSync'];
        if (lastSync != null) {
          final lastSyncTime = DateTime.parse(lastSync);
          final now = DateTime.now();
          final difference = now.difference(lastSyncTime);
          
          // Use cached products if they're less than 1 hour old
          if (difference.inHours < 1) {
            _log.info('📦 Using cached products from StateManager');
            final products = (cachedProducts['products'] as List)
                .map((p) => PurchaseProduct.fromJson(p))
                .toList();
            _backendProducts = products;
            return products;
          }
        }
      }

      // Load products from backend API
      final response = await _apiModule.sendGetRequest('/userauth/purchases/products');
      
      if (response['success'] == true) {
        final productsData = response['products'] as List;
        final products = productsData
            .map((p) => PurchaseProduct.fromJson(p))
            .toList();
        
        _backendProducts = products;
        _log.info('✅ Loaded ${products.length} products from backend API');
        
        // Cache products in StateManager
        StateManager().updateModuleState("in_app_purchases", {
          'products': productsData,
          'lastProductSync': DateTime.now().toIso8601String(),
          'totalProducts': products.length,
        });
        
        return products;
      } else {
        _log.error('❌ Failed to load products from backend: ${response['error']}');
        return [];
      }
    } catch (e) {
      _log.error('❌ Error loading products from backend: $e');
      return [];
    }
  }

  /// Trigger product sync on backend
  Future<bool> syncProducts() async {
    try {
      _log.info('🔄 Triggering product sync on backend...');
      
      final response = await _apiModule.sendPostRequest('/userauth/purchases/sync', {});
      
      if (response['success'] == true) {
        _log.info('✅ Product sync triggered successfully');
        return true;
      } else {
        _log.error('❌ Failed to trigger product sync: ${response['error']}');
        return false;
      }
    } catch (e) {
      _log.error('❌ Error triggering product sync: $e');
      return false;
    }
  }

  /// Load products with fallback to sync if none found
  Future<List<PurchaseProduct>> loadProductsWithSync() async {
    try {
      // First try to load existing products
      var products = await loadProducts([]);
      
      // If no products found, trigger sync and try again
      if (products.isEmpty) {
        _log.info('📦 No products found, triggering sync...');
        final syncSuccess = await syncProducts();
        
        if (syncSuccess) {
          // Wait a moment for sync to complete
          await Future.delayed(Duration(seconds: 2));
          
          // Try loading products again
          products = await loadProducts([]);
          _log.info('📦 Loaded ${products.length} products after sync');
        }
      }
      
      return products;
    } catch (e) {
      _log.error('❌ Error in loadProductsWithSync: $e');
      return [];
    }
  }

  /// Load native platform products for purchase flow
  Future<List<ProductDetails>> loadNativeProducts(List<String> productIds) async {
    try {
      _log.info('🛍 Loading native platform products: $productIds');
      
      if (!_isAvailable) {
        _log.info('⚠️ In-app purchases not available');
        return [];
      }

      final ProductDetailsResponse response = await _inAppPurchase.queryProductDetails(productIds.toSet());
      
      if (response.notFoundIDs.isNotEmpty) {
        _log.info('⚠️ Products not found: ${response.notFoundIDs}');
      }

      _nativeProducts = response.productDetails;
      _log.info('✅ Loaded ${_nativeProducts.length} native products');

      return _nativeProducts;
    } catch (e) {
      _log.error('❌ Error loading native products: $e');
      return [];
    }
  }

  /// Purchase a product
  Future<Map<String, dynamic>> purchaseProduct(PurchaseProduct product) async {
    try {
      _log.info('💳 Starting purchase for product: ${product.id}');
      
      if (!_isAvailable) {
        return {
          'success': false,
          'error': 'In-app purchases not available',
          'status': app_purchase_status.PurchaseStatus.failed,
        };
      }

      // Find the native product details for this backend product
      final nativeProduct = _nativeProducts.firstWhere(
        (p) => p.id == product.id,
        orElse: () => throw Exception('Native product not found: ${product.id}'),
      );

      // Create purchase parameters
      final PurchaseParam purchaseParam = PurchaseParam(
        productDetails: nativeProduct,
      );

      // Start the purchase
      final bool success = await _inAppPurchase.buyNonConsumable(
        purchaseParam: purchaseParam,
      );

      if (success) {
        _log.info('✅ Purchase initiated successfully');
        return {
          'success': true,
          'status': app_purchase_status.PurchaseStatus.processing,
          'message': 'Purchase initiated',
        };
      } else {
        _log.error('❌ Failed to initiate purchase');
        return {
          'success': false,
          'error': 'Failed to initiate purchase',
          'status': app_purchase_status.PurchaseStatus.failed,
        };
      }
    } catch (e) {
      _log.error('❌ Error purchasing product: $e');
      return {
        'success': false,
        'error': 'Purchase error: $e',
        'status': app_purchase_status.PurchaseStatus.failed,
      };
    }
  }

  /// Handle purchase updates
  void _onPurchaseUpdate(List<PurchaseDetails> purchaseDetailsList) {
    _log.info('📦 Processing ${purchaseDetailsList.length} purchase updates');
    
    for (final PurchaseDetails purchaseDetails in purchaseDetailsList) {
      _log.info('🔄 Processing purchase: ${purchaseDetails.productID} - ${purchaseDetails.status}');
      
      switch (purchaseDetails.status) {
        case PurchaseStatus.pending:
          _handlePendingPurchase(purchaseDetails);
          break;
        case PurchaseStatus.purchased:
          _handlePurchasedProduct(purchaseDetails);
          break;
        case PurchaseStatus.restored:
          _handleRestoredProduct(purchaseDetails);
          break;
        case PurchaseStatus.error:
          _handlePurchaseError(purchaseDetails);
          break;
        case PurchaseStatus.canceled:
          _handleCanceledPurchase(purchaseDetails);
          break;
        default:
          _log.info('⚠️ Unknown purchase status: ${purchaseDetails.status}');
      }
    }
  }

  /// Handle pending purchase
  void _handlePendingPurchase(PurchaseDetails purchaseDetails) {
    _log.info('⏳ Purchase pending: ${purchaseDetails.productID}');
    _updatePurchaseState(app_purchase_status.PurchaseStatus.pending, purchaseDetails);
  }

  /// Handle successful purchase
  Future<void> _handlePurchasedProduct(PurchaseDetails purchaseDetails) async {
    _log.info('✅ Purchase completed: ${purchaseDetails.productID}');
    
    try {
      // Create receipt for verification
      final receipt = PurchaseReceipt(
        purchaseId: purchaseDetails.purchaseID ?? '',
        productId: purchaseDetails.productID,
        platform: _getPlatform(),
        receiptData: purchaseDetails.verificationData.serverVerificationData,
        transactionId: purchaseDetails.purchaseID,
        purchaseDate: DateTime.now(),
      );

      // Verify purchase with server
      final verificationResult = await _verificationService.verifyPurchase(receipt);
      
      if (verificationResult['success'] == true) {
        _log.info('✅ Purchase verified successfully');
        _updatePurchaseState(app_purchase_status.PurchaseStatus.completed, purchaseDetails);
        
        // Complete the purchase
        await _inAppPurchase.completePurchase(purchaseDetails);
      } else {
        _log.error('❌ Purchase verification failed: ${verificationResult['error']}');
        _updatePurchaseState(app_purchase_status.PurchaseStatus.failed, purchaseDetails);
      }
    } catch (e) {
      _log.error('❌ Error handling purchased product: $e');
      _updatePurchaseState(app_purchase_status.PurchaseStatus.failed, purchaseDetails);
    }
  }

  /// Handle restored purchase
  void _handleRestoredProduct(PurchaseDetails purchaseDetails) {
    _log.info('🔄 Purchase restored: ${purchaseDetails.productID}');
    _updatePurchaseState(app_purchase_status.PurchaseStatus.completed, purchaseDetails);
  }

  /// Handle purchase error
  void _handlePurchaseError(PurchaseDetails purchaseDetails) {
    _log.error('❌ Purchase error: ${purchaseDetails.error}');
    _updatePurchaseState(app_purchase_status.PurchaseStatus.failed, purchaseDetails);
  }

  /// Handle canceled purchase
  void _handleCanceledPurchase(PurchaseDetails purchaseDetails) {
    _log.info('❌ Purchase canceled: ${purchaseDetails.productID}');
    _updatePurchaseState(app_purchase_status.PurchaseStatus.cancelled, purchaseDetails);
  }

  /// Update purchase state in StateManager
  void _updatePurchaseState(app_purchase_status.PurchaseStatus status, PurchaseDetails purchaseDetails) {
    final stateManager = StateManager();
    final currentState = stateManager.getModuleState<Map<String, dynamic>>("in_app_purchases");
    
    final updatedPurchases = List<Map<String, dynamic>>.from(currentState?['purchases'] ?? []);
    updatedPurchases.add({
      'productId': purchaseDetails.productID,
      'purchaseId': purchaseDetails.purchaseID,
      'status': status.apiValue,
      'timestamp': DateTime.now().toIso8601String(),
      'error': purchaseDetails.error?.message,
    });

    final newState = <String, dynamic>{
      'purchases': updatedPurchases,
      'lastPurchaseStatus': status.apiValue,
    };
    
    if (currentState != null) {
      newState.addAll(currentState);
    }
    
    stateManager.updateModuleState("in_app_purchases", newState);
  }

  /// Get product type from ProductDetails
  String _getProductType(ProductDetails product) {
    // This is a simplified implementation
    // In a real app, you'd determine this based on your product configuration
    if (product.id.contains('subscription')) {
      return 'subscription';
    } else if (product.id.contains('consumable')) {
      return 'consumable';
    } else {
      return 'non_consumable';
    }
  }

  /// Get current platform
  String _getPlatform() {
    if (Platform.isAndroid) return 'google_play';
    if (Platform.isIOS) return 'app_store';
    return 'unknown';
  }

  /// Dispose resources
  void dispose() {
    _log.info('🗑 Disposing PlatformPurchaseService');
    _subscription?.cancel();
    _verificationService.dispose();
  }
} 