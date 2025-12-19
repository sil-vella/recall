from core.modules.base_module import BaseModule
from tools.logger.custom_logging import custom_log
from typing import Dict, Any
from flask import request, jsonify
from datetime import datetime
from utils.config.config import Config
import os
import json

# Logging switch for this module
LOGGING_SWITCH = False


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
        """Check for available mobile app updates (public endpoint).

        Uses a dynamic mobile_release.json manifest when available so that
        mobile app versions are decoupled from the Flask backend version.
        """
        try:
            custom_log("SystemActions: Check updates request received", level="INFO", isOn=LOGGING_SWITCH)
            
            app_name = Config.APP_NAME
            app_id = Config.APP_ID
            download_base_url = Config.APP_DOWNLOAD_BASE_URL
            
            # Try to load mobile release manifest from secrets (no restart required to update)
            manifest = None
            manifest_path_used = None
            manifest_paths = [
                os.getenv("MOBILE_RELEASE_MANIFEST", "/app/secrets/mobile_release.json"),
                "./secrets/mobile_release.json",
            ]

            for path in manifest_paths:
                try:
                    if os.path.exists(path):
                        with open(path, "r", encoding="utf-8") as f:
                            manifest = json.load(f)
                            manifest_path_used = path
                            custom_log(f"SystemActions: Loaded mobile_release manifest from {path}", level="INFO", isOn=LOGGING_SWITCH)
                            break
                except Exception as e:
                    custom_log(f"SystemActions: Failed to read mobile_release manifest at {path}: {e}", level="ERROR", isOn=LOGGING_SWITCH)

            # Determine mobile app versions from manifest (fallback to backend Config if missing)
            if manifest:
                server_version = str(manifest.get("latest_version", Config.APP_VERSION))
                min_supported_version = str(manifest.get("min_supported_version", server_version))
            else:
                # Fallback: use backend config version when no manifest exists
                server_version = str(Config.APP_VERSION)
                min_supported_version = server_version

            # Get client's current version from query parameter (optional)
            client_version = request.args.get("current_version", server_version)
            
            # Compare versions using simple semantic version tuples
            update_available = False
            update_required = False
            
            def _parse_version(v: str):
                parts = []
                for token in str(v).split("."):
                    try:
                        parts.append(int(token))
                    except ValueError:
                        break
                return tuple(parts) if parts else (0,)

            try:
                client_tuple = _parse_version(client_version)
                server_tuple = _parse_version(server_version)
                min_supported_tuple = _parse_version(min_supported_version)
                    
                update_available = client_tuple < server_tuple
                update_required = client_tuple < min_supported_tuple

                version_msg = (
                    "SystemActions: Version comparison - "
                    f"Client: {client_version} ({client_tuple}), "
                    f"Latest: {server_version} ({server_tuple}), "
                    f"MinSupported: {min_supported_version} ({min_supported_tuple}), "
                    f"UpdateAvailable: {update_available}, UpdateRequired: {update_required}"
                )
                custom_log(version_msg, level="INFO", isOn=LOGGING_SWITCH)
            except Exception as e:
                custom_log(f"SystemActions: Error comparing versions: {e}", level="WARNING", isOn=LOGGING_SWITCH)
                # Safe fallback: only indicate that an update is available if versions differ
                update_available = client_version != server_version
                update_required = False
            
            # Generate download link (version-specific)
            download_link = ""
            if update_available:
                # Format: {base_url}/v{version}/app.apk
                download_link = f"{download_base_url}/v{server_version}/app.apk"
                custom_log(f"SystemActions: Generated download link: {download_link}", level="INFO", isOn=LOGGING_SWITCH)
            
            # Build response payload
            response_data = {
                "success": True,
                "app_id": app_id,
                "app_name": app_name,
                "current_version": client_version,
                "server_version": server_version,
                "update_available": update_available,
                "update_required": update_required,
                "download_link": download_link if update_available else "",
                "timestamp": datetime.utcnow().isoformat(),
            }
            
            # Include extra metadata when manifest is used
            if manifest is not None:
                response_data["min_supported_version"] = min_supported_version
                if manifest_path_used:
                    response_data["manifest_path"] = manifest_path_used

            summary_msg = (
                "SystemActions: Returning version info - "
                f"Client: {client_version}, Latest: {server_version}, "
                f"UpdateAvailable: {update_available}, UpdateRequired: {update_required}"
            )
            custom_log(summary_msg, level="INFO", isOn=LOGGING_SWITCH)
            return jsonify(response_data), 200
            
        except Exception as e:
            custom_log(f"SystemActions: Error in check_updates: {e}", level="ERROR", isOn=LOGGING_SWITCH)
            return jsonify(
                {
                "success": False,
                "error": "Failed to check for updates",
                    "message": str(e),
                }
            ), 500