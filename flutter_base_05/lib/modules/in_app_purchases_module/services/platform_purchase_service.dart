import 'dart:async';
import 'dart:io';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../../../core/managers/state_manager.dart';
import '../../../core/managers/module_manager.dart';
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
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  List<ProductDetails> _products = [];
  bool _isAvailable = false;

  /// Initialize the purchase service
  Future<void> initialize(ModuleManager moduleManager) async {
    try {
      _log.info('🔧 Initializing PlatformPurchaseService...');
      
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
        
        _log.info('✅ PlatformPurchaseService initialized successfully');
      } else {
        _log.warning('⚠️ In-app purchases not available on this device');
      }
    } catch (e) {
      _log.error('❌ Error initializing PlatformPurchaseService: $e');
      rethrow;
    }
  }

  /// Load available products
  Future<List<PurchaseProduct>> loadProducts(List<String> productIds) async {
    try {
      _log.info('🛍 Loading products: $productIds');
      
      if (!_isAvailable) {
        _log.info('⚠️ In-app purchases not available');
        return [];
      }

      final ProductDetailsResponse response = await _inAppPurchase.queryProductDetails(productIds.toSet());
      
      if (response.notFoundIDs.isNotEmpty) {
        _log.info('⚠️ Products not found: ${response.notFoundIDs}');
      }

      _products = response.productDetails;
      _log.info('✅ Loaded ${_products.length} products');

      // Convert to our model
      return _products.map((product) => PurchaseProduct(
        id: product.id,
        title: product.title,
        description: product.description,
        price: product.rawPrice,
        currencyCode: product.currencyCode,
        productType: _getProductType(product),
        metadata: {
          'productId': product.id,
          'title': product.title,
        },
      )).toList();
    } catch (e) {
      _log.error('❌ Error loading products: $e');
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

      // Find the product details
      final productDetails = _products.firstWhere(
        (p) => p.id == product.id,
        orElse: () => throw Exception('Product not found: ${product.id}'),
      );

      // Create purchase parameters
      final PurchaseParam purchaseParam = PurchaseParam(
        productDetails: productDetails,
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