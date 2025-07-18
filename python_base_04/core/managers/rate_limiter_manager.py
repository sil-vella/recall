from core.managers.redis_manager import RedisManager
from tools.logger.custom_logging import custom_log
from datetime import datetime, timedelta
import time
from typing import Optional, Dict, Any, List, Union
from flask import request
from utils.config.config import Config
from redis.exceptions import RedisError

class RateLimiterManager:
    _instance = None
    _initialized = False

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(RateLimiterManager, cls).__new__(cls)
        return cls._instance

    def __init__(self, redis_manager=None):
        if not RateLimiterManager._initialized:
            # Use provided redis_manager or create a new one
            self.redis_manager = redis_manager if redis_manager else RedisManager()
            self._setup_config()
            RateLimiterManager._initialized = True
            custom_log("RateLimiterManager initialized")

    def set_redis_manager(self, redis_manager):
        """Set the Redis manager instance (for dependency injection)."""
        self.redis_manager = redis_manager
        custom_log("RateLimiterManager Redis manager updated")

    def _setup_config(self):
        """Set up rate limiting configuration from Config."""
        self.config = {
            'ip': {
                'requests': Config.RATE_LIMIT_IP_REQUESTS,
                'window': Config.RATE_LIMIT_IP_WINDOW,
                'prefix': Config.RATE_LIMIT_IP_PREFIX,
                'enabled': True
            },
            'user': {
                'requests': Config.RATE_LIMIT_USER_REQUESTS,
                'window': Config.RATE_LIMIT_USER_WINDOW,
                'prefix': Config.RATE_LIMIT_USER_PREFIX,
                'enabled': True
            },
            'api_key': {
                'requests': Config.RATE_LIMIT_API_KEY_REQUESTS,
                'window': Config.RATE_LIMIT_API_KEY_WINDOW,
                'prefix': Config.RATE_LIMIT_API_KEY_PREFIX,
                'enabled': True
            }
        }

    def _get_client_ip(self) -> str:
        """Get the client's IP address from the request."""
        if request.environ.get('HTTP_X_FORWARDED_FOR'):
            # If behind a proxy
            return request.environ['HTTP_X_FORWARDED_FOR'].split(',')[0]
        return request.environ.get('REMOTE_ADDR', 'unknown')

    def _get_user_id(self) -> Optional[str]:
        """Get the user ID from the request context or JWT token."""
        try:
            auth_header = request.headers.get('Authorization')
            if auth_header and auth_header.startswith('Bearer '):
                token = auth_header.split(' ')[1]
                
                # Import JWT manager and decode token
                from core.managers.jwt_manager import JWTManager, TokenType
                jwt_manager = JWTManager()
                
                # Verify token and extract user_id
                payload = jwt_manager.verify_token(token, TokenType.ACCESS)
                if payload:
                    user_id = payload.get('user_id')
                    if user_id:
                        custom_log(f"Extracted user_id {user_id} from JWT token for rate limiting")
                        return str(user_id)
                    else:
                        custom_log("JWT token valid but no user_id found")
                        return None
                else:
                    custom_log("Invalid JWT token in rate limiting check")
                    return None
            else:
                custom_log("No Authorization header found for rate limiting")
                return None
                
        except Exception as e:
            custom_log(f"Error extracting user_id from JWT token: {str(e)}", level="ERROR")
        return None

    def _get_api_key(self) -> Optional[str]:
        """Get the API key from the request headers."""
        return request.headers.get('X-API-Key')

    def _generate_redis_key(self, identifier: str, limit_type: str) -> str:
        """Generate a Redis key for rate limiting."""
        prefix = self.config[limit_type]['prefix']
        return f"{prefix}:{identifier}"

    def _generate_ban_key(self, identifier: str, limit_type: str) -> str:
        """Generate a Redis key for ban status."""
        return f"{Config.AUTO_BAN_PREFIX}:{limit_type}:{identifier}"

    def _generate_violations_key(self, identifier: str, limit_type: str) -> str:
        """Generate a Redis key for tracking violations."""
        return f"{Config.AUTO_BAN_VIOLATIONS_PREFIX}:{limit_type}:{identifier}"

    def _is_banned(self, identifier: str, limit_type: str) -> bool:
        """Check if an identifier is currently banned."""
        if not Config.AUTO_BAN_ENABLED:
            return False

        ban_key = self._generate_ban_key(identifier, limit_type)
        try:
            return self.redis_manager.exists(ban_key)
        except RedisError as e:
            custom_log(f"Redis error checking ban status: {str(e)}", level="ERROR")
            return False

    def _track_violation(self, identifier: str, limit_type: str) -> bool:
        """Track a rate limit violation and ban if threshold is reached."""
        if not Config.AUTO_BAN_ENABLED:
            return False

        violations_key = self._generate_violations_key(identifier, limit_type)
        try:
            # Increment violation count
            violations = self.redis_manager.incr(violations_key)
            
            # Set expiration on the violations key
            self.redis_manager.expire(violations_key, Config.AUTO_BAN_WINDOW)
            
            # Check if ban threshold reached
            if violations >= Config.AUTO_BAN_VIOLATIONS_THRESHOLD:
                self._ban_identifier(identifier, limit_type)
                return True
                
            return False
        except RedisError as e:
            custom_log(f"Redis error tracking violation: {str(e)}", level="ERROR")
            return False

    def _ban_identifier(self, identifier: str, limit_type: str) -> None:
        """Ban an identifier for the configured duration."""
        ban_key = self._generate_ban_key(identifier, limit_type)
        try:
            self.redis_manager.set(ban_key, 1, expire=Config.AUTO_BAN_DURATION)
            custom_log(
                f"Banned {limit_type} {identifier} for {Config.AUTO_BAN_DURATION} seconds",
                level="WARNING"
            )
        except RedisError as e:
            custom_log(f"Redis error setting ban: {str(e)}", level="ERROR")

    def check_rate_limit(self, limit_types: Union[str, List[str]] = 'ip', 
                        identifiers: Optional[Dict[str, str]] = None) -> Dict[str, Any]:
        """
        Check if the request is within rate limits for specified types.
        
        Args:
            limit_types: Single type or list of types to check ('ip', 'user', 'api_key')
            identifiers: Optional dict of identifiers for each type
            
        Returns:
            Dict containing:
                - allowed: bool
                - remaining: Dict[str, int]  # Remaining requests per type
                - reset_time: Dict[str, int]  # Reset time per type
                - exceeded_types: List[str]  # Types that exceeded limits
                - banned_types: List[str]  # Types that are banned
        """
        if not Config.RATE_LIMIT_ENABLED:
            return {
                'allowed': True,
                'remaining': {},
                'reset_time': {},
                'exceeded_types': [],
                'banned_types': []
            }

        # Convert single type to list
        if isinstance(limit_types, str):
            limit_types = [limit_types]

        # Initialize result
        result = {
            'allowed': True,
            'remaining': {},
            'reset_time': {},
            'exceeded_types': [],
            'banned_types': []
        }

        # Get identifiers if not provided
        if identifiers is None:
            identifiers = {}
            if 'ip' in limit_types:
                identifiers['ip'] = self._get_client_ip()
            if 'user' in limit_types:
                identifiers['user'] = self._get_user_id()
            if 'api_key' in limit_types:
                identifiers['api_key'] = self._get_api_key()

        try:
            for limit_type in limit_types:
                if not self.config[limit_type]['enabled']:
                    continue

                identifier = identifiers.get(limit_type)
                if not identifier:
                    continue

                # Check if banned
                if self._is_banned(identifier, limit_type):
                    result['allowed'] = False
                    result['banned_types'].append(limit_type)
                    continue

                # Generate Redis key
                key = self._generate_redis_key(identifier, limit_type)
                limit_config = self.config[limit_type]

                # Get current count
                current = self.redis_manager.get(key)
                if current is None:
                    # First request in window
                    self.redis_manager.set(key, 1, expire=limit_config['window'])
                    result['remaining'][limit_type] = limit_config['requests'] - 1
                    result['reset_time'][limit_type] = int(time.time()) + limit_config['window']
                    continue

                current = int(current)
                if current >= limit_config['requests']:
                    # Rate limit exceeded
                    ttl = self.redis_manager.ttl(key)
                    result['allowed'] = False
                    result['remaining'][limit_type] = 0
                    result['reset_time'][limit_type] = int(time.time()) + ttl
                    result['exceeded_types'].append(limit_type)
                    
                    # Track violation and check if ban should be applied
                    if self._track_violation(identifier, limit_type):
                        result['banned_types'].append(limit_type)
                    continue

                # Increment counter
                self.redis_manager.incr(key)
                result['remaining'][limit_type] = limit_config['requests'] - (current + 1)
                result['reset_time'][limit_type] = int(time.time()) + self.redis_manager.ttl(key)

        except RedisError as e:
            custom_log(f"Redis error in rate limiting: {str(e)}", level="ERROR")
            # On Redis error, allow the request but log the error
            return {
                'allowed': True,
                'remaining': {},
                'reset_time': {},
                'exceeded_types': [],
                'banned_types': []
            }

        return result

    def reset_rate_limit(self, limit_type: str, identifier: str) -> bool:
        """Reset the rate limit for a given identifier."""
        key = self._generate_redis_key(identifier, limit_type)
        return self.redis_manager.delete(key)

    def get_rate_limit_status(self, limit_type: str, identifier: str) -> Dict[str, Any]:
        """Get the current rate limit status for an identifier."""
        key = self._generate_redis_key(identifier, limit_type)
        current = self.redis_manager.get(key)
        ttl = self.redis_manager.ttl(key)
        
        if current is None:
            return {
                'current': 0,
                'remaining': self.config[limit_type]['requests'],
                'reset_time': int(time.time()) + self.config[limit_type]['window'],
                'banned': self._is_banned(identifier, limit_type)
            }
        
        current = int(current)
        return {
            'current': current,
            'remaining': self.config[limit_type]['requests'] - current,
            'reset_time': int(time.time()) + ttl,
            'banned': self._is_banned(identifier, limit_type)
        } 