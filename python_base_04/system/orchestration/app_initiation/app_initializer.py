"""
Main Application Manager

This module contains the core AppInitializer class that orchestrates the entire application.
It delegates specific responsibilities to specialized classes for better separation of concerns.
"""

from flask import Flask
from tools.logger.custom_logging import custom_log, log_function_call
from apscheduler.schedulers.background import BackgroundScheduler
from system.managers.service_manager import ServicesManager
from system.managers.hooks_manager import HooksManager
from system.managers.module_manager import ModuleManager
from system.managers.rate_limiter_manager import RateLimiterManager

from .manager_initializer import ManagerInitializer
from .middleware_setup import MiddlewareSetup
from .health_checker import HealthChecker


class AppInitializer:
    """
    Main application orchestrator that manages the Flask application lifecycle.
    
    This class coordinates all managers and middleware setup, delegating specific
    responsibilities to specialized classes for better maintainability.
    """
    
    def __init__(self):
        """Initialize the AppInitializer with all required components."""
        # Core managers
        self.services_manager = ServicesManager()
        self.hooks_manager = HooksManager()
        self.module_manager = ModuleManager()
        
        # Flask app reference
        self.flask_app = None
        self.scheduler = None
        self._initialized = False
        
        # Initialize specialized components
        self.manager_initializer = ManagerInitializer(self)
        self.middleware_setup = MiddlewareSetup(self)
        self.health_checker = HealthChecker(self)
        
        custom_log("AppInitializer instance created with modular components.")

    def is_initialized(self) -> bool:
        """Check if the AppInitializer is properly initialized."""
        return self._initialized

    @log_function_call
    def initialize(self, app: Flask):
        """
        Initialize all application components and middleware.
        
        Args:
            app: Flask application instance
        """
        if not hasattr(app, "add_url_rule"):
            raise RuntimeError("AppInitializer requires a valid Flask app instance.")

        self.flask_app = app
        custom_log(f"AppInitializer initialized with Flask app: {self.flask_app}")

        # Initialize scheduler
        self.scheduler = BackgroundScheduler()
        self.scheduler.start()

        # Initialize all managers through the specialized initializer
        self.manager_initializer.initialize_all_managers(app)
        
        # Initialize services
        self.services_manager.initialize_services()

        # Register common hooks before module initialization
        self._register_common_hooks()

        # Initialize modules
        custom_log("Initializing modules...")
        self.module_manager.initialize_modules(self)

        # Set up all middleware through the specialized setup class
        self.middleware_setup.setup_all_middleware()
        
        # Mark as initialized
        self._initialized = True
        
        custom_log("✅ AppInitializer initialization completed successfully")

    def run(self, app: Flask, **kwargs):
        """Run the Flask application."""
        app.run(**kwargs)

    def _register_common_hooks(self):
        """Register common hooks that modules can use."""
        try:
            # Register user_created hook
            self.register_hook("user_created")
            custom_log("✅ Registered common hook: user_created")
            
            # Add more common hooks here as needed
            # self.register_hook("payment_processed")
            # self.register_hook("user_login")
            # self.register_hook("user_logout")
            
        except Exception as e:
            custom_log(f"❌ Error registering common hooks: {e}", level="ERROR")

    @log_function_call
    def register_hook(self, hook_name: str):
        """
        Register a new hook by delegating to the HooksManager.
        
        Args:
            hook_name: The name of the hook
        """
        self.hooks_manager.register_hook(hook_name)
        custom_log(f"Hook '{hook_name}' registered via AppInitializer.")

    @log_function_call
    def register_hook_callback(self, hook_name: str, callback, priority: int = 10, context: str = None):
        """
        Register a callback for a specific hook by delegating to the HooksManager.
        
        Args:
            hook_name: The name of the hook
            callback: The callback function
            priority: Priority of the callback (lower number = higher priority)
            context: Optional context for the callback
        """
        self.hooks_manager.register_hook_callback(hook_name, callback, priority, context)
        callback_name = callback.__name__ if hasattr(callback, "__name__") else str(callback)
        custom_log(f"Callback '{callback_name}' registered for hook '{hook_name}' (priority: {priority}, context: {context}).")

    @log_function_call
    def trigger_hook(self, hook_name: str, data=None, context: str = None):
        """
        Trigger a specific hook by delegating to the HooksManager.
        
        Args:
            hook_name: The name of the hook to trigger
            data: Data to pass to the callback
            context: Optional context to filter callbacks
        """
        custom_log(f"Triggering hook '{hook_name}' with data: {data} and context: {context}.")
        self.hooks_manager.trigger_hook(hook_name, data, context)

    # Delegate health checking to specialized class
    def check_database_connection(self) -> bool:
        """Check if the database connection is healthy."""
        return self.health_checker.check_database_connection()

    def check_redis_connection(self) -> bool:
        """Check if the Redis connection is healthy."""
        return self.health_checker.check_redis_connection()

    # Delegate manager access to specialized class
    def get_db_manager(self, role: str = "read_write"):
        """Get the appropriate database manager instance."""
        return self.manager_initializer.get_db_manager(role)

    def get_redis_manager(self):
        """Get the Redis manager instance."""
        return self.manager_initializer.get_redis_manager()

    def get_state_manager(self):
        """Get the state manager instance."""
        return self.manager_initializer.get_state_manager()

    def get_websocket_manager(self):
        """Get the WebSocket manager instance."""
        return self.manager_initializer.get_websocket_manager() 