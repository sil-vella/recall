from system.orchestration.modules_orch.base_files.module_orch_base import ModuleOrchestratorBase
from tools.logger.custom_logging import custom_log
from typing import Dict, Any, Optional
from system.modules.credit_system_module.credit_system_main import CreditSystemModule
from flask import request, jsonify
from datetime import datetime


class CreditSystemOrchestrator(ModuleOrchestratorBase):
    """
    Orchestrator for CreditSystemModule.
    Handles system integration, lifecycle management, and request forwarding.
    """
    
    def __init__(self, manager_initializer):
        """
        Initialize the credit system orchestrator.
        
        Args:
            manager_initializer: ManagerInitializer instance for accessing all managers
        """
        super().__init__(manager_initializer)
        self.manager_initializer = manager_initializer
        self.module = None
        self.is_initialized = False
        custom_log("CreditSystemOrchestrator created")

    def initialize(self):
        """Initialize the orchestrator and module."""
        try:
            # Create module instance (no config needed - module accesses secrets directly)
            self.module = CreditSystemModule()
            
            # Initialize the module
            self.module.initialize()
            
            # Register hooks with the system
            self._register_hooks()
            
            # Register route callback with hooks manager
            self._register_route_callback()
            
            self.is_initialized = True
            custom_log("✅ CreditSystemOrchestrator initialized successfully")
            
        except Exception as e:
            custom_log(f"❌ Failed to initialize CreditSystemOrchestrator: {e}", level="ERROR")
            raise

    def _register_route_callback(self):
        """Register route callback with the hooks manager."""
        try:
            hooks_manager = self.manager_initializer.get_manager('hooks_manager')
            if hooks_manager:
                hooks_manager.register_hook_callback(
                    "register_routes",
                    self.register_routes_callback,
                    priority=10,
                    context="credit_system_orchestrator"
                )
                custom_log("✅ CreditSystemOrchestrator registered route callback with hooks manager")
            else:
                custom_log("⚠️ Hooks manager not available for route registration")
                
        except Exception as e:
            custom_log(f"❌ Failed to register route callback: {e}", level="ERROR")

    def register_routes_callback(self, data=None):
        """Register credit system routes when the register_routes hook is triggered."""
        try:
            from flask import current_app
            
            # Get routes needed by the module
            routes_needed = self.module.get_routes_needed()
            
            # Register each route with Flask
            for route_info in routes_needed:
                route = route_info['route']
                methods = route_info['methods']
                handler_name = route_info['handler']
                
                # Get the handler method from this orchestrator
                handler_method = getattr(self, handler_name, None)
                if handler_method:
                    # Register the route with Flask
                    current_app.add_url_rule(
                        route,
                        f"credit_system_{handler_name}",
                        handler_method,
                        methods=methods
                    )
                    custom_log(f"✅ Registered route: {route} -> {handler_name}")
                else:
                    custom_log(f"❌ Handler method {handler_name} not found for route {route}")
            
            custom_log(f"✅ CreditSystemOrchestrator registered {len(routes_needed)} routes via hook")
            
        except Exception as e:
            custom_log(f"❌ Error registering routes via hook: {e}", level="ERROR")

    def _register_hooks(self):
        """Register module hooks with the system."""
        try:
            hooks_manager = self.manager_initializer.get_manager('hooks_manager')
            if hooks_manager:
                # Get hooks needed by the module
                hooks_needed = self.module.get_hooks_needed()
                
                for hook_info in hooks_needed:
                    event = hook_info['event']
                    priority = hook_info.get('priority', 10)
                    context = hook_info.get('context', 'credit_system')
                    
                    # Register the hook
                    hooks_manager.register_hook(
                        event=event,
                        callback=self._handle_hook_event,
                        priority=priority,
                        context=context
                    )
                    custom_log(f"✅ Registered hook: {event} (priority: {priority})")
                    
        except Exception as e:
            custom_log(f"❌ Failed to register hooks: {e}", level="ERROR")

    def _handle_hook_event(self, event_name: str, event_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Handle hook events from the system.
        
        Args:
            event_name: Name of the hook event
            event_data: Data passed with the hook
            
        Returns:
            Dict with processing result
        """
        try:
            if self.module:
                return self.module.process_hook_event(event_name, event_data)
            else:
                return {
                    'success': False,
                    'error': 'Module not initialized'
                }
        except Exception as e:
            custom_log(f"❌ Error handling hook event {event_name}: {e}", level="ERROR")
            return {
                'success': False,
                'error': f'Hook processing error: {str(e)}'
            }

    # Flask Route Handlers
    def health_check(self):
        """Get credit system health status."""
        try:
            if not self.is_initialized:
                return jsonify({
                    "success": False,
                    "error": "Orchestrator not initialized"
                }), 503
            
            health_data = self.module.health_check()
            return jsonify(health_data), 200
            
        except Exception as e:
            custom_log(f"❌ Error in health check: {e}", level="ERROR")
            return jsonify({
                "success": False,
                "error": "Internal server error"
            }), 500

    def get_config(self):
        """Get credit system configuration."""
        try:
            if not self.is_initialized:
                return jsonify({
                    "success": False,
                    "error": "Orchestrator not initialized"
                }), 503
            
            config_data = self.module.get_config()
            return jsonify(config_data), 200
            
        except Exception as e:
            custom_log(f"❌ Error getting config: {e}", level="ERROR")
            return jsonify({
                "success": False,
                "error": "Internal server error"
            }), 500

    def forward_request(self):
        """Forward request to credit system."""
        try:
            if not self.is_initialized:
                return jsonify({
                    "success": False,
                    "error": "Orchestrator not initialized"
                }), 503
            
            data = request.get_json()
            if not data:
                return jsonify({
                    "success": False,
                    "error": "Request data is required"
                }), 400
            
            result = self.module.forward_request(data)
            
            if result['success']:
                return jsonify(result['data']), result.get('status_code', 200)
            else:
                return jsonify({
                    "success": False,
                    "error": result['error']
                }), 500
            
        except Exception as e:
            custom_log(f"❌ Error forwarding request: {e}", level="ERROR")
            return jsonify({
                "success": False,
                "error": "Internal server error"
            }), 500

    def process_user_creation(self):
        """Process user creation in credit system."""
        try:
            if not self.is_initialized:
                return jsonify({
                    "success": False,
                    "error": "Orchestrator not initialized"
                }), 503
            
            data = request.get_json()
            if not data:
                return jsonify({
                    "success": False,
                    "error": "User data is required"
                }), 400
            
            result = self.module.process_user_creation(data)
            
            if result['success']:
                return jsonify(result), 200
            else:
                return jsonify({
                    "success": False,
                    "error": result['error']
                }), 400
            
        except Exception as e:
            custom_log(f"❌ Error processing user creation: {e}", level="ERROR")
            return jsonify({
                "success": False,
                "error": "Internal server error"
            }), 500

    def dispose(self):
        """Cleanup orchestrator resources."""
        try:
            if self.module:
                # Module doesn't have dispose method, but we can clean up references
                self.module = None
            
            self.is_initialized = False
            custom_log("CreditSystemOrchestrator disposed")
            
        except Exception as e:
            custom_log(f"❌ Error disposing orchestrator: {e}", level="ERROR") 