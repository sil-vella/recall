from typing import Dict, Any, Optional
from flask import request, jsonify
from datetime import datetime
from tools.logger.custom_logging import custom_log
from system.orchestration.modules_orch.base_files.module_orch_base import ModuleOrchestratorBase
from system.modules.stripe_module.stripe_main import StripeModule


class StripeOrchestrator(ModuleOrchestratorBase):
    """Orchestrator for Stripe payment processing module."""
    
    def __init__(self, manager_initializer):
        super().__init__(manager_initializer)
        self.module = None

    def initialize(self):
        """Initialize the orchestrator and module."""
        try:
            # Create module (no config needed - module handles its own secrets)
            self.module = StripeModule()
            self.module.initialize()
            
            # Register hooks and route callbacks
            self._register_hooks()
            self._register_route_callback()
            
            custom_log("✅ StripeOrchestrator initialized successfully")
            
        except Exception as e:
            custom_log(f"❌ Error initializing StripeOrchestrator: {e}", level="ERROR")
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
                    context=hook_info.get('context', 'stripe')
                )
                custom_log(f"Registered hook: {hook_info['event']} for StripeOrchestrator", level="DEBUG")
            
            custom_log("✅ StripeOrchestrator registered hooks", level="INFO")
            
        except Exception as e:
            custom_log(f"Error registering hooks: {e}", level="ERROR")

    def _register_route_callback(self):
        """Register route callback with hooks manager."""
        try:
            self.hooks_manager.register_hook_callback(
                "register_routes",
                self.register_routes_callback,
                priority=10,
                context="stripe_orchestrator"
            )
            custom_log("StripeOrchestrator registered route callback with hooks manager", level="INFO")
            
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
                        f"stripe_{handler_name}",
                        handler_method,
                        methods=methods
                    )
                    custom_log(f"Registered route: {route} -> {handler_name}", level="DEBUG")
            
            custom_log("StripeOrchestrator registered routes via hook", level="INFO")
            
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

    def create_payment_intent(self):
        """Create a Stripe payment intent."""
        try:
            data = request.get_json()
            if not data:
                return jsonify({"success": False, "error": "No data provided"}), 400
            
            # Use module for business logic
            result = self.module.process_payment_intent_creation(data)
            
            if not result['success']:
                return jsonify({"success": False, "error": result['error']}), 400
            
            return jsonify(result), 200
            
        except Exception as e:
            custom_log(f"Error creating payment intent: {e}", level="ERROR")
            return jsonify({"success": False, "error": "Internal server error"}), 500

    def confirm_payment(self):
        """Confirm a payment and process credit purchase."""
        try:
            data = request.get_json()
            if not data:
                return jsonify({"success": False, "error": "No data provided"}), 400
            
            payment_intent_id = data.get('payment_intent_id')
            if not payment_intent_id:
                return jsonify({"success": False, "error": "Payment intent ID is required"}), 400
            
            # Use module for business logic
            result = self.module.process_payment_confirmation(payment_intent_id)
            
            if not result['success']:
                return jsonify({"success": False, "error": result['error']}), 400
            
            # Use stored database manager to persist transaction
            if result.get('transaction_data'):
                inserted_id = self.db_manager.insert("credit_purchases", result['transaction_data'])
                
                if not inserted_id:
                    return jsonify({"success": False, "error": "Failed to save transaction"}), 500
                
                # Update user credits through transactions module hook
                self._update_user_credits(
                    result['transaction_data']['user_id'],
                    result['transaction_data']['credits_purchased']
                )
                
                return jsonify({
                    "success": True,
                    "message": "Payment confirmed and credits added",
                    "transaction_id": str(inserted_id),
                    "credits_purchased": result['credits_purchased']
                }), 200
            
            return jsonify({
                "success": True,
                "message": "Payment confirmed",
                "credits_purchased": result['credits_purchased']
            }), 200
            
        except Exception as e:
            custom_log(f"Error confirming payment: {e}", level="ERROR")
            return jsonify({"success": False, "error": "Internal server error"}), 500

    def handle_webhook(self):
        """Handle Stripe webhook events."""
        try:
            payload = request.data
            signature = request.headers.get('stripe-signature')
            
            if not signature:
                return jsonify({"success": False, "error": "Missing signature"}), 400
            
            # Use module for business logic
            result = self.module.process_webhook_event(payload.decode('utf-8'), signature)
            
            if not result['success']:
                return jsonify({"success": False, "error": result['error']}), 400
            
            # Handle webhook event based on type
            if result.get('event_type') == 'payment_succeeded':
                self._handle_webhook_payment_succeeded(result)
            elif result.get('event_type') == 'payment_failed':
                self._handle_webhook_payment_failed(result)
            elif result.get('event_type') == 'dispute_created':
                self._handle_webhook_dispute_created(result)
            
            return jsonify({"success": True, "message": "Webhook processed"}), 200
            
        except Exception as e:
            custom_log(f"Error handling webhook: {e}", level="ERROR")
            return jsonify({"success": False, "error": "Internal server error"}), 500

    def _handle_webhook_payment_succeeded(self, result: Dict[str, Any]):
        """Handle payment succeeded webhook event."""
        try:
            user_id = result.get('user_id')
            amount_usd = result.get('amount_usd', 0)
            credit_amount = result.get('credits_purchased', 0)
            payment_intent_id = result.get('payment_intent_id')
            
            # Create transaction record
            transaction_data = {
                'user_id': user_id,
                'payment_intent_id': payment_intent_id,
                'amount_usd': amount_usd,
                'credits_purchased': credit_amount,
                'status': 'completed',
                'payment_method': 'stripe',
                'created_at': datetime.utcnow().isoformat(),
                'stripe_payment_intent': payment_intent_id,
                'source': 'webhook'
            }
            
            # Use stored database manager to persist
            inserted_id = self.db_manager.insert("credit_purchases", transaction_data)
            
            if inserted_id:
                # Update user credits
                self._update_user_credits(user_id, credit_amount)
                custom_log(f"✅ Webhook payment succeeded processed for user {user_id}: {credit_amount} credits")
            
        except Exception as e:
            custom_log(f"Error handling webhook payment succeeded: {e}", level="ERROR")

    def _handle_webhook_payment_failed(self, result: Dict[str, Any]):
        """Handle payment failed webhook event."""
        try:
            user_id = result.get('user_id')
            payment_intent_id = result.get('payment_intent_id')
            failure_reason = result.get('failure_reason')
            
            # Log payment failure
            custom_log(f"❌ Webhook payment failed for user {user_id}: {failure_reason}")
            
            # Could add additional failure handling logic here
            
        except Exception as e:
            custom_log(f"Error handling webhook payment failed: {e}", level="ERROR")

    def _handle_webhook_dispute_created(self, result: Dict[str, Any]):
        """Handle dispute created webhook event."""
        try:
            dispute_id = result.get('dispute_id')
            charge_id = result.get('charge_id')
            amount = result.get('amount')
            reason = result.get('reason')
            
            # Log dispute creation
            custom_log(f"⚠️ Webhook dispute created: {dispute_id} for charge {charge_id}, reason: {reason}")
            
            # Could add dispute handling logic here
            
        except Exception as e:
            custom_log(f"Error handling webhook dispute created: {e}", level="ERROR")

    def get_payment_status(self, payment_intent_id):
        """Get payment status."""
        try:
            # Use module for business logic
            result = self.module.process_payment_status_request(payment_intent_id)
            
            if not result['success']:
                return jsonify({"success": False, "error": result['error']}), 400
            
            return jsonify(result), 200
            
        except Exception as e:
            custom_log(f"Error getting payment status: {e}", level="ERROR")
            return jsonify({"success": False, "error": "Internal server error"}), 500

    def get_credit_packages(self):
        """Get available credit packages."""
        try:
            # Use module for business logic
            result = self.module.process_credit_packages_request()
            
            if not result['success']:
                return jsonify({"success": False, "error": result['error']}), 400
            
            return jsonify(result), 200
            
        except Exception as e:
            custom_log(f"Error getting credit packages: {e}", level="ERROR")
            return jsonify({"success": False, "error": "Internal server error"}), 500

    def create_customer(self):
        """Create a Stripe customer."""
        try:
            data = request.get_json()
            if not data:
                return jsonify({"success": False, "error": "No data provided"}), 400
            
            # Use module for business logic
            result = self.module.process_customer_creation(data)
            
            if not result['success']:
                return jsonify({"success": False, "error": result['error']}), 400
            
            return jsonify(result), 201
            
        except Exception as e:
            custom_log(f"Error creating customer: {e}", level="ERROR")
            return jsonify({"success": False, "error": "Internal server error"}), 500

    def get_customer(self, customer_id):
        """Get customer details."""
        try:
            # Use module for business logic
            result = self.module.process_customer_retrieval(customer_id)
            
            if not result['success']:
                return jsonify({"success": False, "error": result['error']}), 400
            
            return jsonify(result), 200
            
        except Exception as e:
            custom_log(f"Error getting customer: {e}", level="ERROR")
            return jsonify({"success": False, "error": "Internal server error"}), 500

    def list_payment_methods(self):
        """List customer payment methods."""
        try:
            customer_id = request.args.get('customer_id')
            if not customer_id:
                return jsonify({"success": False, "error": "Customer ID is required"}), 400
            
            # Use module for business logic
            result = self.module.process_payment_methods_list(customer_id)
            
            if not result['success']:
                return jsonify({"success": False, "error": result['error']}), 400
            
            return jsonify(result), 200
            
        except Exception as e:
            custom_log(f"Error listing payment methods: {e}", level="ERROR")
            return jsonify({"success": False, "error": "Internal server error"}), 500

    def get_payment_method(self, payment_method_id):
        """Get payment method details."""
        try:
            # Use module for business logic
            result = self.module.process_payment_method_retrieval(payment_method_id)
            
            if not result['success']:
                return jsonify({"success": False, "error": result['error']}), 400
            
            return jsonify(result), 200
            
        except Exception as e:
            custom_log(f"Error getting payment method: {e}", level="ERROR")
            return jsonify({"success": False, "error": "Internal server error"}), 500

    def _update_user_credits(self, user_id: str, credit_amount: int):
        """Update user credits through transactions module hook."""
        try:
            # Trigger hook for credit update
            hook_data = {
                'user_id': user_id,
                'credit_amount': credit_amount,
                'source': 'stripe_payment',
                'timestamp': datetime.utcnow().isoformat()
            }
            
            self.hooks_manager.trigger_hook('user_credits_updated', hook_data)
            custom_log(f"✅ Triggered user credits update hook for user {user_id}: {credit_amount} credits")
            
        except Exception as e:
            custom_log(f"Error updating user credits: {e}", level="ERROR")

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
                'message': 'Request forwarded to Stripe module',
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
                "orchestrator": "stripe_orchestrator",
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
                "orchestrator": "stripe_orchestrator",
                "status": "error",
                "error": str(e)
            }

    def get_config(self) -> Dict[str, Any]:
        """Get orchestrator configuration."""
        try:
            module_config = self.module.get_config() if self.module else {}
            
            return {
                "orchestrator": "stripe_orchestrator",
                "module_config": module_config,
                "managers": {
                    "db_manager": "available" if self.db_manager else "not_available",
                    "jwt_manager": "available" if self.jwt_manager else "not_available",
                    "hooks_manager": "available" if self.hooks_manager else "not_available"
                }
            }
            
        except Exception as e:
            custom_log(f"Error getting config: {e}", level="ERROR")
            return {
                "orchestrator": "stripe_orchestrator",
                "status": "error",
                "error": str(e)
            }

    def dispose(self):
        """Cleanup orchestrator resources."""
        try:
            if self.module:
                # Module cleanup if needed
                pass
            
            custom_log("StripeOrchestrator disposed successfully")
            
        except Exception as e:
            custom_log(f"Error disposing StripeOrchestrator: {e}", level="ERROR") 