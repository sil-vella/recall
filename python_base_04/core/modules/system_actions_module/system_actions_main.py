from core.modules.base_module import BaseModule
from tools.logger.custom_logging import custom_log
from typing import Dict, Any
from flask import request, jsonify
from datetime import datetime
from utils.config.config import Config

# Logging switch for this module
LOGGING_SWITCH = True


class SystemActionsModule(BaseModule):
    def __init__(self, app_manager=None):
        """Initialize the SystemActionsModule."""
        super().__init__(app_manager)
        
        # Set dependencies
        self.dependencies = []

    def initialize(self, app_manager):
        """Initialize the SystemActionsModule with AppManager."""
        self.app_manager = app_manager
        self.app = app_manager.flask_app
        self.register_routes()
        
        # Register module actions with UserActionsManager
        self._register_module_actions()
        
        self._initialized = True

    def register_routes(self):
        """Register system actions routes."""
        try:
            # Register the check-updates endpoint as public (no authentication)
            self._register_route_helper("/public/check-updates", self.check_updates, methods=["GET"])
            custom_log("SystemActions: Registered check-updates endpoint", level="INFO", isOn=LOGGING_SWITCH)
        except Exception as e:
            custom_log(f"SystemActions: Error registering routes: {e}", level="ERROR", isOn=LOGGING_SWITCH)

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
            pass



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
            
            return {
                "success": True,
                "event_logged": log_entry
            }
            
        except Exception as e:
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

    def check_updates(self):
        """Check for available updates (public endpoint)"""
        try:
            custom_log("SystemActions: Check updates request received", level="INFO", isOn=LOGGING_SWITCH)
            
            # Get server app version from config
            server_version = Config.APP_VERSION
            app_name = Config.APP_NAME
            app_id = Config.APP_ID
            download_base_url = Config.APP_DOWNLOAD_BASE_URL
            
            # Get client's current version from query parameter (optional)
            client_version = request.args.get('current_version', server_version)
            
            # Compare versions
            update_available = False
            update_required = False
            
            if client_version != server_version:
                # Parse versions to compare major versions
                try:
                    client_major = int(client_version.split('.')[0]) if '.' in client_version else int(client_version)
                    server_major = int(server_version.split('.')[0]) if '.' in server_version else int(server_version)
                    
                    update_available = True
                    # Update is required if major version has changed
                    update_required = server_major > client_major
                    
                    custom_log(f"SystemActions: Version comparison - Client: {client_version} (major: {client_major}), Server: {server_version} (major: {server_major}), Required: {update_required}", level="INFO", isOn=LOGGING_SWITCH)
                except (ValueError, IndexError) as e:
                    custom_log(f"SystemActions: Error parsing versions: {e}", level="WARNING", isOn=LOGGING_SWITCH)
                    # If version parsing fails, assume update available but not required
                    update_available = True
                    update_required = False
            
            # Generate download link (version-specific)
            download_link = ""
            if update_available:
                # Construct version-specific download URL
                # Format: {base_url}/v{version}/app.apk (or app.ipa for iOS)
                download_link = f"{download_base_url}/v{server_version}/app.apk"
                custom_log(f"SystemActions: Generated download link: {download_link}", level="INFO", isOn=LOGGING_SWITCH)
            
            # Return version information
            response_data = {
                "success": True,
                "app_id": app_id,
                "app_name": app_name,
                "current_version": client_version,
                "server_version": server_version,
                "update_available": update_available,
                "update_required": update_required,
                "download_link": download_link if update_available else "",
                "timestamp": datetime.utcnow().isoformat()
            }
            
            custom_log(f"SystemActions: Returning version info - Client: {client_version}, Server: {server_version}, Required: {update_required}", level="INFO", isOn=LOGGING_SWITCH)
            return jsonify(response_data), 200
            
        except Exception as e:
            custom_log(f"SystemActions: Error in check_updates: {e}", level="ERROR", isOn=LOGGING_SWITCH)
            return jsonify({
                "success": False,
                "error": "Failed to check for updates",
                "message": str(e)
            }), 500 