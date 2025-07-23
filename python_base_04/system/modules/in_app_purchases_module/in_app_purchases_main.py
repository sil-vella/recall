"""
In-App Purchases Module - Pure Business Logic

Handles in-app purchase verification and management business logic.
Completely decoupled from system dependencies.
"""

from typing import Dict, Any, Optional, List
from tools.logger.custom_logging import custom_log
from datetime import datetime
import os


class InAppPurchasesModule:
    """
    Pure business logic module for in-app purchases.
    Completely decoupled from system dependencies.
    """
    
    def __init__(self):
        """
        Initialize InAppPurchasesModule with independent secret access.
        No dependencies on system managers or Flask.
        """
        self.module_name = "in_app_purchases_module"
        # Secrets directory is inside the module directory
        self.secrets_dir = f"system/modules/{self.module_name}/secrets"
        custom_log(f"InAppPurchasesModule created with independent secrets: {self.secrets_dir}")

    def initialize(self):
        """Initialize the module."""
        custom_log(f"InAppPurchasesModule initialized with independent secrets from {self.secrets_dir}")

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

    def _get_google_play_secret(self) -> str:
        """
        Get Google Play secret with module-specific secrets first, then environment, then default.
        """
        # Try module-specific secret first
        module_secret = self._read_module_secret("google_play_secret")
        if module_secret:
            return module_secret
        
        # Try environment variable
        env_value = self._get_environment_variable("GOOGLE_PLAY_SECRET")
        if env_value:
            return env_value
        
        # Default fallback
        return "your-google-play-secret-key"

    def _get_app_store_secret(self) -> str:
        """
        Get App Store secret with module-specific secrets first, then environment, then default.
        """
        # Try module-specific secret first
        module_secret = self._read_module_secret("app_store_secret")
        if module_secret:
            return module_secret
        
        # Try environment variable
        env_value = self._get_environment_variable("APP_STORE_SECRET")
        if env_value:
            return env_value
        
        # Default fallback
        return "your-app-store-secret-key"

    def get_secret_sources(self) -> Dict[str, Any]:
        """
        Get information about secret sources for debugging.
        
        Returns:
            Dict with secret source information
        """
        return {
            "module_secrets_dir": self.secrets_dir,
            "google_play_secret": "configured" if self._get_google_play_secret() else "not_found",
            "app_store_secret": "configured" if self._get_app_store_secret() else "not_found",
            "environment_variables": {
                "GOOGLE_PLAY_SECRET": bool(self._get_environment_variable("GOOGLE_PLAY_SECRET")),
                "APP_STORE_SECRET": bool(self._get_environment_variable("APP_STORE_SECRET"))
            }
        }

    def validate_purchase_data(self, purchase_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Validate purchase data for verification.
        
        Args:
            purchase_data: Purchase data to validate
            
        Returns:
            Dict with validation result
        """
        try:
            # Validate required fields (user_id will be provided by orchestrator from JWT)
            required_fields = ["platform", "receipt_data", "product_id"]
            missing_fields = [field for field in required_fields if not purchase_data.get(field)]
            
            if missing_fields:
                return {
                    'success': False,
                    'error': f"Missing required fields: {', '.join(missing_fields)}"
                }
            
            platform = purchase_data.get("platform")
            receipt_data = purchase_data.get("receipt_data")
            product_id = purchase_data.get("product_id")
            
            # Validate platform
            if platform not in ['google_play', 'app_store']:
                return {
                    'success': False,
                    'error': "Unsupported platform. Must be 'google_play' or 'app_store'"
                }
            
            # Validate receipt data
            if not receipt_data or not isinstance(receipt_data, str):
                return {
                    'success': False,
                    'error': "Invalid receipt data"
                }
            
            # Validate product ID
            if not product_id or not isinstance(product_id, str):
                return {
                    'success': False,
                    'error': "Invalid product ID"
                }
            
            return {
                'success': True,
                'validated_data': {
                    'platform': platform,
                    'receipt_data': receipt_data,
                    'product_id': product_id
                }
            }
            
        except Exception as e:
            return {
                'success': False,
                'error': f'Validation error: {str(e)}'
            }

    def process_purchase_verification(self, purchase_data: Dict[str, Any], user_id: str) -> Dict[str, Any]:
        """
        Process purchase verification (pure business logic).
        
        Args:
            purchase_data: Purchase data to verify
            user_id: User ID from JWT token
            
        Returns:
            Dict with verification result
        """
        try:
            # Validate input data
            validation_result = self.validate_purchase_data(purchase_data)
            if not validation_result['success']:
                return validation_result
            
            # Extract validated data
            platform = validation_result['validated_data']['platform']
            receipt_data = validation_result['validated_data']['receipt_data']
            product_id = validation_result['validated_data']['product_id']
            
            # Mock verification logic (in real implementation, this would call verifiers)
            # For now, we'll simulate verification based on platform
            if platform == 'google_play':
                # Simulate Google Play verification
                verification_result = self._simulate_google_play_verification(receipt_data, product_id)
            elif platform == 'app_store':
                # Simulate App Store verification
                verification_result = self._simulate_app_store_verification(receipt_data, product_id)
            else:
                return {
                    'success': False,
                    'error': 'Unsupported platform'
                }
            
            if verification_result['valid']:
                # Prepare purchase document for orchestrator to persist
                purchase_document = self._prepare_purchase_document(
                    user_id, product_id, platform, verification_result
                )
                
                return {
                    'success': True,
                    'verification_result': verification_result,
                    'purchase_document': purchase_document
                }
            else:
                return {
                    'success': False,
                    'error': verification_result.get('error', 'Invalid purchase'),
                    'verification_result': verification_result
                }
                
        except Exception as e:
            custom_log(f"Error processing purchase verification: {e}", level="ERROR")
            return {
                'success': False,
                'error': f'Verification error: {str(e)}'
            }

    def _simulate_google_play_verification(self, receipt_data: str, product_id: str) -> Dict[str, Any]:
        """
        Simulate Google Play verification (mock implementation).
        In real implementation, this would call the actual Google Play verifier.
        
        Args:
            receipt_data: Receipt data to verify
            product_id: Product ID to verify
            
        Returns:
            Dict with verification result
        """
        # Mock verification logic
        if receipt_data and product_id:
            return {
                'valid': True,
                'platform': 'google_play',
                'product_id': product_id,
                'transaction_id': f"gplay_{datetime.utcnow().timestamp()}",
                'purchase_date': datetime.utcnow().isoformat(),
                'verification_date': datetime.utcnow().isoformat(),
                'status': 'verified'
            }
        else:
            return {
                'valid': False,
                'error': 'Invalid receipt data or product ID'
            }

    def _simulate_app_store_verification(self, receipt_data: str, product_id: str) -> Dict[str, Any]:
        """
        Simulate App Store verification (mock implementation).
        In real implementation, this would call the actual App Store verifier.
        
        Args:
            receipt_data: Receipt data to verify
            product_id: Product ID to verify
            
        Returns:
            Dict with verification result
        """
        # Mock verification logic
        if receipt_data and product_id:
            return {
                'valid': True,
                'platform': 'app_store',
                'product_id': product_id,
                'transaction_id': f"appstore_{datetime.utcnow().timestamp()}",
                'purchase_date': datetime.utcnow().isoformat(),
                'verification_date': datetime.utcnow().isoformat(),
                'status': 'verified'
            }
        else:
            return {
                'valid': False,
                'error': 'Invalid receipt data or product ID'
            }

    def _prepare_purchase_document(self, user_id: str, product_id: str, platform: str, verification_result: Dict[str, Any]) -> Dict[str, Any]:
        """
        Prepare purchase document for database storage.
        
        Args:
            user_id: User ID
            product_id: Product ID
            platform: Platform (google_play or app_store)
            verification_result: Verification result from platform
            
        Returns:
            Dict with purchase document
        """
        return {
            'user_id': user_id,
            'product_id': product_id,
            'platform': platform,
            'transaction_id': verification_result.get('transaction_id'),
            'purchase_date': verification_result.get('purchase_date'),
            'verification_date': verification_result.get('verification_date'),
            'status': verification_result.get('status', 'verified'),
            'created_at': datetime.utcnow().isoformat(),
            'updated_at': datetime.utcnow().isoformat()
        }

    def process_purchase_history_request(self, user_id: str) -> Dict[str, Any]:
        """
        Process purchase history request (pure business logic).
        
        Args:
            user_id: User ID to get history for
            
        Returns:
            Dict with history request result
        """
        try:
            if not user_id:
                return {
                    'success': False,
                    'error': 'User ID is required'
                }
            
            # Return request data for orchestrator to fetch from database
            return {
                'success': True,
                'user_id': user_id,
                'query': {'user_id': user_id}
            }
            
        except Exception as e:
            custom_log(f"Error processing purchase history request: {e}", level="ERROR")
            return {
                'success': False,
                'error': f'History request error: {str(e)}'
            }

    def process_purchase_restoration_request(self, user_id: str) -> Dict[str, Any]:
        """
        Process purchase restoration request (pure business logic).
        
        Args:
            user_id: User ID to restore purchases for
            
        Returns:
            Dict with restoration request result
        """
        try:
            if not user_id:
                return {
                    'success': False,
                    'error': 'User ID is required'
                }
            
            # Return request data for orchestrator to fetch from database
            return {
                'success': True,
                'user_id': user_id,
                'query': {'user_id': user_id, 'status': 'verified'}
            }
            
        except Exception as e:
            custom_log(f"Error processing purchase restoration request: {e}", level="ERROR")
            return {
                'success': False,
                'error': f'Restoration request error: {str(e)}'
            }

    def process_product_sync_request(self, platform: Optional[str] = None) -> Dict[str, Any]:
        """
        Process product sync request (pure business logic).
        
        Args:
            platform: Platform to sync (optional)
            
        Returns:
            Dict with sync request result
        """
        try:
            # Validate platform if provided
            if platform and platform not in ['google_play', 'app_store']:
                return {
                    'success': False,
                    'error': 'Invalid platform. Must be "google_play" or "app_store"'
                }
            
            # Return sync request data for orchestrator to process
            return {
                'success': True,
                'platform': platform,
                'sync_request': {
                    'platform': platform,
                    'started_at': datetime.utcnow().isoformat(),
                    'sync_status': 'pending'
                }
            }
            
        except Exception as e:
            custom_log(f"Error processing product sync request: {e}", level="ERROR")
            return {
                'success': False,
                'error': f'Sync request error: {str(e)}'
            }

    def process_products_request(self, platform: Optional[str] = None) -> Dict[str, Any]:
        """
        Process products request (pure business logic).
        
        Args:
            platform: Platform filter (optional)
            
        Returns:
            Dict with products request result
        """
        try:
            # Validate platform if provided
            if platform and platform not in ['google_play', 'app_store']:
                return {
                    'success': False,
                    'error': 'Invalid platform. Must be "google_play" or "app_store"'
                }
            
            # Return query data for orchestrator to fetch from database
            query = {}
            if platform:
                query['platform'] = platform
            
            return {
                'success': True,
                'query': query,
                'platform_filter': platform
            }
            
        except Exception as e:
            custom_log(f"Error processing products request: {e}", level="ERROR")
            return {
                'success': False,
                'error': f'Products request error: {str(e)}'
            }

    def process_sync_history_request(self, platform: Optional[str] = None, limit: int = 10) -> Dict[str, Any]:
        """
        Process sync history request (pure business logic).
        
        Args:
            platform: Platform filter (optional)
            limit: Number of records to return
            
        Returns:
            Dict with sync history request result
        """
        try:
            # Validate platform if provided
            if platform and platform not in ['google_play', 'app_store']:
                return {
                    'success': False,
                    'error': 'Invalid platform. Must be "google_play" or "app_store"'
                }
            
            # Validate limit
            if not isinstance(limit, int) or limit < 1 or limit > 100:
                return {
                    'success': False,
                    'error': 'Invalid limit. Must be between 1 and 100'
                }
            
            # Return query data for orchestrator to fetch from database
            query = {}
            if platform:
                query['platform'] = platform
            
            return {
                'success': True,
                'query': query,
                'limit': limit,
                'platform_filter': platform
            }
            
        except Exception as e:
            custom_log(f"Error processing sync history request: {e}", level="ERROR")
            return {
                'success': False,
                'error': f'Sync history request error: {str(e)}'
            }

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
        
        # Convert datetime objects to ISO format
        def convert_datetime(obj):
            if isinstance(obj, datetime):
                return obj.isoformat()
            return obj
        
        # Remove sensitive fields
        sensitive_fields = ['password', 'password_hash', 'reset_token', 'reset_token_expires']
        cleaned_data = {k: v for k, v in user_data.items() if k not in sensitive_fields}
        
        # Convert datetime fields
        for key, value in cleaned_data.items():
            if isinstance(value, datetime):
                cleaned_data[key] = value.isoformat()
        
        return cleaned_data

    def health_check(self) -> Dict[str, Any]:
        """Module health check."""
        return {
            "module": self.module_name,
            "status": "healthy",
            "details": "In-app purchases module with Google Play and App Store verification",
            "secret_sources": self.get_secret_sources()
        }

    def get_config(self) -> Dict[str, Any]:
        """Get module configuration."""
        return {
            "module_name": self.module_name,
            "secrets_configured": {
                "google_play_secret": bool(self._get_google_play_secret()),
                "app_store_secret": bool(self._get_app_store_secret())
            },
            "supported_platforms": ["google_play", "app_store"]
        }

    def get_config_requirements(self) -> List[Dict[str, Any]]:
        """Get module configuration requirements."""
        return [
            {
                "name": "google_play_secret",
                "type": "secret",
                "description": "Google Play service account key for purchase verification",
                "required": False,
                "default": "your-google-play-secret-key"
            },
            {
                "name": "app_store_secret",
                "type": "secret",
                "description": "App Store shared secret for purchase verification",
                "required": False,
                "default": "your-app-store-secret-key"
            }
        ]

    def get_hooks_needed(self) -> List[Dict[str, Any]]:
        """Get hooks needed by this module."""
        return [
            {
                'event': 'purchase_verified',
                'priority': 10,
                'context': 'in_app_purchases',
                'description': 'Process verified purchase in in-app purchases module'
            },
            {
                'event': 'products_synced',
                'priority': 10,
                'context': 'in_app_purchases',
                'description': 'Process product sync completion in in-app purchases module'
            }
        ]

    def get_routes_needed(self) -> List[Dict[str, Any]]:
        """Get routes needed by this module."""
        return [
            {
                'route': '/userauth/purchases/verify',
                'methods': ['POST'],
                'handler': 'verify_purchase',
                'description': 'Verify a purchase receipt',
                'auth_required': True
            },
            {
                'route': '/userauth/purchases/history',
                'methods': ['GET'],
                'handler': 'get_purchase_history',
                'description': 'Get user purchase history',
                'auth_required': True
            },
            {
                'route': '/userauth/purchases/restore',
                'methods': ['POST'],
                'handler': 'restore_purchases',
                'description': 'Restore user purchases',
                'auth_required': True
            },
            {
                'route': '/in-app-purchases/sync-products',
                'methods': ['POST'],
                'handler': 'sync_products',
                'description': 'Sync products from stores',
                'auth_required': True
            },
            {
                'route': '/in-app-purchases/products',
                'methods': ['GET'],
                'handler': 'get_products',
                'description': 'Get all synced products',
                'auth_required': True
            },
            {
                'route': '/in-app-purchases/sync-history',
                'methods': ['GET'],
                'handler': 'get_sync_history',
                'description': 'Get sync history',
                'auth_required': True
            }
        ]

    def process_hook_event(self, event_name: str, event_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Process hook events (pure business logic).
        
        Args:
            event_name: Name of the hook event
            event_data: Event data
            
        Returns:
            Dict with processing result
        """
        try:
            if event_name == 'purchase_verified':
                return self._process_purchase_verified_event(event_data)
            elif event_name == 'products_synced':
                return self._process_products_synced_event(event_data)
            else:
                return {
                    'success': False,
                    'error': f'Unknown hook event: {event_name}'
                }
                
        except Exception as e:
            custom_log(f"Error processing hook event {event_name}: {e}", level="ERROR")
            return {
                'success': False,
                'error': f'Hook event processing error: {str(e)}'
            }

    def _process_purchase_verified_event(self, event_data: Dict[str, Any]) -> Dict[str, Any]:
        """Process purchase verified event."""
        return {
            'success': True,
            'message': 'Purchase verified event processed',
            'event_data': event_data
        }

    def _process_products_synced_event(self, event_data: Dict[str, Any]) -> Dict[str, Any]:
        """Process products synced event."""
        return {
            'success': True,
            'message': 'Products synced event processed',
            'event_data': event_data
        } 