from datetime import datetime, timedelta
import jwt
from jwt.exceptions import InvalidTokenError, ExpiredSignatureError, InvalidSignatureError, InvalidAudienceError, InvalidIssuerError
from typing import Dict, Any, Optional, Union
from tools.logger.custom_logging import custom_log
from utils.config.config import Config
from core.managers.redis_manager import RedisManager
from enum import Enum
import hashlib
from flask import request

class TokenType(Enum):
    ACCESS = "access"
    REFRESH = "refresh"

class JWTManager:
    def __init__(self, redis_manager=None):
        # Use provided redis_manager or create a new one
        self.redis_manager = redis_manager if redis_manager else RedisManager()
        self.secret_key = Config.JWT_SECRET_KEY
        self.algorithm = Config.JWT_ALGORITHM
        # Use Config values for token lifetimes
        self.access_token_expire_seconds = Config.JWT_ACCESS_TOKEN_EXPIRES  # From config
        self.refresh_token_expire_seconds = Config.JWT_REFRESH_TOKEN_EXPIRES  # From config
        custom_log("JWTManager initialized")

    def _get_client_fingerprint(self) -> str:
        """Generate a unique client fingerprint based on IP and User-Agent."""
        try:
            # Handle Docker environment - try to get real client IP
            ip = request.headers.get('X-Forwarded-For', request.headers.get('X-Real-IP', request.remote_addr))
            # If it's a comma-separated list, take the first one
            if ip and ',' in ip:
                ip = ip.split(',')[0].strip()
            user_agent = request.headers.get('User-Agent', '')
            fingerprint = hashlib.sha256(f"{ip}-{user_agent}".encode()).hexdigest()
            custom_log(f"Generated fingerprint: {fingerprint[:16]}... for IP: {ip}")
            return fingerprint
        except Exception as e:
            custom_log(f"Error generating client fingerprint: {str(e)}")
            return ""

    def create_token(self, data: Dict[str, Any], token_type: TokenType, expires_in: Optional[int] = None) -> str:
        """Create a new JWT token of specified type with client binding."""
        to_encode = data.copy()
        
        # Set expiration based on token type
        if expires_in:
            expire = datetime.utcnow() + timedelta(seconds=expires_in)
        else:
            if token_type == TokenType.ACCESS:
                expire = datetime.utcnow() + timedelta(seconds=self.access_token_expire_seconds)
            elif token_type == TokenType.REFRESH:
                expire = datetime.utcnow() + timedelta(seconds=self.refresh_token_expire_seconds)
            else:
                # Default to access token expiration for unknown token types
                expire = datetime.utcnow() + timedelta(seconds=self.access_token_expire_seconds)
        
        # Add client fingerprint for token binding
        client_fingerprint = self._get_client_fingerprint()
        if client_fingerprint:
            to_encode["fingerprint"] = client_fingerprint
            
        to_encode.update({
            "exp": expire,
            "type": token_type.value,
            "iat": datetime.utcnow()
        })
        
        encoded_jwt = jwt.encode(to_encode, self.secret_key, algorithm=self.algorithm)
        
        # Store token in Redis for revocation capability
        self._store_token(encoded_jwt, expire, token_type)
        
        return encoded_jwt

    def verify_token(self, token: str, expected_type: Optional[TokenType] = None) -> Optional[Dict[str, Any]]:
        """Verify a JWT token and return its payload if valid."""
        try:
            # First decode the token to get its type
            try:
                payload = jwt.decode(token, self.secret_key, algorithms=[self.algorithm])
            except InvalidTokenError as e:
                custom_log(f"JWT decode failed: {str(e)}")
                return None
                
            # Check if token is revoked
            if self._is_token_revoked(token):
                custom_log(f"Token revoked: {token[:10]}...")
                return None
                
            # Verify fingerprint if present in token
            token_fingerprint = payload.get("fingerprint")
            if token_fingerprint:
                current_fingerprint = self._get_client_fingerprint()
                if current_fingerprint and token_fingerprint != current_fingerprint:
                    custom_log(f"Fingerprint mismatch. Token: {token_fingerprint[:16]}..., Current: {current_fingerprint[:16]}...")
                    return None
                
            # Verify token type if specified
            if expected_type:
                token_type = payload.get("type")
                if not token_type:
                    custom_log("Token type missing in payload")
                    return None
                    
                if token_type != expected_type.value:
                    custom_log(f"Invalid token type. Expected: {expected_type.value}, Got: {token_type}")
                    return None
            
            return payload
            
        except ExpiredSignatureError:
            custom_log("Token has expired")
            return None
        except InvalidSignatureError:
            custom_log("Invalid token signature")
            return None
        except InvalidAudienceError:
            custom_log("Invalid token audience")
            return None
        except InvalidIssuerError:
            custom_log("Invalid token issuer")
            return None
        except Exception as e:
            custom_log(f"Token verification failed: {str(e)}")
            return None

    def revoke_token(self, token: str) -> bool:
        """Revoke a token by removing it from Redis."""
        try:
            # First decode the token to get its type
            try:
                payload = jwt.decode(token, self.secret_key, algorithms=[self.algorithm])
                token_type = payload.get("type")
                if not token_type:
                    custom_log("Token type missing in payload")
                    return False
            except InvalidTokenError:
                custom_log("Invalid token format")
                return False
                
            # Revoke token using Redis manager's token methods
            return self.redis_manager.revoke_token(token_type, token)
            
        except Exception as e:
            custom_log(f"Error revoking token: {str(e)}")
            return False

    def refresh_token(self, refresh_token: str) -> Optional[str]:
        """Create a new access token using a refresh token."""
        payload = self.verify_token(refresh_token, TokenType.REFRESH)
        if payload:
            # Remove refresh-specific claims
            new_payload = {k: v for k, v in payload.items() 
                         if k not in ['exp', 'iat', 'type']}
            return self.create_token(new_payload, TokenType.ACCESS)
        return None

    def _store_token(self, token: str, expire: datetime, token_type: TokenType):
        """Store token in Redis with proper prefix and expiration."""
        try:
            # Calculate TTL in seconds, ensuring it's not negative
            ttl = max(1, int((expire - datetime.utcnow()).total_seconds()))
            
            # Store token using Redis manager's token methods
            if not self.redis_manager.store_token(token_type.value, token, expire=ttl):
                custom_log(f"Failed to store {token_type.value} token")
            
        except Exception as e:
            custom_log(f"Error storing token: {str(e)}")
            # Don't raise the exception, just log it
            # This allows the token to still be used even if Redis storage fails

    def _is_token_revoked(self, token: str) -> bool:
        """Check if a token is revoked using prefix-based lookup."""
        try:
            # First decode the token to get its type
            try:
                payload = jwt.decode(token, self.secret_key, algorithms=[self.algorithm])
                token_type = payload.get("type")
                if not token_type:
                    custom_log("Token type missing in payload")
                    return True
            except InvalidTokenError:
                # If we can't decode the token, consider it revoked
                return True
                
            # Check if token is valid in Redis
            return not self.redis_manager.is_token_valid(token_type, token)
            
        except Exception as e:
            custom_log(f"Error checking token revocation: {str(e)}")
            return True  # Fail safe: consider token revoked on error

    def cleanup_expired_tokens(self):
        """Clean up expired tokens from Redis."""
        try:
            custom_log("Starting expired token cleanup")
            
            for token_type in TokenType:
                if not self.redis_manager.cleanup_expired_tokens(token_type.value):
                    custom_log(f"Failed to cleanup expired {token_type.value} tokens")
                    
            custom_log("Completed expired token cleanup")
            
        except Exception as e:
            custom_log(f"Error during token cleanup: {str(e)}")

    # Convenience methods for specific use cases
    def create_access_token(self, data: Dict[str, Any], expires_in: Optional[int] = None) -> str:
        """Create a new access token."""
        return self.create_token(data, TokenType.ACCESS, expires_in)

    def create_refresh_token(self, data: Dict[str, Any], expires_in: Optional[int] = None) -> str:
        """Create a new refresh token."""
        return self.create_token(data, TokenType.REFRESH, expires_in) 