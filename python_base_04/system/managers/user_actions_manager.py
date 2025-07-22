import os
import yaml
import json
from typing import Dict, Any, List, Optional, Callable
from flask import request, jsonify
from tools.logger.custom_logging import custom_log

from datetime import datetime


class UserActionsManager:
    """
    Manager for handling user actions across all modules.
    Allows modules to register their own actions and declarations.
    """
    
    def __init__(self):
        """Initialize the UserActionsManager."""
        self.registered_actions = {}  # {action_name: action_config}
        self.module_actions = {}      # {module_name: [action_names]}
        self.action_handlers = {}     # {action_name: handler_function}
        self.declarations_dir = os.path.join(os.path.dirname(__file__), "..", "modules")
        
        custom_log("UserActionsManager initialized")

    def register_module_actions(self, module_name: str, actions_config: Dict[str, Any], 
                              handlers: Dict[str, Callable] = None):
        """
        Register actions for a specific module.
        
        :param module_name: Name of the module registering actions
        :param actions_config: Dictionary of action configurations
        :param handlers: Dictionary of handler functions for the actions
        """
        try:
            if module_name not in self.module_actions:
                self.module_actions[module_name] = []
            
            # Register each action
            for action_name, action_config in actions_config.items():
                full_action_name = f"{module_name}.{action_name}"
                
                # Store action configuration
                self.registered_actions[full_action_name] = {
                    'module': module_name,
                    'action_name': action_name,
                    'config': action_config
                }
                
                # Store handler if provided
                if handlers and action_name in handlers:
                    self.action_handlers[full_action_name] = handlers[action_name]
                
                # Track action for this module
                self.module_actions[module_name].append(full_action_name)
                
                custom_log(f"✅ Registered action '{full_action_name}' for module '{module_name}'")
            
            custom_log(f"✅ Module '{module_name}' registered {len(actions_config)} actions")
            
        except Exception as e:
            custom_log(f"❌ Error registering actions for module '{module_name}': {e}", level="ERROR")

    def load_module_declarations(self, module_name: str) -> Dict[str, Any]:
        """
        Load action declarations from a module's declarations directory.
        
        :param module_name: Name of the module
        :return: Dictionary of action configurations
        """
        try:
            # Look for declarations in module directory
            module_dir = os.path.join(self.declarations_dir, module_name)
            declarations_file = os.path.join(module_dir, "declarations", "actions.yaml")
            
            if os.path.exists(declarations_file):
                with open(declarations_file, 'r') as f:
                    config = yaml.safe_load(f)
                
                actions = config.get('actions', {})
                custom_log(f"✅ Loaded {len(actions)} action declarations from {declarations_file}")
                return actions
            else:
                custom_log(f"⚠️ No declarations file found for module '{module_name}': {declarations_file}")
                return {}
                
        except Exception as e:
            custom_log(f"❌ Error loading declarations for module '{module_name}': {e}", level="ERROR")
            return {}

    def execute_action(self, action_name: str, request_data: Dict[str, Any] = None) -> Dict[str, Any]:
        """
        Execute a registered action.
        
        :param action_name: Full action name (module.action_name)
        :param request_data: Data for the action
        :return: Action result
        """
        try:
            if action_name not in self.registered_actions:
                return {
                    'success': False,
                    'error': f'Action "{action_name}" not found',
                    'available_actions': list(self.registered_actions.keys())
                }
            
            action_info = self.registered_actions[action_name]
            action_config = action_info['config']
            
            # Validate required parameters
            required_params = action_config.get('required_params', [])
            missing_params = [param for param in required_params if param not in (request_data or {})]
            
            if missing_params:
                return {
                    'success': False,
                    'error': f'Missing required parameters: {missing_params}',
                    'required_params': required_params,
                    'optional_params': action_config.get('optional_params', [])
                }
            
            # Execute action based on type
            action_type = action_config.get('type', 'function')
            result = self._execute_action_by_type(action_type, action_config, request_data or {}, action_name)
            
            return {
                'success': True,
                'action': action_name,
                'module': action_info['module'],
                'result': result
            }
            
        except Exception as e:
            custom_log(f"❌ Error executing action '{action_name}': {e}", level="ERROR")
            return {
                'success': False,
                'error': f'Failed to execute action: {str(e)}'
            }

    def _execute_action_by_type(self, action_type: str, action_config: Dict, 
                               request_data: Dict, action_name: str) -> Any:
        """Execute action based on its type."""
        if action_type == "function":
            return self._execute_function_action(action_config, request_data, action_name)
        elif action_type == "database":
            return self._execute_database_action(action_config, request_data)
        elif action_type == "external_api":
            return self._execute_external_api_action(action_config, request_data)
        else:
            raise ValueError(f"Unknown action type: {action_type}")

    def _execute_function_action(self, action_config: Dict, request_data: Dict, action_name: str) -> Any:
        """Execute a function-based action."""
        function_name = action_config.get("function")
        
        # Check if we have a custom handler for this action
        if action_name in self.action_handlers:
            handler = self.action_handlers[action_name]
            return handler(request_data)
        
        # Fallback to built-in functions
        if function_name == "validate_user_permissions":
            return self._validate_user_permissions(request_data)
        elif function_name == "get_system_status":
            return self._get_system_status(request_data)
        else:
            raise ValueError(f"Unknown function: {function_name}")

    def _execute_database_action(self, action_config: Dict, request_data: Dict) -> Any:
        """Execute a database action."""
        operation = action_config.get("operation")
        collection = action_config.get("collection")
        query = request_data.get("query", {})
        
        if operation == "find":
            # Note: User-specific database operations should be forwarded to credit system
            if collection == "users":
                raise ValueError("User operations should be handled by credit system")
            
            # For non-user collections, this would need database manager access
            # For now, return a placeholder
            return {
                'operation': operation,
                'collection': collection,
                'query': query,
                'message': 'Database operation framework available'
            }
        else:
            raise ValueError(f"Unknown database operation: {operation}")

    def _execute_external_api_action(self, action_config: Dict, request_data: Dict) -> Any:
        """Execute an external API action."""
        import requests
        
        url = action_config.get("url")
        method = action_config.get("method", "GET")
        
        if not url:
            raise ValueError("External API URL not configured")
        
        # Make request to external API
        response = requests.request(
            method=method,
            url=url,
            json=request_data,
            timeout=30
        )
        
        return {
            'status_code': response.status_code,
            'response': response.json() if response.content else {}
        }

    def _validate_user_permissions(self, request_data: Dict) -> Dict:
        """Validate user permissions (generic utility function)."""
        try:
            user_id = request_data.get("user_id")
            permission = request_data.get("permission")
            resource_id = request_data.get("resource_id")
            
            if not user_id or not permission:
                return {
                    "valid": False,
                    "error": "User ID and permission are required"
                }
            
            # This is a generic permission validation framework
            # Specific user permission logic should be handled by credit system
            return {
                "valid": True,
                "user_id": user_id,
                "permission": permission,
                "resource_id": resource_id,
                "message": "Permission validation framework available"
            }
            
        except Exception as e:
            custom_log(f"Error validating user permissions: {e}")
            return {
                "valid": False,
                "error": f"Permission validation error: {str(e)}"
            }

    def _get_system_status(self, request_data: Dict) -> Dict:
        """Get system status information."""
        include_details = request_data.get("include_details", False)
        
        status = {
            "status": "healthy",
            "timestamp": str(datetime.utcnow()),
            "registered_actions": len(self.registered_actions),
            "registered_modules": len(self.module_actions)
        }
        
        if include_details:
            status["details"] = {
                "modules": list(self.module_actions.keys()),
                "actions": list(self.registered_actions.keys())
            }
        
        return status

    def list_actions(self, module_name: str = None) -> Dict[str, Any]:
        """
        List all registered actions, optionally filtered by module.
        
        :param module_name: Optional module name to filter by
        :return: Dictionary of actions
        """
        try:
            if module_name:
                # Filter actions for specific module
                module_actions = self.module_actions.get(module_name, [])
                actions = {action: self.registered_actions[action] for action in module_actions}
            else:
                # Return all actions
                actions = self.registered_actions
            
            # Format actions for display
            formatted_actions = {}
            for action_name, action_info in actions.items():
                config = action_info['config']
                formatted_actions[action_name] = {
                    'module': action_info['module'],
                    'description': config.get('description', ''),
                    'type': config.get('type', ''),
                    'required_params': config.get('required_params', []),
                    'optional_params': config.get('optional_params', []),
                    'examples': config.get('examples', [])
                }
            
            return {
                'success': True,
                'actions': formatted_actions,
                'total_actions': len(formatted_actions),
                'module_filter': module_name
            }
            
        except Exception as e:
            custom_log(f"❌ Error listing actions: {e}", level="ERROR")
            return {
                'success': False,
                'error': f'Failed to list actions: {str(e)}'
            }

    def unregister_module_actions(self, module_name: str):
        """
        Unregister all actions for a specific module.
        
        :param module_name: Name of the module to unregister
        """
        try:
            if module_name in self.module_actions:
                # Remove all actions for this module
                actions_to_remove = self.module_actions[module_name]
                for action_name in actions_to_remove:
                    self.registered_actions.pop(action_name, None)
                    self.action_handlers.pop(action_name, None)
                
                # Remove module entry
                del self.module_actions[module_name]
                
                custom_log(f"✅ Unregistered {len(actions_to_remove)} actions for module '{module_name}'")
            else:
                custom_log(f"⚠️ No actions found for module '{module_name}'")
                
        except Exception as e:
            custom_log(f"❌ Error unregistering actions for module '{module_name}': {e}", level="ERROR")

    def health_check(self) -> Dict[str, Any]:
        """Perform health check for UserActionsManager."""
        try:
            total_actions = len(self.registered_actions)
            total_modules = len(self.module_actions)
            
            return {
                'status': 'healthy',
                'total_actions': total_actions,
                'total_modules': total_modules,
                'modules': list(self.module_actions.keys()),
                'details': {
                    'action_handlers': len(self.action_handlers),
                    'declarations_dir': self.declarations_dir
                }
            }
            
        except Exception as e:
            return {
                'status': 'unhealthy',
                'error': f'Health check failed: {str(e)}'
            }

    def get_action_info(self, action_name: str) -> Optional[Dict[str, Any]]:
        """
        Get detailed information about a specific action.
        
        :param action_name: Full action name
        :return: Action information or None if not found
        """
        if action_name in self.registered_actions:
            action_info = self.registered_actions[action_name]
            return {
                'action_name': action_name,
                'module': action_info['module'],
                'config': action_info['config'],
                'has_handler': action_name in self.action_handlers
            }
        return None


 