"""
Module Registry - Central discovery and configuration for all application modules.
This replaces the plugin registry system with a more direct module approach.
"""

from typing import Dict, List, Type, Any
from tools.logger.custom_logging import custom_log
import os
import importlib
import inspect

LOGGING_SWITCH = True

class ModuleRegistry:
    """
    Central registry for all available modules in the application.
    Handles module discovery, dependency resolution, and configuration.
    """
    
    @staticmethod
    def get_modules() -> Dict[str, Type]:
        """
        Auto-discover modules by scanning the modules directory.
        Looks for directories with __init__.py files and imports the main module class.
        
        :return: Dictionary mapping module keys to module classes
        """
        # Clear import cache to prevent stale module imports
        importlib.invalidate_caches()
        
        modules = {}
        modules_dir = os.path.join(os.path.dirname(__file__), '..', 'modules')
        
        try:
            # Scan the modules directory
            for item in os.listdir(modules_dir):
                item_path = os.path.join(modules_dir, item)
                custom_log(f"DEBUG: Scanning module: {item_path}", level="INFO", isOn=LOGGING_SWITCH)

                # Allow disabling specific modules purely via registry logic.
                # Credit system is currently not used in the cleco stack, so skip it.
                if item == "credit_system_module":
                    continue
                
                # Check if it's a directory and has __init__.py
                if os.path.isdir(item_path) and os.path.exists(os.path.join(item_path, '__init__.py')):
                    try:
                        # Import the module package
                        module_package = f"core.modules.{item}"
                        module_module = importlib.import_module(module_package)
                        
                        # Look for the main module class in __all__ or inspect the module
                        custom_log(f"DEBUG: Looking for module class in {item}", level="INFO", isOn=LOGGING_SWITCH)
                        
                        if hasattr(module_module, '__all__') and module_module.__all__:
                            # Get the first class from __all__
                            class_name = module_module.__all__[0]
                            custom_log(f"DEBUG: Found __all__ with class: {class_name}", level="INFO", isOn=LOGGING_SWITCH)
                            module_class = getattr(module_module, class_name)
                        else:
                            # Fallback: look for classes that inherit from BaseModule
                            custom_log(f"DEBUG: No __all__ found, searching for BaseModule subclasses", level="INFO", isOn=LOGGING_SWITCH)
                            module_class = None
                            for name, obj in inspect.getmembers(module_module):
                                if inspect.isclass(obj):
                                    custom_log(f"DEBUG: Found class {name}: {obj}", level="INFO", isOn=LOGGING_SWITCH)
                                    custom_log(f"DEBUG: Class bases: {obj.__bases__}", level="INFO", isOn=LOGGING_SWITCH)
                                    
                                    # Check if it inherits from BaseModule
                                    is_base_module = False
                                    for base in obj.__bases__:
                                        base_name = getattr(base, '__name__', str(base))
                                        custom_log(f"DEBUG: Checking base {base_name} for BaseModule", level="INFO", isOn=LOGGING_SWITCH)
                                        if base_name == 'BaseModule' or 'BaseModule' in str(base):
                                            is_base_module = True
                                            custom_log(f"DEBUG: Found BaseModule subclass: {name}", level="INFO", isOn=LOGGING_SWITCH)
                                            break
                                    
                                    if is_base_module:
                                        module_class = obj
                                        break
                        
                        if module_class:
                            # Use directory name as module key (keep full name)
                            module_key = item
                            modules[module_key] = module_class
                            custom_log(f"DEBUG: Successfully discovered module: {module_key} -> {module_class.__name__}", level="INFO", isOn=LOGGING_SWITCH)
                            print(f"DEBUG: Discovered module: {module_key} -> {module_class.__name__}")
                        else:
                            custom_log(f"WARNING: No module class found in {item}", level="WARNING", isOn=LOGGING_SWITCH)
                            print(f"DEBUG: No module class found in {item}")
                    except Exception as e:
                        custom_log(f"ERROR: Failed to import module {item}: {e}", level="ERROR", isOn=LOGGING_SWITCH)
                        import traceback
                        custom_log(f"ERROR: Traceback: {traceback.format_exc()}", level="ERROR", isOn=LOGGING_SWITCH)
                        continue
            return modules
            
        except Exception as e:
            return {}
    
    @staticmethod
    def get_module_dependencies() -> Dict[str, List[str]]:
        """
        Return module dependency graph.
        Defines which modules depend on which other modules.
        
        :return: Dictionary mapping module keys to their dependencies
        """
        dependencies = {
            "user_management_module": [],  # Core user management - no dependencies
            "analytics_module": ["user_management_module"],  # Needs user management for JWT auth
            # Credit system module is currently disabled for cleco.pro stack
            "system_actions_module": [],  # Core system actions - no dependencies
            "wallet_module": ["user_management_module"],  # Needs user management
            "transactions_module": ["user_management_module", "wallet_module"],  # Needs users and wallet
            "cleco_game": ["user_management_module"],  # Needs user management for JWT auth
            # "communications_module": [],  # Communications module - no dependencies (temporarily disabled due to missing debugpy)
            # "stripe_module": ["user_management_module"],  # Needs user management (temporarily disabled due to missing stripe)
        }
        return dependencies
    
    @staticmethod
    def get_module_configuration() -> Dict[str, Dict[str, Any]]:
        """
        Return module-specific configuration settings.
        
        :return: Dictionary mapping module keys to their config
        """
        return {
            "communications_module": {
                "enabled": True,
                "priority": 1,
                "health_check_enabled": True,
            },
            "user_management_module": {
                "enabled": True,
                "priority": 2,
                "health_check_enabled": True,
                "session_timeout": 3600,
            },
            "analytics_module": {
                "enabled": True,
                "priority": 3,
                "health_check_enabled": True,
            },
            "stripe_module": {
                "enabled": True,
                "priority": 4,
                "health_check_enabled": True,
                "verification_timeout": 30,
            },
            "cleco_game": {
                "enabled": True,
                "priority": 5,
                "health_check_enabled": True,
                "websocket_required": True,
            },
            "credit_system_module": {
                # Credit system module is currently disabled for cleco stack
                "enabled": False,
                "priority": 6,
                "health_check_enabled": True,
            },
            "system_actions_module": {
                "enabled": True,
                "priority": 7,
                "health_check_enabled": True,
            },
            "wallet_module": {
                "enabled": True,
                "priority": 8,
                "health_check_enabled": True,
            },
            "transactions_module": {
                "enabled": True,
                "priority": 9,
                "health_check_enabled": True,
            },
        }
    
    @staticmethod
    def validate_module_registry() -> bool:
        """
        Validate that all registered modules and dependencies are consistent.
        
        :return: True if registry is valid, False otherwise
        """
        try:
            custom_log("DEBUG: Starting module registry validation", level="INFO", isOn=LOGGING_SWITCH)
            
            modules = ModuleRegistry.get_modules()
            custom_log(f"DEBUG: Discovered modules: {list(modules.keys())}", level="INFO", isOn=LOGGING_SWITCH)
            
            dependencies = ModuleRegistry.get_module_dependencies()
            custom_log(f"DEBUG: Module dependencies: {dependencies}", level="INFO", isOn=LOGGING_SWITCH)
            
            print(f"DEBUG: Found modules: {list(modules.keys())}")
            print(f"DEBUG: Dependencies: {dependencies}")
            
            # Check if all dependency references exist
            for module_key, deps in dependencies.items():
                custom_log(f"DEBUG: Checking module {module_key} and dependencies {deps}", level="INFO", isOn=LOGGING_SWITCH)
                custom_log(f"DEBUG: Available modules: {list(modules.keys())}", level="INFO", isOn=LOGGING_SWITCH)
                
                if module_key not in modules:
                    custom_log(f"ERROR: Module {module_key} not found in discovered modules", level="ERROR", isOn=LOGGING_SWITCH)
                    custom_log(f"ERROR: Available modules: {list(modules.keys())}", level="ERROR", isOn=LOGGING_SWITCH)
                    return False
                    
                for dep in deps:
                    custom_log(f"DEBUG: Checking dependency {dep} for module {module_key}", level="INFO", isOn=LOGGING_SWITCH)
                    if dep not in modules:
                        custom_log(f"ERROR: Dependency {dep} not found in discovered modules for module {module_key}", level="ERROR", isOn=LOGGING_SWITCH)
                        custom_log(f"ERROR: Available modules: {list(modules.keys())}", level="ERROR", isOn=LOGGING_SWITCH)
                        return False
                    else:
                        custom_log(f"DEBUG: Dependency {dep} found for module {module_key}", level="INFO", isOn=LOGGING_SWITCH)
            
            # Check for circular dependencies (basic check)
            if ModuleRegistry._has_circular_dependency(dependencies):
                print("DEBUG: Circular dependency detected")
                return False
            print("DEBUG: Module registry validation passed")
            return True
            
        except Exception as e:
            print(f"DEBUG: Exception in validate_module_registry: {e}")
            return False
    
    @staticmethod
    def _has_circular_dependency(dependencies: Dict[str, List[str]]) -> bool:
        """
        Check for circular dependencies using DFS.
        
        :param dependencies: Dependency graph
        :return: True if circular dependency exists
        """
        def dfs(node, visited, rec_stack):
            visited.add(node)
            rec_stack.add(node)
            
            for neighbor in dependencies.get(node, []):
                if neighbor not in visited:
                    if dfs(neighbor, visited, rec_stack):
                        return True
                elif neighbor in rec_stack:
                    return True
            
            rec_stack.remove(node)
            return False
        
        visited = set()
        for node in dependencies:
            if node not in visited:
                if dfs(node, visited, set()):
                    return True
        return False
    
    @staticmethod
    def get_module_load_order() -> List[str]:
        """
        Get the correct order to load modules based on dependencies.
        Uses topological sort to resolve dependencies.
        
        :return: List of module keys in dependency order
        """
        dependencies = ModuleRegistry.get_module_dependencies()
        modules = list(ModuleRegistry.get_modules().keys())
        
        # Topological sort implementation
        in_degree = {module: 0 for module in modules}
        
        # Calculate in-degrees
        for module in modules:
            for dep in dependencies.get(module, []):
                if dep in in_degree:
                    in_degree[module] += 1
        
        # Queue for modules with no dependencies
        queue = [module for module, degree in in_degree.items() if degree == 0]
        load_order = []
        
        while queue:
            current = queue.pop(0)
            load_order.append(current)
            
            # Update in-degrees for dependent modules
            for module in modules:
                if current in dependencies.get(module, []):
                    in_degree[module] -= 1
                    if in_degree[module] == 0:
                        queue.append(module)
        
        if len(load_order) != len(modules):
            raise RuntimeError("Circular dependency detected in module dependencies")
        return load_order 