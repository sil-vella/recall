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
    WEBSOCKET = "websocket"

class JWTManager:
    def __init__(self, redis_manager=None):
        # Use provided redis_manager or create a new one
        self.redis_manager = redis_manager if redis_manager else RedisManager()
        self.secret_key = Config.JWT_SECRET_KEY
        self.algorithm = Config.JWT_ALGORITHM
        # Use Config values for token lifetimes
        self.access_token_expire_seconds = Config.JWT_ACCESS_TOKEN_EXPIRES  # From config
        self.refresh_token_expire_seconds = Config.JWT_REFRESH_TOKEN_EXPIRES  # From config
        
        # State change tracking
        self._previous_state = None
        self._pending_refresh_tokens = set()  # Track tokens that need refresh when game ends
        
        # Register state change callback
        self._register_state_change_callback()
        
        custom_log("JWTManager initialized with state change listener")

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
        """Create a new JWT token of specified type with client binding and state-dependent TTL."""
        to_encode = data.copy()
        
        # Get state-dependent TTL
        actual_expires_in = self._get_state_dependent_ttl(token_type, expires_in)
        
        # Set expiration based on token type and state
        if actual_expires_in:
            expire = datetime.utcnow() + timedelta(seconds=actual_expires_in)
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
            
            # Comprehensive claims validation
            if not self._validate_token_claims(payload):
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

    def _validate_token_claims(self, payload: Dict[str, Any]) -> bool:
        """Validate JWT token claims comprehensively."""
        try:
            # Check required claims
            required_claims = ['exp', 'iat', 'type']
            for claim in required_claims:
                if claim not in payload:
                    custom_log(f"Missing required claim: {claim}")
                    return False
            
            # Validate expiration (exp)
            exp = payload.get('exp')
            if exp:
                try:
                    exp_timestamp = int(exp)
                    current_timestamp = int(datetime.utcnow().timestamp())
                    if exp_timestamp <= current_timestamp:
                        custom_log("Token has expired")
                        return False
                except (ValueError, TypeError):
                    custom_log("Invalid expiration claim format")
                    return False
            
            # Validate issued at (iat)
            iat = payload.get('iat')
            if iat:
                try:
                    iat_timestamp = int(iat)
                    current_timestamp = int(datetime.utcnow().timestamp())
                    # Token should not be issued in the future (with 5 minute tolerance)
                    if iat_timestamp > (current_timestamp + 300):
                        custom_log("Token issued in the future")
                        return False
                except (ValueError, TypeError):
                    custom_log("Invalid issued at claim format")
                    return False
            
            # Validate not before (nbf) if present
            nbf = payload.get('nbf')
            if nbf:
                try:
                    nbf_timestamp = int(nbf)
                    current_timestamp = int(datetime.utcnow().timestamp())
                    if nbf_timestamp > current_timestamp:
                        custom_log("Token not yet valid")
                        return False
                except (ValueError, TypeError):
                    custom_log("Invalid not before claim format")
                    return False
            
            # Validate audience (aud) if present
            aud = payload.get('aud')
            if aud:
                # Add your audience validation logic here
                # For now, we'll just log it
                custom_log(f"Token audience: {aud}")
            
            # Validate issuer (iss) if present
            iss = payload.get('iss')
            if iss:
                # Add your issuer validation logic here
                # For now, we'll just log it
                custom_log(f"Token issuer: {iss}")
            
            # Validate custom claims
            if not self._validate_custom_claims(payload):
                return False
            
            return True
            
        except Exception as e:
            custom_log(f"Error validating token claims: {str(e)}")
            return False

    def _validate_custom_claims(self, payload: Dict[str, Any]) -> bool:
        """Validate custom JWT claims."""
        try:
            # Validate user_id if present
            user_id = payload.get('user_id')
            if user_id:
                if not isinstance(user_id, (str, int)):
                    custom_log("Invalid user_id claim format")
                    return False
            
            # Validate username if present
            username = payload.get('username')
            if username:
                if not isinstance(username, str):
                    custom_log("Invalid username claim format")
                    return False
            
            # Validate email if present
            email = payload.get('email')
            if email:
                if not isinstance(email, str):
                    custom_log("Invalid email claim format")
                    return False
                # Basic email format validation
                if '@' not in email or '.' not in email:
                    custom_log("Invalid email format in token")
                    return False
            
            # Validate roles if present
            roles = payload.get('roles')
            if roles:
                if not isinstance(roles, (list, set)):
                    custom_log("Invalid roles claim format")
                    return False
                for role in roles:
                    if not isinstance(role, str):
                        custom_log("Invalid role format in token")
                        return False
            
            return True
            
        except Exception as e:
            custom_log(f"Error validating custom claims: {str(e)}")
            return False

    def validate_token(self, token: str, expected_type: Optional[TokenType] = None) -> Optional[Dict[str, Any]]:
        """Alias for verify_token to maintain compatibility with existing code."""
        return self.verify_token(token, expected_type)

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
        # Check if we should delay refresh during game states
        if self.should_delay_token_refresh():
            custom_log("🎮 App in game state - delaying token refresh")
            # Track this token for later refresh when game ends
            token_hash = hashlib.sha256(refresh_token.encode()).hexdigest()[:16]
            self._pending_refresh_tokens.add(token_hash)
            custom_log(f"📝 Added token {token_hash} to pending refresh list")
            return None  # Return None to indicate refresh should be delayed
        
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

    def _get_state_dependent_ttl(self, token_type: TokenType, expires_in: Optional[int] = None) -> Optional[int]:
        """
        Get TTL based on current app state.
        Returns None to use default TTL, or custom TTL value.
        """
        try:
            # Get main app state
            main_state = self._get_main_app_state()
            
            # Always use normal TTL - we don't extend TTL anymore
            # Instead, we delay refresh and resume when game ends
            if expires_in:
                custom_log(f"📱 App in state '{main_state}', using custom TTL: {expires_in}s for {token_type.value} token")
                return expires_in
            else:
                custom_log(f"📱 App in state '{main_state}', using default TTL for {token_type.value} token")
                return None
                    
        except Exception as e:
            custom_log(f"❌ Error getting state-dependent TTL: {e}", level="ERROR")
            # Fallback to default TTL
            return None

    def should_delay_token_refresh(self) -> bool:
        """
        Check if token refresh should be delayed based on current app state.
        Returns True for game states (delay refresh), False for normal states (allow refresh).
        """
        try:
            current_state = self._get_main_app_state()
            game_states = ["active_game", "pre_game", "post_game"]
            
            should_delay = current_state in game_states
            custom_log(f"🎮 Checking token refresh delay - State: {current_state}, Delay: {should_delay}")
            
            return should_delay
            
        except Exception as e:
            custom_log(f"❌ Error checking token refresh delay: {e}", level="ERROR")
            return False  # Fail safe: allow refresh on error

    def _register_state_change_callback(self):
        """Register callback for main state changes to handle token refresh resumption."""
        try:
            from core.managers.state_manager import StateManager
            
            state_manager = StateManager()
            state_manager.register_callback("main_state", self._on_main_state_changed)
            custom_log("✅ JWT state change callback registered")
            
        except Exception as e:
            custom_log(f"❌ Failed to register JWT state change callback: {e}", level="ERROR")

    def _on_main_state_changed(self, state_id: str, transition: str, data: Dict[str, Any]):
        """
        Callback triggered when main app state changes.
        Resumes token refresh when transitioning from game states to normal states.
        """
        try:
            if state_id != "main_state":
                return
                
            new_state = data.get("app_status", "unknown")
            old_state = self._previous_state
            
            custom_log(f"🔄 JWT State change detected: {old_state} → {new_state}")
            
            # Check if we're transitioning from game state to normal state
            game_states = ["active_game", "pre_game", "post_game"]
            normal_states = ["idle", "busy", "maintenance"]
            
            was_in_game = old_state in game_states if old_state else False
            is_now_normal = new_state in normal_states
            
            if was_in_game and is_now_normal:
                custom_log("🎮 Game ended - resuming token refresh for pending tokens")
                self._resume_pending_token_refresh()
            
            # Update previous state
            self._previous_state = new_state
            
        except Exception as e:
            custom_log(f"❌ Error in JWT state change callback: {e}", level="ERROR")

    def _resume_pending_token_refresh(self):
        """Resume token refresh for all pending tokens when game state ends."""
        try:
            if not self._pending_refresh_tokens:
                custom_log("📝 No pending tokens to refresh")
                return
                
            custom_log(f"🔄 Resuming refresh for {len(self._pending_refresh_tokens)} pending tokens")
            
            # Process pending tokens (in a real implementation, you'd store the actual tokens)
            # For now, we just log that refresh should be resumed
            for token_id in self._pending_refresh_tokens:
                custom_log(f"🔄 Resuming refresh for token: {token_id}")
                
            # Clear pending tokens
            self._pending_refresh_tokens.clear()
            custom_log("✅ All pending token refreshes resumed")
            
        except Exception as e:
            custom_log(f"❌ Error resuming pending token refresh: {e}", level="ERROR")

    def _get_main_app_state(self) -> str:
        """
        Get the main app state from StateManager.
        Returns the app_status or 'unknown' if not available.
        """
        try:
            # Import here to avoid circular imports
            from core.managers.state_manager import StateManager
            
            state_manager = StateManager()
            main_state = state_manager.get_state("main_state")
            
            if main_state and main_state.get("data"):
                app_status = main_state["data"].get("app_status", "unknown")
                custom_log(f"📊 Main app state: {app_status}")
                return app_status
            else:
                custom_log("⚠️ Main app state not found, using 'unknown'")
                return "unknown"
                
        except Exception as e:
            custom_log(f"❌ Error getting main app state: {e}", level="ERROR")
            return "unknown" 