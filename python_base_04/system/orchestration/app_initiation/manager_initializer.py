"""
Manager Initializer

This module handles the initialization of all application managers.
It centralizes the creation and configuration of database, Redis, JWT, and other managers.
"""

from flask import Flask
from tools.logger.custom_logging import custom_log
from system.managers.database_manager import DatabaseManager
from system.managers.redis_manager import RedisManager
from system.managers.state_manager import StateManager
from system.managers.jwt_manager import JWTManager
from system.managers.user_actions_manager import UserActionsManager
from system.managers.action_discovery_manager import ActionDiscoveryManager
from system.managers.websockets.websocket_manager import WebSocketManager


class ManagerInitializer:
    """
    Handles the initialization and management of all application managers.
    
    This class is responsible for creating and configuring all managers
    used throughout the application, ensuring proper dependencies and connections.
    """
    
    def __init__(self, app_manager):
        """
        Initialize the ManagerInitializer.
        
        Args:
            app_manager: Reference to the main AppManager instance
        """
        self.app_manager = app_manager
        
        # Manager instances
        self.db_manager = None
        self.analytics_db = None
        self.admin_db = None
        self.redis_manager = None
        self.rate_limiter_manager = None
        self.state_manager = None
        self.jwt_manager = None
        self.user_actions_manager = None
        self.action_discovery_manager = None
        self.websocket_manager = None
        
        custom_log("ManagerInitializer created")

    def initialize_all_managers(self, app: Flask):
        """
        Initialize all application managers in the correct order.
        
        Args:
            app: Flask application instance
        """
        custom_log("Starting manager initialization...")
        
        # Initialize database managers (using singleton pattern)
        self._initialize_database_managers()
        
        # Initialize Redis manager
        self._initialize_redis_manager()
        
        # Initialize rate limiter manager
        self._initialize_rate_limiter_manager()
        
        # Initialize state manager
        self._initialize_state_manager()
        
        # Initialize JWT manager
        self._initialize_jwt_manager()
        
        # Initialize user actions manager
        self._initialize_user_actions_manager()
        
        # Initialize action discovery manager
        self._initialize_action_discovery_manager()
        
        # Initialize WebSocket manager
        self._initialize_websocket_manager(app)
        
        custom_log("✅ All managers initialized successfully")

    def _initialize_database_managers(self):
        """Initialize database managers with singleton pattern."""
        self.db_manager = DatabaseManager(role="read_write")
        # Use the same instance for all database operations
        self.analytics_db = self.db_manager
        self.admin_db = self.db_manager
        
        # Set the database manager in the app manager
        self.app_manager.db_manager = self.db_manager
        self.app_manager.analytics_db = self.analytics_db
        self.app_manager.admin_db = self.admin_db
        
        custom_log("✅ Database managers initialized")

    def _initialize_redis_manager(self):
        """Initialize Redis manager."""
        self.redis_manager = RedisManager()
        
        # Set the Redis manager in the app manager
        self.app_manager.redis_manager = self.redis_manager
        
        custom_log("✅ Redis manager initialized")

    def _initialize_rate_limiter_manager(self):
        """Initialize rate limiter manager."""
        from system.managers.rate_limiter_manager import RateLimiterManager
        
        self.rate_limiter_manager = RateLimiterManager()
        self.rate_limiter_manager.set_redis_manager(self.redis_manager)
        
        # Set the rate limiter manager in the app manager
        self.app_manager.rate_limiter_manager = self.rate_limiter_manager
        
        custom_log("✅ Rate limiter manager initialized")

    def _initialize_state_manager(self):
        """Initialize state manager."""
        self.state_manager = StateManager(
            redis_manager=self.redis_manager, 
            database_manager=self.db_manager
        )
        
        # Set the state manager in the app manager
        self.app_manager.state_manager = self.state_manager
        
        custom_log("✅ State manager initialized")

    def _initialize_jwt_manager(self):
        """Initialize JWT manager."""
        self.jwt_manager = JWTManager(redis_manager=self.redis_manager)
        
        # Set the JWT manager in the app manager
        self.app_manager.jwt_manager = self.jwt_manager
        
        custom_log("✅ JWT manager initialized")

    def _initialize_user_actions_manager(self):
        """Initialize user actions manager."""
        self.user_actions_manager = UserActionsManager()
        
        # Set the user actions manager in the app manager
        self.app_manager.user_actions_manager = self.user_actions_manager
        
        custom_log("✅ User actions manager initialized")

    def _initialize_action_discovery_manager(self):
        """Initialize action discovery manager."""
        self.action_discovery_manager = ActionDiscoveryManager(self.app_manager)
        self.action_discovery_manager.discover_all_actions()
        
        # Set the action discovery manager in the app manager
        self.app_manager.action_discovery_manager = self.action_discovery_manager
        
        custom_log("✅ Action discovery manager initialized")

    def _initialize_websocket_manager(self, app: Flask):
        """Initialize WebSocket manager."""
        self.websocket_manager = WebSocketManager()
        self.websocket_manager.set_jwt_manager(self.jwt_manager)
        self.websocket_manager.set_room_access_check(
            self.websocket_manager.room_manager.check_room_access
        )
        self.websocket_manager.initialize(app, use_builtin_handlers=True)
        
        # Set the WebSocket manager in the app manager
        self.app_manager.websocket_manager = self.websocket_manager
        
        custom_log("✅ WebSocket manager initialized")

    # Manager access methods
    def get_db_manager(self, role: str = "read_write"):
        """
        Get the appropriate database manager instance.
        
        Args:
            role: Database role (read_write, read_only, admin)
            
        Returns:
            DatabaseManager instance
            
        Raises:
            ValueError: If unknown database role
        """
        if role == "read_write":
            return self.db_manager
        elif role == "read_only":
            return self.analytics_db
        elif role == "admin":
            return self.admin_db
        else:
            raise ValueError(f"Unknown database role: {role}")

    def get_redis_manager(self):
        """Get the Redis manager instance."""
        return self.redis_manager

    def get_state_manager(self):
        """Get the state manager instance."""
        return self.state_manager

    def get_websocket_manager(self):
        """Get the WebSocket manager instance."""
        return self.websocket_manager 