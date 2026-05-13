from core.modules.base_module import BaseModule
from core.modules.user_management_module import tier_rank_level_matcher as matcher
from core.managers.database_manager import DatabaseManager
from core.managers.jwt_manager import JWTManager, TokenType
from core.managers.redis_manager import RedisManager
from utils.config.config import Config
from flask import request, jsonify, send_file, abort
from datetime import datetime
from typing import Dict, Any, Optional, Tuple
from bson import ObjectId
import bcrypt
import os
import uuid
import re
import secrets
import smtplib
import ssl
import string
import requests as http_requests
import traceback
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

# Lazy import for GoogleAuthService to avoid import errors if google-auth is not installed
try:
    from core.services.google_auth_service import GoogleAuthService
    GOOGLE_AUTH_AVAILABLE = True
except ImportError:
    GOOGLE_AUTH_AVAILABLE = False
    GoogleAuthService = None
except Exception:
    GOOGLE_AUTH_AVAILABLE = False
    GoogleAuthService = None

from core.services.analytics_service import AnalyticsService


class UserManagementModule(BaseModule):
    # Logging switch: /public/register, /public/register-guest, login, Google sign-in, invite search, etc.
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
        self._register_auth_route_helper("/userauth/users/profile/avatar", self.upload_profile_avatar, methods=["POST"])
        self._register_auth_route_helper("/public/avatar-media/<filename>", self.serve_profile_avatar, methods=["GET"])
        self._register_auth_route_helper("/userauth/users/search", self.search_users, methods=["POST"])
        # Public route for fetching user profile by userId (for Dart backend)
        self._register_auth_route_helper("/public/users/profile", self.get_user_profile_by_id, methods=["POST"])
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
            if data is None:
                return jsonify({
                    "success": False,
                    "error": "Request body must be JSON with username, email, and password",
                }), 400

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
                    'role': 'player',
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
                
                # Ensure dutch_game module exists with rank and level (preserve existing or default)
                if 'modules' not in user_data:
                    user_data['modules'] = {}
                if 'dutch_game' not in user_data['modules']:
                    user_data['modules']['dutch_game'] = {}
                # Preserve existing rank and level from guest account, or default from matcher
                if 'rank' not in user_data['modules']['dutch_game']:
                    user_data['modules']['dutch_game']['rank'] = matcher.DEFAULT_RANK
                if 'level' not in user_data['modules']['dutch_game']:
                    user_data['modules']['dutch_game']['level'] = matcher.DEFAULT_LEVEL
                # Apply registration defaults for converted accounts.
                user_data['modules']['dutch_game']['subscription_tier'] = matcher.TIER_REGULAR
                user_data['modules']['dutch_game']['coins'] = Config.REGISTRATION_COIN_BONUS
                
            else:
                # Prepare user data with comprehensive structure (new account)
                user_data = {
                # Core fields
                'username': username,
                'email': email,
                'password': hashed_password.decode('utf-8'),
                'status': 'active',
                'role': 'player',
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
                        'coins': Config.REGISTRATION_COIN_BONUS,
                        'level': matcher.DEFAULT_LEVEL,
                        'rank': matcher.DEFAULT_RANK,
                        'win_rate': 0.0,
                        'subscription_tier': matcher.TIER_REGULAR,
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
                        self.db_manager.delete("users", {"_id": ObjectId(guest_user_id)})
                except Exception:
                    # Log error but don't fail registration (data integrity maintained)
                    pass
            
            # Remove password from response
            user_data.pop('password', None)
            user_data['_id'] = user_id
            
            # Trigger user_created hook for other modules to listen to
            if self.app_manager:
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
            
            # Send confirmation email (non-blocking: failure does not fail registration)
            self._send_confirmation_email(email, username)

            
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
        max_attempts = 10
        for attempt in range(max_attempts):
            random_id = ''.join(secrets.choice(string.ascii_lowercase + string.digits) for _ in range(8))
            username = f"Guest_{random_id}"
            # Check uniqueness
            existing = self.db_manager.find_one("users", {"username": username})
            if not existing:
                return username
        raise Exception("Failed to generate unique guest username")

    def create_guest_user(self):
        """Create a new guest user account with auto-generated credentials."""
        try:
            # Generate unique guest username
            username = self._generate_guest_username()
            
            # Generate email from username
            email = f"guest_{username}@guest.local"
            
            # Use username as password
            password = username
            
            
            # Hash password
            hashed_password = bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt())
            
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
                'role': 'player',
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
                        'coins': Config.REGISTRATION_COIN_BONUS,
                        'level': matcher.DEFAULT_LEVEL,
                        'rank': matcher.DEFAULT_RANK,
                        'win_rate': 0.0,
                        'subscription_tier': matcher.TIER_REGULAR,
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
                    "error": "Failed to create guest account"
                }), 500
            
            
            # Remove password from response
            user_data.pop('password', None)
            user_data['_id'] = user_id
            
            # Trigger user_created hook for other modules to listen to
            if self.app_manager:
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
                self.app_manager.trigger_hook("user_created", hook_data)
            
            
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
            modified_count = self.db_manager.update("users", {"_id": user_id}, update_data)
            
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

    def search_users_by_username(self, username, limit=50):
        """Internal: search users by username or email (partial, case-insensitive). Same doc appears once if it matches both. Returns (list of user dicts with user_id, no password), or ([], error_msg)."""
        try:
            q = (username or '').strip()
            if len(q) < 2:
                return [], 'username must be at least 2 characters'
            escaped = re.escape(q)
            regex = {'$regex': escaped, '$options': 'i'}
            query = {'$or': [{'username': regex}, {'email': regex}]}
            limit = min(int(limit), 50) if limit is not None else 50
            users_raw = self.analytics_db.find("users", query)
            users_raw = list(users_raw) if users_raw else []
            seen_ids = set()
            out = []
            for user in users_raw:
                uid = user.get('_id')
                if uid is None:
                    continue
                uid_str = str(uid)
                if uid_str in seen_ids:
                    continue
                seen_ids.add(uid_str)
                u = dict(user)
                u.pop('password', None)
                u['user_id'] = uid_str
                out.append(u)
                if len(out) >= limit:
                    break
            return out, None
        except Exception as e:
            return [], str(e)

    def search_users(self):
        """Search users by username (and optionally email/status). JWT required. Requires username with min length 2."""
        try:
            data = request.get_json(silent=True) or {}
            username = (data.get('username') or '').strip()
            if len(username) < 2:
                return jsonify({
                    'success': False,
                    'error': 'username is required and must be at least 2 characters',
                    'users': []
                }), 400
            limit = min(int(data.get('limit', 50)), 50)
            query = {'username': {'$regex': re.escape(username), '$options': 'i'}}
            if data.get('email'):
                email_escaped = re.escape(str(data.get('email', '')).strip())
                if email_escaped:
                    query['email'] = {'$regex': email_escaped, '$options': 'i'}
            if data.get('status'):
                query['status'] = data['status']
            users_raw = self.analytics_db.find("users", query)
            users_raw = list(users_raw)[:limit] if users_raw else []
            out = []
            for user in users_raw:
                user.pop('password', None)
                uid = user.get('_id')
                if uid is not None:
                    user['user_id'] = str(uid)
                out.append(user)
            return jsonify({'success': True, 'users': out}), 200
        except Exception as e:
            return jsonify({'success': False, 'error': 'Failed to search users', 'users': []}), 500

    def _prepare_single_session_login(
        self, user_id: str, force_new_session: bool
    ) -> Tuple[Optional[int], Optional[Tuple[Dict[str, Any], int]]]:
        """
        Enforce one active login per user (sliding window = refresh TTL).
        Returns (auth_gen, None) on success. auth_gen -1 means skip embedding (Redis down).
        On conflict: (None, (response_body_dict, http_status)).
        """
        redis_mgr = self.app_manager.get_redis_manager() if self.app_manager else None
        try:
            redis_ok = bool(redis_mgr and redis_mgr.ping())
        except Exception:
            redis_ok = False

        if not redis_ok:
            return -1, None

        uid = str(user_id)
        active = redis_mgr.is_user_login_session_active(uid)
        if active and not force_new_session:
            return None, (
                {
                    "success": False,
                    "error": "SESSION_ACTIVE_ELSEWHERE",
                    "code": "SESSION_ACTIVE_ELSEWHERE",
                    "message": (
                        "This account is already signed in on another device. "
                        "Continue here to sign out the other session and use this device."
                    ),
                },
                409,
            )

        if force_new_session:
            gen = redis_mgr.bump_user_auth_generation(uid)
        else:
            gen = redis_mgr.get_user_auth_generation(uid)
            if gen == 0:
                redis_mgr.set_user_auth_generation(uid, 1)
                gen = 1

        return gen, None

    def login_user(self):
        """Authenticate user and return JWT tokens."""
        try:
            data = request.get_json()
            force_new_session = bool(data.get("force_new_session", False))

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

            try:
                check_result = bcrypt.checkpw(password.encode('utf-8'), stored_password.encode('utf-8'))
            except Exception as e:
                check_result = False
            
            if not check_result:
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

            auth_gen, session_err = self._prepare_single_session_login(str(user["_id"]), force_new_session)
            if session_err:
                err_body, err_status = session_err
                return jsonify(err_body), err_status
            
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
            if auth_gen is not None and auth_gen >= 0:
                access_token_payload['auth_gen'] = auth_gen
                refresh_token_payload['auth_gen'] = auth_gen
            
            # Get JWT manager from app_manager
            jwt_manager = self.app_manager.jwt_manager
            access_token = jwt_manager.create_token(access_token_payload, TokenType.ACCESS)
            refresh_token = jwt_manager.create_token(refresh_token_payload, TokenType.REFRESH)

            redis_mgr = self.app_manager.get_redis_manager() if self.app_manager else None
            if redis_mgr and auth_gen is not None and auth_gen >= 0:
                redis_mgr.set_user_login_session_active(str(user["_id"]), Config.JWT_REFRESH_TOKEN_EXPIRES)
            
            # Remove password from response
            user.pop('password', None)
            
            # Ensure account_type is included in response (for Flutter to determine guest status)
            if 'account_type' not in user:
                user['account_type'] = account_type
            # Ensure role is included (default: player)
            if 'role' not in user:
                user['role'] = 'player'

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
            return jsonify({
                "success": False,
                "error": "Internal server error"
            }), 500

    def google_signin(self):
        """Handle Google Sign-In authentication."""
        try:
            data = request.get_json()
            force_new_session = bool(data.get("force_new_session", False))

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
                
                if not GOOGLE_AUTH_AVAILABLE or GoogleAuthService is None:
                    return jsonify({
                        "success": False,
                        "error": "Google Sign-In with ID token requires google-auth package. Please install it."
                    }), 503
                
                google_auth_service = GoogleAuthService()
                user_info = google_auth_service.get_user_info(id_token_string)
            elif access_token and user_info_from_client:
                # Fallback for web: Verify access token and use provided user info
                
                # Verify access token by calling Google's tokeninfo endpoint
                try:
                    token_info_response = http_requests.get(
                        f'https://www.googleapis.com/oauth2/v1/tokeninfo?access_token={access_token}',
                        timeout=10
                    )
                    
                    if token_info_response.status_code == 200:
                        token_info = token_info_response.json()
                        
                        # Verify the token is valid
                        # For web tokens, we check if the email matches and token is valid
                        token_email = token_info.get('email')
                        client_email = user_info_from_client.get('email')
                        
                        # Verify email matches (if both are present)
                        if token_email and client_email and token_email != client_email:
                            return jsonify({
                                "success": False,
                                "error": "Token email mismatch"
                            }), 401
                        
                        # Verify client ID if configured (optional check)
                        if Config.GOOGLE_CLIENT_ID:
                            token_audience = token_info.get('audience') or token_info.get('issued_to')
                            if token_audience and token_audience != Config.GOOGLE_CLIENT_ID:
                                # Still proceed if email matches - web tokens might have different audience format
                                pass

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
                    else:
                        error_text = token_info_response.text[:200] if token_info_response.text else "Unknown error"
                        return jsonify({
                            "success": False,
                            "error": f"Invalid access token: {token_info_response.status_code}"
                        }), 401
                except Exception as e:
                    import traceback
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
                
            
            # Check if user exists by email
            existing_user = self.db_manager.find_one("users", {"email": email})
            
            if existing_user:
                # User exists - handle account linking or login
                auth_providers = existing_user.get('auth_providers', [])
                
                # Check if Google is already linked
                if 'google' in auth_providers:
                    # Normal Google login - update profile picture if provided
                    
                    # Update profile picture if provided (always update to get latest from Google)
                    update_data = {
                        'updated_at': datetime.utcnow().isoformat()
                    }
                    
                    if picture:
                        update_data['profile.picture'] = picture
                    
                    # Also update name fields if provided and missing
                    if 'profile' not in existing_user:
                        existing_user['profile'] = {}
                    if given_name and not existing_user['profile'].get('first_name'):
                        update_data['profile.first_name'] = given_name
                    if family_name and not existing_user['profile'].get('last_name'):
                        update_data['profile.last_name'] = family_name
                    
                    if len(update_data) > 1:  # More than just updated_at
                        self.db_manager.update("users", {"_id": existing_user["_id"]}, update_data)
                else:
                    # Link Google account to existing account
                    
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
                    if 'profile' not in existing_user:
                        existing_user['profile'] = {}
                    if given_name and not existing_user['profile'].get('first_name'):
                        update_data['profile.first_name'] = given_name
                    if family_name and not existing_user['profile'].get('last_name'):
                        update_data['profile.last_name'] = family_name
                    if picture:
                        update_data['profile.picture'] = picture
                    
                    self.db_manager.update("users", {"_id": existing_user["_id"]}, update_data)
                
                user = existing_user
            else:
                # New user - create account with Google info
                
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
                        'role': 'player',
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
                    
                    # Ensure dutch_game module exists with rank and level (preserve existing or default)
                    if 'modules' not in user_data:
                        user_data['modules'] = {}
                    if 'dutch_game' not in user_data['modules']:
                        user_data['modules']['dutch_game'] = {}
                    # Preserve existing rank and level from guest account, or default from matcher
                    if 'rank' not in user_data['modules']['dutch_game']:
                        user_data['modules']['dutch_game']['rank'] = matcher.DEFAULT_RANK
                    if 'level' not in user_data['modules']['dutch_game']:
                        user_data['modules']['dutch_game']['level'] = matcher.DEFAULT_LEVEL
                    # Apply registration defaults for converted accounts.
                    user_data['modules']['dutch_game']['subscription_tier'] = matcher.TIER_REGULAR
                    user_data['modules']['dutch_game']['coins'] = Config.REGISTRATION_COIN_BONUS
                    
                else:
                    # Prepare user data with comprehensive structure (new account)
                    user_data = {
                        'username': username,
                        'email': email,
                        'password': '',  # No password for Google-only accounts
                        'status': 'active',
                        'account_type': 'normal',
                        'role': 'player',
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
                                'coins': Config.REGISTRATION_COIN_BONUS,
                                'level': matcher.DEFAULT_LEVEL,
                                'rank': matcher.DEFAULT_RANK,
                                'win_rate': 0.0,
                                'subscription_tier': matcher.TIER_REGULAR,
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
                            self.db_manager.delete("users", {"_id": ObjectId(guest_user_id)})
                    except Exception:
                        # Log error but don't fail registration (data integrity maintained)
                        pass
                
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

            auth_gen, session_err = self._prepare_single_session_login(str(user["_id"]), force_new_session)
            if session_err:
                err_body, err_status = session_err
                return jsonify(err_body), err_status
            
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
            if auth_gen is not None and auth_gen >= 0:
                access_token_payload['auth_gen'] = auth_gen
                refresh_token_payload['auth_gen'] = auth_gen
            
            # Get JWT manager from app_manager
            jwt_manager = self.app_manager.jwt_manager
            access_token = jwt_manager.create_token(access_token_payload, TokenType.ACCESS)
            refresh_token = jwt_manager.create_token(refresh_token_payload, TokenType.REFRESH)

            redis_mgr = self.app_manager.get_redis_manager() if self.app_manager else None
            if redis_mgr and auth_gen is not None and auth_gen >= 0:
                redis_mgr.set_user_login_session_active(str(user["_id"]), Config.JWT_REFRESH_TOKEN_EXPIRES)
            
            # Remove password from response
            user.pop('password', None)
            
            # Ensure account_type is included in response
            if 'account_type' not in user:
                user['account_type'] = 'normal'
            # Ensure role is included (default: player)
            if 'role' not in user:
                user['role'] = 'player'
            
            
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
            import traceback
            return jsonify({
                "success": False,
                "error": "Internal server error"
            }), 500

    def logout_user(self):
        """Logout user: revoke access (+ optional refresh), clear session marker, bump auth generation."""
        try:
            # Get token from Authorization header
            auth_header = request.headers.get('Authorization')
            if not auth_header or not auth_header.startswith('Bearer '):
                return jsonify({
                    "success": False,
                    "error": "Missing or invalid authorization header"
                }), 401
            
            token = auth_header.split(' ')[1]
            data = request.get_json(silent=True) or {}
            refresh_from_body = data.get("refresh_token")
            
            # Get JWT manager from app_manager
            jwt_manager = self.app_manager.jwt_manager
            
            # Verify token
            payload = jwt_manager.verify_token(token, TokenType.ACCESS)
            if not payload:
                return jsonify({
                    "success": False,
                    "error": "Invalid or expired token"
                }), 401
            
            uid = payload.get("user_id")
            uid_str = str(uid) if uid is not None else ""

            # Revoke refresh token if client sent it and it belongs to this user
            refresh_revoked = False
            if refresh_from_body:
                rp = jwt_manager.verify_token(refresh_from_body, TokenType.REFRESH)
                if rp and str(rp.get("user_id")) == uid_str:
                    jwt_manager.revoke_token(refresh_from_body)
                    refresh_revoked = True

            # Revoke the access token
            success = jwt_manager.revoke_token(token)

            redis_mgr = self.app_manager.get_redis_manager() if self.app_manager else None
            bumped_gen = None
            if redis_mgr and uid_str:
                redis_mgr.clear_user_login_session_active(uid_str)
                # Invalidate any other copies of access/refresh (other tabs / stale storage)
                bumped_gen = redis_mgr.bump_user_auth_generation(uid_str)


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
            
            # Preserve single-session generation across rotation
            auth_gen = payload.get("auth_gen")

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
            if auth_gen is not None:
                access_token_payload['auth_gen'] = auth_gen
                refresh_token_payload['auth_gen'] = auth_gen
            
            new_access_token = jwt_manager.create_token(access_token_payload, TokenType.ACCESS)
            new_refresh_token = jwt_manager.create_token(refresh_token_payload, TokenType.REFRESH)
            
            # Revoke the old refresh token for security
            jwt_manager.revoke_token(refresh_token)

            redis_mgr = self.app_manager.get_redis_manager() if self.app_manager else None
            if redis_mgr and user_id:
                redis_mgr.set_user_login_session_active(str(user_id), Config.JWT_REFRESH_TOKEN_EXPIRES)
            
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

    def _send_confirmation_email(self, to_email: str, username: str) -> bool:
        """
        Send a confirmation email to the user after account creation.
        Uses SMTP config from Config (MAIL_SMTP_*, MAIL_FROM, MAIL_FROM_NAME).
        Returns True if sent successfully, False otherwise. Does not raise.
        """
        if not Config.MAIL_SMTP_HOST or not Config.MAIL_SMTP_USER or not Config.MAIL_SMTP_PASSWORD:
            return False
        try:
            from_name = Config.MAIL_FROM_NAME or "ReignOfPlay"
            from_addr = Config.MAIL_FROM or Config.MAIL_SMTP_USER
            subject = "Welcome – your account is confirmed"
            text_body = (
                f"Hi {username},\n\n"
                "Your account has been created successfully.\n\n"
                "You can now sign in with your email and password.\n\n"
                "— ReignOfPlay"
            )
            html_body = (
                f"<p>Hi {username},</p>"
                "<p>Your account has been created successfully.</p>"
                "<p>You can now sign in with your email and password.</p>"
                "<p>— ReignOfPlay</p>"
            )
            msg = MIMEMultipart("alternative")
            msg["Subject"] = subject
            msg["From"] = f"{from_name} <{from_addr}>"
            msg["To"] = to_email
            msg.attach(MIMEText(text_body, "plain"))
            msg.attach(MIMEText(html_body, "html"))
            port = Config.MAIL_SMTP_PORT
            encrypt = (Config.MAIL_SMTP_ENCRYPT or "ssl").lower()
            if encrypt == "ssl":
                context = ssl.create_default_context()
                with smtplib.SMTP_SSL(Config.MAIL_SMTP_HOST, port, context=context) as server:
                    server.login(Config.MAIL_SMTP_USER, Config.MAIL_SMTP_PASSWORD)
                    server.sendmail(from_addr, to_email, msg.as_string())
            else:
                with smtplib.SMTP(Config.MAIL_SMTP_HOST, port) as server:
                    if encrypt == "tls":
                        context = ssl.create_default_context()
                        server.starttls(context=context)
                    server.login(Config.MAIL_SMTP_USER, Config.MAIL_SMTP_PASSWORD)
                    server.sendmail(from_addr, to_email, msg.as_string())
            return True
        except Exception as e:
            return False

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
        """Get user profile (JWT auth required - returns current authenticated user's profile)."""
        try:
            # User ID is set by JWT middleware
            user_id = request.user_id
            if not user_id:
                return jsonify({'error': 'User not authenticated'}), 401
            
            # Get user profile from database
            try:
                user = self.analytics_db.find_one("users", {"_id": ObjectId(user_id)})
            except Exception:
                # If ObjectId conversion fails, try with string
                user = self.analytics_db.find_one("users", {"_id": user_id})
            
            if not user:
                return jsonify({'error': 'User not found'}), 404
            
            # Prefer plain email/username from JWT (set at login) so clients see actual values
            # DB stores encrypted (det_...) values; JWT claims hold the plain text
            payload = getattr(request, 'user_payload', None) or {}
            plain_email = payload.get('email') if isinstance(payload.get('email'), str) else None
            plain_username = payload.get('username') if isinstance(payload.get('username'), str) else None
            
            role_from_db = user.get('role', 'player')
            profile = user.get('profile', {}) or {}
            picture = profile.get('picture')
            profile_data = {
                'user_id': user_id,
                'email': plain_email or user.get('email'),
                'username': plain_username or user.get('username'),
                'profile': profile,
                'modules': user.get('modules', {}),
                'role': role_from_db,
            }
            
            return jsonify(profile_data), 200
            
        except Exception as e:
            return jsonify({'error': 'Failed to get user profile'}), 500

    def get_user_profile_by_id(self):
        """Get user profile by userId (public endpoint for Dart backend - no JWT required)."""
        try:
            data = request.get_json()
            user_id = data.get('user_id') if data else None
            
            if not user_id:
                return jsonify({
                    'success': False,
                    'error': 'No user_id provided'
                }), 400
            
            # Get user profile from database
            try:
                user = self.analytics_db.find_one("users", {"_id": ObjectId(user_id)})
            except Exception:
                # If ObjectId conversion fails, try with string
                user = self.analytics_db.find_one("users", {"_id": user_id})
            
            if not user:
                return jsonify({
                    'success': False,
                    'error': 'User not found'
                }), 404
            
            # Extract profile data
            profile = user.get('profile', {})
            username = user.get('username', '')
            first_name = profile.get('first_name', '')
            last_name = profile.get('last_name', '')
            picture = profile.get('picture', '')
            account_type = user.get('account_type', 'regular')  # Get account type for registration differences testing
            role = user.get('role', 'player')
            
            # Build full name (first_name + last_name, fallback to empty string)
            full_name = ''
            if first_name or last_name:
                full_name = f"{first_name} {last_name}".strip()
            
            
            return jsonify({
                'success': True,
                'user_id': user_id,
                'username': username,
                'full_name': full_name,
                'first_name': first_name,
                'last_name': last_name,
                'profile_picture': picture,
                'account_type': account_type,  # Include account type for registration differences testing
                'role': role,
            }), 200
            
        except Exception as e:
            return jsonify({
                'success': False,
                'error': 'Failed to get user profile',
                'message': str(e)
            }), 500

    def upload_profile_avatar(self):
        """Upload profile picture (JWT). Expect multipart field ``file`` (.jpg/.jpeg/.png/.webp)."""
        from core.modules.user_management_module import avatar_upload_utils as avu
        try:
            user_id = request.user_id
            if not user_id:
                return jsonify({"success": False, "error": "User not authenticated"}), 401

            max_b = Config.AVATAR_MAX_UPLOAD_BYTES
            cl = request.content_length
            if cl is not None and cl > max_b:
                return jsonify({
                    "success": False,
                    "error": "file_too_large",
                    "message": f"File must be at most {max_b} bytes",
                }), 413

            if "file" not in request.files:
                return jsonify({
                    "success": False,
                    "error": "missing_file",
                    "message": "Multipart field 'file' is required",
                }), 400

            f = request.files["file"]
            if not f or not f.filename:
                return jsonify({"success": False, "error": "empty_file", "message": "No file selected"}), 400

            if not avu.allowed_upload_extension(f.filename):
                return jsonify({
                    "success": False,
                    "error": "invalid_extension",
                    "message": "Allowed extensions: .jpg, .jpeg, .png, .webp",
                }), 400

            if not avu.declared_mime_allowed(f.content_type):
                return jsonify({
                    "success": False,
                    "error": "invalid_content_type",
                    "message": "Allowed types: image/jpeg, image/png, image/webp",
                }), 400

            raw, err = avu.read_upload_bytes(f.stream, max_b)
            if err == "file_too_large":
                return jsonify({
                    "success": False,
                    "error": "file_too_large",
                    "message": f"File must be at most {max_b} bytes",
                }), 413
            if err:
                return jsonify({"success": False, "error": err, "message": "Invalid upload"}), 400

            magic_fmt = avu.detect_format_from_magic(raw)
            if not magic_fmt or not avu.mime_matches_magic(f.content_type, magic_fmt):
                return jsonify({
                    "success": False,
                    "error": "mime_mismatch",
                    "message": "File content does not match declared type",
                }), 400

            webp_bytes, perr = avu.process_avatar_image(
                raw,
                max_edge_px=Config.AVATAR_MAX_EDGE_PX,
                max_dimension_px=Config.AVATAR_MAX_DIMENSION_PX,
                max_image_pixels=Config.AVATAR_MAX_IMAGE_PIXELS,
            )
            if perr:
                return jsonify({
                    "success": False,
                    "error": perr,
                    "message": "Could not process image",
                }), 400

            storage_root = os.path.abspath(os.path.expanduser(Config.AVATAR_STORAGE_DIR))
            os.makedirs(storage_root, exist_ok=True)

            fname = f"{uuid.uuid4().hex}.webp"
            dest = os.path.join(storage_root, fname)
            with open(dest, "wb") as out:
                out.write(webp_bytes)

            base = (Config.AVATAR_PUBLIC_BASE_URL or Config.APP_URL or "").rstrip("/")
            if not base:
                return jsonify({
                    "success": False,
                    "error": "server_misconfigured",
                    "message": "Set AVATAR_PUBLIC_BASE_URL or APP_URL",
                }), 503

            public_url = f"{base}/public/avatar-media/{fname}"

            try:
                oid = ObjectId(user_id)
            except Exception:
                return jsonify({"success": False, "error": "invalid_user_id", "message": "Invalid user id"}), 400

            now = datetime.utcnow().isoformat()
            update_data = {
                "profile.picture": public_url,
                "updated_at": now,
                "profile_updated_at": now,
            }
            modified_count = self.db_manager.update("users", {"_id": oid}, update_data)

            if modified_count > 0:
                return jsonify({
                    "success": True,
                    "message": "Avatar updated",
                    "profile_picture": public_url,
                }), 200
            return jsonify({
                "success": False,
                "error": "update_failed",
                "message": "User not found or not updated",
            }), 500

        except Exception as e:
            return jsonify({"success": False, "error": "server_error", "message": "Upload failed"}), 500

    def serve_profile_avatar(self, filename):
        """Public GET for normalized WebP avatars (opaque filename)."""
        from core.modules.user_management_module import avatar_upload_utils as avu
        from core.modules.user_management_module.avatar_upload_utils import STORED_NAME_RE, safe_join_under_root
        try:
            if not filename or not STORED_NAME_RE.match(filename):
                abort(404)
            storage_root = os.path.abspath(os.path.expanduser(Config.AVATAR_STORAGE_DIR))
            path = safe_join_under_root(storage_root, filename)
            if not path or not os.path.isfile(path):
                abort(404)
            return send_file(path, mimetype="image/webp", max_age=86400)
        except Exception:
            abort(404)

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
            modified_count = self.db_manager.update("users", {"_id": user_id}, update_data)
            
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
            modified_count = self.db_manager.update("users", {"_id": user_id}, update_data)
            
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

