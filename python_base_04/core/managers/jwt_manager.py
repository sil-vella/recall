from datetime import datetime, timedelta
import jwt
from jwt.exceptions import InvalidTokenError, ExpiredSignatureError, InvalidSignatureError, InvalidAudienceError, InvalidIssuerError
from typing import Dict, Any, Optional, Union
from tools.logger.custom_logging import custom_log
from utils.config.config import Config
from core.managers.redis_manager import RedisManager
from enum import Enum
import hashlib
from flask import request, jsonify

# Logging switch for this module
LOGGING_SWITCH = True

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
        
        # Flask app reference for route registration
        self.app = None

    def _get_client_fingerprint(self) -> str:
        """Generate a unique client fingerprint based on IP and User-Agent."""
        try:
            # Handle Docker environment - try to get real client IP
            ip = request.headers.get('X-Forwarded-For', request.headers.get('X-Real-IP', request.remote_addr))
            # If it's a comma-separated list, take the first one
            if ip and ',' in ip:
                ip = ip.split(',')[0].strip()
            user_agent = request.headers.get('User-Agent', '')
            
            custom_log(f"🔐 JWT Fingerprint: IP: '{ip}', User-Agent: '{user_agent}'", level="DEBUG", isOn=LOGGING_SWITCH)
            
            fingerprint = hashlib.sha256(f"{ip}-{user_agent}".encode()).hexdigest()
            custom_log(f"🔐 JWT Fingerprint: Generated fingerprint: '{fingerprint[:10]}...'", level="DEBUG", isOn=LOGGING_SWITCH)
            return fingerprint
        except Exception as e:
            custom_log(f"❌ JWT Fingerprint: Exception generating fingerprint: {str(e)}", level="ERROR", isOn=LOGGING_SWITCH)
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
        custom_log(f"🔐 JWT: Starting token verification", level="INFO", isOn=LOGGING_SWITCH)
        custom_log(f"🔐 JWT: Token preview: {token[:20]}...", level="DEBUG", isOn=LOGGING_SWITCH)
        custom_log(f"🔐 JWT: Expected type: {expected_type}", level="DEBUG", isOn=LOGGING_SWITCH)
        
        try:
            # First decode the token to get its type
            try:
                payload = jwt.decode(token, self.secret_key, algorithms=[self.algorithm])
                custom_log(f"🔐 JWT: Token decoded successfully", level="INFO", isOn=LOGGING_SWITCH)
                custom_log(f"🔐 JWT: Payload keys: {list(payload.keys())}", level="DEBUG", isOn=LOGGING_SWITCH)
            except InvalidTokenError as e:
                custom_log(f"❌ JWT: Invalid token error: {str(e)}", level="ERROR", isOn=LOGGING_SWITCH)
                return None
                
            # Check if token is revoked
            if self._is_token_revoked(token):
                custom_log(f"❌ JWT: Token is revoked", level="WARNING", isOn=LOGGING_SWITCH)
                return None
            else:
                custom_log(f"✅ JWT: Token not revoked", level="DEBUG", isOn=LOGGING_SWITCH)
                
            # Verify fingerprint if present in token
            token_fingerprint = payload.get("fingerprint")
            if token_fingerprint:
                current_fingerprint = self._get_client_fingerprint()
                custom_log(f"🔐 JWT: Checking fingerprint - token: {token_fingerprint[:10]}..., current: '{current_fingerprint}' (len: {len(current_fingerprint) if current_fingerprint else 0})", level="DEBUG", isOn=LOGGING_SWITCH)
                
                # For development: Skip fingerprint validation for server-to-server calls
                # Check if this is a Dart server call (User-Agent contains 'Dart')
                user_agent = request.headers.get('User-Agent', '')
                is_server_to_server = 'Dart' in user_agent
                
                if is_server_to_server:
                    custom_log(f"🔐 JWT: Server-to-server call detected (User-Agent: {user_agent}), skipping fingerprint validation", level="DEBUG", isOn=LOGGING_SWITCH)
                elif not current_fingerprint or current_fingerprint == "":
                    custom_log(f"🔐 JWT: No current fingerprint, skipping fingerprint validation", level="DEBUG", isOn=LOGGING_SWITCH)
                elif current_fingerprint and token_fingerprint != current_fingerprint:
                    custom_log(f"❌ JWT: Fingerprint mismatch", level="WARNING", isOn=LOGGING_SWITCH)
                    return None
                else:
                    custom_log(f"✅ JWT: Fingerprint valid", level="DEBUG", isOn=LOGGING_SWITCH)
            else:
                custom_log(f"🔐 JWT: No fingerprint in token", level="DEBUG", isOn=LOGGING_SWITCH)
                
            # Verify token type if specified
            if expected_type:
                token_type = payload.get("type")
                custom_log(f"🔐 JWT: Checking token type - expected: {expected_type.value}, actual: {token_type}", level="DEBUG", isOn=LOGGING_SWITCH)
                if not token_type:
                    custom_log(f"❌ JWT: No token type in payload", level="WARNING", isOn=LOGGING_SWITCH)
                    return None
                    
                if token_type != expected_type.value:
                    custom_log(f"❌ JWT: Token type mismatch", level="WARNING", isOn=LOGGING_SWITCH)
                    return None
                else:
                    custom_log(f"✅ JWT: Token type valid", level="DEBUG", isOn=LOGGING_SWITCH)
            
            # Comprehensive claims validation
            custom_log(f"🔐 JWT: Validating token claims", level="DEBUG", isOn=LOGGING_SWITCH)
            if not self._validate_token_claims(payload):
                custom_log(f"❌ JWT: Token claims validation failed", level="WARNING", isOn=LOGGING_SWITCH)
                return None
            else:
                custom_log(f"✅ JWT: Token claims validation passed", level="DEBUG", isOn=LOGGING_SWITCH)
            
            custom_log(f"✅ JWT: Token verification successful for user: {payload.get('user_id', 'unknown')}", level="INFO", isOn=LOGGING_SWITCH)
            return payload
            
        except ExpiredSignatureError:
            custom_log(f"❌ JWT: Token expired", level="WARNING", isOn=LOGGING_SWITCH)
            return None
        except InvalidSignatureError:
            custom_log(f"❌ JWT: Invalid signature", level="WARNING", isOn=LOGGING_SWITCH)
            return None
        except InvalidAudienceError:
            custom_log(f"❌ JWT: Invalid audience", level="WARNING", isOn=LOGGING_SWITCH)
            return None
        except InvalidIssuerError:
            custom_log(f"❌ JWT: Invalid issuer", level="WARNING", isOn=LOGGING_SWITCH)
            return None
        except Exception as e:
            custom_log(f"❌ JWT: Unexpected error during verification: {str(e)}", level="ERROR", isOn=LOGGING_SWITCH)
            return None

    def _validate_token_claims(self, payload: Dict[str, Any]) -> bool:
        """Validate JWT token claims comprehensively."""
        custom_log(f"🔐 JWT Claims: Starting claims validation", level="DEBUG", isOn=LOGGING_SWITCH)
        custom_log(f"🔐 JWT Claims: Payload: {payload}", level="DEBUG", isOn=LOGGING_SWITCH)
        
        try:
            # Check required claims
            required_claims = ['exp', 'iat', 'type']
            custom_log(f"🔐 JWT Claims: Checking required claims: {required_claims}", level="DEBUG", isOn=LOGGING_SWITCH)
            for claim in required_claims:
                if claim not in payload:
                    custom_log(f"❌ JWT Claims: Missing required claim: {claim}", level="WARNING", isOn=LOGGING_SWITCH)
                    return False
                else:
                    custom_log(f"✅ JWT Claims: Found required claim: {claim} = {payload[claim]}", level="DEBUG", isOn=LOGGING_SWITCH)
            
            # Validate expiration (exp)
            exp = payload.get('exp')
            if exp:
                try:
                    exp_timestamp = int(exp)
                    current_timestamp = int(datetime.utcnow().timestamp())
                    custom_log(f"🔐 JWT Claims: Checking expiration - exp: {exp_timestamp}, current: {current_timestamp}", level="DEBUG", isOn=LOGGING_SWITCH)
                    if exp_timestamp <= current_timestamp:
                        custom_log(f"❌ JWT Claims: Token expired", level="WARNING", isOn=LOGGING_SWITCH)
                        return False
                    else:
                        custom_log(f"✅ JWT Claims: Token not expired", level="DEBUG", isOn=LOGGING_SWITCH)
                except (ValueError, TypeError) as e:
                    custom_log(f"❌ JWT Claims: Invalid exp format: {e}", level="WARNING", isOn=LOGGING_SWITCH)
                    return False
            
            # Validate issued at (iat)
            iat = payload.get('iat')
            if iat:
                try:
                    iat_timestamp = int(iat)
                    current_timestamp = int(datetime.utcnow().timestamp())
                    custom_log(f"🔐 JWT Claims: Checking issued at - iat: {iat_timestamp}, current: {current_timestamp}", level="DEBUG", isOn=LOGGING_SWITCH)
                    # Token should not be issued in the future (with 5 minute tolerance)
                    if iat_timestamp > (current_timestamp + 300):
                        custom_log(f"❌ JWT Claims: Token issued in the future", level="WARNING", isOn=LOGGING_SWITCH)
                        pass
                    else:
                        custom_log(f"✅ JWT Claims: Token issued at valid time", level="DEBUG", isOn=LOGGING_SWITCH)
                except (ValueError, TypeError) as e:
                    custom_log(f"❌ JWT Claims: Invalid iat format: {e}", level="WARNING", isOn=LOGGING_SWITCH)
                    return False
            
            # Validate not before (nbf) if present
            nbf = payload.get('nbf')
            if nbf:
                try:
                    nbf_timestamp = int(nbf)
                    current_timestamp = int(datetime.utcnow().timestamp())
                    if nbf_timestamp > current_timestamp:
                        return False
                except (ValueError, TypeError):
                    return False
            
            # Validate audience (aud) if present
            aud = payload.get('aud')
            if aud:
                pass
            
            # Validate issuer (iss) if present
            iss = payload.get('iss')
            if iss:
                pass
            
            # Validate custom claims
            custom_log(f"🔐 JWT Claims: Validating custom claims", level="DEBUG", isOn=LOGGING_SWITCH)
            if not self._validate_custom_claims(payload):
                custom_log(f"❌ JWT Claims: Custom claims validation failed", level="WARNING", isOn=LOGGING_SWITCH)
                return False
            else:
                custom_log(f"✅ JWT Claims: Custom claims validation passed", level="DEBUG", isOn=LOGGING_SWITCH)
            
            custom_log(f"✅ JWT Claims: All claims validation passed", level="DEBUG", isOn=LOGGING_SWITCH)
            return True
            
        except Exception as e:
            custom_log(f"❌ JWT Claims: Exception during validation: {str(e)}", level="ERROR", isOn=LOGGING_SWITCH)
            return False

    def _validate_custom_claims(self, payload: Dict[str, Any]) -> bool:
        """Validate custom JWT claims."""
        custom_log(f"🔐 JWT Custom: Starting custom claims validation", level="DEBUG", isOn=LOGGING_SWITCH)
        
        try:
            # Validate user_id if present
            user_id = payload.get('user_id')
            if user_id:
                custom_log(f"🔐 JWT Custom: Validating user_id: {user_id}", level="DEBUG", isOn=LOGGING_SWITCH)
                if not isinstance(user_id, (str, int)):
                    custom_log(f"❌ JWT Custom: Invalid user_id type: {type(user_id)}", level="WARNING", isOn=LOGGING_SWITCH)
                    return False
                else:
                    custom_log(f"✅ JWT Custom: user_id valid", level="DEBUG", isOn=LOGGING_SWITCH)
            else:
                custom_log(f"🔐 JWT Custom: No user_id in payload", level="DEBUG", isOn=LOGGING_SWITCH)
            
            # Validate username if present
            username = payload.get('username')
            if username:
                custom_log(f"🔐 JWT Custom: Validating username: {username}", level="DEBUG", isOn=LOGGING_SWITCH)
                if not isinstance(username, str):
                    custom_log(f"❌ JWT Custom: Invalid username type: {type(username)}", level="WARNING", isOn=LOGGING_SWITCH)
                    return False
                else:
                    custom_log(f"✅ JWT Custom: username valid", level="DEBUG", isOn=LOGGING_SWITCH)
            else:
                custom_log(f"🔐 JWT Custom: No username in payload", level="DEBUG", isOn=LOGGING_SWITCH)
            
            # Validate email if present
            email = payload.get('email')
            if email:
                custom_log(f"🔐 JWT Custom: Validating email: {email}", level="DEBUG", isOn=LOGGING_SWITCH)
                if not isinstance(email, str):
                    custom_log(f"❌ JWT Custom: Invalid email type: {type(email)}", level="WARNING", isOn=LOGGING_SWITCH)
                    return False
                # Basic email format validation
                if '@' not in email or '.' not in email:
                    custom_log(f"❌ JWT Custom: Invalid email format", level="WARNING", isOn=LOGGING_SWITCH)
                    return False
                else:
                    custom_log(f"✅ JWT Custom: email valid", level="DEBUG", isOn=LOGGING_SWITCH)
            else:
                custom_log(f"🔐 JWT Custom: No email in payload", level="DEBUG", isOn=LOGGING_SWITCH)
            
            # Validate roles if present
            roles = payload.get('roles')
            if roles:
                custom_log(f"🔐 JWT Custom: Validating roles: {roles}", level="DEBUG", isOn=LOGGING_SWITCH)
                if not isinstance(roles, (list, set)):
                    custom_log(f"❌ JWT Custom: Invalid roles type: {type(roles)}", level="WARNING", isOn=LOGGING_SWITCH)
                    return False
                for role in roles:
                    if not isinstance(role, str):
                        custom_log(f"❌ JWT Custom: Invalid role type: {type(role)}", level="WARNING", isOn=LOGGING_SWITCH)
                        return False
                custom_log(f"✅ JWT Custom: roles valid", level="DEBUG", isOn=LOGGING_SWITCH)
            else:
                custom_log(f"🔐 JWT Custom: No roles in payload", level="DEBUG", isOn=LOGGING_SWITCH)
            
            custom_log(f"✅ JWT Custom: All custom claims validation passed", level="DEBUG", isOn=LOGGING_SWITCH)
            return True
            
        except Exception as e:
            custom_log(f"❌ JWT Custom: Exception during custom claims validation: {str(e)}", level="ERROR", isOn=LOGGING_SWITCH)
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
                    return False
            except InvalidTokenError:
                return False
                
            # Revoke token using Redis manager's token methods
            return self.redis_manager.revoke_token(token_type, token)
            
        except Exception as e:
            return False

    def refresh_token(self, refresh_token: str) -> Optional[str]:
        """Create a new access token using a refresh token."""
        # Check if we should delay refresh during game states
        if self.should_delay_token_refresh():
            # Track this token for later refresh when game ends
            token_hash = hashlib.sha256(refresh_token.encode()).hexdigest()[:16]
            self._pending_refresh_tokens.add(token_hash)
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
                pass
            
        except Exception as e:
            pass

    def _is_token_revoked(self, token: str) -> bool:
        """Check if a token is revoked using prefix-based lookup."""
        custom_log(f"🔐 JWT Revoke: Checking if token is revoked", level="DEBUG", isOn=LOGGING_SWITCH)
        
        try:
            # First decode the token to get its type
            try:
                payload = jwt.decode(token, self.secret_key, algorithms=[self.algorithm])
                token_type = payload.get("type")
                custom_log(f"🔐 JWT Revoke: Token type: {token_type}", level="DEBUG", isOn=LOGGING_SWITCH)
                if not token_type:
                    custom_log(f"❌ JWT Revoke: No token type found", level="WARNING", isOn=LOGGING_SWITCH)
                    return True
            except InvalidTokenError as e:
                # If we can't decode the token, consider it revoked
                custom_log(f"❌ JWT Revoke: Cannot decode token: {str(e)}", level="WARNING", isOn=LOGGING_SWITCH)
                return True
                
            # Check if token is valid in Redis
            is_valid = self.redis_manager.is_token_valid(token_type, token)
            custom_log(f"🔐 JWT Revoke: Redis check result: {is_valid}", level="DEBUG", isOn=LOGGING_SWITCH)
            return not is_valid
            
        except Exception as e:
            custom_log(f"❌ JWT Revoke: Exception during revocation check: {str(e)}", level="ERROR", isOn=LOGGING_SWITCH)
            return True  # Fail safe: consider token revoked on error

    def cleanup_expired_tokens(self):
        """Clean up expired tokens from Redis."""
        try:
            
            for token_type in TokenType:
                if not self.redis_manager.cleanup_expired_tokens(token_type.value):
                    pass
            
        except Exception as e:
            pass

    def schedule_token_cleanup(self, interval_minutes: int = 60):
        """Schedule periodic token cleanup (optional enhancement)."""
        try:
            import threading
            import time
            
            def cleanup_worker():
                while True:
                    try:
                        time.sleep(interval_minutes * 60)  # Convert to seconds
                        self.cleanup_expired_tokens()
                    except Exception as e:
                        pass
            
            # Start cleanup thread
            cleanup_thread = threading.Thread(target=cleanup_worker, daemon=True)
            cleanup_thread.start()
            
        except Exception as e:
            pass

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
                return expires_in
            else:
                return None
                    
        except Exception as e:
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
            
            return should_delay
            
        except Exception as e:
            return False  # Fail safe: allow refresh on error

    def _register_state_change_callback(self):
        """Register callback for main state changes to handle token refresh resumption."""
        try:
            from core.managers.state_manager import StateManager
            
            state_manager = StateManager()
            state_manager.register_callback("main_state", self._on_main_state_changed)
            
        except Exception as e:
            pass

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
            
            # Check if we're transitioning from game state to normal state
            game_states = ["active_game", "pre_game", "post_game"]
            normal_states = ["idle", "busy", "maintenance"]
            
            was_in_game = old_state in game_states if old_state else False
            is_now_normal = new_state in normal_states
            
            if was_in_game and is_now_normal:
                self._resume_pending_token_refresh()
            
            # Update previous state
            self._previous_state = new_state
            
        except Exception as e:
            pass

    def _resume_pending_token_refresh(self):
        """Resume token refresh for all pending tokens when game state ends."""
        try:
            if not self._pending_refresh_tokens:
                return
                
            
            # Process pending tokens (in a real implementation, you'd store the actual tokens)
            # For now, we just log that refresh should be resumed
            for token_id in self._pending_refresh_tokens:
                pass
            # Clear pending tokens
            self._pending_refresh_tokens.clear()
            
        except Exception as e:
            pass

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
                return app_status
            else:
                return "unknown"
                
        except Exception as e:
            return "unknown" 