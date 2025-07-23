from tools.logger.custom_logging import custom_log
from datetime import datetime
from typing import Dict, Any, Optional, List
import requests
import os


class CreditSystemModule:
    """
    Pure business logic module for credit system operations.
    Completely decoupled from global config - uses only module-specific secrets.
    """
    
    def __init__(self):
        """
        Initialize CreditSystemModule with completely independent secret access.
        No dependencies on global config class.
        """
        self.module_name = "credit_system_module"
        # Secrets directory is inside the module directory
        self.secrets_dir = f"system/modules/{self.module_name}/secrets"
        custom_log(f"CreditSystemModule created with independent secrets: {self.secrets_dir}")

    def initialize(self):
        """Initialize the module."""
        custom_log(f"CreditSystemModule initialized with independent secrets from {self.secrets_dir}")

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

    def _get_credit_system_url(self) -> str:
        """
        Get credit system URL with module-specific secrets first, then environment, then default.
        Completely independent of config class.
        """
        # Try module-specific secret first
        module_secret = self._read_module_secret("credit_system_url")
        if module_secret:
            return module_secret
        
        # Try environment variable
        env_value = self._get_environment_variable("CREDIT_SYSTEM_URL")
        if env_value:
            return env_value
        
        # Default fallback
        return "http://localhost:8000"

    def _get_api_key(self) -> str:
        """
        Get API key with module-specific secrets first, then environment, then default.
        Completely independent of config class.
        """
        # Try module-specific secret first
        module_secret = self._read_module_secret("api_key")
        if module_secret:
            return module_secret
        
        # Try environment variable
        env_value = self._get_environment_variable("CREDIT_SYSTEM_API_KEY")
        if env_value:
            return env_value
        
        # Default fallback
        return ""

    def get_secret_sources(self) -> Dict[str, Any]:
        """
        Get information about where secrets are being read from.
        
        Returns:
            Dict with secret source information
        """
        url_secret = self._read_module_secret("credit_system_url")
        api_key_secret = self._read_module_secret("api_key")
        url_env = self._get_environment_variable("CREDIT_SYSTEM_URL")
        api_key_env = self._get_environment_variable("CREDIT_SYSTEM_API_KEY")
        
        return {
            'credit_system_url': {
                'module_secret': bool(url_secret),
                'module_secret_path': f"{self.secrets_dir}/credit_system_url" if url_secret else None,
                'environment_variable': bool(url_env),
                'environment_name': 'CREDIT_SYSTEM_URL' if url_env else None,
                'fallback_used': not bool(url_secret or url_env),
                'value': url_secret or url_env or self._get_credit_system_url()
            },
            'api_key': {
                'module_secret': bool(api_key_secret),
                'module_secret_path': f"{self.secrets_dir}/api_key" if api_key_secret else None,
                'environment_variable': bool(api_key_env),
                'environment_name': 'CREDIT_SYSTEM_API_KEY' if api_key_env else None,
                'fallback_used': not bool(api_key_secret or api_key_env),
                'configured': bool(api_key_secret or api_key_env or self._get_api_key())
            }
        }

    def process_user_creation(self, user_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Process user creation event.
        
        Args:
            user_data: User data dictionary
            
        Returns:
            Dict with success status and response data
        """
        try:
            user_id = user_data.get('user_id')
            username = user_data.get('username')
            email = user_data.get('email')
            app_id = user_data.get('app_id')
            app_name = user_data.get('app_name')
            source = user_data.get('source', 'external_app')
            
            custom_log(f"Processing user creation for {username} ({email})")
            
            # Prepare data for credit system
            credit_system_user_data = {
                'email': email,
                'username': username,
                'password': 'temporary_password_123',
                'status': 'active',
                'app_id': app_id,
                'app_name': app_name,
                    'source': source,
                    'created_via': 'external_app'
            }
            
            # Forward to credit system
            headers = {
                'X-API-Key': self._get_api_key(),
                'Content-Type': 'application/json'
            }
            
            target_url = f"{self._get_credit_system_url()}/users/create"
            
            response = requests.post(
                url=target_url,
                headers=headers,
                json=credit_system_user_data,
                timeout=30
            )
                
            if response.status_code in [200, 201]:
                return {
                    'success': True,
                    'message': f'User {username} synced to credit system',
                    'data': response.json()
                }
            else:
                return {
                    'success': False,
                    'error': f'Sync failed - status {response.status_code}',
                    'data': response.text
                }
                
        except Exception as e:
            return {
                'success': False,
                'error': f'Error processing user creation: {str(e)}'
            }

    def forward_request(self, request_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Forward a request to the credit system.
        
        Args:
            request_data: Dictionary with method, path, headers, data
            
        Returns:
            Dict with response status and data
        """
        try:
            method = request_data.get('method', 'GET')
            path = request_data.get('path', '')
            headers = request_data.get('headers', {})
            data = request_data.get('data')
            
            # Add API key to headers
            headers['X-API-Key'] = self._get_api_key()
            headers['Content-Type'] = 'application/json'
            
            target_url = f"{self._get_credit_system_url()}{path}"
            
            response = requests.request(
                method=method,
                url=target_url,
                headers=headers,
                json=data if data else None,
                timeout=30
            )
            
            return {
                'success': True,
                'status_code': response.status_code,
                'data': response.json() if response.content else {},
                'headers': dict(response.headers)
            }
            
        except Exception as e:
            return {
                'success': False,
                'error': f'Error forwarding request: {str(e)}'
            }

    def health_check(self) -> Dict[str, Any]:
        """
        Perform health check on credit system.
        
        Returns:
            Dict with health status
        """
        try:
            response = requests.get(
                f"{self._get_credit_system_url()}/health",
                headers={'X-API-Key': self._get_api_key()},
                timeout=5
            )
            
            return {
                'status': 'healthy' if response.status_code == 200 else 'unhealthy',
                'url': self._get_credit_system_url(),
                'api_key_configured': bool(self._get_api_key()),
                'response_code': response.status_code,
                'secret_sources': self.get_secret_sources()
            }
            
        except Exception as e:
            return {
                'status': 'unhealthy',
                'error': str(e),
                'url': self._get_credit_system_url(),
                'api_key_configured': bool(self._get_api_key()),
                'secret_sources': self.get_secret_sources()
            }

    def get_config(self) -> Dict[str, Any]:
        """Get module configuration with secret source information."""
        return {
            'credit_system_url': self._get_credit_system_url(),
            'api_key_configured': bool(self._get_api_key()),
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
                'key': 'credit_system_url',
                'description': 'External credit system API URL',
                'required': True,
                'default': 'http://localhost:8000',
                'type': 'string',
                'module_secret_file': f'{self.secrets_dir}/credit_system_url',
                'global_secret_file': 'credit_system_url',
                'env_var': 'CREDIT_SYSTEM_URL',
                'decoupled': True
            },
            {
                'key': 'api_key',
                'description': 'API key for credit system authentication',
                'required': True,
                'default': '',
                'type': 'string',
                'sensitive': True,
                'module_secret_file': f'{self.secrets_dir}/api_key',
                'global_secret_file': 'credit_system_api_key',
                'env_var': 'CREDIT_SYSTEM_API_KEY',
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
                'priority': 15,
                'context': 'credit_system',
                'description': 'Process user creation in credit system'
            }
        ]

    def get_routes_needed(self) -> List[Dict[str, Any]]:
        """
        Declare what routes this module needs.
        Returns list of route requirements for the orchestrator to register.
        """
        return [
            {
                'route': '/credit-system/health',
                'methods': ['GET'],
                'handler': 'health_check',
                'description': 'Check credit system health',
                'auth_required': False
            },
            {
                'route': '/credit-system/config',
                'methods': ['GET'],
                'handler': 'get_config',
                'description': 'Get credit system configuration',
                'auth_required': False
            },
            {
                'route': '/credit-system/forward',
                'methods': ['POST'],
                'handler': 'forward_request',
                'description': 'Forward request to credit system',
                'auth_required': True
            },
            {
                'route': '/credit-system/user/create',
                'methods': ['POST'],
                'handler': 'process_user_creation',
                'description': 'Process user creation in credit system',
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
        else:
            return {
                'success': False,
                'error': f'Unknown hook event: {event_name}'
            } 