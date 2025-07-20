"""
In-App Purchases Module

Handles in-app purchase verification and management for both Google Play and App Store.
"""

from flask import Blueprint, request, jsonify
from typing import Dict, Any, Optional
from ..base_module import BaseModule
from core.managers.app_manager import AppManager
from tools.logger.custom_logging import custom_log
from datetime import datetime

# Import the actual verifiers
from .verifiers.google_play_verifier import GooglePlayVerifier
from .verifiers.app_store_verifier import AppStoreVerifier
from .sync.product_sync_manager import ProductSyncManager


class InAppPurchasesModule(BaseModule):
    """Module for handling in-app purchases and receipt verification."""
    
    def __init__(self, app_manager: Optional[AppManager] = None):
        super().__init__(app_manager)
        self.module_name = "in_app_purchases_module"
        self.dependencies = ["user_management_module", "credit_system_module"]
        
        # Initialize verifiers and sync manager
        self.google_play_verifier = None
        self.app_store_verifier = None
        self.product_sync_manager = None
        
    def initialize(self, app_manager: AppManager):
        """Initialize the in-app purchases module."""
        self.app_manager = app_manager
        custom_log(f"Initializing {self.module_name}", level="INFO")
        
        # Initialize verifiers
        self._initialize_verifiers()
        
        # Register routes
        self.register_routes()
        
        custom_log(f"{self.module_name} initialized successfully", level="INFO")
    
    def _perform_initial_sync(self):
        """Perform initial product sync from both platforms."""
        try:
            custom_log("🔄 Performing initial product sync...", level="INFO")
            
            # Sync products from both platforms
            sync_result = self.product_sync_manager.sync_all_products()
            
            if "error" not in sync_result:
                total_products = (
                    sync_result.get("app_store", {}).get("products_synced", 0) +
                    sync_result.get("google_play", {}).get("products_synced", 0)
                )
                custom_log(f"✅ Initial sync completed: {total_products} products synced", level="INFO")
            else:
                custom_log(f"⚠️ Initial sync had issues: {sync_result.get('error')}", level="WARNING")
                
        except Exception as e:
            custom_log(f"❌ Initial sync failed: {e}", level="ERROR")
    
    def _initialize_database_schema(self):
        """Initialize database schema for in-app purchases module."""
        try:
            custom_log("🗄️ Initializing in-app purchases database schema...", level="INFO")
            
            # Get database manager
            db_manager = self.app_manager.get_db_manager(role="read_write")
            
            # Check if collections exist, if not create them
            collections = db_manager.db.list_collection_names()
            
            if "store_products" not in collections:
                custom_log("📝 Creating store_products collection...", level="INFO")
                db_manager.db.create_collection("store_products")
                # Create indexes
                db_manager.db.store_products.create_index([("product_id", 1), ("platform", 1)], unique=True)
                db_manager.db.store_products.create_index([("platform", 1)])
                db_manager.db.store_products.create_index([("product_type", 1)])
                db_manager.db.store_products.create_index([("available", 1)])
                db_manager.db.store_products.create_index([("last_synced", 1)])
            
            if "user_purchases" not in collections:
                custom_log("💳 Creating user_purchases collection...", level="INFO")
                db_manager.db.create_collection("user_purchases")
                # Create indexes
                db_manager.db.user_purchases.create_index([("user_id", 1)])
                db_manager.db.user_purchases.create_index([("product_id", 1)])
                db_manager.db.user_purchases.create_index([("transaction_id", 1)], unique=True)
                db_manager.db.user_purchases.create_index([("status", 1)])
                db_manager.db.user_purchases.create_index([("purchase_date", 1)])
                db_manager.db.user_purchases.create_index([("platform", 1)])
            
            if "sync_history" not in collections:
                custom_log("🔄 Creating sync_history collection...", level="INFO")
                db_manager.db.create_collection("sync_history")
                # Create indexes
                db_manager.db.sync_history.create_index([("platform", 1)])
                db_manager.db.sync_history.create_index([("started_at", 1)])
                db_manager.db.sync_history.create_index([("sync_status", 1)])
            
            # Update users collection with in-app purchases module data
            self._update_users_with_module_data()
            
            # Update module registry
            self._update_module_registry()
            
            custom_log("✅ Database schema initialized successfully", level="INFO")
            
        except Exception as e:
            custom_log(f"❌ Error initializing database schema: {e}", level="ERROR")
    
    def _update_users_with_module_data(self):
        """Update existing users with in-app purchases module data."""
        try:
            db_manager = self.app_manager.get_db_manager(role="read_write")
            
            # Update all users to include in-app purchases module
            update_result = db_manager.update(
                "users",
                {},
                {
                    "$set": {
                        "modules.in_app_purchases": {
                            "enabled": True,
                            "active_purchases": [],
                            "subscription_status": "none",
                            "last_purchase_date": None,
                            "total_spent": 0,
                            "currency": "USD",
                            "last_updated": datetime.now()
                        }
                    }
                }
            )
            
            custom_log(f"✅ Updated {update_result} users with in-app purchases module", level="INFO")
            
        except Exception as e:
            custom_log(f"❌ Error updating users with module data: {e}", level="ERROR")
    
    def _update_module_registry(self):
        """Update module registry with in-app purchases module."""
        try:
            db_manager = self.app_manager.get_db_manager(role="read_write")
            
            # Check if module already exists
            existing_module = db_manager.find_one(
                "user_modules",
                {"module_name": "in_app_purchases"}
            )
            
            if not existing_module:
                # Add module to registry
                module_data = {
                    "module_name": "in_app_purchases",
                    "display_name": "In-App Purchases Module",
                    "description": "In-app purchase and subscription management",
                    "status": "active",
                    "version": "1.0.0",
                    "schema": {
                        "enabled": "boolean",
                        "active_purchases": "array",
                        "subscription_status": "string",
                        "last_purchase_date": "date",
                        "total_spent": "number",
                        "currency": "string",
                        "last_updated": "date"
                    },
                    "created_at": datetime.now(),
                    "updated_at": datetime.now()
                }
                
                db_manager.insert("user_modules", module_data)
                custom_log("✅ Added in-app purchases module to registry", level="INFO")
            else:
                custom_log("ℹ️ In-app purchases module already exists in registry", level="INFO")
                
        except Exception as e:
            custom_log(f"❌ Error updating module registry: {e}", level="ERROR")
    
    def _initialize_verifiers(self):
        """Initialize platform-specific verifiers and sync manager."""
        try:
            # Initialize product sync manager
            self.product_sync_manager = ProductSyncManager(self.app_manager)
            
            # Initialize Google Play verifier
            self.google_play_verifier = GooglePlayVerifier(self.app_manager)
            self.google_play_verifier.product_sync_manager = self.product_sync_manager
            
            # Initialize App Store verifier  
            self.app_store_verifier = AppStoreVerifier(self.app_manager)
            self.app_store_verifier.product_sync_manager = self.product_sync_manager
            
            # Perform initial product sync
            self._perform_initial_sync()
            
            custom_log("Purchase verifiers and sync manager initialized", level="INFO")
        except Exception as e:
            custom_log(f"Error initializing verifiers: {e}", level="ERROR")
    
    def register_routes(self):
        """Register module routes."""
        try:
            # Create blueprint for userauth routes
            self.blueprint = Blueprint('in_app_purchases', __name__)
            
            # Register routes
            self.blueprint.route('/userauth/purchases/verify', methods=['POST'])(self.verify_purchase)
            self.blueprint.route('/userauth/purchases/history', methods=['GET'])(self.get_purchase_history)
            self.blueprint.route('/userauth/purchases/restore', methods=['POST'])(self.restore_purchases)
            
            # Sync management routes
            self.blueprint.route('/userauth/purchases/sync', methods=['POST'])(self.sync_products)
            self.blueprint.route('/userauth/purchases/products', methods=['GET'])(self.get_products)
            self.blueprint.route('/userauth/purchases/sync/history', methods=['GET'])(self.get_sync_history)
            
            # Initialize database schema
            self._initialize_database_schema()
            
            custom_log("In-app purchases routes registered", level="INFO")
        except Exception as e:
            custom_log(f"Error registering routes: {e}", level="ERROR")
    
    def verify_purchase(self):
        """Verify a purchase receipt."""
        try:
            data = request.get_json()
            if not data:
                return jsonify({"error": "No data provided"}), 400
            
            # Extract purchase data
            platform = data.get('platform')
            receipt_data = data.get('receipt_data')
            product_id = data.get('product_id')
            user_id = data.get('user_id')
            
            if not all([platform, receipt_data, product_id, user_id]):
                return jsonify({"error": "Missing required fields"}), 400
            
            # Verify based on platform
            if platform == 'google_play':
                result = self.google_play_verifier.verify_purchase(receipt_data, product_id)
            elif platform == 'app_store':
                result = self.app_store_verifier.verify_purchase(receipt_data, product_id)
            else:
                return jsonify({"error": "Unsupported platform"}), 400
            
            if result['valid']:
                # Update user credits/features
                self._update_user_purchase(user_id, product_id, result)
                return jsonify({"success": True, "message": "Purchase verified"})
            else:
                return jsonify({"success": False, "error": "Invalid purchase"}), 400
                
        except Exception as e:
            custom_log(f"Error verifying purchase: {e}", level="ERROR")
            return jsonify({"error": "Internal server error"}), 500
    
    def get_purchase_history(self):
        """Get user's purchase history."""
        try:
            # Get user ID from JWT token
            user_id = self._get_user_id_from_token()
            if not user_id:
                return jsonify({"error": "Unauthorized"}), 401
            
            # Get purchase history from database
            history = self._get_user_purchase_history(user_id)
            
            return jsonify({
                "success": True,
                "purchases": history
            })
            
        except Exception as e:
            custom_log(f"Error getting purchase history: {e}", level="ERROR")
            return jsonify({"error": "Internal server error"}), 500
    
    def restore_purchases(self):
        """Restore user's purchases."""
        try:
            # Get user ID from JWT token
            user_id = self._get_user_id_from_token()
            if not user_id:
                return jsonify({"error": "Unauthorized"}), 401
            
            # Restore purchases logic
            restored_purchases = self._restore_user_purchases(user_id)
            
            return jsonify({
                "success": True,
                "restored_purchases": restored_purchases
            })
            
        except Exception as e:
            custom_log(f"Error restoring purchases: {e}", level="ERROR")
            return jsonify({"error": "Internal server error"}), 500
    
    def _get_user_id_from_token(self) -> Optional[str]:
        """Extract user ID from JWT token."""
        try:
            # Get JWT manager
            jwt_manager = self.app_manager.jwt_manager
            
            # Get token from request headers
            auth_header = request.headers.get('Authorization')
            if not auth_header or not auth_header.startswith('Bearer '):
                return None
            
            token = auth_header.split(' ')[1]
            
            # Validate token and extract user ID
            payload = jwt_manager.validate_token(token)
            return payload.get('user_id')
            
        except Exception as e:
            custom_log(f"Error extracting user ID from token: {e}", level="ERROR")
            return None
    
    def _update_user_purchase(self, user_id: str, product_id: str, verification_result: Dict[str, Any]):
        """Update user's purchase record."""
        try:
            # Get database manager
            db_manager = self.app_manager.get_db_manager(role="read_write")
            
            # Insert purchase record
            purchase_data = {
                "user_id": user_id,
                "product_id": product_id,
                "platform": verification_result.get('platform'),
                "transaction_id": verification_result.get('transaction_id'),
                "purchase_date": verification_result.get('purchase_date'),
                "amount": verification_result.get('amount'),
                "currency": verification_result.get('currency'),
                "status": "verified",
                "receipt_data": verification_result.get('receipt_data'),
                "verification_response": verification_result,
                "expires_date": verification_result.get('expires_date'),
                "auto_renew_status": verification_result.get('auto_renew_status'),
                "created_at": datetime.now(),
                "updated_at": datetime.now()
            }
            
            db_manager.insert("user_purchases", purchase_data)
            
            # Update user's module data
            self._update_user_module_data(user_id, product_id, verification_result)
            
            custom_log(f"Purchase recorded for user {user_id}", level="INFO")
            
        except Exception as e:
            custom_log(f"Error updating user purchase: {e}", level="ERROR")
    
    def _update_user_module_data(self, user_id: str, product_id: str, verification_result: Dict[str, Any]):
        """Update user's in-app purchases module data."""
        try:
            db_manager = self.app_manager.get_db_manager(role="read_write")
            
            # Get current user data
            user = db_manager.find_one("users", {"_id": user_id})
            if not user:
                custom_log(f"User {user_id} not found", level="ERROR")
                return
            
            # Get product info
            product = db_manager.find_one("store_products", {
                "product_id": product_id,
                "platform": verification_result.get('platform')
            })
            
            # Update user's module data
            module_update = {
                "modules.in_app_purchases.last_purchase_date": datetime.now(),
                "modules.in_app_purchases.total_spent": user.get("modules", {}).get("in_app_purchases", {}).get("total_spent", 0) + verification_result.get('amount', 0),
                "modules.in_app_purchases.last_updated": datetime.now()
            }
            
            # Add to active purchases if it's a non-consumable or subscription
            if product and product.get("product_type") in ["non_consumable", "subscription"]:
                active_purchases = user.get("modules", {}).get("in_app_purchases", {}).get("active_purchases", [])
                if product_id not in active_purchases:
                    active_purchases.append(product_id)
                    module_update["modules.in_app_purchases.active_purchases"] = active_purchases
            
            # Update subscription status
            if product and product.get("product_type") == "subscription":
                module_update["modules.in_app_purchases.subscription_status"] = "active"
            
            db_manager.update("users", {"_id": user_id}, {"$set": module_update})
            
            custom_log(f"Updated module data for user {user_id}", level="INFO")
            
        except Exception as e:
            custom_log(f"Error updating user module data: {e}", level="ERROR")
    
    def _get_user_purchase_history(self, user_id: str) -> list:
        """Get user's purchase history from database."""
        try:
            db_manager = self.app_manager.get_db_manager(role="read_only")
            
            result = db_manager.find(
                "user_purchases",
                {"user_id": user_id}
            )
            
            # Sort by purchase_date descending
            if result:
                result.sort(key=lambda x: x.get("purchase_date", datetime.min), reverse=True)
            
            return result if result else []
            
        except Exception as e:
            custom_log(f"Error getting purchase history: {e}", level="ERROR")
            return []
    
    def _restore_user_purchases(self, user_id: str) -> list:
        """Restore user's purchases (placeholder for now)."""
        try:
            # Get purchase history
            purchases = self._get_user_purchase_history(user_id)
            
            # Filter for valid purchases that need restoration
            restored_purchases = []
            for purchase in purchases:
                if purchase.get('status') == 'verified':
                    restored_purchases.append(purchase)
            
            custom_log(f"Restored {len(restored_purchases)} purchases for user {user_id}", level="INFO")
            return restored_purchases
            
        except Exception as e:
            custom_log(f"Error restoring purchases: {e}", level="ERROR")
            return []
    
    def sync_products(self):
        """Manually trigger product sync from both platforms."""
        try:
            # Get user ID from JWT token
            user_id = self._get_user_id_from_token()
            if not user_id:
                return jsonify({"error": "Unauthorized"}), 401
            
            # Perform sync
            sync_result = self.product_sync_manager.sync_all_products()
            
            if "error" not in sync_result:
                return jsonify({
                    "success": True,
                    "message": "Product sync completed",
                    "result": sync_result
                })
            else:
                return jsonify({
                    "success": False,
                    "error": sync_result.get("error")
                }), 500
                
        except Exception as e:
            custom_log(f"Error syncing products: {e}", level="ERROR")
            return jsonify({"error": "Internal server error"}), 500
    
    def get_products(self):
        """Get all synced products."""
        try:
            # Get user ID from JWT token
            user_id = self._get_user_id_from_token()
            if not user_id:
                return jsonify({"error": "Unauthorized"}), 401
            
            # Get platform filter from query params
            platform = request.args.get('platform')
            
            products = self.product_sync_manager.get_all_products(platform)
            
            return jsonify({
                "success": True,
                "products": products,
                "total": len(products)
            })
            
        except Exception as e:
            custom_log(f"Error getting products: {e}", level="ERROR")
            return jsonify({"error": "Internal server error"}), 500
    
    def get_sync_history(self):
        """Get sync history."""
        try:
            # Get user ID from JWT token
            user_id = self._get_user_id_from_token()
            if not user_id:
                return jsonify({"error": "Unauthorized"}), 401
            
            # Get platform filter from query params
            platform = request.args.get('platform')
            limit = int(request.args.get('limit', 10))
            
            history = self.product_sync_manager.get_sync_history(platform, limit)
            
            return jsonify({
                "success": True,
                "history": history,
                "total": len(history)
            })
            
        except Exception as e:
            custom_log(f"Error getting sync history: {e}", level="ERROR")
            return jsonify({"error": "Internal server error"}), 500
    
    def configure(self):
        """Configure module settings."""
        custom_log(f"Configuring {self.module_name}", level="INFO")
        # Add any configuration logic here
    
    def dispose(self):
        """Cleanup module resources."""
        custom_log(f"Disposing {self.module_name}", level="INFO")
        # Add any cleanup logic here
    
    def declare_dependencies(self) -> list:
        """Declare module dependencies."""
        return self.dependencies
    
    def health_check(self) -> Dict[str, Any]:
        """Module health check."""
        return {
            "module": self.module_name,
            "status": "healthy" if self.app_manager else "not_initialized",
            "details": "In-app purchases module with Google Play and App Store verification"
        } 