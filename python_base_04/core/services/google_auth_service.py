"""
Google Authentication Service

This service handles verification of Google ID tokens for OAuth2 authentication.
"""

from typing import Dict, Any, Optional
from google.auth.transport import requests
from google.oauth2 import id_token
from utils.config.config import Config
from tools.logger.custom_logging import custom_log


class GoogleAuthService:
    """Service for verifying Google ID tokens."""
    
    def __init__(self):
        """Initialize Google Auth Service."""
        self.client_id = Config.GOOGLE_CLIENT_ID
        
    def verify_id_token(self, id_token_string: str) -> Optional[Dict[str, Any]]:
        """
        Verify Google ID token and return user info.
        
        Args:
            id_token_string: The Google ID token string to verify
            
        Returns:
            Dictionary containing user information if token is valid, None otherwise
            {
                'sub': Google user ID,
                'email': User email,
                'email_verified': Whether email is verified,
                'name': User full name,
                'picture': Profile picture URL,
                'given_name': First name,
                'family_name': Last name
            }
        """
        try:
            if not self.client_id:
                custom_log("GoogleAuthService: GOOGLE_CLIENT_ID not configured", level="ERROR")
                return None
            
            # Verify the token
            request_obj = requests.Request()
            idinfo = id_token.verify_oauth2_token(
                id_token_string, 
                request_obj, 
                self.client_id
            )
            
            # Verify the issuer
            if idinfo['iss'] not in ['accounts.google.com', 'https://accounts.google.com']:
                custom_log(f"GoogleAuthService: Invalid token issuer: {idinfo.get('iss')}", level="WARNING")
                return None
            
            # Token is valid, return user info
            custom_log(f"GoogleAuthService: Token verified successfully for email: {idinfo.get('email')}", level="DEBUG")
            return idinfo
            
        except ValueError as e:
            # Invalid token
            custom_log(f"GoogleAuthService: Token verification failed - Invalid token: {e}", level="ERROR")
            import traceback
            custom_log(f"GoogleAuthService: ValueError traceback: {traceback.format_exc()}", level="ERROR")
            return None
        except Exception as e:
            # Other errors (network, etc.)
            custom_log(f"GoogleAuthService: Token verification error: {e}", level="ERROR")
            import traceback
            custom_log(f"GoogleAuthService: Exception traceback: {traceback.format_exc()}", level="ERROR")
            return None
    
    def get_user_info(self, id_token_string: str) -> Optional[Dict[str, Any]]:
        """
        Extract user information from verified token.
        
        This is a convenience method that calls verify_id_token and extracts
        relevant user information.
        
        Args:
            id_token_string: The Google ID token string to verify
            
        Returns:
            Dictionary with user information:
            {
                'google_id': Google user ID (sub),
                'email': User email,
                'email_verified': Whether email is verified,
                'name': User full name,
                'picture': Profile picture URL,
                'given_name': First name,
                'family_name': Last name
            }
        """
        idinfo = self.verify_id_token(id_token_string)
        
        if not idinfo:
            return None
        
        return {
            'google_id': idinfo.get('sub'),
            'email': idinfo.get('email'),
            'email_verified': idinfo.get('email_verified', False),
            'name': idinfo.get('name'),
            'picture': idinfo.get('picture'),
            'given_name': idinfo.get('given_name'),
            'family_name': idinfo.get('family_name')
        }
