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
