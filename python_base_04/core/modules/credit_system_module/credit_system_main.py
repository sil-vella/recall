from core.modules.base_module import BaseModule
from core.managers.database_manager import DatabaseManager
from core.managers.jwt_manager import JWTManager, TokenType
from core.managers.redis_manager import RedisManager
from tools.logger.custom_logging import custom_log
from flask import request, jsonify
from datetime import datetime
from typing import Dict, Any
from bson import ObjectId
import bcrypt
import re
import requests
from utils.config.config import Config


class CreditSystemModule(BaseModule):
    def __init__(self, app_manager=None):
        """Initialize the CreditSystemModule."""
        super().__init__(app_manager)
        
        # Set dependencies
        self.dependencies = ["communications_module"]
        
        # Use centralized managers from app_manager instead of creating new instances
        if app_manager:
            self.db_manager = app_manager.get_db_manager(role="read_write")
            self.analytics_db = app_manager.get_db_manager(role="read_only")
            self.redis_manager = app_manager.get_redis_manager()
        else:
            # Fallback for testing or when app_manager is not provided
            self.db_manager = DatabaseManager(role="read_write")
            self.analytics_db = DatabaseManager(role="read_only")
            self.redis_manager = RedisManager()
        
        # Credit system configuration
        self.credit_system_url = Config.CREDIT_SYSTEM_URL
        # Use dynamic API key getter that generates if empty
        self.api_key = Config.get_credit_system_api_key()

    def initialize(self, app_manager):
        """Initialize the CreditSystemModule with AppManager."""
        self.app_manager = app_manager
        self.app = app_manager.flask_app
        self.initialize_database()
        self.register_routes()
        
        # Register hooks for user events
        self._register_hooks()
        
        self._initialized = True

    def _register_hooks(self):
        """Register hooks for user-related events."""
        if self.app_manager:
            # Register callback for user creation
            self.app_manager.register_hook_callback(
                "user_created", 
                self._on_user_created, 
                priority=15, 
                context="credit_system"
            )

    def _on_user_created(self, hook_data):
        """Handle user creation event - forward to credit system."""
        try:
            user_id = hook_data.get('user_id')
            username = hook_data.get('username')
            email = hook_data.get('email')  # Raw email from request (non-encrypted)
            user_data = hook_data.get('user_data', {})
            app_id = hook_data.get('app_id')
            app_name = hook_data.get('app_name')
            source = hook_data.get('source', 'external_app')
            
            # Prepare data for credit system with multi-tenant structure
            credit_system_user_data = {
                # Core user fields
                'email': email,  # Raw email from request
                'username': username,
                'password': 'temporary_password_123',  # Credit system will generate proper password
                'status': 'active',
                
                # Profile data from external app
                'first_name': user_data.get('profile', {}).get('first_name', ''),
                'last_name': user_data.get('profile', {}).get('last_name', ''),
                'phone': user_data.get('profile', {}).get('phone', ''),
                'timezone': user_data.get('profile', {}).get('timezone', 'UTC'),
                'language': user_data.get('profile', {}).get('language', 'en'),
                
                # App-specific data for multi-tenant structure
                'app_id': app_id,
                'app_name': app_name,
                'app_version': '1.0.0',
                'app_username': username,  # App-specific username
                'app_display_name': f"{user_data.get('profile', {}).get('first_name', '')} {user_data.get('profile', {}).get('last_name', '')}".strip() or username,
                'nickname': username[:2].upper(),
                'avatar_url': '',
                'theme': 'auto',
                'notifications_enabled': True,
                'custom_fields': {
                    'source': source,
                    'external_user_id': str(user_id),
                    'created_via': 'external_app'
                },
                
                # App connection settings
                'permissions': ['read', 'write', 'wallet_access'],
                'sync_frequency': 'realtime',
                'wallet_updates': True,
                'profile_updates': True,
                'transaction_history': True,
                'requests_per_minute': 100,
                'requests_per_hour': 1000
            }
            
            # Forward user creation to credit system
            try:
                headers = {
                    'X-API-Key': self.api_key,
                    'Content-Type': 'application/json'
                }
                
                target_url = f"{self.credit_system_url}/users/create"
                
                response = requests.post(
                    url=target_url,
                    headers=headers,
                    json=credit_system_user_data,
                    timeout=30
                )
                
                if response.status_code == 200 or response.status_code == 201:
                    response_data = response.json()
                    
                    # Create welcome notification in external app
                    self._create_welcome_notification(user_id, username, email, app_name)
                    
                else:
                    pass
            except requests.exceptions.RequestException as e:
                pass
            except Exception as e:
                pass
        except Exception as e:
            pass

    def _create_welcome_notification(self, user_id, username, email, app_name):
        """Create welcome notification for new user."""
        try:
            notification_data = {
                'user_id': user_id,
                'type': 'welcome',
                'title': f'Welcome to {app_name}!',
                'message': f'Hello {username}! Your account has been successfully created and synced with the credit system.',
                'priority': 'normal',
                'status': 'unread',
                'created_at': datetime.utcnow().isoformat(),
                'metadata': {
                    'source': 'credit_system_module',
                    'app_name': app_name,
                    'email': email
                }
            }
            
            # Insert notification using database manager
            notification_id = self.db_manager.insert("notifications", notification_data)
            
            if notification_id:
                pass
            else:
                pass
        except Exception as e:
            pass

    def register_routes(self):
        """Register wildcard routes that capture all user-related requests."""

    def forward_user_request(self, subpath=None):
        """Forward user management requests to credit system with API key."""
        try:
            # Get the current request path and method
            path = request.path
            method = request.method
            
            # Build the target path on credit system
            # Use subpath parameter when available (for wildcard routes), otherwise use full path
            if subpath is not None:
                # For wildcard routes like /users/<path:subpath>
                # Reconstruct the full path to determine the target
                if path.startswith('/users/'):
                    target_path = f"/users/{subpath}"
                elif path.startswith('/auth/users/'):
                    target_path = f"/auth/{subpath}"
                else:
                    target_path = path  # Fallback
            else:
                # For base routes like /users (no subpath)
                target_path = self._build_credit_system_path(path)
            
            # Prepare headers with API key
            headers = {
                'X-API-Key': self.api_key,
                'Content-Type': 'application/json'
            }
            
            # Forward any existing Authorization header (JWT tokens)
            auth_header = request.headers.get('Authorization')
            if auth_header:
                headers['Authorization'] = auth_header
            
            # Prepare request data
            data = None
            if method in ['POST', 'PUT']:
                data = request.get_json()
            
            # Build target URL
            target_url = f"{self.credit_system_url}{target_path}"
            if data:
                pass
            
            # Make request to credit system
            response = requests.request(
                method=method,
                url=target_url,
                headers=headers,
                json=data if data else None,
                timeout=30
            )
            
            # Forward the response back to the client
            response_data = response.json() if response.content else {}
            status_code = response.status_code
            
            return jsonify(response_data), status_code
            
        except requests.exceptions.RequestException as e:
            return jsonify({
                "success": False,
                "error": "Credit system unavailable",
                "message": "Unable to connect to credit system"
            }), 503
            
        except Exception as e:
            return jsonify({
                "success": False,
                "error": "Internal server error",
                "message": "Failed to process request"
            }), 500

    def _build_credit_system_path(self, external_path):
        """Build the target path for credit system based on external app path."""
        # Remove leading slash and split path
        path_parts = external_path.strip('/').split('/')
        
        if len(path_parts) < 1:
            return external_path  # Return as-is if invalid path
        
        # Handle /users/* paths
        if path_parts[0] == 'users':
            # Forward /users to /users (let credit system handle it)
            # Forward /users/create to /users/create
            # Forward /users/123 to /users/123
            # Forward /users/123/profile to /users/123/profile
            return f"/{'/'.join(path_parts)}"
        
        # Handle /auth/users/* paths
        elif path_parts[0] == 'auth' and len(path_parts) > 1 and path_parts[1] == 'users':
            # Forward /auth/users/login to /auth/login
            # Forward /auth/users/logout to /auth/logout
            # Forward /auth/users/123 to /auth/123
            # Forward /auth/users/me to /auth/me
            if len(path_parts) == 3:
                # /auth/users/login -> /auth/login
                return f"/auth/{path_parts[2]}"
            elif len(path_parts) == 4:
                # /auth/users/123/profile -> /auth/123/profile
                return f"/auth/{path_parts[2]}/{path_parts[3]}"
            else:
                # Fallback for complex paths
                return f"/auth/{'/'.join(path_parts[2:])}"
        
        # Return original path if no mapping found
        return external_path

    def initialize_database(self):
        """Verify database connection for user operations."""
        try:
            # Check if database is available
            if not self.analytics_db.available:
                return
                
            # Simple connection test
            self.analytics_db.db.command('ping')
        except Exception as e:
            pass

    def test_debug(self):
        """Test endpoint to verify debug logging works."""
        print("[DEBUG] Test endpoint called!")
        print(f"[DEBUG] Database manager: {self.db_manager}")
        print(f"[DEBUG] Analytics DB: {self.analytics_db}")
        print(f"[DEBUG] Credit system URL: {self.credit_system_url}")
        print(f"[DEBUG] API key configured: {'Yes' if self.api_key else 'No'}")
        return jsonify({
            "message": "Debug test successful",
            "credit_system_url": self.credit_system_url,
            "api_key_configured": bool(self.api_key)
        }), 200

    def health_check(self) -> Dict[str, Any]:
        """Perform health check for CreditSystemModule."""
        health_status = super().health_check()
        health_status['dependencies'] = self.dependencies
        
        # Add credit system connection status
        try:
            # Test connection to credit system
            response = requests.get(
                f"{self.credit_system_url}/health",
                headers={'X-API-Key': self.api_key},
                timeout=5
            )
            credit_system_status = "healthy" if response.status_code == 200 else "unhealthy"
        except Exception as e:
            credit_system_status = f"error: {str(e)}"
        
        # Add database queue status
        try:
            queue_status = self.db_manager.get_queue_status()
            health_status['details'] = {
                'database_queue': {
                    'queue_size': queue_status['queue_size'],
                    'worker_alive': queue_status['worker_alive'],
                    'queue_enabled': queue_status['queue_enabled'],
                    'pending_results': queue_status['pending_results']
                },
                'credit_system_connection': {
                    'status': credit_system_status,
                    'url': self.credit_system_url,
                    'api_key_configured': bool(self.api_key)
                }
            }
        except Exception as e:
            health_status['details'] = {
                'database_queue': f'error: {str(e)}',
                'credit_system_connection': {
                    'status': credit_system_status,
                    'url': self.credit_system_url,
                    'api_key_configured': bool(self.api_key)
                }
            }
        
        return health_status 