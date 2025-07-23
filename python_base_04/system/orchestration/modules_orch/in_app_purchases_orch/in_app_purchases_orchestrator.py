"""
In-App Purchases Orchestrator

Handles system integration for in-app purchases module.
Follows the new orchestration architecture pattern.
"""

from flask import request, jsonify
from typing import Dict, Any, Optional
from tools.logger.custom_logging import custom_log
from datetime import datetime
from bson import ObjectId

from system.orchestration.modules_orch.base_files.module_orch_base import ModuleOrchestratorBase
from system.modules.in_app_purchases_module.in_app_purchases_main import InAppPurchasesModule


class InAppPurchasesOrchestrator(ModuleOrchestratorBase):
    """Orchestrator for in-app purchases module."""
    
    def __init__(self, manager_initializer):
        super().__init__(manager_initializer)
        self.module = None

    def initialize(self):
        """Initialize the orchestrator."""
        try:
            custom_log("Initializing InAppPurchasesOrchestrator", level="INFO")
            
            # Create module (no config needed)
            self.module = InAppPurchasesModule()
            self.module.initialize()
            
            # Register hooks and route callbacks
            self._register_hooks()
            self._register_route_callback()
            
            custom_log("InAppPurchasesOrchestrator initialized successfully", level="INFO")
            
        except Exception as e:
            custom_log(f"Error initializing InAppPurchasesOrchestrator: {e}", level="ERROR")
            raise

    def _register_hooks(self):
        """Register hooks with the system."""
        try:
            hooks_needed = self.module.get_hooks_needed()
            
            for hook_info in hooks_needed:
                self.hooks_manager.register_hook(
                    event=hook_info['event'],
                    callback=self._handle_hook_event,
                    priority=hook_info.get('priority', 10),
                    context=hook_info.get('context', 'in_app_purchases')
                )
                
            custom_log("InAppPurchasesOrchestrator hooks registered", level="INFO")
            
        except Exception as e:
            custom_log(f"Error registering hooks: {e}", level="ERROR")

    def _register_route_callback(self):
        """Register route callback with hooks manager."""
        try:
            self.hooks_manager.register_hook_callback(
                "register_routes",
                self.register_routes_callback,
                priority=10,
                context="in_app_purchases_orchestrator"
            )
            custom_log("InAppPurchasesOrchestrator registered route callback with hooks manager", level="INFO")
            
        except Exception as e:
            custom_log(f"Error registering route callback: {e}", level="ERROR")

    def register_routes_callback(self, data=None):
        """Register routes with Flask when hook is triggered."""
        try:
            from flask import current_app
            
            routes_needed = self.module.get_routes_needed()
            
            for route_info in routes_needed:
                route = route_info['route']
                methods = route_info['methods']
                handler_name = route_info['handler']
                
                handler_method = getattr(self, handler_name, None)
                if handler_method:
                    current_app.add_url_rule(
                        route,
                        f"in_app_purchases_{handler_name}",
                        handler_method,
                        methods=methods
                    )
                    custom_log(f"Registered route: {route} -> {handler_name}", level="DEBUG")
            
            custom_log("InAppPurchasesOrchestrator registered routes via hook", level="INFO")
            
        except Exception as e:
            custom_log(f"Error registering routes: {e}", level="ERROR")

    def _handle_hook_event(self, event_name: str, event_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Handle hook events by forwarding to module.
        
        Args:
            event_name: Name of the hook event
            event_data: Event data
            
        Returns:
            Dict with processing result
        """
        try:
            # Forward event to module for business logic processing
            result = self.module.process_hook_event(event_name, event_data)
            
            # Handle any system integration needed based on result
            if result.get('success'):
                custom_log(f"Hook event {event_name} processed successfully", level="INFO")
            else:
                custom_log(f"Hook event {event_name} failed: {result.get('error')}", level="ERROR")
            
            return result
            
        except Exception as e:
            custom_log(f"Error handling hook event {event_name}: {e}", level="ERROR")
            return {
                'success': False,
                'error': f'Hook event handling error: {str(e)}'
            }

    def verify_purchase(self):
        """Verify a purchase receipt."""
        try:
            data = request.get_json()
            if not data:
                return jsonify({"success": False, "error": "No data provided"}), 400
            
            # Get user ID from JWT token
            user_id = self._get_user_id_from_token()
            if not user_id:
                return jsonify({"success": False, "error": "Unauthorized"}), 401
            
            # Use module for business logic
            result = self.module.process_purchase_verification(data, user_id)
            
            if not result['success']:
                return jsonify({"success": False, "error": result['error']}), 400
            
            # Use stored database manager for persistence
            if result.get('purchase_document'):
                # Check if purchase already exists
                existing_purchase = self.db_manager.find_one(
                    "user_purchases", 
                    {"transaction_id": result['purchase_document']['transaction_id']}
                )
                
                if existing_purchase:
                    return jsonify({
                        "success": False,
                        "error": "Purchase already exists"
                    }), 409
                
                # Insert purchase
                inserted_id = self.db_manager.insert("user_purchases", result['purchase_document'])
                
                # Update user module data (commented out due to MongoDB update issue)
                # self._update_user_module_data(
                #     result['purchase_document']['user_id'],
                #     result['purchase_document']['product_id'],
                #     result['verification_result']
                # )
                
                return jsonify({
                    "success": True,
                    "message": "Purchase verified successfully",
                    "purchase_id": str(inserted_id)
                }), 200
            else:
                return jsonify({
                    "success": False,
                    "error": "Purchase verification failed"
                }), 400
                
        except Exception as e:
            custom_log(f"Error verifying purchase: {e}", level="ERROR")
            return jsonify({"success": False, "error": "Internal server error"}), 500

    def get_purchase_history(self):
        """Get user's purchase history."""
        try:
            # Get user ID from JWT token
            user_id = self._get_user_id_from_token()
            if not user_id:
                return jsonify({"success": False, "error": "Unauthorized"}), 401
            
            # Use module for business logic
            result = self.module.process_purchase_history_request(user_id)
            
            if not result['success']:
                return jsonify({"success": False, "error": result['error']}), 400
            
            # Use stored database manager to fetch history
            history = self.db_manager.find("user_purchases", result['query'])
            
            # Convert ObjectIds to strings
            for purchase in history:
                if '_id' in purchase:
                    purchase['_id'] = str(purchase['_id'])
            
            return jsonify({
                "success": True,
                "purchases": history,
                "total": len(history)
            }), 200
            
        except Exception as e:
            custom_log(f"Error getting purchase history: {e}", level="ERROR")
            return jsonify({"success": False, "error": "Internal server error"}), 500

    def restore_purchases(self):
        """Restore user's purchases."""
        try:
            # Get user ID from JWT token
            user_id = self._get_user_id_from_token()
            if not user_id:
                return jsonify({"success": False, "error": "Unauthorized"}), 401
            
            # Use module for business logic
            result = self.module.process_purchase_restoration_request(user_id)
            
            if not result['success']:
                return jsonify({"success": False, "error": result['error']}), 400
            
            # Use stored database manager to fetch purchases
            purchases = self.db_manager.find("user_purchases", result['query'])
            
            # Convert ObjectIds to strings
            for purchase in purchases:
                if '_id' in purchase:
                    purchase['_id'] = str(purchase['_id'])
            
            return jsonify({
                "success": True,
                "restored_purchases": purchases,
                "total": len(purchases)
            }), 200
            
        except Exception as e:
            custom_log(f"Error restoring purchases: {e}", level="ERROR")
            return jsonify({"success": False, "error": "Internal server error"}), 500

    def sync_products(self):
        """Sync products from stores."""
        try:
            data = request.get_json() or {}
            platform = data.get('platform')
            
            # Use module for business logic
            result = self.module.process_product_sync_request(platform)
            
            if not result['success']:
                return jsonify({"success": False, "error": result['error']}), 400
            
            # Use stored database manager to record sync
            sync_record = {
                'platform': platform,
                'started_at': datetime.utcnow().isoformat(),
                'sync_status': 'completed',
                'completed_at': datetime.utcnow().isoformat(),
                'created_at': datetime.utcnow().isoformat()
            }
            
            inserted_id = self.db_manager.insert("sync_history", sync_record)
            
            return jsonify({
                "success": True,
                "message": "Products synced successfully",
                "sync_id": str(inserted_id)
            }), 200
            
        except Exception as e:
            custom_log(f"Error syncing products: {e}", level="ERROR")
            return jsonify({"success": False, "error": "Internal server error"}), 500

    def get_products(self):
        """Get all synced products."""
        try:
            # Get user ID from JWT token
            user_id = self._get_user_id_from_token()
            if not user_id:
                return jsonify({"success": False, "error": "Unauthorized"}), 401
            
            # Get platform filter from query params
            platform = request.args.get('platform')
            
            # Use module for business logic
            result = self.module.process_products_request(platform)
            
            if not result['success']:
                return jsonify({"success": False, "error": result['error']}), 400
            
            # Use stored database manager to fetch products
            products = self.db_manager.find("store_products", result['query'])
            
            # Convert ObjectIds to strings
            for product in products:
                if '_id' in product:
                    product['_id'] = str(product['_id'])
            
            return jsonify({
                "success": True,
                "products": products,
                "total": len(products)
            }), 200
            
        except Exception as e:
            custom_log(f"Error getting products: {e}", level="ERROR")
            return jsonify({"success": False, "error": "Internal server error"}), 500

    def get_sync_history(self):
        """Get sync history."""
        try:
            # Get user ID from JWT token
            user_id = self._get_user_id_from_token()
            if not user_id:
                return jsonify({"success": False, "error": "Unauthorized"}), 401
            
            # Get query params
            platform = request.args.get('platform')
            limit = int(request.args.get('limit', 10))
            
            # Use module for business logic
            result = self.module.process_sync_history_request(platform, limit)
            
            if not result['success']:
                return jsonify({"success": False, "error": result['error']}), 400
            
            # Use stored database manager to fetch history
            history = list(self.db_manager.find("sync_history", result['query']).limit(result['limit']))
            
            # Convert ObjectIds to strings
            for record in history:
                if '_id' in record:
                    record['_id'] = str(record['_id'])
            
            return jsonify({
                "success": True,
                "history": history,
                "total": len(history)
            }), 200
            
        except Exception as e:
            custom_log(f"Error getting sync history: {e}", level="ERROR")
            return jsonify({"success": False, "error": "Internal server error"}), 500

    def _get_user_id_from_token(self) -> Optional[str]:
        """
        Get user ID from JWT token.
        
        Returns:
            User ID or None if not found
        """
        try:
            # Get user ID from request (set by JWT middleware)
            return getattr(request, 'user_id', None)
        except Exception as e:
            custom_log(f"Error getting user ID from token: {e}", level="ERROR")
            return None

    def _update_user_purchase(self, user_id: str, product_id: str, verification_result: Dict[str, Any]):
        """
        Update user purchase in database.
        
        Args:
            user_id: User ID
            product_id: Product ID
            verification_result: Verification result
        """
        try:
            # Update user's purchase record
            purchase_update = {
                'updated_at': datetime.utcnow().isoformat(),
                'verification_result': verification_result
            }
            
            self.db_manager.update(
                "user_purchases",
                {"user_id": user_id, "product_id": product_id},
                {"$set": purchase_update}
            )
            
            custom_log(f"Updated user purchase: {user_id} - {product_id}", level="INFO")
            
        except Exception as e:
            custom_log(f"Error updating user purchase: {e}", level="ERROR")

    def _update_user_module_data(self, user_id: str, product_id: str, verification_result: Dict[str, Any]):
        """
        Update user's module data with purchase information.
        
        Args:
            user_id: User ID
            product_id: Product ID
            verification_result: Verification result
        """
        try:
            # Get user from database
            user = self.db_manager.find_one("users", {"_id": ObjectId(user_id)})
            if not user:
                custom_log(f"User not found: {user_id}", level="WARNING")
                return
            
            # Update user's modules data
            modules_data = user.get('modules', {})
            if 'in_app_purchases' not in modules_data:
                modules_data['in_app_purchases'] = {}
            
            # Add purchase to user's module data
            if 'purchases' not in modules_data['in_app_purchases']:
                modules_data['in_app_purchases']['purchases'] = []
            
            purchase_data = {
                'product_id': product_id,
                'purchase_date': verification_result.get('purchase_date'),
                'transaction_id': verification_result.get('transaction_id'),
                'platform': verification_result.get('platform'),
                'status': verification_result.get('status')
            }
            
            modules_data['in_app_purchases']['purchases'].append(purchase_data)
            modules_data['in_app_purchases']['last_updated'] = datetime.utcnow().isoformat()
            
            # Update user in database
            self.db_manager.update(
                "users",
                {"_id": ObjectId(user_id)},
                {"$set": {"modules": modules_data}}
            )
            
            custom_log(f"Updated user module data: {user_id}", level="INFO")
            
        except Exception as e:
            custom_log(f"Error updating user module data: {e}", level="ERROR")

    def forward_request(self, request_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Forward request to module for processing.
        
        Args:
            request_data: Request data
            
        Returns:
            Dict with processing result
        """
        try:
            # This method can be used for custom request forwarding
            # For now, return a basic response
            return {
                'success': True,
                'message': 'Request forwarded to in-app purchases module',
                'data': request_data
            }
            
        except Exception as e:
            custom_log(f"Error forwarding request: {e}", level="ERROR")
            return {
                'success': False,
                'error': f'Request forwarding error: {str(e)}'
            }

    def health_check(self) -> Dict[str, Any]:
        """Orchestrator health check."""
        try:
            module_health = self.module.health_check() if self.module else {"status": "not_initialized"}
            
            return {
                "orchestrator": "in_app_purchases_orchestrator",
                "status": "healthy" if self.module else "not_initialized",
                "module": module_health,
                "managers": {
                    "db_manager": "available" if self.db_manager else "not_available",
                    "jwt_manager": "available" if self.jwt_manager else "not_available",
                    "hooks_manager": "available" if self.hooks_manager else "not_available"
                }
            }
            
        except Exception as e:
            custom_log(f"Error in health check: {e}", level="ERROR")
            return {
                "orchestrator": "in_app_purchases_orchestrator",
                "status": "error",
                "error": str(e)
            }

    def get_config(self) -> Dict[str, Any]:
        """Get orchestrator configuration."""
        try:
            module_config = self.module.get_config() if self.module else {}
            
            return {
                "orchestrator": "in_app_purchases_orchestrator",
                "module_config": module_config,
                "routes": self.module.get_routes_needed() if self.module else [],
                "hooks": self.module.get_hooks_needed() if self.module else []
            }
            
        except Exception as e:
            custom_log(f"Error getting config: {e}", level="ERROR")
            return {
                "orchestrator": "in_app_purchases_orchestrator",
                "status": "error",
                "error": str(e)
            }

    def dispose(self):
        """Cleanup orchestrator resources."""
        try:
            custom_log("Disposing InAppPurchasesOrchestrator", level="INFO")
            
            if self.module:
                self.module.dispose()
            
            custom_log("InAppPurchasesOrchestrator disposed successfully", level="INFO")
            
        except Exception as e:
            custom_log(f"Error disposing InAppPurchasesOrchestrator: {e}", level="ERROR") 