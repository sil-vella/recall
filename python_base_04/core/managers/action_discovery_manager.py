import os
import yaml
import importlib
from typing import Dict, Any, List, Optional, Callable
from datetime import datetime


class ActionDiscoveryManager:
    """
    Manager for discovering and executing actions from YAML declarations.
    Implements single wildcard route with YAML-based action discovery.
    """
    
    def __init__(self, app_manager=None):
        """Initialize the ActionDiscoveryManager."""
        self.app_manager = app_manager
        self.actions_registry = {}  # {action_name: action_config}
        self.yaml_files = []        # Track all YAML files
        self.modules_dir = os.path.join(os.path.dirname(__file__), "..", "modules")
        self.last_scan = None
        
        def discover_all_actions(self):
        """Scan all modules for YAML declarations and cache them."""
        try:
            if not os.path.exists(self.modules_dir):
                return
            
            # Clear existing registry
            self.actions_registry = {}
            
            # Scan all module directories
            for module_dir in os.listdir(self.modules_dir):
                module_path = os.path.join(self.modules_dir, module_dir)
                
                if os.path.isdir(module_path):
                    yaml_path = os.path.join(module_path, "declarations", "actions.yaml")
                    
                    if os.path.exists(yaml_path):
                        actions = self._load_yaml_actions(yaml_path, module_dir)
                        self.actions_registry.update(actions)
                        self.yaml_files.append(yaml_path)
                        } actions")
            
            self.last_scan = datetime.utcnow()
            } total actions")
            
        except Exception as e:
            def _load_yaml_actions(self, yaml_path: str, module_name: str) -> Dict[str, Any]:
        """Load actions from YAML file and prefix with module name."""
        try:
            with open(yaml_path, 'r') as f:
                config = yaml.safe_load(f)
            
            actions = {}
            for action_name, action_config in config.get('actions', {}).items():
                full_action_name = f"{module_name}.{action_name}"
                actions[full_action_name] = {
                    'module': module_name,
                    'action_name': action_name,
                    'config': action_config,
                    'yaml_file': yaml_path
                }
            
            return actions
            
        except Exception as e:
            return {}

    def find_action(self, action_name: str) -> Optional[Dict[str, Any]]:
        """Search for action across all YAML files."""
        try:
            # Direct match
            if action_name in self.actions_registry:
                return self.actions_registry[action_name]
            
            # Search by action name (without module prefix)
            for full_name, action_info in self.actions_registry.items():
                if action_info['action_name'] == action_name:
                    return action_info
            
            # Fuzzy search
            for full_name, action_info in self.actions_registry.items():
                if action_name.lower() in full_name.lower():
                    return action_info
            
            return None
            
        except Exception as e:
            return None

    def parse_url_args(self, args_string: str) -> Dict[str, Any]:
        """Parse arguments from URL path."""
        try:
            if not args_string:
                return {}
            
            args_parts = args_string.split('/')
            parsed_args = {}
            
            # Basic positional argument mapping
            # This can be enhanced with YAML-defined URL patterns
            if len(args_parts) >= 1:
                parsed_args['arg1'] = args_parts[0]
            if len(args_parts) >= 2:
                parsed_args['arg2'] = args_parts[1]
            if len(args_parts) >= 3:
                parsed_args['arg3'] = args_parts[2]
            if len(args_parts) >= 4:
                parsed_args['arg4'] = args_parts[3]
            
            return parsed_args
            
        except Exception as e:
            return {}

    def validate_action_args(self, action_info: Dict[str, Any], parsed_args: Dict[str, Any]) -> Dict[str, Any]:
        """Validate arguments against YAML declaration."""
        try:
            config = action_info['config']
            required_params = config.get('required_params', [])
            optional_params = config.get('optional_params', [])
            
            errors = []
            missing_params = []
            
            # Check required parameters
            for param in required_params:
                if param not in parsed_args:
                    missing_params.append(param)
            
            if missing_params:
                errors.append(f"Missing required parameters: {missing_params}")
            
            # Check parameter types (if specified in YAML)
            type_validations = config.get('parameter_types', {})
            for param, expected_type in type_validations.items():
                if param in parsed_args:
                    if not self._validate_parameter_type(parsed_args[param], expected_type):
                        errors.append(f"Parameter '{param}' has invalid type")
            
            return {
                'valid': len(errors) == 0,
                'errors': errors,
                'required_params': required_params,
                'optional_params': optional_params
            }
            
        except Exception as e:
            return {
                'valid': False,
                'errors': [f"Validation error: {str(e)}"]
            }

    def _validate_parameter_type(self, value: Any, expected_type: str) -> bool:
        """Validate parameter type."""
        try:
            if expected_type == "int":
                int(value)
                return True
            elif expected_type == "float":
                float(value)
                return True
            elif expected_type == "bool":
                return str(value).lower() in ['true', 'false', '1', '0']
            elif expected_type == "string":
                return isinstance(value, str)
            else:
                return True  # Unknown type, assume valid
        except (ValueError, TypeError):
            return False

    def execute_action_logic(self, action_info: Dict[str, Any], parsed_args: Dict[str, Any]) -> Any:
        """Execute the action based on YAML configuration."""
        try:
            module_name = action_info['module']
            function_name = action_info['config']['function']
            action_type = action_info['config']['type']
            
            # Map module name from YAML to actual module name
            # YAML uses 'system_actions_module' but module is registered as 'system_actions'
            actual_module_name = module_name.replace('_module', '')
            
            # Get module instance from app_manager's module_manager
            if self.app_manager and hasattr(self.app_manager, 'module_manager'):
                module_instance = self.app_manager.module_manager.get_module(actual_module_name)
                if module_instance:
                    # Execute function
                    handler_method = getattr(module_instance, f"_{function_name}")
                    return handler_method(parsed_args)
                else:
                    raise ValueError(f"Module {actual_module_name} not found")
            else:
                raise ValueError("AppManager or ModuleManager not available")
                
        except Exception as e:
            raise

    def list_all_actions(self) -> Dict[str, Any]:
        """List all discovered actions."""
        try:
            formatted_actions = {}
            
            for action_name, action_info in self.actions_registry.items():
                config = action_info['config']
                formatted_actions[action_name] = {
                    'module': action_info['module'],
                    'description': config.get('description', ''),
                    'type': config.get('type', ''),
                    'url_pattern': config.get('url_pattern', ''),
                    'required_params': config.get('required_params', []),
                    'optional_params': config.get('optional_params', []),
                    'examples': config.get('examples', [])
                }
            
            return {
                'success': True,
                'actions': formatted_actions,
                'total_actions': len(formatted_actions),
                'modules': list(set(info['module'] for info in self.actions_registry.values())),
                'last_scan': str(self.last_scan) if self.last_scan else None
            }
            
        except Exception as e:
            return {
                'success': False,
                'error': f'Failed to list actions: {str(e)}'
            }

    def health_check(self) -> Dict[str, Any]:
        """Perform health check for ActionDiscoveryManager."""
        try:
            return {
                'status': 'healthy',
                'total_actions': len(self.actions_registry),
                'yaml_files': len(self.yaml_files),
                'last_scan': str(self.last_scan) if self.last_scan else None,
                'modules_dir': self.modules_dir,
                'details': {
                    'actions_registry_size': len(self.actions_registry),
                    'yaml_files_found': self.yaml_files
                }
            }
            
        except Exception as e:
            return {
                'status': 'unhealthy',
                'error': f'Health check failed: {str(e)}'
            }

    def refresh_cache(self):
        """Refresh the action cache by re-scanning YAML files."""
        try:
            self.discover_all_actions()
            except Exception as e:
            