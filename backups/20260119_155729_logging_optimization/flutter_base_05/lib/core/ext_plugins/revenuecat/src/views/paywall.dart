import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../constant.dart';
import '../../../../../utils/consts/theme_consts.dart';

/// Generic Paywall Widget for RevenueCat
/// Can be customized for your app's specific needs
class Paywall extends StatefulWidget {
  final Offering offering;
  final Function(bool)? onPurchaseComplete;

  const Paywall({
    Key? key, 
    required this.offering,
    this.onPurchaseComplete,
  }) : super(key: key);

  @override
  _PaywallState createState() => _PaywallState();
}

class _PaywallState extends State<Paywall> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: SafeArea(
        child: Wrap(
          children: <Widget>[
            Container(
              height: 70.0,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(25.0)
                ),
              ),
              child: Center(
                  child: Text(
                  '✨ Premium Subscription',
                  style: AppTextStyles.headingSmall().copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textOnAccent,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(
                top: 32, 
                bottom: 16, 
                left: 16.0, 
                right: 16.0
              ),
              child: SizedBox(
                width: double.infinity,
                child: Text(
                  'PREMIUM FEATURES',
                  style: AppTextStyles.bodyMedium().copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            ListView.builder(
              itemCount: widget.offering.availablePackages.length,
              itemBuilder: (BuildContext context, int index) {
                var myProductList = widget.offering.availablePackages;
                return Card(
                  color: AppColors.surfaceVariant,
                  child: ListTile(
                    onTap: () async {
                      try {
                        final purchaseResult = await Purchases.purchasePackage(
                          myProductList[index]
                        );
                        
                        // In v9, purchasePackage returns PurchaseResult
                        // We need to check if the purchase was successful
                        if (purchaseResult.customerInfo != null) {
                          final customerInfo = purchaseResult.customerInfo!;
                          EntitlementInfo? entitlement = customerInfo
                              .entitlements.all[entitlementID];
                          bool isActive = entitlement?.isActive ?? false;
                          
                          widget.onPurchaseComplete?.call(isActive);
                        } else {
                          // Handle failed purchase
                          widget.onPurchaseComplete?.call(false);
                        }
                      } catch (e) {
                        // Purchase error
                      }

                      setState(() {});
                      Navigator.pop(context);
                    },
                    title: Text(
                      myProductList[index].storeProduct.title,
                      style: AppTextStyles.bodyMedium().copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      myProductList[index].storeProduct.description,
                      style: AppTextStyles.bodySmall(),
                    ),
                    trailing: Text(
                      myProductList[index].storeProduct.priceString,
                      style: AppTextStyles.bodyMedium().copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              },
              shrinkWrap: true,
              physics: const ClampingScrollPhysics(),
            ),
            Padding(
              padding: const EdgeInsets.only(
                top: 32, 
                bottom: 16, 
                left: 16.0, 
                right: 16.0
              ),
              child: SizedBox(
                width: double.infinity,
                child: Text(
                  footerText,
                  style: AppTextStyles.bodySmall(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
