import '../../00_base/adapter_base.dart';
import '../../ext_plugins/revenuecat/main.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../../tools/logging/logger.dart';

/// RevenueCat adapter tracing (enable-logging-switch.mdc).
const bool LOGGING_SWITCH = false;

/// RevenueCat Adapter - Seamlessly integrates RevenueCat with existing architecture
/// This adapter acts as a bridge between RevenueCat and your existing StateManager
/// without requiring changes to either system.
class RevenueCatAdapter extends AdapterBase {
  static RevenueCatAdapter? _instance;

  final Logger _logger = Logger();

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
    try {
      // Initialize RevenueCat SDK (when dependency is added)
      await _initializeRevenueCatSDK();

      // Register subscription state in existing StateManager
      _registerWithStateManager();

      // Set up listeners for automatic state updates
      _setupStateListeners();

    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.warning('RevenueCatAdapter: _initializeAdapter failed: $e');
      }
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

      if (isLoggedIn && userId != null) {
        if (LOGGING_SWITCH) {
          _logger.info('RevenueCatAdapter: Purchases.logIn at init userId=$userId');
        }
        // Link RevenueCat to authenticated user
        await Purchases.logIn(userId);
      } else {
        if (LOGGING_SWITCH) {
          _logger.info('RevenueCatAdapter: anonymous RC user at init (not logged in)');
        }
        // Let RevenueCat create anonymous ID for guest users
      }

    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('RevenueCatAdapter: _initializeRevenueCatSDK error: $e', error: e);
      }
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
  }

  /// Set up listeners for automatic state synchronization
  void _setupStateListeners() {
    // Set up real RevenueCat listener
    Purchases.addCustomerInfoUpdateListener((customerInfo) {
      if (LOGGING_SWITCH) {
        _logger.info(
          'RevenueCatAdapter: customerInfo update entitlements=${customerInfo.entitlements.all.keys.toList()}',
        );
      }
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

    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.warning('RevenueCatAdapter: _updateStateManager: $e');
      }
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

    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.warning('RevenueCatAdapter: _triggerHooks: $e');
      }
    }
  }

  /// Check if user has access to a feature (seamless integration)
  bool hasFeatureAccess(String feature) {
    try {
      final subscriptionState = stateManager.getModuleState<Map<String, dynamic>>("subscription");
      if (subscriptionState == null) return false;

      final features = subscriptionState['features'] as List<dynamic>? ?? [];
      final hasAccess = features.contains(feature);

      return hasAccess;

    } catch (e) {
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
      // Get offerings from RevenueCat plugin
      final offerings = await Purchases.getOfferings();
      final offering = offerings.current;
      if (LOGGING_SWITCH) {
        _logger.info(
          'RevenueCatAdapter: purchaseProduct currentOffering=${offering?.identifier} '
          'packageIds=${offering?.availablePackages.map((p) => p.storeProduct.identifier).toList() ?? []}',
        );
      }

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
      }

      if (LOGGING_SWITCH) {
        _logger.info('RevenueCatAdapter: purchaseProduct success productId=$productId');
      }
      return {"success": true, "message": "Product purchased successfully"};

    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.warning('RevenueCatAdapter: purchaseProduct failed: $e');
      }
      return {"success": false, "error": "Purchase failed: $e"};
    }
  }

  /// Restore purchases (seamless integration)
  Future<Map<String, dynamic>> restorePurchases() async {
    try {
      // Restore purchases using RevenueCat plugin
      final customerInfo = await Purchases.restorePurchases();
      
      // Update state with restored purchase data
      _updateStateManager({
        'isSubscribed': customerInfo.entitlements.all.isNotEmpty,
        'plan': customerInfo.entitlements.all.keys.firstOrNull ?? 'free',
        'features': customerInfo.entitlements.all.keys.toList(),
      });

      if (LOGGING_SWITCH) {
        _logger.info('RevenueCatAdapter: restorePurchases done');
      }
      return {"success": true, "message": "Purchases restored"};

    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.warning('RevenueCatAdapter: restorePurchases failed: $e');
      }
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
      if (LOGGING_SWITCH) {
        _logger.warning('RevenueCatAdapter: getProducts failed: $e');
      }
      return [];
    }
  }

  /// Handle user authentication changes (called when user logs in/out)
  Future<void> handleUserAuthChange() async {
    if (!isInitialized) {
      return;
    }

    try {
      final userData = authManager.getCurrentUserData();
      final userId = userData['userId'];
      final isLoggedIn = userData['isLoggedIn'] ?? false;
      
      if (isLoggedIn && userId != null) {
        if (LOGGING_SWITCH) {
          _logger.info('RevenueCatAdapter: handleUserAuthChange logIn userId=$userId');
        }
        // Link RevenueCat to authenticated user
        await Purchases.logIn(userId);
      } else {
        if (LOGGING_SWITCH) {
          _logger.info('RevenueCatAdapter: handleUserAuthChange logOut');
        }
        // Log out from RevenueCat (creates new anonymous ID)
        await Purchases.logOut();
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.warning('RevenueCatAdapter: handleUserAuthChange error: $e');
      }
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