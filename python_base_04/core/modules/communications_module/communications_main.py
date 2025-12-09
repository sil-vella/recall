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
import debugpy

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

    def initialize(self, app_manager):
        """Initialize the CommunicationsModule with AppManager."""
        self.app_manager = app_manager
        self.app = app_manager.flask_app
        
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
            pass

    def register_routes(self):
        """Register all CommunicationsModule routes."""
        
        # Register core routes
        self._register_route_helper("/", self.home, methods=["GET"])
        self._register_route_helper("/get-db-data", self.get_all_database_data, methods=["GET"])
        
        # Register API key management routes (using unified API key manager)
        self._register_route_helper("/api-keys/validate", self.api_key_manager.validate_api_key_endpoint, methods=["POST"])
        self._register_route_helper("/api-keys/revoke", self.api_key_manager.revoke_api_key_endpoint, methods=["POST"])
        self._register_route_helper("/api-keys/stored", self.api_key_manager.list_stored_api_keys_endpoint, methods=["GET"])
        self._register_route_helper("/api-keys/request-from-credit-system", self.api_key_manager.request_api_key_from_credit_system_endpoint, methods=["POST"])
        
        # Register JWT test route
        self._register_route_helper("/test-jwt", self.test_jwt, methods=["POST"])

    def initialize_database(self):
        """
        Verify database connection without creating collections or indexes.
        
        Note: This method only verifies the database connection. It does NOT create
        collections, indexes, or seed data. Database structure setup is handled
        exclusively by Ansible playbooks (09 or 10).
        """
        if self._verify_database_connection():
            pass
        else:
            pass

    def _verify_database_connection(self) -> bool:
        """
        Verify database connection without creating anything.
        
        Note: Database structure setup is handled exclusively by Ansible playbooks.
        """
        try:
            # Check if database is available
            if not self.admin_db.available:
                return False
                
            # Simple connection test - just ping the database
            self.admin_db.db.command('ping')
            return True
        except Exception as e:
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
            return {"error": f"Failed to retrieve database data: {str(e)}"}, 500

    def test_jwt(self):
        debugpy.breakpoint()
        """Test JWT token validation and return token information."""
        try:
            # Get JWT manager from app_manager
            jwt_manager = self.app_manager.jwt_manager
            
            # Get the Authorization header
            auth_header = request.headers.get('Authorization')
            
            if not auth_header:
                return jsonify({
                    "success": False,
                    "message": "No Authorization header provided",
                    "error": "Missing JWT token"
                }), 401
            
            # Extract token from Authorization header
            if auth_header.startswith('Bearer '):
                token = auth_header[7:]  # Remove 'Bearer ' prefix
            else:
                token = auth_header
            
            # Verify the token
            payload = jwt_manager.verify_token(token, TokenType.ACCESS)
            
            if not payload:
                return jsonify({
                    "success": False,
                    "message": "Invalid or expired JWT token",
                    "error": "Token validation failed"
                }), 401
            
            # Return token information (excluding sensitive data)
            token_info = {
                "success": True,
                "message": "JWT token is valid",
                "token_info": {
                    "user_id": payload.get("user_id"),
                    "type": payload.get("type"),
                    "issued_at": payload.get("iat"),
                    "expires_at": payload.get("exp"),
                    "fingerprint": payload.get("fingerprint", "")[:16] + "..." if payload.get("fingerprint") else None
                },
                "ttl_info": {
                    "access_token_expires": Config.JWT_ACCESS_TOKEN_EXPIRES,
                    "refresh_token_expires": Config.JWT_REFRESH_TOKEN_EXPIRES
                }
            }
            return jsonify(token_info), 200
            
        except Exception as e:
            return jsonify({
                "success": False,
                "message": "JWT test failed",
                "error": str(e)
            }), 500

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
                'token_info': {
                    'user_id': payload.get('user_id'),
                    'type': payload.get('type'),
                    'issued_at': payload.get('iat'),
                    'expires_at': payload.get('exp'),
                    'fingerprint': payload.get('fingerprint', '')[:16] + '...' if payload.get('fingerprint') else None
                },
                'ttl_info': {
                    'access_token_expires': Config.JWT_ACCESS_TOKEN_EXPIRES,
                    'refresh_token_expires': Config.JWT_REFRESH_TOKEN_EXPIRES
                }
            }
            return jsonify(token_info), 200
            
        except Exception as e:
            return jsonify({
                "success": False,
                "message": "JWT test failed",
                "error": str(e)
            }), 500

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