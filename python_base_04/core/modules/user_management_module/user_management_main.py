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


class UserManagementModule(BaseModule):
    # Logging switch for guest registration and conversion testing
    LOGGING_SWITCH = True
    
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
                    'cleco_game': {
                        'enabled': True,
                        'wins': 0,
                        'losses': 0,
                        'total_matches': 0,
                        'points': 0,
                        'level': 1,
                        'rank': 'beginner',
                        'win_rate': 0.0,
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
            else:
                custom_log(f"UserManagement: Regular registration completed successfully - User ID: {user_id}, Username: {username}, Email: {email}", level="INFO", isOn=UserManagementModule.LOGGING_SWITCH)
            
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
                    'cleco_game': {
                        'enabled': True,
                        'wins': 0,
                        'losses': 0,
                        'total_matches': 0,
                        'points': 0,
                        'level': 1,
                        'rank': 'beginner',
                        'win_rate': 0.0,
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

