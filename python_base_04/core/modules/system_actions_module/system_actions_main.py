from core.modules.base_module import BaseModule
from tools.logger.custom_logging import custom_log
from typing import Dict, Any
from flask import request, jsonify
from datetime import datetime


class SystemActionsModule(BaseModule):
    def __init__(self, app_manager=None):
        """Initialize the SystemActionsModule."""
        super().__init__(app_manager)
        
        # Set dependencies
        self.dependencies = []
        
        custom_log("SystemActionsModule created")

    def initialize(self, app_manager):
        """Initialize the SystemActionsModule with AppManager."""
        self.app_manager = app_manager
        self.app = app_manager.flask_app
        self.register_routes()
        
        # Register module actions with UserActionsManager
        self._register_module_actions()
        
        self._initialized = True
        custom_log("SystemActionsModule initialized")

    def register_routes(self):
        """Register system actions routes."""
        # No routes needed - actions are handled by the single wildcard route in main app
        # /actions/<action_name>/<args> handles all actions
        custom_log("SystemActionsModule: No routes to register (using single wildcard route)")

    def _register_module_actions(self):
        """Register this module's actions with the UserActionsManager."""
        try:
            # Load actions from YAML declarations
            actions_config = self.load_module_declarations()
            
            # Define handlers for these actions
            handlers = {
                "get_system_info": self._get_system_info,
                "log_system_event": self._log_system_event,
                "validate_system_permissions": self._validate_system_permissions,
                "get_module_status": self._get_module_status
            }
            
            # Register with UserActionsManager
            self.register_module_actions(actions_config, handlers)
            
        except Exception as e:
            custom_log(f"❌ Error registering module actions: {e}", level="ERROR")



    def _get_system_info(self, request_data: Dict[str, Any]) -> Dict[str, Any]:
        """Get detailed system information."""
        try:
            include_details = request_data.get("include_details", False)
            include_metrics = request_data.get("include_metrics", False)
            
            info = {
                "module": "system_actions",
                "status": "healthy",
                "timestamp": str(datetime.utcnow()),
                "version": "1.0.0"
            }
            
            if include_details:
                info["details"] = {
                    "dependencies": self.dependencies,
                    "routes_count": len(self.registered_routes),
                    "initialized": self._initialized
                }
            
            if include_metrics:
                info["metrics"] = {
                    "memory_usage": "placeholder",
                    "cpu_usage": "placeholder",
                    "uptime": "placeholder"
                }
            
            return info
            
        except Exception as e:
            custom_log(f"❌ Error getting system info: {e}", level="ERROR")
            return {"error": f"Failed to get system info: {str(e)}"}

    def _log_system_event(self, request_data: Dict[str, Any]) -> Dict[str, Any]:
        """Log a system event."""
        try:
            # Map URL args to parameters
            event_type = request_data.get("event_type") or request_data.get("arg1")
            message = request_data.get("message") or request_data.get("arg2")
            severity = request_data.get("severity", "info")
            metadata = request_data.get("metadata", {})
            
            if not event_type or not message:
                return {"error": "event_type and message are required"}
            
            # Log the event
            log_entry = {
                "event_type": event_type,
                "message": message,
                "severity": severity,
                "metadata": metadata,
                "timestamp": str(datetime.utcnow()),
                "module": "system_actions"
            }
            
            custom_log(f"📝 System event logged: {event_type} - {message}")
            
            return {
                "success": True,
                "event_logged": log_entry
            }
            
        except Exception as e:
            custom_log(f"❌ Error logging system event: {e}", level="ERROR")
            return {"error": f"Failed to log system event: {str(e)}"}

    def _validate_system_permissions(self, request_data: Dict[str, Any]) -> Dict[str, Any]:
        """Validate system-level permissions."""
        try:
            # Map URL args to parameters
            permission = request_data.get("permission") or request_data.get("arg1")
            resource = request_data.get("resource") or request_data.get("arg2")
            user_id = request_data.get("user_id")
            
            if not permission or not resource:
                return {"error": "permission and resource are required"}
            
            # This is a simple permission validation framework
            # In a real system, this would check against user roles and permissions
            valid_permissions = ["admin", "read", "write", "delete"]
            valid_resources = ["system_config", "user_data", "logs", "metrics"]
            
            is_valid = (
                permission in valid_permissions and 
                resource in valid_resources
            )
            
            return {
                "valid": is_valid,
                "permission": permission,
                "resource": resource,
                "user_id": user_id,
                "message": "System permission validation completed"
            }
            
        except Exception as e:
            custom_log(f"❌ Error validating system permissions: {e}", level="ERROR")
            return {"error": f"Failed to validate permissions: {str(e)}"}

    def _get_module_status(self, request_data: Dict[str, Any]) -> Dict[str, Any]:
        """Get status of a specific module."""
        try:
            # Map URL args to parameters
            module_name = request_data.get("module_name") or request_data.get("arg1")
            include_details = request_data.get("include_details", False)
            
            if not module_name:
                return {"error": "module_name is required"}
            
            # Get module from app_manager
            if self.app_manager:
                module_instance = self.app_manager.get_module(module_name)
                if module_instance:
                    status = {
                        "module": module_name,
                        "status": "healthy" if module_instance.is_initialized() else "not_initialized",
                        "initialized": module_instance.is_initialized()
                    }
                    
                    if include_details:
                        status["details"] = {
                            "dependencies": module_instance.dependencies,
                            "routes_count": len(module_instance.registered_routes),
                            "health": module_instance.health_check()
                        }
                    
                    return status
                else:
                    return {
                        "module": module_name,
                        "status": "not_found",
                        "error": f"Module '{module_name}' not found"
                    }
            else:
                return {"error": "AppManager not available"}
                
        except Exception as e:
            custom_log(f"❌ Error getting module status: {e}", level="ERROR")
            return {"error": f"Failed to get module status: {str(e)}"}

    def health_check(self) -> Dict[str, Any]:
        """Perform health check for SystemActionsModule."""
        health_status = super().health_check()
        health_status['dependencies'] = self.dependencies
        
        # Add UserActionsManager status
        try:
            if self.app_manager and self.app_manager.user_actions_manager:
                actions_count = len(self.app_manager.user_actions_manager.module_actions.get("system_actions", []))
                health_status['details'] = {
                    'registered_actions': actions_count,
                    'user_actions_manager_available': True
                }
            else:
                health_status['details'] = {
                    'user_actions_manager_available': False
                }
        except Exception as e:
            health_status['details'] = {
                'error': f'Failed to check UserActionsManager: {str(e)}'
            }
        
        return health_status 