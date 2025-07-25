"""
Google Play Developer API Client

Handles authentication and API calls to Google Play Developer API.
"""

import json
import time
from typing import Dict, List, Any, Optional
from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError
from tools.logger.custom_logging import custom_log


class GooglePlayAPIClient:
    """Client for Google Play Developer API."""
    
    def __init__(self, app_manager):
        self.app_manager = app_manager
        self.service = None
        self.package_name = None
        self.credentials = None
        
    def initialize(self):
        """Initialize the Google Play API client."""
        try:
            # Load configuration
            self.package_name = self.app_manager.config.GOOGLE_PLAY_PACKAGE_NAME
            service_account_data = self.app_manager.config.GOOGLE_PLAY_SERVICE_ACCOUNT_FILE
            
            if not service_account_data:
                custom_log("⚠️ Google Play service account not configured", level="WARNING")
                return False
            
            # Handle both file path and JSON content
            if service_account_data.startswith('{'):
                # JSON content provided directly
                import json
                service_account_info = json.loads(service_account_data)
                self.credentials = service_account.Credentials.from_service_account_info(
                    service_account_info,
                    scopes=['https://www.googleapis.com/auth/androidpublisher']
                )
            else:
                # File path provided
                self.credentials = service_account.Credentials.from_service_account_file(
                    service_account_data,
                    scopes=['https://www.googleapis.com/auth/androidpublisher']
                )
            
            # Build the service
            self.service = build('androidpublisher', 'v3', credentials=self.credentials)
            
            custom_log("✅ Google Play API client initialized successfully", level="INFO")
            return True
            
        except Exception as e:
            custom_log(f"❌ Failed to initialize Google Play API client: {e}", level="ERROR")
            return False
    
    def get_in_app_products(self) -> List[Dict[str, Any]]:
        """Get all in-app products from Google Play Console."""
        try:
            if not self.service:
                raise Exception("Google Play API client not initialized")
            
            # Call the API
            request = self.service.inappproducts().list(
                packageName=self.package_name
            )
            response = request.execute()
            
            products = []
            for product in response.get('inappproduct', []):
                products.append(self._parse_product(product))
            
            custom_log(f"✅ Retrieved {len(products)} in-app products from Google Play", level="INFO")
            return products
            
        except HttpError as e:
            custom_log(f"❌ Google Play API error: {e}", level="ERROR")
            return []
        except Exception as e:
            custom_log(f"❌ Error getting in-app products: {e}", level="ERROR")
            return []
    
    def get_subscriptions(self) -> List[Dict[str, Any]]:
        """Get all subscriptions from Google Play Console."""
        try:
            if not self.service:
                raise Exception("Google Play API client not initialized")
            
            # Call the API
            request = self.service.monetization().subscriptions().list(
                packageName=self.package_name
            )
            response = request.execute()
            
            subscriptions = []
            for subscription in response.get('subscriptions', []):
                subscriptions.append(self._parse_subscription(subscription))
            
            custom_log(f"✅ Retrieved {len(subscriptions)} subscriptions from Google Play", level="INFO")
            return subscriptions
            
        except HttpError as e:
            custom_log(f"❌ Google Play API error: {e}", level="ERROR")
            return []
        except Exception as e:
            custom_log(f"❌ Error getting subscriptions: {e}", level="ERROR")
            return []
    
    def verify_purchase(self, purchase_token: str, product_id: str) -> Dict[str, Any]:
        """Verify a purchase using Google Play Developer API."""
        try:
            if not self.service:
                raise Exception("Google Play API client not initialized")
            
            # Call the API
            request = self.service.purchases().products().get(
                packageName=self.package_name,
                productId=product_id,
                token=purchase_token
            )
            response = request.execute()
            
            return self._parse_purchase_verification(response)
            
        except HttpError as e:
            custom_log(f"❌ Google Play API error: {e}", level="ERROR")
            return {"valid": False, "error": str(e)}
        except Exception as e:
            custom_log(f"❌ Error verifying purchase: {e}", level="ERROR")
            return {"valid": False, "error": str(e)}
    
    def _parse_product(self, product_data: Dict[str, Any]) -> Dict[str, Any]:
        """Parse Google Play product data into our format."""
        try:
            # Extract price information
            price_info = product_data.get('defaultPrice', {})
            price_micros = price_info.get('priceMicros', 0)
            price = price_micros / 1000000  # Convert micros to dollars
            
            return {
                "product_id": product_data.get("sku"),
                "product_type": "consumable",  # or "non_consumable" based on product type
                "title": product_data.get("defaultLanguage", {}).get("title"),
                "description": product_data.get("defaultLanguage", {}).get("description"),
                "price": price,
                "currency": price_info.get("priceCurrencyCode", "USD"),
                "localized_price": f"${price:.2f}",
                "available": product_data.get("status") == "active",
                "last_synced": time.time()
            }
        except Exception as e:
            custom_log(f"❌ Error parsing product data: {e}", level="ERROR")
            return {}
    
    def _parse_subscription(self, subscription_data: Dict[str, Any]) -> Dict[str, Any]:
        """Parse Google Play subscription data into our format."""
        try:
            # Extract price information
            price_info = subscription_data.get('basePlans', [{}])[0].get('pricingPhases', [{}])[0]
            price_micros = price_info.get('pricingPhasePrice', {}).get('priceMicros', 0)
            price = price_micros / 1000000  # Convert micros to dollars
            
            return {
                "product_id": subscription_data.get("productId"),
                "product_type": "subscription",
                "title": subscription_data.get("title"),
                "description": subscription_data.get("description"),
                "price": price,
                "currency": price_info.get('pricingPhasePrice', {}).get('priceCurrencyCode', 'USD'),
                "subscription_period": subscription_data.get("subscriptionPeriod"),
                "introductory_price": subscription_data.get("introductoryPriceInfo", {}).get("introductoryPriceAmountMicros"),
                "introductory_period": subscription_data.get("introductoryPriceInfo", {}).get("introductoryPricePeriod"),
                "available": subscription_data.get("status") == "active",
                "last_synced": time.time()
            }
        except Exception as e:
            custom_log(f"❌ Error parsing subscription data: {e}", level="ERROR")
            return {}
    
    def _parse_purchase_verification(self, verification_data: Dict[str, Any]) -> Dict[str, Any]:
        """Parse purchase verification response."""
        try:
            # Convert purchase time from milliseconds to seconds
            purchase_time = verification_data.get('purchaseTime', 0)
            if purchase_time:
                purchase_time = purchase_time / 1000
            
            # Convert price from micros to dollars
            price_micros = verification_data.get('priceAmountMicros', 0)
            price = price_micros / 1000000
            
            return {
                "valid": verification_data.get("purchaseState") == 0,  # 0 = purchased
                "platform": "google_play",
                "product_id": verification_data.get("productId"),
                "transaction_id": verification_data.get("orderId"),
                "purchase_date": purchase_time,
                "amount": price,
                "currency": verification_data.get("priceCurrencyCode", "USD"),
                "purchase_state": verification_data.get("purchaseState"),
                "acknowledgement_state": verification_data.get("acknowledgementState"),
                "purchase_token": verification_data.get("purchaseToken"),
                "order_id": verification_data.get("orderId"),
                "purchase_time": verification_data.get("purchaseTime"),
                "developer_payload": verification_data.get("developerPayload", ""),
                "purchase_type": verification_data.get("purchaseType")
            }
        except Exception as e:
            custom_log(f"❌ Error parsing purchase verification: {e}", level="ERROR")
            return {"valid": False, "error": f"Parse error: {str(e)}"}
    
    def health_check(self) -> Dict[str, Any]:
        """Health check for the Google Play API client."""
        try:
            if not self.service:
                return {
                    "client": "GooglePlayAPIClient",
                    "status": "not_initialized",
                    "error": "Service not initialized"
                }
            
            # Try a simple API call to test connectivity
            request = self.service.inappproducts().list(
                packageName=self.package_name,
                maxResults=1
            )
            response = request.execute()
            
            return {
                "client": "GooglePlayAPIClient",
                "status": "healthy",
                "package_name": self.package_name,
                "api_accessible": True,
                "products_count": len(response.get('inappproduct', []))
            }
            
        except Exception as e:
            return {
                "client": "GooglePlayAPIClient",
                "status": "unhealthy",
                "error": str(e)
            } 