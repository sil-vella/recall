import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:in_app_purchase/in_app_purchase.dart';

/// Google Play purchase token for server verify (not the Play order id).
String playPurchaseToken(PurchaseDetails purchase) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    final data = purchase.verificationData.serverVerificationData.trim();
    if (data.isNotEmpty) {
      return data;
    }
  }
  return purchase.purchaseID?.trim() ?? '';
}

/// StoreKit 2 signed transaction JWS for Apple server verify.
String appleSignedTransaction(PurchaseDetails purchase) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    final data = purchase.verificationData.serverVerificationData.trim();
    if (data.isNotEmpty) {
      return data;
    }
  }
  return '';
}

/// Request body for native store coin verify endpoints.
Map<String, String> nativeCoinVerifyBody(PurchaseDetails purchase) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    final signed = appleSignedTransaction(purchase);
    if (signed.isNotEmpty) {
      return {'signed_transaction': signed};
    }
    final txId = purchase.purchaseID?.trim() ?? '';
    if (txId.isNotEmpty) {
      return {'transaction_id': txId};
    }
    return {};
  }

  final token = playPurchaseToken(purchase);
  if (token.isEmpty) {
    return {};
  }
  return {'purchase_token': token};
}

/// Request body for native store subscription verify endpoints.
Map<String, String> nativeSubscriptionVerifyBody(
  PurchaseDetails purchase, {
  required String productId,
}) {
  final body = <String, String>{'product_id': productId};
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    final signed = appleSignedTransaction(purchase);
    if (signed.isNotEmpty) {
      body['signed_transaction'] = signed;
      return body;
    }
    final txId = purchase.purchaseID?.trim() ?? '';
    if (txId.isNotEmpty) {
      body['transaction_id'] = txId;
    }
    return body;
  }

  final token = playPurchaseToken(purchase);
  if (token.isNotEmpty) {
    body['purchase_token'] = token;
  }
  return body;
}

bool get isNativeAndroidStore => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

bool get isNativeIosStore => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

bool get isNativeMobileStore => isNativeAndroidStore || isNativeIosStore;
