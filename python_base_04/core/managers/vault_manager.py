import requests
import json
import os
import logging
from typing import Dict, Any, Optional
from datetime import datetime, timedelta


class VaultManager:
    """
    HashiCorp Vault Manager using AppRole authentication.
    
    This manager handles authentication and secret retrieval from Vault
    using the REST API (no hvac dependency required).
    
    Gracefully handles missing configuration for local development.
    """
    
    def __init__(self):
        """Initialize the Vault manager with AppRole authentication."""
        self.logger = logging.getLogger(__name__)
        
        # Vault configuration
        self.vault_addr = os.getenv('VAULT_ADDR', 'http://vault-proxy:8200')
        self.role_id = os.getenv('VAULT_ROLE_ID')
        self.secret_id = os.getenv('VAULT_SECRET_ID')
        
        # Authentication state
        self.client_token = None
        self.token_expiry = None
        self.lease_duration = None
        self.available = False  # Track if Vault is available for use
        
        # Try to validate configuration and authenticate
        if self._validate_config():
            if self._authenticate():
                self.available = True
                self.logger.info("✅ VaultManager initialized successfully")
            else:
                self.logger.warning("⚠️ VaultManager initialized but authentication failed - using file-based secrets")
        else:
            self.logger.warning("⚠️ VaultManager initialized but configuration incomplete - using file-based secrets")
    
    def _validate_config(self) -> bool:
        """
        Validate Vault configuration.
        
        Returns:
            bool: True if configuration is valid, False otherwise
        """
        missing_vars = []
        
        if not self.role_id:
            missing_vars.append("VAULT_ROLE_ID")
        if not self.secret_id:
            missing_vars.append("VAULT_SECRET_ID")
        if not self.vault_addr:
            missing_vars.append("VAULT_ADDR")
        
        if missing_vars:
            self.logger.warning(f"⚠️ Missing Vault environment variables: {', '.join(missing_vars)}")
            self.logger.warning("⚠️ VaultManager will be unavailable - falling back to file-based secrets")
            return False
        
        self.logger.info(f"✅ Vault configuration validated: {self.vault_addr}")
        return True
    
    def _authenticate(self) -> bool:
        """
        Authenticate with Vault using AppRole.
        
        Returns:
            bool: True if authentication successful, False otherwise
        """
        try:
            auth_data = {
                'role_id': self.role_id,
                'secret_id': self.secret_id
            }
            
            response = requests.post(
                f'{self.vault_addr}/v1/auth/approle/login',
                json=auth_data,
                timeout=10
            )
            
            if response.status_code == 200:
                auth_result = response.json()
                auth_info = auth_result.get('auth', {})
                
                self.client_token = auth_info.get('client_token')
                self.lease_duration = auth_info.get('lease_duration', 3600)
                
                # Set token expiry (with 5 minute buffer)
                self.token_expiry = datetime.now() + timedelta(seconds=self.lease_duration - 300)
                
                self.logger.info(f"✅ Vault authentication successful (lease: {self.lease_duration}s)")
                return True
            else:
                self.logger.warning(f"⚠️ Vault authentication failed: {response.status_code} - {response.text}")
                return False
                
        except requests.exceptions.RequestException as e:
            self.logger.warning(f"⚠️ Vault authentication request failed: {e}")
            return False
        except Exception as e:
            self.logger.warning(f"⚠️ Vault authentication error: {e}")
            return False
    
    def _ensure_authenticated(self) -> bool:
        """
        Ensure we have a valid authentication token.
        
        Returns:
            bool: True if authenticated, False otherwise
        """
        if not self.available:
            return False
            
        # Check if token exists and is not expired
        if (self.client_token and 
            self.token_expiry and 
            datetime.now() < self.token_expiry):
            return True
        
        # Re-authenticate if token is missing or expired
        self.logger.info("Token expired or missing, re-authenticating...")
        success = self._authenticate()
        if not success:
            self.available = False
            self.logger.warning("⚠️ Vault re-authentication failed - marking as unavailable")
        return success
    
    def get_secret(self, path: str) -> Optional[Dict[str, Any]]:
        """
        Retrieve a secret from Vault.
        
        Args:
            path (str): Secret path (e.g., 'flask-app/mongodb')
            
        Returns:
            Optional[Dict[str, Any]]: Secret data or None if not found or Vault unavailable
        """
        if not self.available:
            return None
            
        if not self._ensure_authenticated():
            self.logger.warning("⚠️ Cannot retrieve secret: authentication failed")
            return None
        
        try:
            headers = {
                'X-Vault-Token': self.client_token
            }
            
            # Use KV v2 API format
            api_path = f'/v1/secret/data/{path}'
            response = requests.get(
                f'{self.vault_addr}{api_path}',
                headers=headers,
                timeout=10
            )
            
            if response.status_code == 200:
                secret_data = response.json()
                # KV v2 stores data in data.data
                if 'data' in secret_data and 'data' in secret_data['data']:
                    secrets = secret_data['data']['data']
                    self.logger.info(f"✅ Retrieved secret from path: {path}")
                    return secrets
                else:
                    self.logger.warning(f"⚠️ No data found in secret path: {path}")
                    return None
            elif response.status_code == 404:
                self.logger.warning(f"⚠️ Secret not found: {path}")
                return None
            else:
                self.logger.warning(f"⚠️ Failed to retrieve secret {path}: {response.status_code}")
                return None
                
        except requests.exceptions.RequestException as e:
            self.logger.warning(f"⚠️ Request failed for secret {path}: {e}")
            return None
        except Exception as e:
            self.logger.warning(f"⚠️ Error retrieving secret {path}: {e}")
            return None
    
    def get_secret_value(self, path: str, key: str, default: Any = None) -> Any:
        """
        Get a specific value from a secret.
        
        Args:
            path (str): Secret path
            key (str): Key within the secret
            default (Any): Default value if key not found
            
        Returns:
            Any: Secret value or default
        """
        if not self.available:
            return default
            
        secret = self.get_secret(path)
        if secret and key in secret:
            return secret[key]
        return default
    
    def get_mongodb_secrets(self) -> Optional[Dict[str, Any]]:
        """Get MongoDB secrets from Vault."""
        if not self.available:
            return None
        return self.get_secret('flask-app/mongodb')
    
    def get_redis_secrets(self) -> Optional[Dict[str, Any]]:
        """Get Redis secrets from Vault."""
        if not self.available:
            return None
        return self.get_secret('flask-app/redis')
    
    def get_app_secrets(self) -> Optional[Dict[str, Any]]:
        """Get Flask application secrets from Vault."""
        if not self.available:
            return None
        return self.get_secret('flask-app/app')
    
    def get_stripe_secrets(self) -> Optional[Dict[str, Any]]:
        """Get Stripe secrets from Vault."""
        if not self.available:
            return None
        return self.get_secret('flask-app/stripe')
    
    def get_monitoring_secrets(self) -> Optional[Dict[str, Any]]:
        """Get monitoring secrets from Vault."""
        if not self.available:
            return None
        return self.get_secret('flask-app/monitoring')
    
    def health_check(self) -> bool:
        """
        Check Vault health and connectivity.
        
        Returns:
            bool: True if Vault is healthy, False otherwise
        """
        if not self.available:
            return False
            
        try:
            response = requests.get(
                f'{self.vault_addr}/v1/sys/health',
                timeout=10
            )
            
            if response.status_code == 200:
                health_data = response.json()
                if health_data.get('sealed', True):
                    self.logger.warning("⚠️ Vault is sealed")
                    return False
                else:
                    self.logger.info("✅ Vault health check passed")
                    return True
            else:
                self.logger.warning(f"⚠️ Vault health check failed: {response.status_code}")
                return False
                
        except requests.exceptions.RequestException as e:
            self.logger.warning(f"⚠️ Vault health check request failed: {e}")
            return False
        except Exception as e:
            self.logger.warning(f"⚠️ Vault health check error: {e}")
            return False
    
    def get_connection_info(self) -> Dict[str, Any]:
        """
        Get Vault connection information for debugging.
        
        Returns:
            Dict[str, Any]: Connection information
        """
        return {
            'vault_addr': self.vault_addr,
            'available': self.available,
            'authenticated': self.client_token is not None,
            'token_expiry': self.token_expiry.isoformat() if self.token_expiry else None,
            'lease_duration': self.lease_duration,
            'role_id': self.role_id[:15] + '...' if self.role_id else None
        } 