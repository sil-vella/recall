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

from system.managers.rate_limiter_manager import RateLimiterManager
from system.orchestration.modules_orch.base_files.module_orch_base import ModuleOrchestratorBase

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

        # Initialize modules (now handled by individual managers via hooks)
        custom_log("Initializing modules via hook system...")

        # Set up all middleware through the specialized setup class
        self.middleware_setup.setup_all_middleware()
        
        # Mark as initialized
        self._initialized = True

        # Initialize module orchestrator base before route registration hook
        self.module_orch_base = ModuleOrchestratorBase(self.manager_initializer)
        custom_log("ModuleOrchestratorBase initialized in AppInitializer.")
        
        # Initialize all module orchestrators
        self.module_orch_base.initialize_orchestrators()
        custom_log("All module orchestrators initialized.")

        # Trigger route registration hook within Flask application context
        with app.app_context():
            self.hooks_manager.trigger_hook("register_routes")
        
        custom_log("✅ AppInitializer initialization completed successfully")

    def run(self, app: Flask, **kwargs):
        """Run the Flask application."""
        app.run(**kwargs)

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