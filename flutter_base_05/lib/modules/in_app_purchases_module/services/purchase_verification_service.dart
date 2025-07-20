import '../../../modules/connections_api_module/connections_api_module.dart';
import '../../../core/managers/module_manager.dart';
import '../../../tools/logging/logger.dart';
import '../models/purchase_receipt.dart';

/// Service for verifying purchases with the server
class PurchaseVerificationService {
  static final Logger _log = Logger();
  late ConnectionsApiModule _apiModule;

  /// Initialize the verification service
  Future<void> initialize(ModuleManager moduleManager) async {
    try {
      _log.info('🔧 Initializing PurchaseVerificationService...');
      // Get ConnectionsApiModule from ModuleManager
      final apiModule = moduleManager.getModuleByType<ConnectionsApiModule>();
      if (apiModule != null) {
        _apiModule = apiModule;
      } else {
        throw Exception('ConnectionsApiModule not found in ModuleManager');
      }
      _log.info('✅ PurchaseVerificationService initialized');
    } catch (e) {
      _log.error('❌ Error initializing PurchaseVerificationService: $e');
      rethrow;
    }
  }

  /// Verify a purchase with the server
  Future<Map<String, dynamic>> verifyPurchase(PurchaseReceipt receipt) async {
    try {
      _log.info('🔍 Verifying purchase: ${receipt.purchaseId}');
      
      // Prepare verification data
      final verificationData = {
        'purchase_id': receipt.purchaseId,
        'product_id': receipt.productId,
        'platform': receipt.platform,
        'receipt_data': receipt.receiptData,
        'transaction_id': receipt.transactionId,
        'purchase_date': receipt.purchaseDate.toIso8601String(),
      };

      // Send verification request to server
      final response = await _apiModule.sendPostRequest(
        '/userauth/purchases/verify',
        verificationData,
      );

      if (response['success'] == true) {
        _log.info('✅ Purchase verified successfully');
        return {
          'success': true,
          'verified': true,
          'data': response['data'],
        };
      } else {
        _log.error('❌ Purchase verification failed: ${response['error']}');
        return {
          'success': false,
          'verified': false,
          'error': response['error'],
        };
      }
    } catch (e) {
      _log.error('❌ Error verifying purchase: $e');
      return {
        'success': false,
        'verified': false,
        'error': 'Verification error: $e',
      };
    }
  }

  /// Verify multiple purchases
  Future<List<Map<String, dynamic>>> verifyPurchases(List<PurchaseReceipt> receipts) async {
    try {
      _log.info('🔍 Verifying ${receipts.length} purchases');
      
      final results = <Map<String, dynamic>>[];
      
      for (final receipt in receipts) {
        final result = await verifyPurchase(receipt);
        results.add(result);
      }
      
      _log.info('✅ Verified ${receipts.length} purchases');
      return results;
    } catch (e) {
      _log.error('❌ Error verifying purchases: $e');
      return [];
    }
  }

  /// Get purchase history from server
  Future<List<Map<String, dynamic>>> getPurchaseHistory() async {
    try {
      _log.info('📋 Fetching purchase history');
      
      final response = await _apiModule.sendGetRequest('/userauth/purchases/history');
      
      if (response['success'] == true) {
        _log.info('✅ Retrieved purchase history');
        return List<Map<String, dynamic>>.from(response['data'] ?? []);
      } else {
        _log.error('❌ Failed to get purchase history: ${response['error']}');
        return [];
      }
    } catch (e) {
      _log.error('❌ Error getting purchase history: $e');
      return [];
    }
  }

  /// Restore purchases
  Future<Map<String, dynamic>> restorePurchases() async {
    try {
      _log.info('🔄 Restoring purchases');
      
      final response = await _apiModule.sendPostRequest('/userauth/purchases/restore', {});
      
      if (response['success'] == true) {
        _log.info('✅ Purchases restored successfully');
        return {
          'success': true,
          'restored_count': response['restored_count'] ?? 0,
          'data': response['data'],
        };
      } else {
        _log.error('❌ Failed to restore purchases: ${response['error']}');
        return {
          'success': false,
          'error': response['error'],
        };
      }
    } catch (e) {
      _log.error('❌ Error restoring purchases: $e');
      return {
        'success': false,
        'error': 'Restore error: $e',
      };
    }
  }

  /// Dispose resources
  void dispose() {
    _log.info('🗑 Disposing PurchaseVerificationService');
  }
} 