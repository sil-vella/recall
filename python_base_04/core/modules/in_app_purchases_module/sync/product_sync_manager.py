"""
Product Sync Manager

Handles automatic synchronization of products from Google Play and App Store.
Manages product database and sync history.
"""

import time
import json
from typing import Dict, List, Any, Optional
from datetime import datetime, timedelta
from tools.logger.custom_logging import custom_log


class ProductSyncManager:
    """Manages automatic synchronization of products from app stores."""
    
    def __init__(self, app_manager):
        self.app_manager = app_manager
        self.db_manager = app_manager.get_db_manager(role="read_write")
        
        # Sync configuration
        self.sync_interval_hours = 24  # Sync every 24 hours
        self.last_sync = {}  # Track last sync time per platform
        
        custom_log("ProductSyncManager initialized", level="INFO")
    
    def sync_all_products(self) -> Dict[str, Any]:
        """Sync products from both platforms."""
        try:
            custom_log("🔄 Starting full product sync from both platforms", level="INFO")
            
            results = {
                "app_store": self.sync_app_store_products(),
                "google_play": self.sync_google_play_products(),
                "timestamp": datetime.now().isoformat()
            }
            
            # Log summary
            total_products = (
                results["app_store"].get("products_synced", 0) + 
                results["google_play"].get("products_synced", 0)
            )
            
            custom_log(f"✅ Full sync completed: {total_products} total products", level="INFO")
            
            return results
            
        except Exception as e:
            custom_log(f"❌ Full sync failed: {e}", level="ERROR")
            return {"error": str(e)}
    
    def sync_app_store_products(self) -> Dict[str, Any]:
        """Sync products from App Store Connect."""
        sync_start = time.time()
        sync_id = None
        
        try:
            custom_log("🍎 Starting App Store product sync", level="INFO")
            
            # Create sync history record
            sync_id = self._create_sync_history("app_store", "full")
            
            # Simulate App Store API call (placeholder for real implementation)
            app_store_products = self._simulate_app_store_sync()
            
            # Process and store products
            sync_result = self._process_products("app_store", app_store_products)
            
            # Update sync history
            sync_duration = int((time.time() - sync_start) * 1000)
            self._update_sync_history(sync_id, sync_result, sync_duration)
            
            custom_log(f"✅ App Store sync completed: {sync_result['products_synced']} products", level="INFO")
            return sync_result
            
        except Exception as e:
            error_msg = f"App Store sync failed: {e}"
            custom_log(f"❌ {error_msg}", level="ERROR")
            
            if sync_id:
                self._update_sync_history(sync_id, {"error": error_msg}, 0)
            
            return {"error": error_msg}
    
    def sync_google_play_products(self) -> Dict[str, Any]:
        """Sync products from Google Play Console using real API."""
        sync_start = time.time()
        sync_id = None
        
        try:
            custom_log("🤖 Starting Google Play product sync", level="INFO")
            
            # Create sync history record
            sync_id = self._create_sync_history("google_play", "full")
            
            # Initialize Google Play API client
            from .google_play_api_client import GooglePlayAPIClient
            api_client = GooglePlayAPIClient(self.app_manager)
            
            if not api_client.initialize():
                raise Exception("Failed to initialize Google Play API client")
            
            # Get products from Google Play
            in_app_products = api_client.get_in_app_products()
            subscriptions = api_client.get_subscriptions()
            
            # Combine all products
            google_play_products = in_app_products + subscriptions
            
            # Process and store products
            sync_result = self._process_products("google_play", google_play_products)
            
            # Update sync history
            sync_duration = int((time.time() - sync_start) * 1000)
            self._update_sync_history(sync_id, sync_result, sync_duration)
            
            custom_log(f"✅ Google Play sync completed: {sync_result['products_synced']} products", level="INFO")
            return sync_result
            
        except Exception as e:
            error_msg = f"Google Play sync failed: {e}"
            custom_log(f"❌ {error_msg}", level="ERROR")
            
            if sync_id:
                self._update_sync_history(sync_id, {"error": error_msg}, 0)
            
            return {"error": error_msg}
    
    def _simulate_app_store_sync(self) -> List[Dict[str, Any]]:
        """Simulate App Store product sync (placeholder for real API)."""
        return [
            {
                "product_id": "premium_feature_1",
                "product_type": "non_consumable",
                "title": "Premium Feature 1",
                "description": "Unlock premium feature 1",
                "price": 0.99,
                "currency": "USD",
                "localized_price": "$0.99",
                "available": True
            },
            {
                "product_id": "premium_feature_2",
                "product_type": "non_consumable",
                "title": "Premium Feature 2",
                "description": "Unlock premium feature 2",
                "price": 1.99,
                "currency": "USD",
                "localized_price": "$1.99",
                "available": True
            },
            {
                "product_id": "subscription_monthly",
                "product_type": "subscription",
                "title": "Premium Monthly",
                "description": "Monthly premium subscription",
                "price": 4.99,
                "currency": "USD",
                "localized_price": "$4.99",
                "subscription_period": "P1M",
                "introductory_price": 2.99,
                "introductory_period": "P1W",
                "trial_period": "P3D",
                "family_sharing": True,
                "available": True
            },
            {
                "product_id": "subscription_yearly",
                "product_type": "subscription",
                "title": "Premium Yearly",
                "description": "Yearly premium subscription",
                "price": 49.99,
                "currency": "USD",
                "localized_price": "$49.99",
                "subscription_period": "P1Y",
                "introductory_price": 39.99,
                "introductory_period": "P1M",
                "family_sharing": True,
                "available": True
            },
            {
                "product_id": "coins_100",
                "product_type": "consumable",
                "title": "100 Coins",
                "description": "Get 100 coins",
                "price": 0.99,
                "currency": "USD",
                "localized_price": "$0.99",
                "available": True
            },
            {
                "product_id": "coins_500",
                "product_type": "consumable",
                "title": "500 Coins",
                "description": "Get 500 coins",
                "price": 3.99,
                "currency": "USD",
                "localized_price": "$3.99",
                "available": True
            }
        ]
    
    def _simulate_google_play_sync(self) -> List[Dict[str, Any]]:
        """Simulate Google Play product sync (placeholder for real API)."""
        return [
            {
                "product_id": "premium_feature_1",
                "product_type": "non_consumable",
                "title": "Premium Feature 1",
                "description": "Unlock premium feature 1",
                "price": 0.99,
                "currency": "USD",
                "localized_price": "$0.99",
                "available": True
            },
            {
                "product_id": "premium_feature_2",
                "product_type": "non_consumable",
                "title": "Premium Feature 2",
                "description": "Unlock premium feature 2",
                "price": 1.99,
                "currency": "USD",
                "localized_price": "$1.99",
                "available": True
            },
            {
                "product_id": "subscription_monthly",
                "product_type": "subscription",
                "title": "Premium Monthly",
                "description": "Monthly premium subscription",
                "price": 4.99,
                "currency": "USD",
                "localized_price": "$4.99",
                "subscription_period": "P1M",
                "introductory_price": 2.99,
                "introductory_period": "P1W",
                "available": True
            },
            {
                "product_id": "subscription_yearly",
                "product_type": "subscription",
                "title": "Premium Yearly",
                "description": "Yearly premium subscription",
                "price": 49.99,
                "currency": "USD",
                "localized_price": "$49.99",
                "subscription_period": "P1Y",
                "introductory_price": 39.99,
                "introductory_period": "P1M",
                "available": True
            },
            {
                "product_id": "coins_100",
                "product_type": "consumable",
                "title": "100 Coins",
                "description": "Get 100 coins",
                "price": 0.99,
                "currency": "USD",
                "localized_price": "$0.99",
                "available": True
            },
            {
                "product_id": "coins_500",
                "product_type": "consumable",
                "title": "500 Coins",
                "description": "Get 500 coins",
                "price": 3.99,
                "currency": "USD",
                "localized_price": "$3.99",
                "available": True
            }
        ]
    
    def _process_products(self, platform: str, products: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Process and store products in database."""
        try:
            products_synced = 0
            products_updated = 0
            products_added = 0
            
            for product in products:
                # Prepare product data
                product_data = {
                    "product_id": product["product_id"],
                    "platform": platform,
                    "product_type": product["product_type"],
                    "title": product.get("title"),
                    "description": product.get("description"),
                    "price": product.get("price"),
                    "currency": product.get("currency"),
                    "localized_price": product.get("localized_price"),
                    "subscription_period": product.get("subscription_period"),
                    "introductory_price": product.get("introductory_price"),
                    "introductory_period": product.get("introductory_period"),
                    "trial_period": product.get("trial_period"),
                    "family_sharing": product.get("family_sharing", False),
                    "available": product.get("available", True),
                    "last_synced": datetime.now()
                }
                
                # Check if product exists
                existing_product = self._get_product(product["product_id"], platform)
                
                if existing_product:
                    # Update existing product
                    self._update_product(product_data)
                    products_updated += 1
                else:
                    # Add new product
                    self._add_product(product_data)
                    products_added += 1
                
                products_synced += 1
            
            return {
                "products_synced": products_synced,
                "products_updated": products_updated,
                "products_added": products_added,
                "products_removed": 0  # Not implemented yet
            }
            
        except Exception as e:
            custom_log(f"❌ Error processing products: {e}", level="ERROR")
            return {"error": str(e)}
    
    def _get_product(self, product_id: str, platform: str) -> Optional[Dict[str, Any]]:
        """Get product from database."""
        try:
            result = self.db_manager.find_one(
                "store_products",
                {"product_id": product_id, "platform": platform}
            )
            return result
        except Exception as e:
            custom_log(f"❌ Error getting product: {e}", level="ERROR")
            return None
    
    def _add_product(self, product_data: Dict[str, Any]):
        """Add new product to database."""
        try:
            # Add MongoDB-specific fields
            product_data["created_at"] = datetime.now()
            product_data["updated_at"] = datetime.now()
            
            self.db_manager.insert("store_products", product_data)
        except Exception as e:
            custom_log(f"❌ Error adding product: {e}", level="ERROR")
            raise
    
    def _update_product(self, product_data: Dict[str, Any]):
        """Update existing product in database."""
        try:
            # Add MongoDB-specific fields
            product_data["updated_at"] = datetime.now()
            
            # Remove fields that shouldn't be updated
            update_data = {k: v for k, v in product_data.items() 
                         if k not in ["product_id", "platform", "created_at"]}
            
            self.db_manager.update(
                "store_products",
                {"product_id": product_data["product_id"], "platform": product_data["platform"]},
                {"$set": update_data}
            )
        except Exception as e:
            custom_log(f"❌ Error updating product: {e}", level="ERROR")
            raise
    
    def _create_sync_history(self, platform: str, sync_type: str) -> str:
        """Create sync history record."""
        try:
            sync_record = {
                "platform": platform,
                "sync_type": sync_type,
                "started_at": datetime.now()
            }
            
            result_id = self.db_manager.insert("sync_history", sync_record)
            return result_id
        except Exception as e:
            custom_log(f"❌ Error creating sync history: {e}", level="ERROR")
            return None
    
    def _update_sync_history(self, sync_id: str, sync_result: Dict[str, Any], duration_ms: int):
        """Update sync history record."""
        try:
            status = "success" if "error" not in sync_result else "failed"
            error_message = sync_result.get("error")
            
            update_data = {
                "products_synced": sync_result.get("products_synced", 0),
                "products_updated": sync_result.get("products_updated", 0),
                "products_added": sync_result.get("products_added", 0),
                "products_removed": sync_result.get("products_removed", 0),
                "sync_status": status,
                "error_message": error_message,
                "sync_duration_ms": duration_ms,
                "completed_at": datetime.now()
            }
            
            self.db_manager.update(
                "sync_history",
                {"_id": sync_id},
                {"$set": update_data}
            )
        except Exception as e:
            custom_log(f"❌ Error updating sync history: {e}", level="ERROR")
    
    def get_all_products(self, platform: Optional[str] = None) -> List[Dict[str, Any]]:
        """Get all products from database."""
        try:
            if platform:
                result = self.db_manager.find(
                    "store_products",
                    {"platform": platform}
                )
            else:
                result = self.db_manager.find(
                    "store_products",
                    {}
                )
            
            return result if result else []
        except Exception as e:
            custom_log(f"❌ Error getting products: {e}", level="ERROR")
            return []
    
    def get_product_by_id(self, product_id: str, platform: str) -> Optional[Dict[str, Any]]:
        """Get specific product by ID and platform."""
        return self._get_product(product_id, platform)
    
    def get_sync_history(self, platform: Optional[str] = None, limit: int = 10) -> List[Dict[str, Any]]:
        """Get sync history."""
        try:
            if platform:
                result = self.db_manager.find(
                    "sync_history",
                    {"platform": platform}
                )
            else:
                result = self.db_manager.find(
                    "sync_history",
                    {}
                )
            
            # Sort by started_at descending and limit results
            if result:
                result.sort(key=lambda x: x.get("started_at", datetime.min), reverse=True)
                result = result[:limit]
            
            return result if result else []
        except Exception as e:
            custom_log(f"❌ Error getting sync history: {e}", level="ERROR")
            return []
    
    def health_check(self) -> Dict[str, Any]:
        """Health check for the sync manager."""
        try:
            total_products = len(self.get_all_products())
            recent_syncs = self.get_sync_history(limit=5)
            
            return {
                "sync_manager": "ProductSyncManager",
                "status": "healthy",
                "total_products": total_products,
                "recent_syncs": len(recent_syncs),
                "last_sync": self.last_sync
            }
        except Exception as e:
            return {
                "sync_manager": "ProductSyncManager",
                "status": "unhealthy",
                "error": str(e)
            } 