import os
import json
from tools.logger.custom_logging import custom_log, log_function_call
from utils.config.config import Config
from core.managers.redis_manager import RedisManager
from core.managers.jwt_manager import JWTManager, TokenType
from core.managers.database_manager import DatabaseManager
from core.managers.api_key_manager import APIKeyManager
from tools.error_handling import ErrorHandler
from datetime import datetime, timedelta
import time
import uuid
import logging
from flask import request, jsonify
from typing import Dict, Any
from core.modules.base_module import BaseModule


class CommunicationsModule(BaseModule):
    def __init__(self, app_manager=None):
        """Initialize the CommunicationsModule."""
        super().__init__(app_manager)
        
        # Set dependencies
        self.dependencies = []
        
        # Use centralized managers from app_manager instead of creating new instances
        if app_manager:
            self.admin_db = app_manager.get_db_manager(role="read_write")
            self.analytics_db = app_manager.get_db_manager(role="read_only")
            self.redis_manager = app_manager.get_redis_manager()
        else:
            # Fallback for testing or when app_manager is not provided
            self.admin_db = DatabaseManager(role="read_write")
            self.analytics_db = DatabaseManager(role="read_only")
            self.redis_manager = RedisManager()
        
        # Initialize API key manager for external app
        self.api_key_manager = APIKeyManager(self.redis_manager)

        custom_log(f"CommunicationsModule module created with shared managers")

    def initialize(self, app_manager):
        """Initialize the CommunicationsModule with AppManager."""
        self.app_manager = app_manager
        self.app = app_manager.flask_app
        custom_log(f"CommunicationsModule initialized with AppManager")
        
        # Ensure collections exist in the database
        self.initialize_database()
        
        # Register routes
        self.register_routes()
        
        # Register hooks for user events
        self._register_hooks()
        
        # Auto-generate API key for external app if needed (using unified manager)
        self.api_key_manager.ensure_external_app_api_key()
        
        # Mark as initialized
        self._initialized = True

    def _register_hooks(self):
        """Register hooks for user-related events."""
        if self.app_manager:
            # Note: Welcome notifications are now handled in CreditSystemModule callback
            # No need for separate communications hook callback
            custom_log("🎣 CommunicationsModule: Welcome notifications handled in CreditSystemModule - no hook callback needed")

    def register_routes(self):
        """Register all CommunicationsModule routes."""
        custom_log("Registering CommunicationsModule routes...")
        
        # Register core routes
        self._register_route_helper("/", self.home, methods=["GET"])
        self._register_route_helper("/get-db-data", self.get_all_database_data, methods=["GET"])
        
        # Register API key management routes (using unified API key manager)
        self._register_route_helper("/api-keys/validate", self.api_key_manager.validate_api_key_endpoint, methods=["POST"])
        self._register_route_helper("/api-keys/revoke", self.api_key_manager.revoke_api_key_endpoint, methods=["POST"])
        self._register_route_helper("/api-keys/stored", self.api_key_manager.list_stored_api_keys_endpoint, methods=["GET"])
        self._register_route_helper("/api-keys/request-from-credit-system", self.api_key_manager.request_api_key_from_credit_system_endpoint, methods=["POST"])
        
        custom_log(f"CommunicationsModule registered {len(self.registered_routes)} routes")

    def initialize_database(self):
        """Verify database connection without creating collections or indexes."""
        custom_log("⚙️ Verifying database connection...")
        if self._verify_database_connection():
            custom_log("✅ Database connection verified.")
        else:
            custom_log("⚠️ Database connection unavailable - running with limited functionality")

    def _verify_database_connection(self) -> bool:
        """Verify database connection without creating anything."""
        try:
            # Check if database is available
            if not self.admin_db.available:
                custom_log("⚠️ Database unavailable - connection verification skipped")
                return False
                
            # Simple connection test - just ping the database
            self.admin_db.db.command('ping')
            custom_log("✅ Database connection verified successfully")
            return True
        except Exception as e:
            custom_log(f"⚠️ Database connection verification failed: {e}")
            custom_log("⚠️ Database operations will be limited - suitable for local development")
            return False

    def home(self):
        """Handle the root route."""
        return {"message": "CommunicationsModule module is running", "version": "2.0", "module": "communications_module"}

    def get_all_database_data(self):
        """Get all data from all collections in the database."""
        try:
            # Use the database manager to get all data
            all_data = self.admin_db.get_all_database_data()
            
            # Return the data as JSON response
            return all_data
            
        except Exception as e:
            custom_log(f"❌ Error in get_all_database_data endpoint: {e}", level="ERROR")
            return {"error": f"Failed to retrieve database data: {str(e)}"}, 500

    def health_check(self) -> Dict[str, Any]:
        """Perform health check for CommunicationsModule."""
        health_status = super().health_check()
        health_status['dependencies'] = self.dependencies
        # Add database queue status
        try:
            queue_status = self.admin_db.get_queue_status()
            health_status['details'] = {
                'database_queue': {
                    'queue_size': queue_status['queue_size'],
                    'worker_alive': queue_status['worker_alive'],
                    'queue_enabled': queue_status['queue_enabled'],
                    'pending_results': queue_status['pending_results']
                },
                'api_key_manager': {
                    'status': 'operational',
                    'external_app_key_configured': bool(self.api_key_manager.load_credit_system_api_key())
                }
            }
        except Exception as e:
            health_status['details'] = {
                'database_queue': f'error: {str(e)}',
                'api_key_manager': {
                    'status': 'operational',
                    'external_app_key_configured': bool(self.api_key_manager.load_credit_system_api_key())
                }
            }
        
        return health_status