import '../../00_base/adapter_base.dart';
import '../../../tools/logging/logger.dart';
import '../../ext_plugins/revenuecat/main.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// RevenueCat Adapter - Seamlessly integrates RevenueCat with existing architecture
/// This adapter acts as a bridge between RevenueCat and your existing StateManager
/// without requiring changes to either system.
class RevenueCatAdapter extends AdapterBase {
  static final Logger _log = Logger();
  static RevenueCatAdapter? _instance;

  // RevenueCat SDK instance (will be initialized when dependency is added)
  dynamic _purchases;

  factory RevenueCatAdapter() {
    _instance ??= RevenueCatAdapter._internal();
    return _instance!;
  }

  RevenueCatAdapter._internal();

  @override
  String get adapterKey => 'revenuecat_adapter';

  @override
  Future<void> _initializeAdapter() async {
    _log.info('🔗 Initializing RevenueCat adapter...');

    try {
      // Initialize RevenueCat SDK (when dependency is added)
      await _initializeRevenueCatSDK();

      // Register subscription state in existing StateManager
      _registerWithStateManager();

      // Set up listeners for automatic state updates
      _setupStateListeners();

      _log.info('✅ RevenueCat adapter initialized successfully');

    } catch (e) {
      _log.error('❌ Error initializing RevenueCat adapter: $e');
      // Continue without RevenueCat - app will work with free features
    }
  }

  /// Initialize RevenueCat SDK with user authentication
  Future<void> _initializeRevenueCatSDK() async {
    try {
      // Initialize the RevenueCat plugin (real SDK)
      await configureRevenueCatSDK();
      
      // Get user data from AuthManager (best approach)
      final userData = authManager.getCurrentUserData();
      final userId = userData['userId'];
      final isLoggedIn = userData['isLoggedIn'] ?? false;
      
      _log.info('🔍 User authentication status: ${isLoggedIn ? "logged in" : "not logged in"}');
      _log.info('🔍 User ID: ${userId ?? "none"}');
      
      if (isLoggedIn && userId != null) {
        // Link RevenueCat to authenticated user
        await Purchases.logIn(userId);
        _log.info('✅ RevenueCat linked to authenticated user: $userId');
      } else {
        // Let RevenueCat create anonymous ID for guest users
        _log.info('ℹ️ No authenticated user, RevenueCat will create anonymous ID');
      }

    } catch (e) {
      _log.error('❌ RevenueCat SDK initialization failed: $e');
      rethrow;
    }
  }

  /// Register subscription state with existing StateManager
  void _registerWithStateManager() {
    // Use existing StateManager without modifications
    stateManager.registerModuleState("subscription", {
      "isSubscribed": false,
      "plan": "free",
      "features": [],
      "isLoading": false,
      "lastUpdated": DateTime.now().toIso8601String(),
    });

    _log.info('✅ Subscription state registered with StateManager');
  }

  /// Set up listeners for automatic state synchronization
  void _setupStateListeners() {
    _log.info('👂 RevenueCat state listeners setup');

    // Set up real RevenueCat listener
    Purchases.addCustomerInfoUpdateListener((customerInfo) {
      _updateStateManager({
        'isSubscribed': customerInfo.entitlements.all.isNotEmpty,
        'plan': customerInfo.entitlements.all.keys.firstOrNull ?? 'free',
        'features': customerInfo.entitlements.all.keys.toList(),
      });
      _triggerHooks({
        'isSubscribed': customerInfo.entitlements.all.isNotEmpty,
        'plan': customerInfo.entitlements.all.keys.firstOrNull ?? 'free',
        'features': customerInfo.entitlements.all.keys.toList(),
      });
    });
  }

  /// Update StateManager with RevenueCat data
  void _updateStateManager(Map<String, dynamic> customerInfo) {
    try {
      final isSubscribed = customerInfo['isSubscribed'] ?? false;
      final plan = customerInfo['plan'] ?? 'free';
      final features = customerInfo['features'] ?? [];

      stateManager.updateModuleState("subscription", {
        "isSubscribed": isSubscribed,
        "plan": plan,
        "features": features,
        "isLoading": false,
        "lastUpdated": DateTime.now().toIso8601String(),
      });

      _log.info('🔄 Subscription state updated: $plan');

    } catch (e) {
      _log.error('❌ Error updating subscription state: $e');
    }
  }

  /// Trigger existing hooks with subscription data
  void _triggerHooks(Map<String, dynamic> customerInfo) {
    try {
      final isSubscribed = customerInfo['isSubscribed'] ?? false;

      if (isSubscribed) {
        hooksManager.triggerHookWithData('subscription_active', {
          'plan': customerInfo['plan'],
          'features': customerInfo['features'],
        });
      } else {
        hooksManager.triggerHookWithData('subscription_inactive', {
          'plan': 'free',
        });
      }

      _log.info('🎣 Subscription hooks triggered');

    } catch (e) {
      _log.error('❌ Error triggering subscription hooks: $e');
    }
  }

  /// Check if user has access to a feature (seamless integration)
  bool hasFeatureAccess(String feature) {
    try {
      final subscriptionState = stateManager.getModuleState<Map<String, dynamic>>("subscription");
      if (subscriptionState == null) return false;

      final features = subscriptionState['features'] as List<dynamic>? ?? [];
      final hasAccess = features.contains(feature);

      _log.info('🔍 Feature access check - Feature: $feature, Access: $hasAccess');
      return hasAccess;

    } catch (e) {
      _log.error('❌ Error checking feature access: $e');
      return false;
    }
  }

  /// Get current subscription status (seamless integration)
  Map<String, dynamic> getSubscriptionStatus() {
    try {
      final subscriptionState = stateManager.getModuleState<Map<String, dynamic>>("subscription");
      return subscriptionState ?? {
        "isSubscribed": false,
        "plan": "free",
        "features": [],
      };

    } catch (e) {
      _log.error('❌ Error getting subscription status: $e');
      return {
        "isSubscribed": false,
        "plan": "free",
        "features": [],
      };
    }
  }

  /// Purchase a product (seamless integration)
  Future<Map<String, dynamic>> purchaseProduct(String productId) async {
    try {
      _log.info('💳 Purchasing product: $productId');

      // Get offerings from RevenueCat plugin
      final offerings = await Purchases.getOfferings();
      final offering = offerings.current;
      
      if (offering == null) {
        return {"success": false, "error": "No offerings available"};
      }

      // Find the package with matching product ID
      Package? package;
      for (final pkg in offering.availablePackages) {
        if (pkg.storeProduct.identifier == productId) {
          package = pkg;
          break;
        }
      }

      if (package == null) {
        return {"success": false, "error": "Product not found"};
      }

      // Purchase the package using RevenueCat plugin
      final purchaseResult = await Purchases.purchasePackage(package);
      
      // In v9, purchasePackage returns PurchaseResult
      if (purchaseResult.customerInfo != null) {
        final customerInfo = purchaseResult.customerInfo!;
        // Update state with real purchase data
        _updateStateManager({
          'isSubscribed': customerInfo.entitlements.all.isNotEmpty,
          'plan': customerInfo.entitlements.all.keys.firstOrNull ?? 'free',
          'features': customerInfo.entitlements.all.keys.toList(),
        });
      } else {
        // Handle failed purchase
        _log.warning('⚠️ Purchase completed but no customer info returned');
      }

      return {"success": true, "message": "Product purchased successfully"};

    } catch (e) {
      _log.error('❌ Error purchasing product: $e');
      return {"success": false, "error": "Purchase failed: $e"};
    }
  }

  /// Restore purchases (seamless integration)
  Future<Map<String, dynamic>> restorePurchases() async {
    try {
      _log.info('🔄 Restoring purchases...');

      // Restore purchases using RevenueCat plugin
      final customerInfo = await Purchases.restorePurchases();
      
      // Update state with restored purchase data
      _updateStateManager({
        'isSubscribed': customerInfo.entitlements.all.isNotEmpty,
        'plan': customerInfo.entitlements.all.keys.firstOrNull ?? 'free',
        'features': customerInfo.entitlements.all.keys.toList(),
      });

      return {"success": true, "message": "Purchases restored"};

    } catch (e) {
      _log.error('❌ Error restoring purchases: $e');
      return {"success": false, "error": "Restore failed: $e"};
    }
  }

  /// Get available products (seamless integration)
  Future<List<Map<String, dynamic>>> getProducts() async {
    try {
      // Get offerings from RevenueCat plugin
      final offerings = await Purchases.getOfferings();
      final offering = offerings.current;
      
      if (offering == null) {
        return [];
      }

      // Convert RevenueCat packages to your format
      return offering.availablePackages.map((pkg) => {
        "id": pkg.storeProduct.identifier,
        "title": pkg.storeProduct.title,
        "description": pkg.storeProduct.description,
        "price": pkg.storeProduct.priceString,
        "currencyCode": pkg.storeProduct.currencyCode,
      }).toList();

    } catch (e) {
      _log.error('❌ Error getting products: $e');
      return [];
    }
  }

  /// Handle user authentication changes (called when user logs in/out)
  Future<void> handleUserAuthChange() async {
    if (!isInitialized) {
      _log.info('⏸️ RevenueCat adapter not initialized, skipping auth change');
      return;
    }

    try {
      final userData = authManager.getCurrentUserData();
      final userId = userData['userId'];
      final isLoggedIn = userData['isLoggedIn'] ?? false;
      
      _log.info('🔄 Handling user authentication change');
      _log.info('🔍 User logged in: $isLoggedIn');
      _log.info('🔍 User ID: ${userId ?? "none"}');
      
      if (isLoggedIn && userId != null) {
        // Link RevenueCat to authenticated user
        await Purchases.logIn(userId);
        _log.info('✅ RevenueCat linked to authenticated user: $userId');
      } else {
        // Log out from RevenueCat (creates new anonymous ID)
        await Purchases.logOut();
        _log.info('ℹ️ RevenueCat logged out, will create new anonymous ID');
      }
    } catch (e) {
      _log.error('❌ Error handling user authentication change: $e');
    }
  }

  /// Check if RevenueCat is available
  bool get isAvailable => isInitialized;

  /// Get adapter status for debugging
  @override
  Map<String, dynamic> healthCheck() {
    return {
      "adapter": adapterKey,
      "isInitialized": isInitialized,
      "isAvailable": isAvailable,
      "subscriptionState": getSubscriptionStatus(),
      "userData": authManager.getCurrentUserData(),
    };
  }
} 