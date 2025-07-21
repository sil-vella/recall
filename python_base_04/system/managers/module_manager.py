from tools.logger.custom_logging import custom_log, function_log, game_play_log, log_function_call
from typing import Dict, List, Type, Any, Optional
from system.managers.module_registry import ModuleRegistry
from system.modules.base_module import BaseModule

class ModuleManager:
    def __init__(self):
        # A dictionary to hold all registered modules
        self.modules = {}
        self.module_load_order = []
        self.initialization_errors = {}
        custom_log("ModuleManager instance created - now serving as primary orchestrator")

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
        custom_log(f"Module '{module_key}' registered successfully.")

        # Initialize the module if it has an initialize method
        if hasattr(module_instance, 'initialize'):
            custom_log(f"🔄 Initializing module '{module_key}'...")
            try:
                if app_manager:
                    module_instance.initialize(app_manager)
                    custom_log(f"✅ Module '{module_key}' initialized successfully")
                else:
                    custom_log(f"❌ Cannot initialize module '{module_key}': Missing required app_manager")
            except Exception as e:
                custom_log(f"❌ Error initializing module '{module_key}': {str(e)}")
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
            custom_log(f"Error: Module '{module_key}' is not registered.")
        else:
            custom_log(f"Retrieved module '{module_key}': {module}")
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

        custom_log(f"Calling method '{method_name}' on module '{module_key}' with args: {args}, kwargs: {kwargs}")
        result = getattr(module, method_name)(*args, **kwargs)
        custom_log(f"Method '{method_name}' on module '{module_key}' returned: {result}")
        return result

    @log_function_call
    def discover_modules(self) -> Dict[str, Type[BaseModule]]:
        """
        Auto-discover all available modules using the ModuleRegistry.
        
        :return: Dictionary of module_key: ModuleClass mappings
        """
        try:
            modules = ModuleRegistry.get_modules()
            custom_log(f"Discovered {len(modules)} modules via ModuleRegistry")
            return modules
        except Exception as e:
            custom_log(f"❌ Error discovering modules: {e}")
            return {}
    
    @log_function_call
    def resolve_dependencies(self) -> List[str]:
        """
        Resolve and order modules by dependencies using topological sort.
        
        :return: List of module keys in dependency order
        """
        try:
            load_order = ModuleRegistry.get_module_load_order()
            self.module_load_order = load_order
            custom_log(f"Module load order resolved: {load_order}")
            return load_order
        except Exception as e:
            custom_log(f"❌ Error resolving module dependencies: {e}")
            return []
    
    @log_function_call
    def initialize_modules(self, app_manager):
        """
        Initialize all modules in dependency order.
        This is the main entry point for module initialization.
        
        :param app_manager: AppManager instance
        """
        custom_log("🚀 Starting module initialization process...")
        
        # Validate module registry first
        if not ModuleRegistry.validate_module_registry():
            raise RuntimeError("Module registry validation failed")
        
        # Clear any existing modules
        self.dispose()
        
        # Discover available modules
        modules = self.discover_modules()
        if not modules:
            custom_log("❌ No modules discovered - aborting initialization")
            return
        
        # Resolve dependencies and get load order
        load_order = self.resolve_dependencies()
        if not load_order:
            custom_log("❌ Failed to resolve module dependencies - aborting initialization")
            return
        
        # Initialize modules in dependency order
        for module_key in load_order:
            try:
                if module_key in modules:
                    module_class = modules[module_key]
                    self.register_and_initialize_module(module_key, module_class, app_manager)
                else:
                    custom_log(f"❌ Module {module_key} in load order but not in discovered modules")
            except Exception as e:
                error_msg = f"Failed to initialize module {module_key}: {e}"
                custom_log(f"❌ {error_msg}")
                self.initialization_errors[module_key] = str(e)
                # Continue with other modules rather than failing completely
        
        # Summary
        initialized_count = len([m for m in self.modules.values() if m.is_initialized()])
        custom_log(f"✅ Module initialization complete: {initialized_count}/{len(load_order)} modules initialized")
        
        if self.initialization_errors:
            custom_log(f"⚠️ Initialization errors: {self.initialization_errors}")
    
    @log_function_call
    def register_and_initialize_module(self, module_key: str, module_class: Type[BaseModule], app_manager):
        """
        Register and initialize a single module.
        
        :param module_key: Unique identifier for the module
        :param module_class: Module class to instantiate
        :param app_manager: AppManager instance
        """
        try:
            # Check if module is already registered
            if module_key in self.modules:
                custom_log(f"⚠️ Module {module_key} already registered - skipping")
                return
            
            # Instantiate the module
            custom_log(f"📦 Creating module instance: {module_key}")
            module_instance = module_class(app_manager=app_manager)
            
            # Register the module
            self.modules[module_key] = module_instance
            custom_log(f"✅ Module {module_key} registered successfully")
            
            # Initialize the module
            if hasattr(module_instance, 'initialize'):
                custom_log(f"🔄 Initializing module: {module_key}")
                module_instance.initialize(app_manager)
                
                # Mark as initialized
                module_instance._initialized = True
                custom_log(f"✅ Module {module_key} initialized successfully")
            else:
                custom_log(f"❌ Cannot initialize module {module_key} - missing initialize method")
                
        except Exception as e:
            custom_log(f"❌ Error registering/initializing module {module_key}: {e}")
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
                        custom_log(f"Disposing module: {module_key}")
                        module.dispose()
                except Exception as e:
                    custom_log(f"❌ Error disposing module {module_key}: {e}")

        self.modules.clear()
        self.module_load_order.clear()
        self.initialization_errors.clear()
        custom_log("All modules have been disposed of.")
