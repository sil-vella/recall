import os
import redis
from redis import Redis
from redis.connection import ConnectionPool
from typing import Optional, Any, Union, List, Dict
from tools.logger.custom_logging import custom_log
import hashlib
from utils.config.config import Config
import json
import base64
from cryptography.fernet import Fernet
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from datetime import datetime
import logging
try:
    from redis.retry import ExponentialBackoff, Retry
except ImportError:
    # Fallback for older redis versions
    ExponentialBackoff = None
    Retry = None

# Redis configuration now uses Config class with proper priority system

class RedisManager:
    _instance = None
    _initialized = False

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(RedisManager, cls).__new__(cls)
        return cls._instance

    def __init__(self):
        self.redis = None
        self.connection_pool = None
        self._initialized = False
        self._initialize_connection_pool()
        self.logger = logging.getLogger(__name__)
        self._setup_encryption()
        self._token_prefix = "token"
        self._token_set_prefix = "tokens"

    def _setup_encryption(self):
        """Set up encryption key using PBKDF2."""
        # Use Redis password as salt for key derivation
        redis_password = self._get_redis_password()
        salt = redis_password.encode()
        kdf = PBKDF2HMAC(
            algorithm=hashes.SHA256(),
            length=32,
            salt=salt,
            iterations=100000,
        )
        key = base64.urlsafe_b64encode(kdf.derive(redis_password.encode()))
        self.cipher_suite = Fernet(key)

    def _get_redis_password(self):
        """Get Redis password using Config priority system."""
        return Config.REDIS_PASSWORD

    def _initialize_connection_pool(self):
        """Initialize Redis connection pool with security settings."""
        try:
            # Use Config class values that follow proper priority system
            redis_host = Config.REDIS_HOST
            redis_port = Config.REDIS_PORT
            redis_password = Config.REDIS_PASSWORD

            # Base connection pool settings
            pool_settings = {
                'host': redis_host,
                'port': redis_port,
                'password': redis_password,
                'decode_responses': True,
                'socket_timeout': Config.REDIS_SOCKET_TIMEOUT,
                'socket_connect_timeout': Config.REDIS_SOCKET_CONNECT_TIMEOUT,
                'retry_on_timeout': Config.REDIS_RETRY_ON_TIMEOUT,
                'max_connections': Config.REDIS_MAX_CONNECTIONS,
                'health_check_interval': 30,  # Check connection health every 30 seconds
            }
            
            # Add retry settings only if available
            if Retry is not None and ExponentialBackoff is not None:
                pool_settings['retry'] = Retry(ExponentialBackoff(), Config.REDIS_MAX_RETRIES)
            
            # Add SSL settings only if SSL is enabled
            if Config.REDIS_USE_SSL:
                pool_settings.update({
                    'ssl': True,
                    'ssl_cert_reqs': Config.REDIS_SSL_VERIFY_MODE
                })
            
            # Create connection pool
            self.connection_pool = redis.ConnectionPool(**pool_settings)
            
            # Initialize Redis client (but don't test connection during startup)
            self.redis = redis.Redis(connection_pool=self.connection_pool)
            self._initialized = True
        except Exception as e:
            self._initialized = False
            raise

    def _generate_secure_key(self, prefix, *args):
        """Generate a cryptographically secure cache key."""
        # Combine all arguments into a single string
        key_data = ':'.join(str(arg) for arg in args)
        
        # Use SHA-256 for key generation
        key_hash = hashlib.sha256(key_data.encode()).hexdigest()
        
        # Add prefix and hash to create final key
        return f"{prefix}:{key_hash}"

    def _encrypt_data(self, data):
        """Encrypt data before storing in Redis."""
        try:
            if isinstance(data, set):
                # Convert sets to lists for JSON serialization
                data = json.dumps(list(data))
            elif isinstance(data, (dict, list)):
                data = json.dumps(data)
            elif not isinstance(data, str):
                data = str(data)
            # Encrypt the data
            return self.cipher_suite.encrypt(data.encode()).decode()
        except Exception as e:
            raise

    def _convert_sets_to_lists(self, data):
        """Convert any sets in a dictionary to lists for JSON serialization."""
        result = {}
        for key, value in data.items():
            if isinstance(value, set):
                result[key] = list(value)
            elif isinstance(value, dict):
                result[key] = self._convert_sets_to_lists(value)
            elif isinstance(value, list):
                result[key] = [self._convert_sets_to_lists(item) if isinstance(item, dict) else 
                              (list(item) if isinstance(item, set) else item) for item in value]
            elif isinstance(value, (datetime, int, float)):
                result[key] = str(value)
            else:
                result[key] = value
        return result

    def _decrypt_data(self, encrypted_data):
        """Decrypt data retrieved from Redis."""
        try:
            # Handle None or empty data
            if not encrypted_data:
                return None
                
            # Try to decrypt the data
            decrypted = self.cipher_suite.decrypt(encrypted_data.encode())
            data = json.loads(decrypted.decode())
            
            # Convert lists back to sets for specific fields
            if isinstance(data, dict):
                data = self._convert_lists_to_sets(data)
            elif isinstance(data, list):
                data = [self._convert_lists_to_sets(item) if isinstance(item, dict) else item for item in data]
                
            return data
        except Exception as e:
            # Return None instead of failing - this allows the application to continue
            return None

    def _convert_lists_to_sets(self, data):
        """Convert lists back to sets for specific fields when retrieving data."""
        result = {}
        for key, value in data.items():
            if key in ['rooms', 'user_roles', 'allowed_users', 'allowed_roles'] and isinstance(value, list):
                result[key] = set(value)
            elif isinstance(value, dict):
                result[key] = self._convert_lists_to_sets(value)
            elif isinstance(value, list):
                result[key] = [self._convert_lists_to_sets(item) if isinstance(item, dict) else item for item in value]
            else:
                result[key] = value
        return result

    def get(self, key, *args):
        """Get value from Redis with secure key generation."""
        try:
            secure_key = self._generate_secure_key(key, *args)
            value = self.redis.get(secure_key)
            if value:
                decrypted_value = self._decrypt_data(value)
                if decrypted_value is not None:
                    return decrypted_value
                else:
                    return value
            return None
        except Exception as e:
            return None

    def set(self, key, value, expire=None, *args):
        """Set value in Redis with secure key generation and encryption."""
        try:
            secure_key = self._generate_secure_key(key, *args)
            # Convert sets to lists before encryption to avoid JSON serialization errors
            if isinstance(value, dict):
                value = self._convert_sets_to_lists(value)
            encrypted_value = self._encrypt_data(value)
            if expire:
                self.redis.setex(secure_key, expire, encrypted_value)
            else:
                self.redis.set(secure_key, encrypted_value)
            return True
        except Exception as e:
            return False

    def delete(self, key, *args):
        """Delete value from Redis with secure key generation."""
        try:
            secure_key = self._generate_secure_key(key, *args)
            self.redis.delete(secure_key)
            return True
        except Exception as e:
            return False

    def exists(self, key, *args):
        """Check if key exists in Redis with secure key generation."""
        try:
            secure_key = self._generate_secure_key(key, *args)
            return self.redis.exists(secure_key)
        except Exception as e:
            return False

    def expire(self, key, seconds, *args):
        """Set expiration for key in Redis with secure key generation."""
        try:
            secure_key = self._generate_secure_key(key, *args)
            return self.redis.expire(secure_key, seconds)
        except Exception as e:
            return False

    def ttl(self, key, *args):
        """Get time to live for key in Redis with secure key generation."""
        try:
            secure_key = self._generate_secure_key(key, *args)
            return self.redis.ttl(secure_key)
        except Exception as e:
            return -1

    def incr(self, key, *args):
        """Increment value in Redis with secure key generation."""
        try:
            secure_key = self._generate_secure_key(key, *args)
            # Check if key exists first
            if not self.redis.exists(secure_key):
                # If key doesn't exist, set it to 1
                self.redis.set(secure_key, 1)
                return 1
            else:
                # Check if the existing value is an integer
                current_value = self.redis.get(secure_key)
                if current_value is None:
                    # Key was deleted between exists and get, set to 1
                    self.redis.set(secure_key, 1)
                    return 1
                try:
                    # Try to convert to int to verify it's a valid integer
                    int(current_value)
                    # If successful, increment it
                    return self.redis.incr(secure_key)
                except (ValueError, TypeError):
                    self.redis.set(secure_key, 1)
                    return 1
        except Exception as e:
            return None

    def decr(self, key, *args):
        """Decrement value in Redis with secure key generation."""
        try:
            secure_key = self._generate_secure_key(key, *args)
            return self.redis.decr(secure_key)
        except Exception as e:
            return None

    def hset(self, key, field, value, *args):
        """Set hash field in Redis with secure key generation and encryption."""
        try:
            secure_key = self._generate_secure_key(key, *args)
            encrypted_value = self._encrypt_data(value)
            return self.redis.hset(secure_key, field, encrypted_value)
        except Exception as e:
            return False

    def hget(self, key, field, *args):
        """Get hash field from Redis with secure key generation and decryption."""
        try:
            secure_key = self._generate_secure_key(key, *args)
            value = self.redis.hget(secure_key, field)
            if value:
                return self._decrypt_data(value)
            return None
        except Exception as e:
            return None

    def hdel(self, key, field, *args):
        """Delete hash field from Redis with secure key generation."""
        try:
            secure_key = self._generate_secure_key(key, *args)
            return self.redis.hdel(secure_key, field)
        except Exception as e:
            return False

    def hgetall(self, key, *args):
        """Get all hash fields from Redis with secure key generation and decryption."""
        try:
            secure_key = self._generate_secure_key(key, *args)
            values = self.redis.hgetall(secure_key)
            return {k: self._decrypt_data(v) for k, v in values.items()}
        except Exception as e:
            return {}

    def lpush(self, key, value, *args):
        """Push value to list in Redis with secure key generation and encryption."""
        try:
            secure_key = self._generate_secure_key(key, *args)
            encrypted_value = self._encrypt_data(value)
            return self.redis.lpush(secure_key, encrypted_value)
        except Exception as e:
            return False

    def rpush(self, key, value, *args):
        """Push value to end of list in Redis with secure key generation and encryption."""
        try:
            secure_key = self._generate_secure_key(key, *args)
            encrypted_value = self._encrypt_data(value)
            return self.redis.rpush(secure_key, encrypted_value)
        except Exception as e:
            return False

    def lpop(self, key, *args):
        """Pop value from list in Redis with secure key generation and decryption."""
        try:
            secure_key = self._generate_secure_key(key, *args)
            value = self.redis.lpop(secure_key)
            if value:
                return self._decrypt_data(value)
            return None
        except Exception as e:
            return None

    def rpop(self, key, *args):
        """Pop value from end of list in Redis with secure key generation and decryption."""
        try:
            secure_key = self._generate_secure_key(key, *args)
            value = self.redis.rpop(secure_key)
            if value:
                return self._decrypt_data(value)
            return None
        except Exception as e:
            return None

    def lrange(self, key, start, end, *args):
        """Get range of values from list in Redis with secure key generation and decryption."""
        try:
            secure_key = self._generate_secure_key(key, *args)
            values = self.redis.lrange(secure_key, start, end)
            return [self._decrypt_data(v) for v in values]
        except Exception as e:
            return []

    def dispose(self):
        """Clean up Redis connections."""
        try:
            if self.connection_pool:
                self.connection_pool.disconnect()
        except Exception as e:
            pass

    def set_room_size(self, room_id: str, size: int, expire: int = 3600) -> bool:
        """Set room size in Redis without encryption."""
        try:
            key = f"room:size:{room_id}"
            self.redis.set(key, str(size))  # Convert int to string
            if expire:
                self.redis.expire(key, expire)
            return True
        except Exception as e:
            return False

    def get_room_size(self, room_id: str) -> int:
        """Get room size from Redis without encryption."""
        try:
            key = f"room:size:{room_id}"
            value = self.redis.get(key)
            size = int(value) if value is not None else 0
            return size
        except Exception as e:
            return 0

    def update_room_size(self, room_id: str, delta: int):
        """Update room size atomically."""
        try:
            key = f"room:size:{room_id}"
            
            # Use Redis transaction for atomicity
            with self.redis.pipeline() as pipe:
                while True:
                    try:
                        # Watch the room size key
                        pipe.watch(key)
                        
                        # Get current size
                        current_size = pipe.get(key)
                        current_size = int(current_size) if current_size else 0
                        
                        # Calculate new size
                        new_size = max(0, current_size + delta)
                        
                        # Update size
                        pipe.multi()
                        if new_size > 0:
                            pipe.set(key, str(new_size))
                            pipe.expire(key, 3600)  # 1 hour expiry
                        else:
                            pipe.delete(key)
                            
                        # Execute transaction
                        pipe.execute()
                        return
                        
                    except Exception as e:
                        continue
                        
        except Exception as e:
            pass

    def check_and_increment_room_size(self, room_id: str, room_size_limit: int = 100) -> bool:
        """Atomically check and increment room size if under limit."""
        try:
            key = f"room:size:{room_id}"
            
            # Use Redis transaction for atomicity
            with self.redis.pipeline() as pipe:
                while True:
                    try:
                        # Watch the room size key
                        pipe.watch(key)
                        
                        # Get current size
                        current_size = pipe.get(key)
                        current_size = int(current_size) if current_size else 0
                        
                        # Check if we've hit the limit
                        if current_size >= room_size_limit:
                            return False
                            
                        # Increment size - ensure key exists first
                        pipe.multi()
                        if current_size == 0:
                            # If key doesn't exist, set it to 1 first
                            pipe.set(key, 1)
                        else:
                            # If key exists, increment it
                            pipe.incr(key)
                        pipe.expire(key, 3600)  # 1 hour expiry
                        
                        # Execute transaction
                        pipe.execute()
                        return True
                        
                    except Exception as e:
                        continue
                        
        except Exception as e:
            return False

    def reset_room_size(self, room_id: str):
        """Reset room size to 0."""
        try:
            key = f"room:size:{room_id}"
            self.redis.delete(key)
        except Exception as e:
            pass

    def cleanup_room_keys(self, room_id: str) -> bool:
        """Clean up all Redis keys related to a room using pattern matching."""
        try:
            # Pattern to match all room-related keys
            pattern = f"ws:room:{room_id}:*"
            cursor = 0
            cleaned = 0
            
            while True:
                cursor, keys = self.redis.scan(cursor, match=pattern, count=100)
                for key in keys:
                    self.redis.delete(key)
                    cleaned += 1
                    
                if cursor == 0:
                    break
                    
            return True
            
        except Exception as e:
            return False

    def cleanup_pattern_keys(self, pattern: str, batch_size: int = 100) -> int:
        """Clean up all Redis keys matching a pattern with atomic operations."""
        try:
            cursor = 0
            cleaned = 0
            
            while True:
                cursor, keys = self.redis.scan(cursor, match=pattern, count=batch_size)
                
                if keys:
                    # Use pipeline for atomic deletion
                    pipeline = self.redis.pipeline()
                    for key in keys:
                        pipeline.delete(key)
                        cleaned += 1
                    
                    # Execute deletions atomically
                    results = pipeline.execute()
                    successful_deletions = sum(1 for result in results if result == 1)
                
                if cursor == 0:
                    break
                    
            return cleaned
            
        except Exception as e:
            return 0

    def atomic_key_operations(self, operations: list) -> bool:
        """Execute multiple Redis operations atomically."""
        try:
            pipeline = self.redis.pipeline()
            
            for operation in operations:
                op_type = operation.get('type')
                key = operation.get('key')
                value = operation.get('value')
                expire = operation.get('expire')
                
                if op_type == 'set':
                    if expire:
                        pipeline.setex(key, expire, value)
                    else:
                        pipeline.set(key, value)
                elif op_type == 'delete':
                    pipeline.delete(key)
                elif op_type == 'expire':
                    pipeline.expire(key, value)
                elif op_type == 'hset':
                    field = operation.get('field')
                    pipeline.hset(key, field, value)
                elif op_type == 'hdel':
                    field = operation.get('field')
                    pipeline.hdel(key, field)
            
            # Execute all operations atomically
            results = pipeline.execute()
            return True
            
        except Exception as e:
            return False

    def get_keys_by_pattern(self, pattern: str, max_keys: int = 1000) -> list:
        """Get all keys matching a pattern with pagination."""
        try:
            keys = []
            cursor = 0
            
            while len(keys) < max_keys:
                cursor, batch_keys = self.redis.scan(cursor, match=pattern, count=100)
                keys.extend(batch_keys)
                
                if cursor == 0:
                    break
            return keys[:max_keys]
            
        except Exception as e:
            return []

    def cleanup_api_key_cache(self, app_id: str) -> int:
        """Specialized cleanup for API key cache with comprehensive pattern matching."""
        try:
            
            patterns_to_clean = [
                f"api_key:*",  # Direct API key entries
                f"app_keys:{app_id}",
                f"key_metadata:{app_id}",
                f"key_cache:{app_id}",
                f"app_metadata:{app_id}",
                f"key_usage:*",  # Usage tracking keys
                f"cred_sys_key",  # Credit system specific keys
                f"cred_sys_cache",
                f"cred_sys_metadata"
            ]
            
            total_cleaned = 0
            
            for pattern in patterns_to_clean:
                if pattern == "api_key:*":
                    # For API keys, we need to check the data to match app_id
                    keys = self.get_keys_by_pattern(pattern)
                    keys_to_delete = []
                    
                    for key in keys:
                        key_data = self.get(key.replace('api_key:', 'api_key'))
                        if key_data and key_data.get('app_id') == app_id:
                            keys_to_delete.append(key)
                    
                    if keys_to_delete:
                        pipeline = self.redis.pipeline()
                        for key in keys_to_delete:
                            pipeline.delete(key)
                        results = pipeline.execute()
                        total_cleaned += sum(1 for result in results if result == 1)
                else:
                    # For other patterns, direct deletion
                    cleaned = self.cleanup_pattern_keys(pattern)
                    total_cleaned += cleaned
            return total_cleaned
            
        except Exception as e:
            return 0

    def health_check_cache(self) -> Dict[str, Any]:
        """Health check for cache operations."""
        try:
            health_status = {
                'cache_operations': 'healthy',
                'patterns': {},
                'total_keys': 0
            }
            
            # Check common patterns
            patterns = [
                'api_key:*',
                'app_keys:*',
                'key_metadata:*',
                'key_cache:*',
                'app_metadata:*',
                'cred_sys_key',
                'cred_sys_cache',
                'cred_sys_metadata'
            ]
            
            for pattern in patterns:
                try:
                    keys = self.get_keys_by_pattern(pattern, max_keys=10)
                    health_status['patterns'][pattern] = len(keys)
                    health_status['total_keys'] += len(keys)
                except Exception as e:
                    health_status['patterns'][pattern] = f"error: {str(e)}"
                    health_status['cache_operations'] = 'unhealthy'
            
            return health_status
            
        except Exception as e:
            return {
                'cache_operations': 'unhealthy',
                'error': str(e)
            }

    def _ensure_connection(self):
        """Ensure Redis connection is active."""
        try:
            if not self.redis or not self.redis.ping():
                self._initialize_connection_pool()
            return True
        except Exception as e:
            return False

    def _generate_token_key(self, token_type: str, token: str) -> str:
        """Generate a secure key for token storage."""
        return f"{self._token_prefix}:{token_type}:{token}"

    def _generate_token_set_key(self, token_type: str) -> str:
        """Generate a secure key for token set storage."""
        return f"{self._token_set_prefix}:{token_type}"

    def store_token(self, token_type: str, token: str, expire: int = 1800) -> bool:
        """Store a token with proper key generation and expiration."""
        try:
            if not self._ensure_connection():
                return False

            # Store token with expiration using direct Redis operations
            token_key = self._generate_token_key(token_type, token)
            self.redis.setex(token_key, expire, "1")

            # Add to token set
            set_key = self._generate_token_set_key(token_type)
            self.redis.sadd(set_key, token)
            
            # Set expiration on the set as well
            self.redis.expire(set_key, expire)
            
            return True
        except Exception as e:
            return False

    def is_token_valid(self, token_type: str, token: str) -> bool:
        """Check if a token exists and is valid."""
        try:
            if not self._ensure_connection():
                return False

            token_key = self._generate_token_key(token_type, token)
            return self.redis.exists(token_key)
        except Exception as e:
            return False

    def revoke_token(self, token_type: str, token: str) -> bool:
        """Revoke a token by removing it from both storage and set."""
        try:
            if not self._ensure_connection():
                return False

            # Remove token using direct Redis operations
            token_key = self._generate_token_key(token_type, token)
            self.redis.delete(token_key)

            # Remove from set
            set_key = self._generate_token_set_key(token_type)
            self.redis.srem(set_key, token)

            return True
        except Exception as e:
            return False

    def cleanup_expired_tokens(self, token_type: str) -> bool:
        """Clean up expired tokens for a specific type."""
        try:
            if not self._ensure_connection():
                return False

            set_key = self._generate_token_set_key(token_type)
            tokens = self.redis.smembers(set_key) or set()

            for token in tokens:
                token_key = self._generate_token_key(token_type, token)
                if not self.redis.exists(token_key):
                    # Token has expired, remove from set
                    self.redis.srem(set_key, token)

            return True
        except Exception as e:
            return False

    def get_token_ttl(self, token_type: str, token: str) -> int:
        """Get remaining TTL for a token."""
        try:
            if not self._ensure_connection():
                return -1

            token_key = self._generate_token_key(token_type, token)
            return self.redis.ttl(token_key)
        except Exception as e:
            return -1

    def extend_token_ttl(self, token_type: str, token: str, seconds: int) -> bool:
        """Extend the TTL of a token."""
        try:
            if not self._ensure_connection():
                return False

            token_key = self._generate_token_key(token_type, token)
            return self.redis.expire(token_key, seconds)
        except Exception as e:
            return False

    def ping(self):
        """Check if Redis connection is healthy."""
        try:
            if not self._initialized:
                self._initialize_connection_pool()
            return self.redis.ping()
        except Exception as e:
            self._initialized = False
            return False

    def get_client(self):
        """Get Redis client with connection pool."""
        if not self._initialized:
            self._initialize_connection_pool()
        return self.redis

    def close(self):
        """Close all connections in the pool."""
        if self.connection_pool:
            self.connection_pool.disconnect()

    def get_connection_count(self):
        """Get the number of active connections in the pool."""
        if self.connection_pool:
            return self.connection_pool._created_connections
        return 0

    # Sorted Set operations for queue management
    def zadd(self, key, mapping, *args):
        """Add one or more members to a sorted set, or update its score if it already exists."""
        try:
            secure_key = self._generate_secure_key(key, *args)
            return self.redis.zadd(secure_key, mapping)
        except Exception as e:
            raise

    def zrangebyscore(self, key, min_score, max_score, start=0, num=None, *args):
        """Return a range of members in a sorted set, by score."""
        try:
            secure_key = self._generate_secure_key(key, *args)
            if num is not None:
                return self.redis.zrangebyscore(secure_key, min_score, max_score, start=start, num=num)
            else:
                return self.redis.zrangebyscore(secure_key, min_score, max_score, start=start)
        except Exception as e:
            raise

    def zrem(self, key, *members, **kwargs):
        """Remove one or more members from a sorted set."""
        try:
            secure_key = self._generate_secure_key(key, *kwargs.get('args', []))
            return self.redis.zrem(secure_key, *members)
        except Exception as e:
            raise

    def zcard(self, key, *args):
        """Get the number of members in a sorted set."""
        try:
            secure_key = self._generate_secure_key(key, *args)
            return self.redis.zcard(secure_key)
        except Exception as e:
            raise

    def keys(self, pattern, *args):
        """Find all keys matching the given pattern."""
        try:
            # For keys pattern matching, we need to handle the pattern differently
            # since we're using secure key generation
            # This is a simplified implementation - in production you might want to store
            # a mapping of patterns to actual keys
            return self.redis.keys(pattern)
        except Exception as e:
            raise 
