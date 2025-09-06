import hashlib
import hmac
import time
import os
import requests
from typing import Dict, Any, Optional, List
from tools.logger.custom_logging import custom_log
from utils.config.config import Config
from core.managers.redis_manager import RedisManager
from flask import request, jsonify


class APIKeyManager:
    def __init__(self, redis_manager=None):
        """Initialize the unified API Key Manager."""
        self.redis_manager = redis_manager if redis_manager else RedisManager()
        self.secret_key = Config.ENCRYPTION_KEY
        self.secrets_dir = "/app/secrets"
        self.credit_system_url = Config.CREDIT_SYSTEM_URL
        
        # External app configuration - now from config
        self.app_id = Config.APP_ID
        self.app_name = Config.APP_NAME
        
        # Standardized Redis key patterns
        self.KEY_PATTERNS = {
            'api_key': 'api_key:{key}',
            'app_keys': 'app_keys:{app_id}',
            'key_metadata': 'key_metadata:{app_id}',
            'key_cache': 'key_cache:{app_id}',
            'key_usage': 'key_usage:{key}',
            'app_metadata': 'app_metadata:{app_id}',
            'cred_sys_key': 'cred_sys_key'
        }

    def _get_secret_file_path(self, app_id: str, app_name: str = None) -> str:
        """Get the secret file path for an app."""
        # For external app, always use CRED_SYS prefix for credit system API keys
        if app_id == "credit_system" or app_name == "Credit System":
            return os.path.join(self.secrets_dir, "CRED_SYS_api_key")
        # Use app_name for filename if provided, otherwise use app_id
        filename = f"{app_name}_api_key" if app_name else f"{app_id}_api_key"
        return os.path.join(self.secrets_dir, filename)

    def _save_api_key_to_file(self, app_id: str, api_key: str, key_data: Dict[str, Any]) -> bool:
        """Save API key to a secret file."""
        try:
            # Ensure secrets directory exists
            os.makedirs(self.secrets_dir, exist_ok=True)
            
            # Create the secret file path using app_name from key_data
            app_name = key_data.get('app_name', app_id)
            secret_file = self._get_secret_file_path(app_id, app_name)
            
            # Save API key to file
            with open(secret_file, 'w') as f:
                f.write(api_key)
            return True
            
        except Exception as e:
            return False

    def _load_api_key_from_file(self, app_id: str) -> Optional[str]:
        """Load API key from secret file."""
        try:
            secret_file = self._get_secret_file_path(app_id)
            
            if os.path.exists(secret_file):
                with open(secret_file, 'r') as f:
                    api_key = f.read().strip()
                return api_key
            else:
                return None
                
        except Exception as e:
            return None

    def _get_redis_keys_for_app(self, app_id: str) -> List[str]:
        """Get all Redis keys associated with an app_id using consistent patterns."""
        try:
            keys_to_clear = []
            
            # Pattern 1: Direct API key entries
            pattern1 = "api_key:*"
            keys = self.redis_manager.redis.keys(pattern1)
            for key in keys:
                key_data = self.redis_manager.get(key.replace('api_key:', 'api_key'))
                if key_data and key_data.get('app_id') == app_id:
                    keys_to_clear.append(key)
            
            # Pattern 2: App-specific keys
            patterns = [
                f"app_keys:{app_id}",
                f"key_metadata:{app_id}",
                f"key_cache:{app_id}",
                f"app_metadata:{app_id}"
            ]
            
            for pattern in patterns:
                keys = self.redis_manager.redis.keys(pattern)
                keys_to_clear.extend(keys)
            
            # Pattern 3: Usage tracking keys
            usage_pattern = "key_usage:*"
            usage_keys = self.redis_manager.redis.keys(usage_pattern)
            for key in usage_keys:
                key_data = self.redis_manager.get(key)
                if key_data and key_data.get('app_id') == app_id:
                    keys_to_clear.append(key)
            
            # Pattern 4: Credit system specific keys
            if app_id == "credit_system":
                cred_patterns = [
                    "cred_sys_key",
                    "cred_sys_cache",
                    "cred_sys_metadata"
                ]
                for pattern in cred_patterns:
                    keys = self.redis_manager.redis.keys(pattern)
                    keys_to_clear.extend(keys)
            return keys_to_clear
            
        except Exception as e:
            return []

    def invalidate_api_key_cache(self, app_id: str):
        """Enhanced cache invalidation with atomic operations and comprehensive cleanup."""
        try:
            
            # Get all keys to clear
            keys_to_clear = self._get_redis_keys_for_app(app_id)
            
            if not keys_to_clear:
                return
            
            # Use Redis pipeline for atomic operations
            pipeline = self.redis_manager.redis.pipeline()
            
            cleared_count = 0
            for key in keys_to_clear:
                pipeline.delete(key)
                cleared_count += 1
            
            # Execute all deletions atomically
            results = pipeline.execute()
            
            # Log results
            successful_deletions = sum(1 for result in results if result == 1)
            
            # Clear any file-based caches
            self._clear_file_cache(app_id)
            
        except Exception as e:
            pass

    def _clear_file_cache(self, app_id: str):
        """Clear any file-based caches for the app."""
        try:
            pass
        except Exception as e:
            pass

    def _atomic_key_replacement(self, old_key: str, new_key: str, key_data: Dict[str, Any]) -> bool:
        """Atomically replace an API key in Redis."""
        try:
            pipeline = self.redis_manager.redis.pipeline()
            
            # Store new key using the redis_manager's set method which handles serialization
            self.redis_manager.set(new_key, key_data, expire=2592000)  # 30 days
            
            # Delete old key if it exists
            if old_key:
                pipeline.delete(old_key)
                # Execute the deletion
                pipeline.execute()
            return True
            
        except Exception as e:
            return False

    # === UNIFIED API KEY GENERATION METHODS ===

    def generate_api_key_from_credit_system(self, app_id: str = None, app_name: str = None, permissions: list = None) -> Optional[str]:
        """Generate API key by requesting from credit system."""
        try:
            # Use provided parameters or default to external app config
            target_app_id = app_id or self.app_id
            target_app_name = app_name or self.app_name
            target_permissions = permissions or ["read", "write"]
            
            # Check if we already have an API key for this app
            existing_key = self.get_api_key_for_app(target_app_id)
            if existing_key:
                return existing_key
            
            # Prepare request to credit system
            payload = {
                "app_id": target_app_id,
                "app_name": target_app_name,
                "permissions": target_permissions
            }
            
            headers = {
                "Content-Type": "application/json"
            }
            
            # Make request to credit system
            response = requests.post(
                f"{self.credit_system_url}/api-keys/generate",
                json=payload,
                headers=headers,
                timeout=30
            )
            
            # Accept both 200 and 201 as success if api_key is present
            if response.status_code in (200, 201):
                response_data = response.json()
                if response_data.get('success') and response_data.get('api_key'):
                    api_key = response_data['api_key']
                    
                    # Save the API key
                    if target_app_id == "credit_system":
                        self.save_credit_system_api_key(api_key)
                    else:
                        self._save_api_key_to_file(target_app_id, api_key, {
                            'app_id': target_app_id,
                            'app_name': target_app_name,
                            'permissions': target_permissions
                        })
                    
                    return api_key
                else:
                    return None
            else:
                return None
                
        except requests.exceptions.RequestException as e:
            return None
        except Exception as e:
            return None

    def validate_api_key_with_credit_system(self, api_key: str) -> bool:
        """Validate an API key with the credit system."""
        try:
            payload = {"api_key": api_key}
            headers = {"Content-Type": "application/json"}
            
            response = requests.post(
                f"{self.credit_system_url}/api-keys/validate",
                json=payload,
                headers=headers,
                timeout=10
            )
            
            if response.status_code == 200:
                response_data = response.json()
                return response_data.get('valid', False)
            else:
                return False
                
        except Exception as e:
            return False

    def generate_api_key(self, app_id: str, app_name: str, permissions: list = None) -> str:
        """External apps should not generate API keys - they request them from credit system."""
        raise NotImplementedError("External apps should request API keys from credit system, not generate them locally")

    def get_api_key_for_app(self, app_id: str) -> Optional[str]:
        """Get the API key for a specific app from file."""
        return self._load_api_key_from_file(app_id)

    def save_credit_system_api_key(self, api_key: str) -> bool:
        """Save credit system API key to CRED_SYS_api_key file with enhanced cache management."""
        try:
            
            # Clear any existing credit system cache
            self.invalidate_api_key_cache("credit_system")
            
            # Ensure secrets directory exists
            os.makedirs(self.secrets_dir, exist_ok=True)
            
            # Save to CRED_SYS_api_key file
            secret_file = os.path.join(self.secrets_dir, "CRED_SYS_api_key")
            
            with open(secret_file, 'w') as f:
                f.write(api_key)
            
            # Store metadata in Redis
            self._store_credit_system_metadata(api_key)
            return True
            
        except Exception as e:
            return False

    def _store_credit_system_metadata(self, api_key: str):
        """Store credit system API key metadata for better tracking."""
        try:
            metadata = {
                'app_id': 'credit_system',
                'app_name': 'Credit System',
                'current_key': api_key[:16] + "...",
                'last_updated': str(int(time.time())),
                'key_source': 'external_request'
            }
            
            metadata_key = "cred_sys_metadata"
            self.redis_manager.set(metadata_key, metadata, expire=2592000)
            
        except Exception as e:
            pass

    def load_credit_system_api_key(self) -> Optional[str]:
        """Load credit system API key from CRED_SYS_api_key file."""
        try:
            secret_file = os.path.join(self.secrets_dir, "CRED_SYS_api_key")
            
            if os.path.exists(secret_file):
                with open(secret_file, 'r') as f:
                    api_key = f.read().strip()
                return api_key
            else:
                return None
                
        except Exception as e:
            return None

    def list_stored_api_keys(self) -> Dict[str, str]:
        """List all API keys stored in secret files."""
        try:
            stored_keys = {}
            
            if os.path.exists(self.secrets_dir):
                for filename in os.listdir(self.secrets_dir):
                    if filename.endswith('_api_key'):
                        app_id = filename.replace('_api_key', '')
                        api_key = self._load_api_key_from_file(app_id)
                        if api_key:
                            stored_keys[app_id] = api_key[:16] + "..."
            
            return stored_keys
            
        except Exception as e:
            return {}

    def validate_api_key(self, api_key: str) -> Optional[Dict[str, Any]]:
        """Validate an API key and return app data if valid."""
        try:
            if not api_key:
                return None
            
            # Check if API key exists in Redis
            redis_key = f"api_key:{api_key}"
            key_data = self.redis_manager.get(redis_key)
            
            if not key_data:
                return None
            
            # Check if key is active
            if not key_data.get('is_active', False):
                return None
            
            # Update last used timestamp
            key_data['last_used'] = str(int(time.time()))
            self.redis_manager.set(redis_key, key_data, expire=2592000)
            return key_data
            
        except Exception as e:
            return None

    def revoke_api_key(self, api_key: str) -> bool:
        """Revoke an API key with enhanced cache cleanup."""
        try:
            redis_key = f"api_key:{api_key}"
            key_data = self.redis_manager.get(redis_key)
            
            if key_data:
                app_id = key_data.get('app_id')
                
                # Use atomic operation for revocation
                key_data['is_active'] = False
                key_data['revoked_at'] = str(int(time.time()))
                
                success = self._atomic_key_replacement(None, redis_key, key_data)
                if not success:
                    raise Exception("Failed to revoke API key atomically")
                
                # Comprehensive cache invalidation
                self.invalidate_api_key_cache(app_id)
                return True
            else:
                return False
                
        except Exception as e:
            return False

    def list_api_keys(self) -> list:
        """List all API keys (for admin purposes)."""
        try:
            keys = []
            pattern = "api_key:*"
            api_keys = self.redis_manager.redis.keys(pattern)
            
            for key in api_keys:
                key_data = self.redis_manager.get(key)
                if key_data:
                    # Mask the actual API key
                    masked_key = key.replace("api_key:", "")[:16] + "..."
                    keys.append({
                        'api_key': masked_key,
                        'app_id': key_data.get('app_id'),
                        'app_name': key_data.get('app_name'),
                        'permissions': key_data.get('permissions'),
                        'is_active': key_data.get('is_active'),
                        'created_at': key_data.get('created_at'),
                        'last_used': key_data.get('last_used')
                    })
            
            return keys
            
        except Exception as e:
            return []

    def get_app_by_api_key(self, api_key: str) -> Optional[str]:
        """Get app ID by API key."""
        try:
            key_data = self.validate_api_key(api_key)
            return key_data.get('app_id') if key_data else None
        except Exception as e:
            return None

    def health_check(self) -> Dict[str, Any]:
        """Perform comprehensive health check for unified API Key Manager."""
        try:
            health_status = {
                'module': 'unified_api_key_manager',
                'status': 'healthy',
                'capabilities': {
                    'generation': True,
                    'validation': True,
                    'storage': True,
                    'cache_management': True
                },
                'details': {}
            }
            
            # Test connection to credit system
            try:
                response = requests.get(
                    f"{self.credit_system_url}/health",
                    timeout=5
                )
                credit_system_status = "healthy" if response.status_code == 200 else "unhealthy"
            except Exception as e:
                credit_system_status = f"error: {str(e)}"
            
            # Check Redis connection
            redis_healthy = self.redis_manager.ping()
            
            # Check if secret files exist
            secret_files = {}
            if os.path.exists(self.secrets_dir):
                for filename in os.listdir(self.secrets_dir):
                    if filename.endswith('_api_key'):
                        app_id = filename.replace('_api_key', '')
                        secret_files[app_id] = os.path.exists(os.path.join(self.secrets_dir, filename))
            
            # Check external app API key
            external_app_key_exists = bool(Config.CREDIT_SYSTEM_API_KEY)
            
            health_status['details'] = {
                'credit_system_connection': credit_system_status,
                'credit_system_url': self.credit_system_url,
                'redis_connection': 'healthy' if redis_healthy else 'unhealthy',
                'external_app_key_configured': external_app_key_exists,
                'secret_files': secret_files,
                'app_id': self.app_id,
                'app_name': self.app_name
            }
            
            # Overall status
            if not redis_healthy:
                health_status['status'] = 'unhealthy'
                health_status['details']['reason'] = 'Redis connection required for core functionality'
            elif credit_system_status != 'healthy':
                health_status['status'] = 'degraded'
                health_status['details']['reason'] = 'Credit system connection issues'
            
            return health_status
            
        except Exception as e:
            return {
                'module': 'unified_api_key_manager',
                'status': 'unhealthy',
                'error': str(e)
            }

    # === HTTP ENDPOINT METHODS ===

    def validate_api_key_endpoint(self):
        """Validate an API key endpoint."""
        try:
            data = request.get_json()
            
            if not data.get('api_key'):
                return jsonify({
                    'success': False,
                    'error': 'API key required'
                }), 400
            
            api_key = data['api_key']
            key_data = self.validate_api_key(api_key)
            
            if key_data:
                return jsonify({
                    'success': True,
                    'valid': True,
                    'app_id': key_data.get('app_id'),
                    'app_name': key_data.get('app_name'),
                    'permissions': key_data.get('permissions'),
                    'is_active': key_data.get('is_active')
                }), 200
            else:
                return jsonify({
                    'success': True,
                    'valid': False,
                    'error': 'Invalid or expired API key'
                }), 200
            
        except Exception as e:
            return jsonify({
                'success': False,
                'error': f'Failed to validate API key: {str(e)}'
            }), 500

    def revoke_api_key_endpoint(self):
        """Revoke an API key endpoint."""
        try:
            data = request.get_json()
            
            if not data.get('api_key'):
                return jsonify({
                    'success': False,
                    'error': 'API key required'
                }), 400
            
            api_key = data['api_key']
            success = self.revoke_api_key(api_key)
            
            if success:
                return jsonify({
                    'success': True,
                    'message': 'API key revoked successfully'
                }), 200
            else:
                return jsonify({
                    'success': False,
                    'error': 'Failed to revoke API key'
                }), 400
            
        except Exception as e:
            return jsonify({
                'success': False,
                'error': f'Failed to revoke API key: {str(e)}'
            }), 500

    def list_stored_api_keys_endpoint(self):
        """List all API keys stored in secret files endpoint."""
        try:
            stored_keys = self.list_stored_api_keys()
            
            return jsonify({
                'success': True,
                'stored_api_keys': stored_keys,
                'count': len(stored_keys)
            }), 200
            
        except Exception as e:
            return jsonify({
                'success': False,
                'error': f'Failed to list stored API keys: {str(e)}'
            }), 500

    def request_api_key_from_credit_system_endpoint(self):
        """Request a new API key from the credit system endpoint."""
        try:
            # Generate API key for external app
            api_key = self.generate_api_key_from_credit_system()
            
            if api_key:
                # Save the API key
                self.save_credit_system_api_key(api_key)
                return jsonify({
                    'success': True,
                    'api_key': api_key
                }), 201
            else:
                return jsonify({
                    'success': False,
                    'error': 'Failed to generate API key from credit system'
                }), 500
                
        except Exception as e:
            return jsonify({
                'success': False,
                'error': f'Failed to request API key: {str(e)}'
            }), 500

    def ensure_external_app_api_key(self):
        """Ensure the external app has an API key, generate if needed."""
        try:
            # Check if external app API key exists
            if not Config.CREDIT_SYSTEM_API_KEY or Config.CREDIT_SYSTEM_API_KEY == "":
                
                # Generate API key for external app
                api_key = self.generate_api_key_from_credit_system()
                
                if api_key:
                    # Set the API key in config
                    Config.set_credit_system_api_key(api_key)
                else:
                    pass
            else:
                pass
        except Exception as e:
            pass

    def generate_external_app_api_key(self):
        """Generate API key specifically for this external app."""
        try:
            # Generate API key for external app
            api_key = self.generate_api_key_from_credit_system()
            
            if api_key:
                # Save the API key
                self.save_credit_system_api_key(api_key)
                return api_key
            else:
                return None
            
        except Exception as e:
            return None 