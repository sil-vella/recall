from tools.logger.custom_logging import custom_log, function_log, game_play_log, log_function_call
from typing import Dict, List, Type, Any, Optional
from core.managers.module_registry import ModuleRegistry
from core.modules.base_module import BaseModule

LOGGING_SWITCH = True

class ModuleManager:
    def __init__(self):
        # A dictionary to hold all registered modules
        self.modules = {}
        self.module_load_order = []
        self.initialization_errors = {}

    @log_function_call
    def register_module(self, module_key, module_class, app_manager=None, *args, **kwargs):
        """
        Register and initialize a module.
        :param module_key: str - The unique key for the module.
        :param module_class: type - The class of the module to initialize.
        :param app_manager: AppManager - The central application manager to pass to modules.
        :param args: list - Positional arguments for the module class.
        :param kwargs: dict - Keyword arguments for the module class.
        """
        if module_key in self.modules:
            raise ValueError(f"Module with key '{module_key}' is already registered.")
        
        # Pass the app_manager as a keyword argument if provided
        if app_manager:
            kwargs['app_manager'] = app_manager

        # Instantiate the module
        module_instance = module_class(*args, **kwargs)
        self.modules[module_key] = module_instance

        # Initialize the module if it has an initialize method
        if hasattr(module_instance, 'initialize'):
            try:
                if app_manager:
                    module_instance.initialize(app_manager)
                else:
                    pass
            except Exception as e:
                raise

    @log_function_call
    def get_module(self, module_key):
        """
        Retrieve a registered module.
        :param module_key: str - The unique key for the module.
        :return: object - The module instance or None if not found.
        """
        module = self.modules.get(module_key)
        if not module:
            pass
        else:
            pass
        return module

    @log_function_call
    def call_module_method(self, module_key, method_name, *args, **kwargs):
        """
        Dynamically call a method on a registered module.
        :param module_key: str - The unique key for the module.
        :param method_name: str - The name of the method to call.
        :param args: list - Positional arguments for the method.
        :param kwargs: dict - Keyword arguments for the method.
        :return: Any - The return value of the method call.
        """
        module = self.get_module(module_key)
        if not module:
            raise ValueError(f"Module with key '{module_key}' is not registered.")
        if not hasattr(module, method_name):
            raise AttributeError(f"Module '{module_key}' has no method '{method_name}'.")
        result = getattr(module, method_name)(*args, **kwargs)
        return result

    @log_function_call
    def discover_modules(self) -> Dict[str, Type[BaseModule]]:
        """
        Auto-discover all available modules using the ModuleRegistry.
        
        :return: Dictionary of module_key: ModuleClass mappings
        """
        try:
            custom_log("DEBUG: Starting module discovery", level="INFO", isOn=LOGGING_SWITCH)
            modules = ModuleRegistry.get_modules()
            custom_log(f"DEBUG: Discovered {len(modules)} modules: {list(modules.keys())}", level="INFO", isOn=LOGGING_SWITCH)
            
            # Log each module class
            for module_key, module_class in modules.items():
                custom_log(f"DEBUG: Module {module_key}: {module_class}", level="INFO", isOn=LOGGING_SWITCH)
            
            return modules
        except Exception as e:
            custom_log(f"ERROR: Failed to discover modules: {e}", level="ERROR", isOn=LOGGING_SWITCH)
            import traceback
            custom_log(f"ERROR: Traceback: {traceback.format_exc()}", level="ERROR", isOn=LOGGING_SWITCH)
            return {}
    
    @log_function_call
    def resolve_dependencies(self) -> List[str]:
        """
        Resolve and order modules by dependencies using topological sort.
        
        :return: List of module keys in dependency order
        """
        try:
            custom_log("DEBUG: Starting dependency resolution", level="INFO", isOn=LOGGING_SWITCH)
            load_order = ModuleRegistry.get_module_load_order()
            custom_log(f"DEBUG: Resolved load order: {load_order}", level="INFO", isOn=LOGGING_SWITCH)
            self.module_load_order = load_order
            return load_order
        except Exception as e:
            custom_log(f"ERROR: Failed to resolve dependencies: {e}", level="ERROR", isOn=LOGGING_SWITCH)
            import traceback
            custom_log(f"ERROR: Traceback: {traceback.format_exc()}", level="ERROR", isOn=LOGGING_SWITCH)
            return []
    
    @log_function_call
    def initialize_modules(self, app_manager):
        """
        Initialize all modules in dependency order.
        This is the main entry point for module initialization.
        
        :param app_manager: AppManager instance
        """
        
        custom_log("DEBUG: Starting module manager initialization", level="INFO", isOn=LOGGING_SWITCH)
        
        # Validate module registry first
        custom_log("DEBUG: Validating module registry", level="INFO", isOn=LOGGING_SWITCH)
        if not ModuleRegistry.validate_module_registry():
            custom_log("ERROR: Module registry validation failed", level="ERROR", isOn=LOGGING_SWITCH)
            raise RuntimeError("Module registry validation failed")
        
        custom_log("DEBUG: Module registry validation passed", level="INFO", isOn=LOGGING_SWITCH)
        
        # Clear any existing modules
        custom_log("DEBUG: Clearing existing modules", level="INFO", isOn=LOGGING_SWITCH)
        self.dispose()
        
        # Discover available modules
        custom_log("DEBUG: Discovering available modules", level="INFO", isOn=LOGGING_SWITCH)
        modules = self.discover_modules()
        custom_log(f"DEBUG: Discovered {len(modules)} modules: {list(modules.keys())}", level="INFO", isOn=LOGGING_SWITCH)
        
        if not modules:
            custom_log("WARNING: No modules discovered", level="WARNING", isOn=LOGGING_SWITCH)
            return
        
        # Resolve dependencies and get load order
        custom_log("DEBUG: Resolving module dependencies", level="INFO", isOn=LOGGING_SWITCH)
        load_order = self.resolve_dependencies()
        custom_log(f"DEBUG: Load order resolved: {load_order}", level="INFO", isOn=LOGGING_SWITCH)
        
        if not load_order:
            return
        
        # Initialize modules in dependency order
        custom_log(f"DEBUG: Starting module initialization for {len(load_order)} modules", level="INFO", isOn=LOGGING_SWITCH)
        
        for module_key in load_order:
            try:
                custom_log(f"DEBUG: Processing module {module_key} in load order", level="INFO", isOn=LOGGING_SWITCH)
                
                if module_key in modules:
                    module_class = modules[module_key]
                    custom_log(f"DEBUG: Module {module_key} found in discovered modules, class: {module_class}", level="INFO", isOn=LOGGING_SWITCH)
                    custom_log(f"Initializing module {module_key}", level="INFO", isOn=LOGGING_SWITCH)
                    self.register_and_initialize_module(module_key, module_class, app_manager)
                    custom_log(f"DEBUG: Module {module_key} initialization completed", level="INFO", isOn=LOGGING_SWITCH)
                else:
                    custom_log(f"WARNING: Module {module_key} not found in discovered modules", level="WARNING", isOn=LOGGING_SWITCH)
                    custom_log(f"WARNING: Available modules: {list(modules.keys())}", level="WARNING", isOn=LOGGING_SWITCH)
            except Exception as e:
                error_msg = f"Failed to initialize module {module_key}: {e}"
                custom_log(f"ERROR: {error_msg}", level="ERROR", isOn=LOGGING_SWITCH)
                custom_log(f"ERROR: Exception details: {type(e).__name__}: {str(e)}", level="ERROR", isOn=LOGGING_SWITCH)
                import traceback
                custom_log(f"ERROR: Traceback: {traceback.format_exc()}", level="ERROR", isOn=LOGGING_SWITCH)
                self.initialization_errors[module_key] = str(e)
                # Continue with other modules rather than failing completely
        
        # Summary
        initialized_count = len([m for m in self.modules.values() if m.is_initialized()])
        
        if self.initialization_errors:
            pass
    
    @log_function_call
    def register_and_initialize_module(self, module_key: str, module_class: Type[BaseModule], app_manager):
        """
        Register and initialize a single module.
        
        :param module_key: Unique identifier for the module
        :param module_class: Module class to instantiate
        :param app_manager: AppManager instance
        """
        try:
            custom_log(f"DEBUG: Starting registration and initialization of module {module_key}", level="INFO", isOn=LOGGING_SWITCH)
            custom_log(f"DEBUG: Module class: {module_class}", level="INFO", isOn=LOGGING_SWITCH)
            
            # Check if module is already registered
            if module_key in self.modules:
                custom_log(f"DEBUG: Module {module_key} already registered, skipping", level="INFO", isOn=LOGGING_SWITCH)
                return
                
            custom_log(f"DEBUG: Creating instance of module {module_key}", level="INFO", isOn=LOGGING_SWITCH)
            module_instance = module_class(app_manager=app_manager)
            custom_log(f"DEBUG: Module instance created: {module_instance}", level="INFO", isOn=LOGGING_SWITCH)
            
            custom_log(f"Registering and initializing module {module_key}", level="INFO", isOn=LOGGING_SWITCH)
            
            # Register the module
            self.modules[module_key] = module_instance
            custom_log(f"DEBUG: Module {module_key} registered successfully", level="INFO", isOn=LOGGING_SWITCH)
            
            # Initialize the module
            if hasattr(module_instance, 'initialize'):
                custom_log(f"DEBUG: Module {module_key} has initialize method, calling it", level="INFO", isOn=LOGGING_SWITCH)
                custom_log(f"Initializing module {module_key}", level="INFO", isOn=LOGGING_SWITCH)
                module_instance.initialize(app_manager)
                custom_log(f"DEBUG: Module {module_key} initialize method completed", level="INFO", isOn=LOGGING_SWITCH)
            else:
                custom_log(f"WARNING: Module {module_key} does not have initialize method", level="WARNING", isOn=LOGGING_SWITCH)
                # Mark as initialized
                module_instance._initialized = True
        except Exception as e:
            raise
    
    @log_function_call
    def get_module_status(self) -> Dict[str, Any]:
        """
        Get status information for all modules.
        
        :return: Dictionary containing module status information
        """
        status = {
            'total_modules': len(self.modules),
            'initialized_modules': len([m for m in self.modules.values() if m.is_initialized()]),
            'load_order': self.module_load_order,
            'initialization_errors': self.initialization_errors,
            'modules': {}
        }
        
        for module_key, module in self.modules.items():
            custom_log(f"Getting module status for {module_key}", level="INFO", isOn=LOGGING_SWITCH)
            status['modules'][module_key] = {
                'info': module.get_module_info(),
                'health': module.health_check()
            }
        
        return status
    
    @log_function_call
    def dispose(self):
        """
        Dispose of all registered modules, calling their cleanup methods if available.
        """
        # Dispose in reverse order to respect dependencies
        disposal_order = list(reversed(self.module_load_order)) if self.module_load_order else list(self.modules.keys())
        
        for module_key in disposal_order:
            if module_key in self.modules:
                module = self.modules[module_key]
                try:
                    if hasattr(module, "dispose"):
                        module.dispose()
                except Exception as e:
                    pass

        self.modules.clear()
        self.module_load_order.clear()
        self.initialization_errors.clear()
