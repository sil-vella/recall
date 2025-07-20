"""
Module Registry - Central discovery and configuration for all application modules.
This replaces the plugin registry system with a more direct module approach.
"""

from typing import Dict, List, Type, Any
from tools.logger.custom_logging import custom_log
import os
import importlib
import inspect


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
                
                # Check if it's a directory and has __init__.py
                if os.path.isdir(item_path) and os.path.exists(os.path.join(item_path, '__init__.py')):
                    try:
                        # Import the module package
                        module_package = f"core.modules.{item}"
                        module_module = importlib.import_module(module_package)
                        
                        # Look for the main module class in __all__ or inspect the module
                        if hasattr(module_module, '__all__') and module_module.__all__:
                            # Get the first class from __all__
                            class_name = module_module.__all__[0]
                            module_class = getattr(module_module, class_name)
                        else:
                            # Fallback: look for classes that inherit from BaseModule
                            module_class = None
                            for name, obj in inspect.getmembers(module_module):
                                if (inspect.isclass(obj) and 
                                    hasattr(obj, '__bases__') and 
                                    any('BaseModule' in str(base) for base in obj.__bases__)):
                                    module_class = obj
                                    break
                        
                        if module_class:
                            # Use directory name as module key (remove '_module' suffix if present)
                            module_key = item.replace('_module', '')
                            modules[module_key] = module_class
                            custom_log(f"✅ Discovered module: {module_key} -> {module_class.__name__}")
                        else:
                            custom_log(f"⚠️ No module class found in {item}")
                            
                    except Exception as e:
                        custom_log(f"❌ Error importing module {item}: {e}")
                        continue
            
            custom_log(f"Auto-discovered {len(modules)} modules: {list(modules.keys())}")
            return modules
            
        except Exception as e:
            custom_log(f"❌ Error scanning modules directory: {e}")
            return {}
    
    @staticmethod
    def get_module_dependencies() -> Dict[str, List[str]]:
        """
        Return module dependency graph.
        Defines which modules depend on which other modules.
        
        :return: Dictionary mapping module keys to their dependencies
        """
        dependencies = {
            "communications": [],  # Core API - no dependencies
            "user_management": ["communications"],  # Needs API infrastructure
            "wallet": ["communications", "user_management"],  # Needs API and users
            "transactions": ["communications", "user_management", "wallet"],  # Needs API, users, and wallet
            "in_app_purchases": ["user_management"],  # Needs user management for purchase verification
        }
        
        custom_log(f"Module dependencies defined: {dependencies}")
        return dependencies
    
    @staticmethod
    def get_module_configuration() -> Dict[str, Dict[str, Any]]:
        """
        Return module-specific configuration settings.
        
        :return: Dictionary mapping module keys to their config
        """
        return {
            "communications": {
                "enabled": True,
                "priority": 1,
                "health_check_enabled": True,
            },
            "user_management": {
                "enabled": True,
                "priority": 2,
                "health_check_enabled": True,
                "session_timeout": 3600,
            },
            "in_app_purchases": {
                "enabled": True,
                "priority": 3,
                "health_check_enabled": True,
                "verification_timeout": 30,
            },
        }
    
    @staticmethod
    def validate_module_registry() -> bool:
        """
        Validate that all registered modules and dependencies are consistent.
        
        :return: True if registry is valid, False otherwise
        """
        try:
            modules = ModuleRegistry.get_modules()
            dependencies = ModuleRegistry.get_module_dependencies()
            
            # Check if all dependency references exist
            for module_key, deps in dependencies.items():
                if module_key not in modules:
                    custom_log(f"❌ Module {module_key} in dependencies but not in modules registry")
                    return False
                    
                for dep in deps:
                    if dep not in modules:
                        custom_log(f"❌ Dependency {dep} for module {module_key} not found in modules registry")
                        return False
            
            # Check for circular dependencies (basic check)
            if ModuleRegistry._has_circular_dependency(dependencies):
                custom_log("❌ Circular dependency detected in module registry")
                return False
            
            custom_log("✅ Module registry validation passed")
            return True
            
        except Exception as e:
            custom_log(f"❌ Module registry validation failed: {e}")
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
        
        custom_log(f"Module load order resolved: {load_order}")
        return load_order 