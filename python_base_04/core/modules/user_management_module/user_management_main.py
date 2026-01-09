from core.modules.base_module import BaseModule
from core.managers.database_manager import DatabaseManager
from core.managers.jwt_manager import JWTManager, TokenType
from core.managers.redis_manager import RedisManager
from tools.logger.custom_logging import custom_log
from utils.config.config import Config
from flask import request, jsonify
from datetime import datetime
from typing import Dict, Any
from bson import ObjectId
import bcrypt
import re
import secrets
import string
import requests as http_requests

# Lazy import for GoogleAuthService to avoid import errors if google-auth is not installed
try:
    from core.services.google_auth_service import GoogleAuthService
    GOOGLE_AUTH_AVAILABLE = True
except ImportError as e:
    GOOGLE_AUTH_AVAILABLE = False
    GoogleAuthService = None
    # Log at module level (before LOGGING_SWITCH is available)
    print(f"⚠️ UserManagement: Failed to import GoogleAuthService - ImportError: {e}")
except Exception as e:
    GOOGLE_AUTH_AVAILABLE = False
    GoogleAuthService = None
    import traceback
    print(f"⚠️ UserManagement: Failed to import GoogleAuthService - Unexpected error: {e}")
    print(f"⚠️ Traceback: {traceback.format_exc()}")

from core.services.analytics_service import AnalyticsService


class UserManagementModule(BaseModule):
    # Logging switch for guest registration and conversion testing
    LOGGING_SWITCH = false
    METRICS_SWITCH = True
    
    def __init__(self, app_manager=None):
        """Initialize the UserManagementModule."""
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

    def initialize(self, app_manager):
        """Initialize the UserManagementModule with AppManager."""
        self.app_manager = app_manager
        self.app = app_manager.flask_app
        self.initialize_database()
        self.register_routes()
        self._initialized = True

    def register_routes(self):
        """Register user management routes with clean authentication-aware system."""
        # Public routes (no authentication required)
        self._register_auth_route_helper("/public/users/info", self.get_public_user_info, methods=["GET"])
        self._register_auth_route_helper("/public/register", self.create_user, methods=["POST"])
        self._register_auth_route_helper("/public/register-guest", self.create_guest_user, methods=["POST"])
        self._register_auth_route_helper("/public/login", self.login_user, methods=["POST"])
        self._register_auth_route_helper("/public/google-signin", self.google_signin, methods=["POST"])
        
        # JWT authenticated routes (user authentication)
        self._register_auth_route_helper("/userauth/users/profile", self.get_user_profile, methods=["GET"])
        self._register_auth_route_helper("/userauth/users/profile", self.update_user_profile, methods=["PUT"])
        self._register_auth_route_helper("/userauth/users/settings", self.get_user_settings, methods=["GET"])
        self._register_auth_route_helper("/userauth/users/settings", self.update_user_settings, methods=["PUT"])
        self._register_auth_route_helper("/userauth/logout", self.logout_user, methods=["POST"])
        self._register_auth_route_helper("/userauth/me", self.get_current_user, methods=["GET"])
        
        # Public routes (no authentication required)
        self._register_auth_route_helper("/public/refresh", self.refresh_token, methods=["POST"])

    def initialize_database(self):
        """
        Verify database connection for user operations.
        
        Note: This method only verifies the database connection. It does NOT create
        collections, indexes, or seed data. Database structure setup is handled
        exclusively by Ansible playbooks (09 or 10).
        """
        try:
            # Check if database is available
            if not self.analytics_db.available:
                return
                
            # Simple connection test
            self.analytics_db.db.command('ping')
        except Exception as e:
            pass

    def create_user(self):
        """Create a new user account with comprehensive setup."""
        try:
            data = request.get_json()
            
            # Validate required fields
            required_fields = ["username", "email", "password"]
            for field in required_fields:
                if not data.get(field):
                    return jsonify({
                        "success": False,
                        "error": f"Missing required field: {field}"
                    }), 400
            
            username = data.get("username")
            email = data.get("email")
            password = data.get("password")
            
            # Check for guest account conversion
            convert_from_guest = data.get("convert_from_guest", False)
            guest_email = data.get("guest_email")
            guest_password = data.get("guest_password")
            guest_user = None
            
            # Log registration attempt
            if convert_from_guest:
                custom_log(f"UserManagement: Registration request received (with guest conversion) - Username: {username}, Email: {email}", level="INFO", isOn=UserManagementModule.LOGGING_SWITCH)
            else:
                custom_log(f"UserManagement: Regular registration request received - Username: {username}, Email: {email}", level="INFO", isOn=UserManagementModule.LOGGING_SWITCH)
            
            # Validate guest account if conversion requested
            if convert_from_guest:
                if not guest_email or not guest_password:
                    return jsonify({
                        "success": False,
                        "error": "Guest email and password are required for account conversion"
                    }), 400
                
                # Find guest user
                guest_user = self.db_manager.find_one("users", {"email": guest_email})
                if not guest_user:
                    return jsonify({
                        "success": False,
                        "error": "Guest account not found"
                    }), 404
                
                # Verify it's actually a guest account
                if guest_user.get("account_type") != "guest":
                    return jsonify({
                        "success": False,
                        "error": "Account is not a guest account"
                    }), 400
                
                # Verify guest password
                stored_password = guest_user.get("password", "").encode('utf-8')
                if not bcrypt.checkpw(guest_password.encode('utf-8'), stored_password):
                    return jsonify({
                        "success": False,
                        "error": "Invalid guest account password"
                    }), 401
                
                custom_log(f"UserManagement: Guest account conversion requested - Guest Email: {guest_email}, New Email: {email}", level="INFO", isOn=UserManagementModule.LOGGING_SWITCH)
            
            # Validate email format
            if not self._is_valid_email(email):
                return jsonify({
                    "success": False,
                    "error": "Invalid email format"
                }), 400
            
            # Validate password strength
            if not self._is_valid_password(password):
                return jsonify({
                    "success": False,
                    "error": "Password must be at least 8 characters long"
                }), 400
            
            # Check if user already exists
            existing_user = self.db_manager.find_one("users", {"email": email})
            if existing_user:
                return jsonify({
                    "success": False,
                    "error": "User with this email already exists"
                }), 409
            
            existing_username = self.db_manager.find_one("users", {"username": username})
            if existing_username:
                return jsonify({
                    "success": False,
                    "error": "Username already taken"
                }), 409
            
            # Hash password
            hashed_password = bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt())
            
            # Get current timestamp for consistent date formatting
            current_time = datetime.utcnow()
            
            # Prepare user data - either from guest account or new structure
            if convert_from_guest and guest_user:
                # Copy all data from guest account except username, email, password, account_type, _id
                guest_data = guest_user.copy()
                
                # Start with new credentials
                user_data = {
                    'username': username,
                    'email': email,
                    'password': hashed_password.decode('utf-8'),
                    'account_type': 'normal',  # Changed from 'guest'
                    'status': guest_data.get('status', 'active'),
                    'created_at': guest_data.get('created_at', current_time.isoformat()),  # Preserve original creation date
                    'updated_at': current_time.isoformat(),
                    'last_login': guest_data.get('last_login'),
                    'login_count': guest_data.get('login_count', 0),
                }
                
                # Copy all other fields from guest account
                fields_to_copy = ['profile', 'preferences', 'modules', 'audit']
                for field in fields_to_copy:
                    if field in guest_data:
                        user_data[field] = guest_data[field]
                
                # Ensure all module fields are preserved (in case guest account has custom modules)
                if 'modules' not in user_data:
                    user_data['modules'] = {}
                elif isinstance(user_data['modules'], dict):
                    # Preserve all existing modules from guest account
                    pass  # Already copied above
                
                custom_log(f"UserManagement: Copied guest account data for conversion - Preserving modules: {list(user_data.get('modules', {}).keys())}", level="INFO", isOn=UserManagementModule.LOGGING_SWITCH)
            else:
                # Prepare user data with comprehensive structure (new account)
                user_data = {
                # Core fields
                'username': username,
                'email': email,
                'password': hashed_password.decode('utf-8'),
                'status': 'active',
                'created_at': current_time.isoformat(),
                'updated_at': current_time.isoformat(),
                'last_login': None,
                'login_count': 0,
                
                # Profile section
                'profile': {
                    'first_name': data.get('first_name', ''),
                    'last_name': data.get('last_name', ''),
                    'phone': data.get('phone', ''),
                    'timezone': data.get('timezone', 'UTC'),
                    'language': data.get('language', 'en')
                },
                
                # Preferences section
                'preferences': {
                    'notifications': {
                        'email': data.get('notifications_email', True),
                        'sms': data.get('notifications_sms', False),
                        'push': data.get('notifications_push', True)
                    },
                    'privacy': {
                        'profile_visible': data.get('profile_visible', True),
                        'activity_visible': data.get('activity_visible', False)
                    }
                },
                
                # Modules section with default configurations
                'modules': {
                    'wallet': {
                        'enabled': True,
                        'balance': 0,
                        'currency': 'credits',
                        'last_updated': current_time.isoformat()
                    },
                    'subscription': {
                        'enabled': False,
                        'plan': None,
                        'expires_at': None
                    },
                    'referrals': {
                        'enabled': True,
                        'referral_code': f"{username.upper()}{current_time.strftime('%Y%m')}",
                        'referrals_count': 0
                    },
                    'dutch_game': {
                        'enabled': True,
                        'wins': 0,
                        'losses': 0,
                        'total_matches': 0,
                        'points': 0,
                        'level': 1,
                        'rank': 'beginner',
                        'win_rate': 0.0,
                        'subscription_tier': 'promotional',
                        'last_match_date': None,
                        'last_updated': current_time.isoformat()
                    }
                },
                
                # Audit section
                'audit': {
                    'last_login': None,
                    'login_count': 0,
                    'password_changed_at': current_time.isoformat(),
                    'profile_updated_at': current_time.isoformat()
                }
            }
            
            # Insert user using database manager
            user_id = self.db_manager.insert("users", user_data)
            
            if not user_id:
                return jsonify({
                    "success": False,
                    "error": "Failed to create user account"
                }), 500
            
            # If guest account conversion, delete the guest account
            if convert_from_guest and guest_user:
                try:
                    guest_user_id = guest_user.get("_id")
                    if guest_user_id:
                        delete_result = self.db_manager.delete("users", {"_id": ObjectId(guest_user_id)})
                        if delete_result:
                            custom_log(f"UserManagement: Successfully deleted guest account after conversion - Guest ID: {guest_user_id}", level="INFO", isOn=UserManagementModule.LOGGING_SWITCH)
                        else:
                            custom_log(f"UserManagement: Warning - Failed to delete guest account after conversion - Guest ID: {guest_user_id}", level="WARNING", isOn=UserManagementModule.LOGGING_SWITCH)
                except Exception as e:
                    # Log error but don't fail registration (data integrity maintained)
                    custom_log(f"UserManagement: Error deleting guest account after conversion: {e}", level="ERROR", isOn=UserManagementModule.LOGGING_SWITCH)
            
            # Remove password from response
            user_data.pop('password', None)
            user_data['_id'] = user_id
            
            # Trigger user_created hook for other modules to listen to
            if self.app_manager:
                # Import config to get app identification
                from utils.config.config import Config
                
                hook_data = {
                    'user_id': user_id,
                    'username': username,
                    'email': email,  # Raw email from request (non-encrypted)
                    'user_data': user_data,
                    'created_at': current_time.isoformat(),
                    'app_id': Config.APP_ID,
                    'app_name': Config.APP_NAME,
                    'source': 'external_app',
                    'account_type': 'normal' if not convert_from_guest else 'converted_from_guest'
                }
                self.app_manager.trigger_hook("user_created", hook_data)
            
            # Log successful registration
            if convert_from_guest:
                custom_log(f"UserManagement: Guest account conversion completed successfully - User ID: {user_id}, Username: {username}, Email: {email}", level="INFO", isOn=UserManagementModule.LOGGING_SWITCH)
                # Track event in analytics service (automatically updates metrics)
                analytics_service = self.app_manager.services_manager.get_service('analytics_service') if self.app_manager else None
                if analytics_service:
                    analytics_service.track_event(
                        user_id=str(user_id),
                        event_type='guest_account_converted',
                        event_data={
                            'conversion_method': 'email',
                            'guest_user_id': str(guest_user.get('_id')) if guest_user else None
                        }
                    )
                    analytics_service.track_event(
                        user_id=str(user_id),
                        event_type='user_registered',
                        event_data={
                            'registration_type': 'email',
                            'account_type': 'normal',
                            'converted_from_guest': True
                        }
                    )
            else:
                custom_log(f"UserManagement: Regular registration completed successfully - User ID: {user_id}, Username: {username}, Email: {email}", level="INFO", isOn=UserManagementModule.LOGGING_SWITCH)
                # Track event in analytics service (automatically updates metrics)
                analytics_service = self.app_manager.services_manager.get_service('analytics_service') if self.app_manager else None
                if analytics_service:
                    analytics_service.track_event(
                        user_id=str(user_id),
                        event_type='user_registered',
                        event_data={
                            'registration_type': 'email',
                            'account_type': 'normal'
                        },
                        metrics_enabled=UserManagementModule.METRICS_SWITCH
                    )
            
            return jsonify({
                "success": True,
                "message": "User created successfully",
                "data": {
                    "user": user_data
                }
            }), 201
            
        except Exception as e:
            return jsonify({
                "success": False,
                "error": "Internal server error"
            }), 500

    def _generate_guest_username(self):
        """Generate unique guest username in format Guest_*******"""
        custom_log("UserManagement: Starting guest username generation", level="INFO", isOn=UserManagementModule.LOGGING_SWITCH)
        max_attempts = 10
        for attempt in range(max_attempts):
            random_id = ''.join(secrets.choice(string.ascii_lowercase + string.digits) for _ in range(8))
            username = f"Guest_{random_id}"
            custom_log(f"UserManagement: Generated candidate username: {username} (attempt {attempt + 1}/{max_attempts})", level="DEBUG", isOn=UserManagementModule.LOGGING_SWITCH)
            # Check uniqueness
            existing = self.db_manager.find_one("users", {"username": username})
            if not existing:
                custom_log(f"UserManagement: Unique guest username generated: {username}", level="INFO", isOn=UserManagementModule.LOGGING_SWITCH)
                return username
            else:
                custom_log(f"UserManagement: Username collision detected: {username}, retrying...", level="DEBUG", isOn=UserManagementModule.LOGGING_SWITCH)
        custom_log("UserManagement: Failed to generate unique guest username after 10 attempts", level="ERROR", isOn=UserManagementModule.LOGGING_SWITCH)
        raise Exception("Failed to generate unique guest username")

    def create_guest_user(self):
        """Create a new guest user account with auto-generated credentials."""
        custom_log("UserManagement: Guest registration request received", level="INFO", isOn=UserManagementModule.LOGGING_SWITCH)
        try:
            # Generate unique guest username
            username = self._generate_guest_username()
            
            # Generate email from username
            email = f"guest_{username}@guest.local"
            
            # Use username as password
            password = username
            
            custom_log(f"UserManagement: Generated guest credentials - Username: {username}, Email: {email}", level="INFO", isOn=UserManagementModule.LOGGING_SWITCH)
            
            # Hash password
            hashed_password = bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt())
            custom_log("UserManagement: Password hashed successfully", level="DEBUG", isOn=UserManagementModule.LOGGING_SWITCH)
            
            # Get current timestamp for consistent date formatting
            current_time = datetime.utcnow()
            
            # Prepare user data with comprehensive structure (same as regular user)
            user_data = {
                # Core fields
                'username': username,
                'email': email,
                'password': hashed_password.decode('utf-8'),
                'status': 'active',
                'account_type': 'guest',  # Mark as guest account
                'created_at': current_time.isoformat(),
                'updated_at': current_time.isoformat(),
                'last_login': None,
                'login_count': 0,
                
                # Profile section
                'profile': {
                    'first_name': '',
                    'last_name': '',
                    'phone': '',
                    'timezone': 'UTC',
                    'language': 'en'
                },
                
                # Preferences section
                'preferences': {
                    'notifications': {
                        'email': False,  # Guest accounts don't need email notifications
                        'sms': False,
                        'push': True
                    },
                    'privacy': {
                        'profile_visible': True,
                        'activity_visible': False
                    }
                },
                
                # Modules section with default configurations
                'modules': {
                    'wallet': {
                        'enabled': True,
                        'balance': 0,
                        'currency': 'credits',
                        'last_updated': current_time.isoformat()
                    },
                    'subscription': {
                        'enabled': False,
                        'plan': None,
                        'expires_at': None
                    },
                    'referrals': {
                        'enabled': True,
                        'referral_code': f"{username.upper()}{current_time.strftime('%Y%m')}",
                        'referrals_count': 0
                    },
                    'dutch_game': {
                        'enabled': True,
                        'wins': 0,
                        'losses': 0,
                        'total_matches': 0,
                        'points': 0,
                        'level': 1,
                        'rank': 'beginner',
                        'win_rate': 0.0,
                        'subscription_tier': 'promotional',
                        'last_match_date': None,
                        'last_updated': current_time.isoformat()
                    }
                },
                
                # Audit section
                'audit': {
                    'last_login': None,
                    'login_count': 0,
                    'password_changed_at': current_time.isoformat(),
                    'profile_updated_at': current_time.isoformat()
                }
            }
            
            # Insert user using database manager
            custom_log(f"UserManagement: Inserting guest user into database: {username}", level="DEBUG", isOn=UserManagementModule.LOGGING_SWITCH)
            user_id = self.db_manager.insert("users", user_data)
            
            if not user_id:
                custom_log(f"UserManagement: Failed to insert guest user into database: {username}", level="ERROR", isOn=UserManagementModule.LOGGING_SWITCH)
                return jsonify({
                    "success": False,
                    "error": "Failed to create guest account"
                }), 500
            
            custom_log(f"UserManagement: Guest user created successfully - User ID: {user_id}, Username: {username}", level="INFO", isOn=UserManagementModule.LOGGING_SWITCH)
            
            # Remove password from response
            user_data.pop('password', None)
            user_data['_id'] = user_id
            
            # Trigger user_created hook for other modules to listen to
            if self.app_manager:
                # Import config to get app identification
                from utils.config.config import Config
                
                hook_data = {
                    'user_id': user_id,
                    'username': username,
                    'email': email,  # Auto-generated email
                    'user_data': user_data,
                    'created_at': current_time.isoformat(),
                    'app_id': Config.APP_ID,
                    'app_name': Config.APP_NAME,
                    'source': 'external_app',
                    'account_type': 'guest'
                }
                custom_log(f"UserManagement: Triggering user_created hook for guest user: {user_id}", level="DEBUG", isOn=UserManagementModule.LOGGING_SWITCH)
                self.app_manager.trigger_hook("user_created", hook_data)
            
            custom_log(f"UserManagement: Guest registration completed successfully - User ID: {user_id}, Username: {username}", level="INFO", isOn=UserManagementModule.LOGGING_SWITCH)
            
            # Track event in analytics service (automatically updates metrics)
            analytics_service = self.app_manager.services_manager.get_service('analytics_service') if self.app_manager else None
            if analytics_service:
                analytics_service.track_event(
                    user_id=str(user_id),
                    event_type='guest_account_created',
                    event_data={
                        'registration_type': 'guest',
                        'account_type': 'guest'
                    }
                )
            
            return jsonify({
                "success": True,
                "message": "Guest account created successfully",
                "data": {
                    "user": user_data,
                    "credentials": {
                        "username": username,
                        "email": email,
                        "password": password  # Return password so frontend can store it
                    }
                }
            }), 201
            
        except Exception as e:
            custom_log(f"Error creating guest user: {e}", level="ERROR", isOn=UserManagementModule.LOGGING_SWITCH)
            return jsonify({
                "success": False,
                "error": "Internal server error"
            }), 500

    def get_user(self, user_id):
        """Get user by ID with queued operation."""
        try:
            user = self.analytics_db.find_one("users", {"_id": user_id})
            if not user:
                return jsonify({'error': 'User not found'}), 404
            
            # Remove password from response
            user.pop('password', None)
            return jsonify(user), 200
            
        except Exception as e:
            return jsonify({'error': 'Failed to get user'}), 500

    def update_user(self, user_id):
        """Update user information with queued operation."""
        try:
            data = request.get_json()
            update_data = {'updated_at': datetime.utcnow().isoformat()}
            
            # Only update allowed fields
            allowed_fields = ['username', 'email', 'status']
            for field in allowed_fields:
                if field in data:
                    update_data[field] = data[field]
            
            # Update user using queue system
            modified_count = self.db_manager.update("users", {"_id": user_id}, {"$set": update_data})
            
            if modified_count > 0:
                return jsonify({
                    'message': 'User updated successfully',
                    'user_id': user_id,
                    'status': 'updated'
                }), 200
            else:
                return jsonify({'error': 'User not found or no changes made'}), 404
                
        except Exception as e:
            return jsonify({'error': 'Failed to update user'}), 500

    def delete_user(self, user_id):
        """Delete a user with queued operation."""
        try:
            # Delete user using queue system
            deleted_count = self.db_manager.delete("users", {"_id": user_id})
            
            if deleted_count > 0:
                return jsonify({
                    'message': 'User deleted successfully',
                    'user_id': user_id,
                    'status': 'deleted'
                }), 200
            else:
                return jsonify({'error': 'User not found'}), 404
                
        except Exception as e:
            return jsonify({'error': 'Failed to delete user'}), 500

    def search_users(self):
        """Search users with filters using queued operation."""
        try:
            data = request.get_json()
            query = {}
            
            if 'username' in data:
                query['username'] = {'$regex': data['username'], '$options': 'i'}
            if 'email' in data:
                query['email'] = {'$regex': data['email'], '$options': 'i'}
            if 'status' in data:
                query['status'] = data['status']
            
            # Search users using queue system
            users = self.analytics_db.find("users", query)
            
            # Remove passwords from response
            for user in users:
                user.pop('password', None)
            
            return jsonify({'users': users}), 200
            
        except Exception as e:
            return jsonify({'error': 'Failed to search users'}), 500





    def login_user(self):
        """Authenticate user and return JWT tokens."""
        try:
            data = request.get_json()
            
            # Validate required fields
            if not data.get("email") or not data.get("password"):
                return jsonify({
                    "success": False,
                    "error": "Email and password are required"
                }), 400
            
            email = data.get("email")
            password = data.get("password")
            
            # Use direct email query instead of fetching all users
            user = self.db_manager.find_one("users", {"email": email})
            
            if not user:
                return jsonify({
                    "success": False,
                    "error": "Invalid email or password"
                }), 401
            
            # Check if user is active
            if user.get("status") != "active":
                return jsonify({
                    "success": False,
                    "error": "Account is not active"
                }), 401
            
            # Verify password
            stored_password = user.get("password", "")
            account_type = user.get("account_type", "normal")  # Default to 'normal' to match registration
            is_guest = account_type == "guest"
            
            if is_guest:
                custom_log(f"UserManagement: Guest account login attempt - Email: {email}, Username: {user.get('username')}", level="INFO", isOn=UserManagementModule.LOGGING_SWITCH)
            else:
                custom_log(f"UserManagement: Regular account login attempt - Email: {email}", level="DEBUG", isOn=UserManagementModule.LOGGING_SWITCH)
            
            try:
                check_result = bcrypt.checkpw(password.encode('utf-8'), stored_password.encode('utf-8'))
            except Exception as e:
                custom_log(f"UserManagement: Password verification error: {e}", level="ERROR", isOn=UserManagementModule.LOGGING_SWITCH)
                check_result = False
            
            if not check_result:
                custom_log(f"UserManagement: Login failed - Invalid password for email: {email}", level="WARNING", isOn=UserManagementModule.LOGGING_SWITCH)
                return jsonify({
                    "success": False,
                    "error": "Invalid email or password"
                }), 401
            
            # Update last login and login count using queue system
            update_data = {
                "last_login": datetime.utcnow().isoformat(),
                "login_count": user.get("login_count", 0) + 1,
                "updated_at": datetime.utcnow().isoformat()
            }
            
            self.db_manager.update("users", {"_id": user["_id"]}, update_data)
            
            # Create JWT tokens
            access_token_payload = {
                'user_id': str(user['_id']),
                'username': user['username'],
                'email': email,  # Use the original email parameter, not the encrypted one from database
                'type': 'access'
            }
            
            refresh_token_payload = {
                'user_id': str(user['_id']),
                'type': 'refresh'
            }
            
            # Get JWT manager from app_manager
            jwt_manager = self.app_manager.jwt_manager
            access_token = jwt_manager.create_token(access_token_payload, TokenType.ACCESS)
            refresh_token = jwt_manager.create_token(refresh_token_payload, TokenType.REFRESH)
            
            # Remove password from response
            user.pop('password', None)
            
            # Ensure account_type is included in response (for Flutter to determine guest status)
            if 'account_type' not in user:
                user['account_type'] = account_type
            
            # Log successful login with account type
            if is_guest:
                custom_log(f"UserManagement: Guest account login successful - User ID: {user['_id']}, Username: {user.get('username')}, Account Type: {account_type}", level="INFO", isOn=UserManagementModule.LOGGING_SWITCH)
            else:
                custom_log(f"UserManagement: Regular account login successful - User ID: {user['_id']}, Email: {email}, Account Type: {account_type}", level="INFO", isOn=UserManagementModule.LOGGING_SWITCH)
            
            # Track event in analytics service (automatically updates metrics)
            analytics_service = self.app_manager.services_manager.get_service('analytics_service') if self.app_manager else None
            if analytics_service:
                analytics_service.track_event(
                    user_id=str(user['_id']),
                    event_type='user_logged_in',
                    event_data={
                        'auth_method': 'email',
                        'account_type': account_type
                    },
                    metrics_enabled=UserManagementModule.METRICS_SWITCH
                )
            
            return jsonify({
                "success": True,
                "message": "Login successful",
                "data": {
                    "user": user,
                    "access_token": access_token,
                    "refresh_token": refresh_token,
                    "token_type": "Bearer",
                    "expires_in": Config.JWT_ACCESS_TOKEN_EXPIRES,  # Access token TTL
                    "refresh_expires_in": Config.JWT_REFRESH_TOKEN_EXPIRES  # Refresh token TTL
                }
            }), 200
            
        except Exception as e:
            custom_log(f"UserManagement: Login error: {e}", level="ERROR", isOn=UserManagementModule.LOGGING_SWITCH)
            return jsonify({
                "success": False,
                "error": "Internal server error"
            }), 500

    def google_signin(self):
        """Handle Google Sign-In authentication."""
        try:
            data = request.get_json()
            
            # Check for guest account conversion
            convert_from_guest = data.get("convert_from_guest", False)
            guest_email = data.get("guest_email")
            guest_password = data.get("guest_password")
            guest_user = None
            
            # Check if we have ID token or access token
            id_token_string = data.get("id_token")
            access_token = data.get("access_token")
            user_info_from_client = data.get("user_info")  # For web fallback
            
            user_info = None
            
            if id_token_string:
                # Preferred: Verify ID token (requires GoogleAuthService)
                custom_log(f"UserManagement: Google Sign-In - GOOGLE_AUTH_AVAILABLE={GOOGLE_AUTH_AVAILABLE}, GoogleAuthService={GoogleAuthService}", level="DEBUG", isOn=UserManagementModule.LOGGING_SWITCH)
                
                if not GOOGLE_AUTH_AVAILABLE or GoogleAuthService is None:
                    custom_log(f"UserManagement: GoogleAuthService not available - GOOGLE_AUTH_AVAILABLE={GOOGLE_AUTH_AVAILABLE}, GoogleAuthService={GoogleAuthService}", level="ERROR", isOn=UserManagementModule.LOGGING_SWITCH)
                    return jsonify({
                        "success": False,
                        "error": "Google Sign-In with ID token requires google-auth package. Please install it."
                    }), 503
                
                custom_log("UserManagement: Google Sign-In - Using ID token", level="INFO", isOn=UserManagementModule.LOGGING_SWITCH)
                google_auth_service = GoogleAuthService()
                custom_log(f"UserManagement: GoogleAuthService initialized with client_id: {google_auth_service.client_id[:20] if google_auth_service.client_id else 'None'}...", level="INFO", isOn=UserManagementModule.LOGGING_SWITCH)
                user_info = google_auth_service.get_user_info(id_token_string)
                if not user_info:
                    custom_log("UserManagement: Google Sign-In - get_user_info returned None (token verification failed)", level="ERROR", isOn=UserManagementModule.LOGGING_SWITCH)
                else:
                    custom_log(f"UserManagement: Google Sign-In - User info obtained: email={user_info.get('email')}", level="INFO", isOn=UserManagementModule.LOGGING_SWITCH)
            elif access_token and user_info_from_client:
                # Fallback for web: Verify access token and use provided user info
                custom_log("UserManagement: Google Sign-In - Using access token (web fallback)", level="INFO", isOn=UserManagementModule.LOGGING_SWITCH)
                
                # Verify access token by calling Google's tokeninfo endpoint
                try:
                    token_info_response = http_requests.get(
                        f'https://www.googleapis.com/oauth2/v1/tokeninfo?access_token={access_token}',
                        timeout=10
                    )
                    
                    if token_info_response.status_code == 200:
                        token_info = token_info_response.json()
                        custom_log(f"UserManagement: Token info received: {token_info}", level="DEBUG", isOn=UserManagementModule.LOGGING_SWITCH)
                        
                        # Verify the token is valid
                        # For web tokens, we check if the email matches and token is valid
                        token_email = token_info.get('email')
                        client_email = user_info_from_client.get('email')
                        
                        # Verify email matches (if both are present)
                        if token_email and client_email and token_email != client_email:
                            custom_log(f"UserManagement: Email mismatch - token: {token_email}, client: {client_email}", level="WARNING", isOn=UserManagementModule.LOGGING_SWITCH)
                            return jsonify({
                                "success": False,
                                "error": "Token email mismatch"
                            }), 401
                        
                        # Verify client ID if configured (optional check)
                        if Config.GOOGLE_CLIENT_ID:
                            token_audience = token_info.get('audience') or token_info.get('issued_to')
                            if token_audience and token_audience != Config.GOOGLE_CLIENT_ID:
                                custom_log(f"UserManagement: Client ID mismatch - token: {token_audience}, config: {Config.GOOGLE_CLIENT_ID}", level="WARNING", isOn=UserManagementModule.LOGGING_SWITCH)
                                # Still proceed if email matches - web tokens might have different audience format
                        
                        # Use user info from client (already fetched from userinfo endpoint)
                        user_info = {
                            'google_id': user_info_from_client.get('id'),
                            'email': user_info_from_client.get('email') or token_email,
                            'email_verified': user_info_from_client.get('verified_email', False) or token_info.get('verified_email', False),
                            'name': user_info_from_client.get('name'),
                            'picture': user_info_from_client.get('picture'),
                            'given_name': user_info_from_client.get('given_name'),
                            'family_name': user_info_from_client.get('family_name')
                        }
                        custom_log(f"UserManagement: Access token verified, user info: {user_info.get('email')}", level="INFO", isOn=UserManagementModule.LOGGING_SWITCH)
                    else:
                        error_text = token_info_response.text[:200] if token_info_response.text else "Unknown error"
                        custom_log(f"UserManagement: Access token verification failed: {token_info_response.status_code} - {error_text}", level="WARNING", isOn=UserManagementModule.LOGGING_SWITCH)
                        return jsonify({
                            "success": False,
                            "error": f"Invalid access token: {token_info_response.status_code}"
                        }), 401
                except Exception as e:
                    custom_log(f"UserManagement: Error verifying access token: {e}", level="ERROR", isOn=UserManagementModule.LOGGING_SWITCH)
                    import traceback
                    custom_log(f"UserManagement: Traceback: {traceback.format_exc()}", level="ERROR", isOn=UserManagementModule.LOGGING_SWITCH)
                    return jsonify({
                        "success": False,
                        "error": f"Error verifying token: {str(e)}"
                    }), 500
            
            # Validate that we have user info
            if not id_token_string and not access_token:
                return jsonify({
                    "success": False,
                    "error": "Google ID token or access token is required"
                }), 400
            
            if not user_info:
                return jsonify({
                    "success": False,
                    "error": "Invalid or expired Google token"
                }), 401
            
            email = user_info.get('email')
            google_id = user_info.get('google_id')
            name = user_info.get('name', '')
            given_name = user_info.get('given_name', '')
            family_name = user_info.get('family_name', '')
            picture = user_info.get('picture')
            
            if not email:
                return jsonify({
                    "success": False,
                    "error": "Email not provided by Google"
                }), 400
            
            # Validate guest account if conversion requested
            if convert_from_guest:
                if not guest_email or not guest_password:
                    return jsonify({
                        "success": False,
                        "error": "Guest email and password are required for account conversion"
                    }), 400
                
                # Find guest user
                guest_user = self.db_manager.find_one("users", {"email": guest_email})
                if not guest_user:
                    return jsonify({
                        "success": False,
                        "error": "Guest account not found"
                    }), 404
                
                # Verify it's actually a guest account
                if guest_user.get("account_type") != "guest":
                    return jsonify({
                        "success": False,
                        "error": "Account is not a guest account"
                    }), 400
                
                # Verify guest password
                stored_password = guest_user.get("password", "").encode('utf-8')
                if not bcrypt.checkpw(guest_password.encode('utf-8'), stored_password):
                    return jsonify({
                        "success": False,
                        "error": "Invalid guest account password"
                    }), 401
                
                custom_log(f"UserManagement: Google Sign-In with guest account conversion requested - Guest Email: {guest_email}, Google Email: {email}", level="INFO", isOn=UserManagementModule.LOGGING_SWITCH)
            
            # Check if user exists by email
            existing_user = self.db_manager.find_one("users", {"email": email})
            
            if existing_user:
                # User exists - handle account linking or login
                auth_providers = existing_user.get('auth_providers', [])
                
                # Check if Google is already linked
                if 'google' in auth_providers:
                    # Normal Google login
                    custom_log(f"UserManagement: Google Sign-In - Existing user with Google auth - Email: {email}", level="INFO", isOn=UserManagementModule.LOGGING_SWITCH)
                else:
                    # Link Google account to existing account
                    custom_log(f"UserManagement: Google Sign-In - Linking Google to existing account - Email: {email}", level="INFO", isOn=UserManagementModule.LOGGING_SWITCH)
                    
                    # Update auth_providers to include Google
                    if not auth_providers:
                        auth_providers = ['email']  # Assume email if not set
                    if 'google' not in auth_providers:
                        auth_providers.append('google')
                    
                    # Update user document
                    update_data = {
                        'auth_providers': auth_providers,
                        'google_id': google_id,
                        'updated_at': datetime.utcnow().isoformat()
                    }
                    
                    # Update profile if Google provides better info
                    if given_name or family_name:
                        if 'profile' not in existing_user:
                            existing_user['profile'] = {}
                        if given_name and not existing_user['profile'].get('first_name'):
                            update_data['profile.first_name'] = given_name
                        if family_name and not existing_user['profile'].get('last_name'):
                            update_data['profile.last_name'] = family_name
                    
                    self.db_manager.update("users", {"_id": existing_user["_id"]}, update_data)
                
                user = existing_user
            else:
                # New user - create account with Google info
                custom_log(f"UserManagement: Google Sign-In - Creating new user - Email: {email}", level="INFO", isOn=UserManagementModule.LOGGING_SWITCH)
                
                # Generate username from email or name
                if given_name and family_name:
                    # Try to create username from name
                    base_username = f"{given_name.lower()}{family_name.lower()}"
                    base_username = re.sub(r'[^a-z0-9]', '', base_username)
                    if len(base_username) < 3:
                        base_username = email.split('@')[0].lower()
                        base_username = re.sub(r'[^a-z0-9]', '', base_username)
                else:
                    # Use email prefix
                    base_username = email.split('@')[0].lower()
                    base_username = re.sub(r'[^a-z0-9]', '', base_username)
                
                # Ensure username meets requirements (3-20 chars, valid format)
                if len(base_username) < 3:
                    base_username = base_username + "123"
                if len(base_username) > 20:
                    base_username = base_username[:20]
                
                # Check uniqueness and generate unique username if needed
                username = base_username
                max_attempts = 10
                for attempt in range(max_attempts):
                    existing = self.db_manager.find_one("users", {"username": username})
                    if not existing:
                        break
                    # Append random suffix
                    suffix = ''.join(secrets.choice(string.ascii_lowercase + string.digits) for _ in range(4))
                    username = f"{base_username[:16]}{suffix}"
                
                # If still not unique, use timestamp
                existing = self.db_manager.find_one("users", {"username": username})
                if existing:
                    timestamp = datetime.utcnow().strftime('%Y%m%d%H%M%S')
                    username = f"{base_username[:10]}{timestamp[-6:]}"
                
                # Create user data structure - either from guest account or new structure
                current_time = datetime.utcnow()
                
                if convert_from_guest and guest_user:
                    # Copy all data from guest account except username, email, password, account_type, _id
                    guest_data = guest_user.copy()
                    
                    # Start with new credentials
                    user_data = {
                        'username': username,
                        'email': email,
                        'password': '',  # No password for Google-only accounts
                        'account_type': 'normal',  # Changed from 'guest'
                        'auth_providers': ['google'],
                        'google_id': google_id,
                        'status': guest_data.get('status', 'active'),
                        'created_at': guest_data.get('created_at', current_time.isoformat()),  # Preserve original creation date
                        'updated_at': current_time.isoformat(),
                        'last_login': guest_data.get('last_login'),
                        'login_count': guest_data.get('login_count', 0),
                    }
                    
                    # Copy all other fields from guest account
                    fields_to_copy = ['profile', 'preferences', 'modules', 'audit']
                    for field in fields_to_copy:
                        if field in guest_data:
                            user_data[field] = guest_data[field]
                    
                    # Update profile with Google info if available
                    if 'profile' not in user_data:
                        user_data['profile'] = {}
                    if given_name:
                        user_data['profile']['first_name'] = given_name
                    if family_name:
                        user_data['profile']['last_name'] = family_name
                    if picture:
                        user_data['profile']['picture'] = picture
                    
                    custom_log(f"UserManagement: Copied guest account data for Google Sign-In conversion - Preserving modules: {list(user_data.get('modules', {}).keys())}", level="INFO", isOn=UserManagementModule.LOGGING_SWITCH)
                else:
                    # Prepare user data with comprehensive structure (new account)
                    user_data = {
                        'username': username,
                        'email': email,
                        'password': '',  # No password for Google-only accounts
                        'status': 'active',
                        'account_type': 'normal',
                        'auth_providers': ['google'],
                        'google_id': google_id,
                        'created_at': current_time.isoformat(),
                        'updated_at': current_time.isoformat(),
                        'last_login': None,
                        'login_count': 0,
                        
                        # Profile section
                        'profile': {
                            'first_name': given_name or '',
                            'last_name': family_name or '',
                            'phone': '',
                            'timezone': 'UTC',
                            'language': 'en',
                            'picture': picture or ''
                        },
                        
                        # Preferences section
                        'preferences': {
                            'notifications': {
                                'email': True,
                                'sms': False,
                                'push': True
                            },
                            'privacy': {
                                'profile_visible': True,
                                'activity_visible': False
                            }
                        },
                        
                        # Modules section with default configurations
                        'modules': {
                            'wallet': {
                                'enabled': True,
                                'balance': 0,
                                'currency': 'credits',
                                'last_updated': current_time.isoformat()
                            },
                            'subscription': {
                                'enabled': False,
                                'plan': None,
                                'expires_at': None
                            },
                            'referrals': {
                                'enabled': True,
                                'referral_code': f"{username.upper()}{current_time.strftime('%Y%m')}",
                                'referrals_count': 0
                            },
                            'dutch_game': {
                                'enabled': True,
                                'wins': 0,
                                'losses': 0,
                                'total_matches': 0,
                                'points': 0,
                                'level': 1,
                                'rank': 'beginner',
                                'win_rate': 0.0,
                                'subscription_tier': 'promotional',
                                'last_match_date': None,
                                'last_updated': current_time.isoformat()
                            }
                        },
                        
                        # Audit section
                        'audit': {
                            'last_login': None,
                            'login_count': 0,
                            'password_changed_at': None,
                            'profile_updated_at': current_time.isoformat()
                        }
                    }
                
                # Insert user
                user_id = self.db_manager.insert("users", user_data)
                
                if not user_id:
                    return jsonify({
                        "success": False,
                        "error": "Failed to create user account"
                    }), 500
                
                # If guest account conversion, delete the guest account
                if convert_from_guest and guest_user:
                    try:
                        guest_user_id = guest_user.get("_id")
                        if guest_user_id:
                            delete_result = self.db_manager.delete("users", {"_id": ObjectId(guest_user_id)})
                            if delete_result:
                                custom_log(f"UserManagement: Successfully deleted guest account after Google Sign-In conversion - Guest ID: {guest_user_id}", level="INFO", isOn=UserManagementModule.LOGGING_SWITCH)
                            else:
                                custom_log(f"UserManagement: Warning - Failed to delete guest account after Google Sign-In conversion - Guest ID: {guest_user_id}", level="WARNING", isOn=UserManagementModule.LOGGING_SWITCH)
                    except Exception as e:
                        # Log error but don't fail registration (data integrity maintained)
                        custom_log(f"UserManagement: Error deleting guest account after Google Sign-In conversion: {e}", level="ERROR", isOn=UserManagementModule.LOGGING_SWITCH)
                
                # Get the created user
                user = self.db_manager.find_one("users", {"_id": user_id})
                
                # Trigger user_created hook
                if self.app_manager:
                    hook_data = {
                        'user_id': user_id,
                        'username': username,
                        'email': email,
                        'user_data': user_data,
                        'created_at': current_time.isoformat(),
                        'app_id': Config.APP_ID,
                        'app_name': Config.APP_NAME,
                        'source': 'external_app',
                        'auth_provider': 'google'
                    }
                    if convert_from_guest:
                        hook_data['converted_from_guest'] = True
                        hook_data['guest_user_id'] = str(guest_user.get("_id")) if guest_user else None
                    self.app_manager.trigger_hook("user_created", hook_data)
                    
                    if convert_from_guest:
                        custom_log(f"UserManagement: Google Sign-In with guest account conversion completed successfully - User ID: {user_id}, Username: {username}, Email: {email}", level="INFO", isOn=UserManagementModule.LOGGING_SWITCH)
                        # Track events in analytics service (automatically updates metrics)
                        analytics_service = self.app_manager.services_manager.get_service('analytics_service') if self.app_manager else None
                        if analytics_service:
                            analytics_service.track_event(
                                user_id=str(user_id),
                                event_type='guest_account_converted',
                                event_data={
                                    'conversion_method': 'google',
                                    'guest_user_id': str(guest_user.get('_id')) if guest_user else None
                                },
                                metrics_enabled=UserManagementModule.METRICS_SWITCH
                            )
                            analytics_service.track_event(
                                user_id=str(user_id),
                                event_type='user_registered',
                                event_data={
                                    'registration_type': 'google',
                                    'account_type': 'normal',
                                    'converted_from_guest': True
                                },
                                metrics_enabled=UserManagementModule.METRICS_SWITCH
                            )
                    else:
                        # Track event in analytics service (automatically updates metrics)
                        analytics_service = self.app_manager.services_manager.get_service('analytics_service') if self.app_manager else None
                        if analytics_service:
                            analytics_service.track_event(
                                user_id=str(user_id),
                                event_type='user_registered',
                                event_data={
                                    'registration_type': 'google',
                                    'account_type': 'normal'
                                }
                            )
            
            # Check if user is active
            if user.get("status") != "active":
                return jsonify({
                    "success": False,
                    "error": "Account is not active"
                }), 401
            
            # Update last login and login count
            update_data = {
                "last_login": datetime.utcnow().isoformat(),
                "login_count": user.get("login_count", 0) + 1,
                "updated_at": datetime.utcnow().isoformat()
            }
            
            self.db_manager.update("users", {"_id": user["_id"]}, update_data)
            
            # Create JWT tokens
            access_token_payload = {
                'user_id': str(user['_id']),
                'username': user['username'],
                'email': email,
                'type': 'access'
            }
            
            refresh_token_payload = {
                'user_id': str(user['_id']),
                'type': 'refresh'
            }
            
            # Get JWT manager from app_manager
            jwt_manager = self.app_manager.jwt_manager
            access_token = jwt_manager.create_token(access_token_payload, TokenType.ACCESS)
            refresh_token = jwt_manager.create_token(refresh_token_payload, TokenType.REFRESH)
            
            # Remove password from response
            user.pop('password', None)
            
            # Ensure account_type is included in response
            if 'account_type' not in user:
                user['account_type'] = 'normal'
            
            custom_log(f"UserManagement: Google Sign-In successful - User ID: {user['_id']}, Email: {email}", level="INFO", isOn=UserManagementModule.LOGGING_SWITCH)
            
            # Track event in analytics service (automatically updates metrics)
            account_type = user.get('account_type', 'normal')
            analytics_service = self.app_manager.services_manager.get_service('analytics_service') if self.app_manager else None
            if analytics_service:
                analytics_service.track_event(
                    user_id=str(user['_id']),
                    event_type='google_sign_in',
                    event_data={
                        'auth_method': 'google',
                        'account_type': account_type
                    },
                    metrics_enabled=UserManagementModule.METRICS_SWITCH
                )
                # Also track as login event
                analytics_service.track_event(
                    user_id=str(user['_id']),
                    event_type='user_logged_in',
                    event_data={
                        'auth_method': 'google',
                        'account_type': account_type
                    },
                    metrics_enabled=UserManagementModule.METRICS_SWITCH
                )
            
            return jsonify({
                "success": True,
                "message": "Google Sign-In successful",
                "data": {
                    "user": user,
                    "access_token": access_token,
                    "refresh_token": refresh_token,
                    "token_type": "Bearer",
                    "expires_in": Config.JWT_ACCESS_TOKEN_EXPIRES,
                    "refresh_expires_in": Config.JWT_REFRESH_TOKEN_EXPIRES
                }
            }), 200
            
        except Exception as e:
            custom_log(f"UserManagement: Google Sign-In error: {e}", level="ERROR", isOn=UserManagementModule.LOGGING_SWITCH)
            return jsonify({
                "success": False,
                "error": "Internal server error"
            }), 500

    def logout_user(self):
        """Logout user and revoke tokens."""
        try:
            # Get token from Authorization header
            auth_header = request.headers.get('Authorization')
            if not auth_header or not auth_header.startswith('Bearer '):
                return jsonify({
                    "success": False,
                    "error": "Missing or invalid authorization header"
                }), 401
            
            token = auth_header.split(' ')[1]
            
            # Get JWT manager from app_manager
            jwt_manager = self.app_manager.jwt_manager
            
            # Verify token
            payload = jwt_manager.verify_token(token, TokenType.ACCESS)
            if not payload:
                return jsonify({
                    "success": False,
                    "error": "Invalid or expired token"
                }), 401
            
            # Revoke the token
            success = jwt_manager.revoke_token(token)
            
            if success:
                return jsonify({
                    "success": True,
                    "message": "Logout successful"
                }), 200
            else:
                return jsonify({
                    "success": False,
                    "error": "Failed to logout"
                }), 500
            
        except Exception as e:
            return jsonify({
                "success": False,
                "error": "Internal server error"
            }), 500

    def refresh_token(self):
        """Refresh access token using refresh token."""
        try:
            data = request.get_json()
            
            if not data.get("refresh_token"):
                return jsonify({
                    "success": False,
                    "error": "Refresh token is required"
                }), 400
            
            refresh_token = data.get("refresh_token")
            
            # Get JWT manager from app_manager
            jwt_manager = self.app_manager.jwt_manager
            
            # Verify refresh token
            payload = jwt_manager.verify_token(refresh_token, TokenType.REFRESH)
            if not payload:
                return jsonify({
                    "success": False,
                    "error": "Invalid or expired refresh token"
                }), 401
            
            # Get user data
            user_id = payload.get("user_id")
            user = self.db_manager.find_one("users", {"_id": ObjectId(user_id)})
            
            if not user:
                return jsonify({
                    "success": False,
                    "error": "User not found"
                }), 401
            
            # Get the original email from the login request
            # Since refresh tokens don't contain email, we need to get it from the original login
            # For now, we'll use the email from the database lookup, but this should be the original email
            # The issue is that the database stores encrypted emails, so we need to handle this properly
            
            # Create new access token
            access_token_payload = {
                'user_id': str(user['_id']),
                'username': user['username'],
                'email': '',  # Use the original email directly for now
                'type': 'access'
            }
            
            # Create new refresh token (token rotation for security)
            refresh_token_payload = {
                'user_id': str(user['_id']),
                'type': 'refresh'
            }
            
            new_access_token = jwt_manager.create_token(access_token_payload, TokenType.ACCESS)
            new_refresh_token = jwt_manager.create_token(refresh_token_payload, TokenType.REFRESH)
            
            # Revoke the old refresh token for security
            jwt_manager.revoke_token(refresh_token)
            
            # Remove password from response
            user.pop('password', None)
            
            return jsonify({
                "success": True,
                "message": "Token refreshed successfully",
                "data": {
                    "user": user,
                    "access_token": new_access_token,
                    "refresh_token": new_refresh_token,  # ✅ NEW REFRESH TOKEN
                    "token_type": "Bearer",
                    "expires_in": Config.JWT_ACCESS_TOKEN_EXPIRES,  # Access token TTL
                    "refresh_expires_in": Config.JWT_REFRESH_TOKEN_EXPIRES  # Refresh token TTL
                }
            }), 200
            
        except Exception as e:
            return jsonify({
                "success": False,
                "error": "Internal server error"
            }), 500

    def get_current_user(self):
        """Get current user information from token."""
        try:
            # Get token from Authorization header
            auth_header = request.headers.get('Authorization')
            if not auth_header or not auth_header.startswith('Bearer '):
                return jsonify({
                    "success": False,
                    "error": "Missing or invalid authorization header"
                }), 401
            
            token = auth_header.split(' ')[1]
            
            # Get JWT manager from app_manager
            jwt_manager = self.app_manager.jwt_manager
            
            # Verify token
            payload = jwt_manager.verify_token(token, TokenType.ACCESS)
            if not payload:
                return jsonify({
                    "success": False,
                    "error": "Invalid or expired token"
                }), 401
            
            # Get user data
            user_id = payload.get("user_id")
            user = self.db_manager.find_one("users", {"_id": ObjectId(user_id)})
            
            if not user:
                return jsonify({
                    "success": False,
                    "error": "User not found"
                }), 401
            
            # Get user's wallet
            wallet = self.db_manager.find_one("wallets", {"user_id": user_id})
            
            # Remove password from response
            user.pop('password', None)
            
            return jsonify({
                "success": True,
                "data": {
                    "user": user,
                    "wallet": wallet
                }
            }), 200
            
        except Exception as e:
            return jsonify({
                "success": False,
                "error": "Internal server error"
            }), 500

    def _prepare_user_response(self, user_data):
        """Prepare user data for JSON response by converting datetime objects."""
        import copy
        response_data = copy.deepcopy(user_data)
        
        # Convert datetime objects to ISO format strings
        datetime_fields = ['created_at', 'updated_at', 'last_login', 'password_changed_at', 'profile_updated_at']
        
        def convert_datetime(obj):
            if isinstance(obj, dict):
                for key, value in obj.items():
                    if isinstance(value, datetime):
                        obj[key] = value.isoformat()
                    elif isinstance(value, dict):
                        convert_datetime(value)
            return obj
        
        # Convert main user data
        response_data = convert_datetime(response_data)
        
        # Convert nested datetime fields
        if 'modules' in response_data:
            for module_name, module_data in response_data['modules'].items():
                if isinstance(module_data, dict) and 'last_updated' in module_data:
                    if isinstance(module_data['last_updated'], datetime):
                        module_data['last_updated'] = module_data['last_updated'].isoformat()
        
        return response_data

    def _is_valid_email(self, email: str) -> bool:
        """Validate email format."""
        pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
        return re.match(pattern, email) is not None

    def _is_valid_password(self, password: str) -> bool:
        """Validate password strength."""
        return len(password) >= 8

    def test_debug(self):
        """Test endpoint for debugging."""
        return jsonify({
            'message': 'User management module is working',
            'module': 'UserManagementModule',
            'timestamp': str(datetime.utcnow())
        })

    def get_public_user_info(self):
        """Get public user information (no auth required)."""
        return jsonify({
            'message': 'Public user info endpoint',
            'module': 'UserManagementModule',
            'auth_required': False
        })

    def get_user_profile(self):
        """Get user profile (JWT auth required)."""
        try:
            # User ID is set by JWT middleware
            user_id = request.user_id
            if not user_id:
                return jsonify({'error': 'User not authenticated'}), 401
            
            # Get user profile from database
            user = self.analytics_db.find_one("users", {"_id": user_id})
            if not user:
                return jsonify({'error': 'User not found'}), 404
            
            # Return profile data
            profile_data = {
                'user_id': user_id,
                'email': user.get('email'),
                'username': user.get('username'),
                'profile': user.get('profile', {}),
                'modules': user.get('modules', {})
            }
            
            return jsonify(profile_data), 200
            
        except Exception as e:
            return jsonify({'error': 'Failed to get user profile'}), 500

    def update_user_profile(self):
        """Update user profile (JWT auth required)."""
        try:
            user_id = request.user_id
            if not user_id:
                return jsonify({'error': 'User not authenticated'}), 401
            
            data = request.get_json()
            update_data = {'updated_at': datetime.utcnow().isoformat()}
            
            # Only allow updating profile fields
            allowed_fields = ['first_name', 'last_name', 'phone', 'timezone', 'language']
            for field in allowed_fields:
                if field in data:
                    update_data[f'profile.{field}'] = data[field]
            
            # Update user profile
            modified_count = self.db_manager.update("users", {"_id": user_id}, {"$set": update_data})
            
            if modified_count > 0:
                return jsonify({
                    'message': 'Profile updated successfully',
                    'user_id': user_id
                }), 200
            else:
                return jsonify({'error': 'Failed to update profile'}), 500
                
        except Exception as e:
            return jsonify({'error': 'Failed to update profile'}), 500

    def get_user_settings(self):
        """Get user settings (JWT auth required)."""
        try:
            user_id = request.user_id
            if not user_id:
                return jsonify({'error': 'User not authenticated'}), 401
            
            user = self.analytics_db.find_one("users", {"_id": user_id})
            if not user:
                return jsonify({'error': 'User not found'}), 404
            
            settings_data = {
                'user_id': user_id,
                'preferences': user.get('preferences', {}),
                'modules': user.get('modules', {})
            }
            
            return jsonify(settings_data), 200
            
        except Exception as e:
            return jsonify({'error': 'Failed to get user settings'}), 500

    def update_user_settings(self):
        """Update user settings (JWT auth required)."""
        try:
            user_id = request.user_id
            if not user_id:
                return jsonify({'error': 'User not authenticated'}), 401
            
            data = request.get_json()
            update_data = {'updated_at': datetime.utcnow().isoformat()}
            
            # Allow updating preferences
            if 'preferences' in data:
                update_data['preferences'] = data['preferences']
            
            # Update user settings
            modified_count = self.db_manager.update("users", {"_id": user_id}, {"$set": update_data})
            
            if modified_count > 0:
                return jsonify({
                    'message': 'Settings updated successfully',
                    'user_id': user_id
                }), 200
            else:
                return jsonify({'error': 'Failed to update settings'}), 500
                
        except Exception as e:
            return jsonify({'error': 'Failed to update settings'}), 500



    def health_check(self) -> Dict[str, Any]:
        """Perform health check for UserManagementModule."""
        health_status = super().health_check()
        health_status['dependencies'] = self.dependencies
        
        # Add database queue status
        try:
            queue_status = self.db_manager.get_queue_status()
            health_status['details'] = {
                'database_queue': {
                    'queue_size': queue_status['queue_size'],
                    'worker_alive': queue_status['worker_alive'],
                    'queue_enabled': queue_status['queue_enabled'],
                    'pending_results': queue_status['pending_results']
                }
            }
        except Exception as e:
            health_status['details'] = {'database_queue': f'error: {str(e)}'}
        
        return health_status 

