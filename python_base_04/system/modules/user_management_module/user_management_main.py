from tools.logger.custom_logging import custom_log
from datetime import datetime
from typing import Dict, Any, Optional, List
import os
import bcrypt
import re
from bson import ObjectId


class UserManagementModule:
    """
    Pure business logic module for user management operations.
    Completely decoupled from system dependencies - accepts data, returns results.
    """
    
    def __init__(self):
        """
        Initialize UserManagementModule with completely independent secret access.
        No dependencies on system managers or Flask.
        """
        self.module_name = "user_management_module"
        # Secrets directory is inside the module directory
        self.secrets_dir = f"system/modules/{self.module_name}/secrets"
        custom_log(f"UserManagementModule created with independent secrets: {self.secrets_dir}")

    def initialize(self):
        """Initialize the module."""
        custom_log(f"UserManagementModule initialized with independent secrets from {self.secrets_dir}")

    def _read_module_secret(self, secret_name: str) -> Optional[str]:
        """
        Read secret from module-specific directory with fallback to global secrets.
        Completely independent of config class.
        
        Args:
            secret_name: Name of the secret file
            
        Returns:
            Secret value or None if not found
        """
        # Module-specific secret paths (priority order)
        secret_paths = [
            f"{self.secrets_dir}/{secret_name}",           # Module-specific secrets
            f"secrets/{secret_name}",                      # Global secrets (fallback)
            f"/run/secrets/{secret_name}",                 # Kubernetes secrets
            f"/app/secrets/{secret_name}",                 # Local development secrets
        ]
        
        for path in secret_paths:
            try:
                if os.path.exists(path):
                    with open(path, 'r') as f:
                        content = f.read().strip()
                        if content:
                            custom_log(f"✅ Found module secret '{secret_name}' in {path}")
                            return content
            except Exception:
                continue
        
        custom_log(f"🔍 Module secret '{secret_name}' not found in any location")
        return None

    def _get_environment_variable(self, env_name: str) -> Optional[str]:
        """
        Get environment variable value.
        
        Args:
            env_name: Environment variable name
            
        Returns:
            Environment variable value or None if not found
        """
        return os.getenv(env_name)

    def _get_jwt_secret(self) -> str:
        """
        Get JWT secret with module-specific secrets first, then environment, then default.
        Completely independent of config class.
        """
        # Try module-specific secret first
        module_secret = self._read_module_secret("jwt_secret")
        if module_secret:
            return module_secret
        
        # Try environment variable
        env_value = self._get_environment_variable("JWT_SECRET_KEY")
        if env_value:
            return env_value
        
        # Default fallback
        return "your-super-secret-key-change-in-production"

    def _get_password_salt_rounds(self) -> int:
        """
        Get password salt rounds with module-specific secrets first, then environment, then default.
        """
        # Try module-specific secret first
        module_secret = self._read_module_secret("password_salt_rounds")
        if module_secret:
            try:
                return int(module_secret)
            except ValueError:
                pass
        
        # Try environment variable
        env_value = self._get_environment_variable("PASSWORD_SALT_ROUNDS")
        if env_value:
            try:
                return int(env_value)
            except ValueError:
                pass
        
        # Default fallback
        return 12

    def get_secret_sources(self) -> Dict[str, Any]:
        """
        Get information about where secrets are being read from.
        
        Returns:
            Dict with secret source information
        """
        jwt_secret = self._read_module_secret("jwt_secret")
        salt_rounds_secret = self._read_module_secret("password_salt_rounds")
        jwt_env = self._get_environment_variable("JWT_SECRET_KEY")
        salt_rounds_env = self._get_environment_variable("PASSWORD_SALT_ROUNDS")
        
        return {
            'jwt_secret': {
                'module_secret': bool(jwt_secret),
                'module_secret_path': f"{self.secrets_dir}/jwt_secret" if jwt_secret else None,
                'environment_variable': bool(jwt_env),
                'environment_name': 'JWT_SECRET_KEY' if jwt_env else None,
                'fallback_used': not bool(jwt_secret or jwt_env),
                'configured': bool(jwt_secret or jwt_env or self._get_jwt_secret())
            },
            'password_salt_rounds': {
                'module_secret': bool(salt_rounds_secret),
                'module_secret_path': f"{self.secrets_dir}/password_salt_rounds" if salt_rounds_secret else None,
                'environment_variable': bool(salt_rounds_env),
                'environment_name': 'PASSWORD_SALT_ROUNDS' if salt_rounds_env else None,
                'fallback_used': not bool(salt_rounds_secret or salt_rounds_env),
                'value': int(salt_rounds_secret or salt_rounds_env or self._get_password_salt_rounds())
            }
        }

    def _is_valid_email(self, email: str) -> bool:
        """
        Validate email format.
        
        Args:
            email: Email address to validate
            
        Returns:
            True if valid email format, False otherwise
        """
        pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
        return re.match(pattern, email) is not None

    def _is_valid_password(self, password: str) -> bool:
        """
        Validate password strength.
        
        Args:
            password: Password to validate
            
        Returns:
            True if password meets requirements, False otherwise
        """
        return len(password) >= 8

    def _hash_password(self, password: str) -> str:
        """
        Hash password using bcrypt.
        
        Args:
            password: Plain text password
            
        Returns:
            Hashed password
        """
        salt_rounds = self._get_password_salt_rounds()
        salt = bcrypt.gensalt(rounds=salt_rounds)
        hashed = bcrypt.hashpw(password.encode('utf-8'), salt)
        return hashed.decode('utf-8')

    def _verify_password(self, password: str, hashed_password: str) -> bool:
        """
        Verify password against hash.
        
        Args:
            password: Plain text password
            hashed_password: Hashed password to compare against
            
        Returns:
            True if password matches hash, False otherwise
        """
        return bcrypt.checkpw(password.encode('utf-8'), hashed_password.encode('utf-8'))

    def _prepare_user_response(self, user_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Prepare user data for response, removing sensitive information.
        
        Args:
            user_data: Raw user data from database
            
        Returns:
            Cleaned user data for response
        """
        if not user_data:
            return {}
        
        # Convert ObjectId to string
        def convert_datetime(obj):
            if isinstance(obj, datetime):
                return obj.isoformat()
            return obj
        
        # Remove sensitive fields
        sensitive_fields = ['password', 'password_hash', 'reset_token', 'reset_token_expires']
        cleaned_data = {k: v for k, v in user_data.items() if k not in sensitive_fields}
        
        # Convert ObjectId
        if '_id' in cleaned_data and isinstance(cleaned_data['_id'], ObjectId):
            cleaned_data['_id'] = str(cleaned_data['_id'])
        
        # Convert datetime fields
        for key, value in cleaned_data.items():
            if isinstance(value, datetime):
                cleaned_data[key] = value.isoformat()
        
        return cleaned_data

    def validate_user_creation_data(self, user_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Validate user creation data.
        
        Args:
            user_data: User data to validate
            
        Returns:
            Dict with validation result
        """
        try:
            # Validate required fields
            required_fields = ["username", "email", "password"]
            missing_fields = [field for field in required_fields if not user_data.get(field)]
            
            if missing_fields:
                return {
                    'success': False,
                    'error': f"Missing required fields: {', '.join(missing_fields)}"
                }
            
            username = user_data.get("username")
            email = user_data.get("email")
            password = user_data.get("password")
            
            # Validate email format
            if not self._is_valid_email(email):
                return {
                    'success': False,
                    'error': "Invalid email format"
                }
            
            # Validate password strength
            if not self._is_valid_password(password):
                return {
                    'success': False,
                    'error': "Password must be at least 8 characters long"
                }
            
            # Validate username (basic check)
            if len(username) < 3:
                return {
                    'success': False,
                    'error': "Username must be at least 3 characters long"
                }
            
            return {
                'success': True,
                'validated_data': {
                    'username': username,
                    'email': email,
                    'password': password
                }
            }
            
        except Exception as e:
            return {
                'success': False,
                'error': f'Validation error: {str(e)}'
            }

    def process_user_creation(self, user_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Process user creation (pure business logic).
        
        Args:
            user_data: User data dictionary with username, email, password
            
        Returns:
            Dict with processing result
        """
        try:
            # Validate input data
            validation_result = self.validate_user_creation_data(user_data)
            if not validation_result['success']:
                return validation_result
            
            validated_data = validation_result['validated_data']
            
            # Hash password
            hashed_password = self._hash_password(validated_data['password'])
            
            # Prepare user document
            user_document = {
                'username': validated_data['username'],
                'email': validated_data['email'],
                'password_hash': hashed_password,
                'status': 'active',
                'created_at': datetime.utcnow().isoformat(),
                'updated_at': datetime.utcnow().isoformat(),
                'profile': {},
                'preferences': {},
                'modules': {}
            }
            
            return {
                'success': True,
                'message': f'User {validated_data["username"]} validated and prepared for creation',
                'user_document': user_document,
                'validation_passed': True
            }
            
        except Exception as e:
            return {
                'success': False,
                'error': f'Error processing user creation: {str(e)}'
            }

    def process_user_login(self, login_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Process user login (pure business logic).
        
        Args:
            login_data: Login data with email and password
            
        Returns:
            Dict with processing result
        """
        try:
            email = login_data.get('email')
            password = login_data.get('password')
            
            if not email or not password:
                return {
                    'success': False,
                    'error': 'Email and password are required'
                }
            
            # Validate email format
            if not self._is_valid_email(email):
                return {
                    'success': False,
                    'error': 'Invalid email format'
                }
            
            # Note: This is pure business logic - actual user lookup would be done by orchestrator
            return {
                'success': True,
                'message': 'Login data validated',
                'validated_data': {
                    'email': email,
                    'password': password
                }
            }
            
        except Exception as e:
            return {
                'success': False,
                'error': f'Error processing login: {str(e)}'
            }

    def verify_password(self, password: str, hashed_password: str) -> Dict[str, Any]:
        """
        Verify password against hash.
        
        Args:
            password: Plain text password
            hashed_password: Hashed password to compare against
            
        Returns:
            Dict with verification result
        """
        try:
            is_valid = self._verify_password(password, hashed_password)
            
            return {
                'success': True,
                'password_valid': is_valid,
                'message': 'Password verification completed'
            }
            
        except Exception as e:
            return {
                'success': False,
                'error': f'Error verifying password: {str(e)}'
            }

    def hash_password(self, password: str) -> Dict[str, Any]:
        """
        Hash password using bcrypt.
        
        Args:
            password: Plain text password
            
        Returns:
            Dict with hashed password
        """
        try:
            hashed_password = self._hash_password(password)
            
            return {
                'success': True,
                'hashed_password': hashed_password,
                'message': 'Password hashed successfully'
            }
            
        except Exception as e:
            return {
                'success': False,
                'error': f'Error hashing password: {str(e)}'
            }

    def validate_user_update_data(self, update_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Validate user update data.
        
        Args:
            update_data: User update data to validate
            
        Returns:
            Dict with validation result
        """
        try:
            allowed_fields = ['username', 'email', 'first_name', 'last_name', 'phone', 'timezone', 'language']
            validated_data = {}
            
            for field, value in update_data.items():
                if field in allowed_fields:
                    if field == 'email' and value:
                        if not self._is_valid_email(value):
                            return {
                                'success': False,
                                'error': f'Invalid email format for {field}'
                            }
                    validated_data[field] = value
            
            return {
                'success': True,
                'validated_data': validated_data,
                'message': 'User update data validated'
            }
            
        except Exception as e:
            return {
                'success': False,
                'error': f'Error validating update data: {str(e)}'
            }

    def health_check(self) -> Dict[str, Any]:
        """
        Perform health check on user management module.
        
        Returns:
            Dict with health status
        """
        try:
            return {
                'status': 'healthy',
                'module': 'UserManagementModule',
                'secrets_configured': bool(self._get_jwt_secret()),
                'salt_rounds': self._get_password_salt_rounds(),
                'secret_sources': self.get_secret_sources()
            }
            
        except Exception as e:
            return {
                'status': 'unhealthy',
                'module': 'UserManagementModule',
                'error': str(e),
                'secret_sources': self.get_secret_sources()
            }

    def get_config(self) -> Dict[str, Any]:
        """Get module configuration with secret source information."""
        return {
            'jwt_secret_configured': bool(self._get_jwt_secret()),
            'salt_rounds': self._get_password_salt_rounds(),
            'secret_sources': self.get_secret_sources(),
            'module_secrets_dir': self.secrets_dir,
            'completely_decoupled': True
        }

    def get_config_requirements(self) -> List[Dict[str, Any]]:
        """
        Declare all configuration requirements for this module.
        Returns list of config requirements for the orchestrator to provide.
        """
        return [
            {
                'key': 'jwt_secret',
                'description': 'JWT secret key for token generation',
                'required': True,
                'default': 'your-super-secret-key-change-in-production',
                'type': 'string',
                'sensitive': True,
                'module_secret_file': f'{self.secrets_dir}/jwt_secret',
                'global_secret_file': 'jwt_secret_key',
                'env_var': 'JWT_SECRET_KEY',
                'decoupled': True
            },
            {
                'key': 'password_salt_rounds',
                'description': 'Number of salt rounds for password hashing',
                'required': False,
                'default': '12',
                'type': 'integer',
                'module_secret_file': f'{self.secrets_dir}/password_salt_rounds',
                'global_secret_file': 'password_salt_rounds',
                'env_var': 'PASSWORD_SALT_ROUNDS',
                'decoupled': True
            }
        ]

    def get_hooks_needed(self) -> List[Dict[str, Any]]:
        """
        Declare what hooks this module needs.
        Returns list of hook requirements for the orchestrator to register.
        """
        return [
            {
                'event': 'user_created',
                'priority': 10,
                'context': 'user_management',
                'description': 'Process user creation in user management'
            },
            {
                'event': 'user_updated',
                'priority': 10,
                'context': 'user_management',
                'description': 'Process user updates in user management'
            },
            {
                'event': 'user_deleted',
                'priority': 10,
                'context': 'user_management',
                'description': 'Process user deletion in user management'
            }
        ]

    def get_routes_needed(self) -> List[Dict[str, Any]]:
        """
        Declare what routes this module needs.
        Returns list of route requirements for the orchestrator to register.
        """
        return [
            {
                'route': '/public/users/info',
                'methods': ['GET'],
                'handler': 'get_public_user_info',
                'description': 'Get public user information (no auth required)',
                'auth_required': False
            },
            {
                'route': '/public/register',
                'methods': ['POST'],
                'handler': 'create_user',
                'description': 'Create a new user account',
                'auth_required': False
            },
            {
                'route': '/public/login',
                'methods': ['POST'],
                'handler': 'login_user',
                'description': 'Authenticate user and generate JWT tokens',
                'auth_required': False
            },
            {
                'route': '/public/refresh',
                'methods': ['POST'],
                'handler': 'refresh_token',
                'description': 'Refresh JWT access token using refresh token',
                'auth_required': False
            },
            {
                'route': '/userauth/users/profile',
                'methods': ['GET'],
                'handler': 'get_user_profile',
                'description': 'Get user profile (JWT auth required)',
                'auth_required': True
            },
            {
                'route': '/userauth/users/profile',
                'methods': ['PUT'],
                'handler': 'update_user_profile',
                'description': 'Update user profile (JWT auth required)',
                'auth_required': True
            },
            {
                'route': '/userauth/users/settings',
                'methods': ['GET'],
                'handler': 'get_user_settings',
                'description': 'Get user settings (JWT auth required)',
                'auth_required': True
            },
            {
                'route': '/userauth/users/settings',
                'methods': ['PUT'],
                'handler': 'update_user_settings',
                'description': 'Update user settings (JWT auth required)',
                'auth_required': True
            },
            {
                'route': '/userauth/logout',
                'methods': ['POST'],
                'handler': 'logout_user',
                'description': 'Logout user and invalidate tokens',
                'auth_required': True
            },
            {
                'route': '/userauth/me',
                'methods': ['GET'],
                'handler': 'get_current_user',
                'description': 'Get current user information (JWT auth required)',
                'auth_required': True
            }
        ]

    def process_hook_event(self, event_name: str, event_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Process a hook event from the system.
        
        Args:
            event_name: Name of the hook event
            event_data: Data passed with the hook
            
        Returns:
            Dict with processing result
        """
        if event_name == 'user_created':
            return self.process_user_creation(event_data)
        elif event_name == 'user_updated':
            return self.validate_user_update_data(event_data)
        elif event_name == 'user_deleted':
            return {
                'success': True,
                'message': f'User deletion processed: {event_data.get("user_id", "unknown")}'
            }
        else:
            return {
                'success': False,
                'error': f'Unknown hook event: {event_name}'
            } 

