from flask_socketio import SocketIO, join_room, leave_room
from flask import request
from typing import Dict, Any, Set, Callable, Optional, List
from tools.logger.custom_logging import custom_log
from core.managers.redis_manager import RedisManager
from core.managers.jwt_manager import JWTManager, TokenType
from core.managers.websockets.ws_event_manager import WSEventManager
from core.managers.websockets.ws_room_manager import WSRoomManager
from core.managers.websockets.ws_session_manager import WSSessionManager
from core.managers.websockets.ws_broadcast_manager import WSBroadcastManager
from core.managers.websockets.ws_event_listeners import WSEventListeners
from core.managers.websockets.ws_event_handlers import WSEventHandlers
from core.validators.websocket_validators import WebSocketValidator
from utils.config.config import Config
import time
import threading
from datetime import datetime
from functools import wraps
import json

LOGGING_SWITCH = True  # Enabled for rank-based matching and debugging

class WebSocketManager:
    def __init__(self):
        self.redis_manager = RedisManager()
        self.validator = WebSocketValidator()
        self.socketio = SocketIO(
            cors_allowed_origins="*",  # Will be overridden by module
            async_mode='threading',
            logger=True,
            engineio_logger=True,
            max_http_buffer_size=Config.WS_MAX_PAYLOAD_SIZE,
            ping_timeout=Config.WS_PING_TIMEOUT,
            ping_interval=Config.WS_PING_INTERVAL
        )
        self.rooms: Dict[str, Set[str]] = {}  # room_id -> set of session_ids
        self.session_rooms: Dict[str, Set[str]] = {}  # session_id -> set of room_ids
        self.room_data: Dict[str, Dict[str, Any]] = {}  # room_id -> room metadata (creator_id, permission, etc.)
        self._room_creation_lock = threading.Lock()  # Lock for preventing race conditions in room creation
        self.rate_limits = {
            'connections': {
                'max': Config.WS_RATE_LIMIT_CONNECTIONS,
                'window': Config.WS_RATE_LIMIT_WINDOW
            },
            'messages': {
                'max': Config.WS_RATE_LIMIT_MESSAGES,
                'window': Config.WS_RATE_LIMIT_WINDOW
            }
        }
        self._jwt_manager = None  # Will be set by the module
        self._room_access_check = None  # Will be set by the module
        self._room_size_limit = Config.WS_ROOM_SIZE_LIMIT
        self._room_size_check_interval = Config.WS_ROOM_SIZE_CHECK_INTERVAL
        self._presence_check_interval = Config.WS_PRESENCE_CHECK_INTERVAL
        self._presence_timeout = Config.WS_PRESENCE_TIMEOUT
        self._presence_cleanup_interval = Config.WS_PRESENCE_CLEANUP_INTERVAL
        
        # Initialize new managers
        self.event_manager = WSEventManager()
        self.room_manager = WSRoomManager()
        self.session_manager = None  # Will be initialized when JWT manager is set
        self.broadcast_manager = None  # Will be initialized after session manager
        
        # Initialize event handlers and listeners
        self.event_handlers = WSEventHandlers(self)
        self.event_listeners = WSEventListeners(self, self.event_handlers)

        # Wire TTL expiry callback: broadcast graceful room closure and disconnect members
        def _on_room_ttl_expired(room_id: str):
            try:
                # Inform clients the room is closing due to TTL expiry
                self.socketio.emit('room_closed', {
                    'room_id': room_id,
                    'reason': 'ttl_expired',
                    'timestamp': datetime.now().isoformat()
                }, room=room_id)
                
                # 🎣 Trigger room_closed hook for game cleanup logic
                room_data = {
                    'room_id': room_id,
                    'reason': 'ttl_expired',
                    'timestamp': datetime.now().isoformat()
                }
                self.trigger_hook('room_closed', room_data)

                # Best-effort: force leave members from in-memory map
                members = list(self.rooms.get(room_id, set()))
                for sid in members:
                    try:
                        leave_room(room_id, sid=sid)
                    except Exception:
                        pass
                # Clear memory and Redis data for the room
                self._cleanup_room_data(room_id)
            except Exception as e:
                pass

        self.room_manager.on_room_ttl_expired = _on_room_ttl_expired

    def set_cors_origins(self, origins: list):
        """Set allowed CORS origins."""
        self.socketio.cors_allowed_origins = origins

    def validate_origin(self, origin: str) -> bool:
        """Validate if the origin is allowed."""
        # Allow all origins if "*" is in the allowed origins
        if "*" in self.socketio.cors_allowed_origins:
            return True
        # Allow mobile app origin
        if origin == "app://mobile":
            return True
        # Check if origin is in the allowed list
        return origin in self.socketio.cors_allowed_origins

    def check_rate_limit(self, client_id: str, limit_type: str) -> bool:
        """Check if client has exceeded rate limits."""
        if limit_type not in self.rate_limits:
            return True  # Unknown limit type, allow by default
            
        limit = self.rate_limits[limit_type]
        key = self.redis_manager._generate_secure_key("rate_limit", limit_type, client_id)
        count = self.redis_manager.get(key) or 0
        
        if count >= limit['max']:
            return False
            
        return True

    def update_rate_limit(self, client_id: str, limit_type: str):
        """Update rate limit counter."""
        if limit_type not in self.rate_limits:
            return
            
        limit = self.rate_limits[limit_type]
        key = self.redis_manager._generate_secure_key("rate_limit", limit_type, client_id)
        self.redis_manager.incr(key)
        self.redis_manager.expire(key, limit['window'])

    def store_session_data(self, session_id: str, session_data: Dict[str, Any]):
        """Store session data in Redis."""
        try:
            
            # Create a deep copy for storage
            data_to_store = session_data.copy()
            
            # Convert any sets to lists for JSON serialization
            if 'rooms' in data_to_store:
                if isinstance(data_to_store['rooms'], set):
                    data_to_store['rooms'] = list(data_to_store['rooms'])
                elif not isinstance(data_to_store['rooms'], list):
                    data_to_store['rooms'] = []
            
            if 'user_roles' in data_to_store:
                if isinstance(data_to_store['user_roles'], set):
                    data_to_store['user_roles'] = list(data_to_store['user_roles'])
                elif not isinstance(data_to_store['user_roles'], list):
                    data_to_store['user_roles'] = []
            
            # Convert any integers to strings
            if 'user_id' in data_to_store and isinstance(data_to_store['user_id'], int):
                data_to_store['user_id'] = str(data_to_store['user_id'])
            
            # Handle any nested structures
            for key, value in data_to_store.items():
                if isinstance(value, (set, datetime)):
                    data_to_store[key] = str(value)
                elif isinstance(value, (int, float)):
                    data_to_store[key] = str(value)
                elif isinstance(value, list):
                    # Convert any sets within lists to lists
                    data_to_store[key] = [
                        list(item) if isinstance(item, set) else 
                        str(item) if isinstance(item, (datetime, int, float)) else 
                        item 
                        for item in value
                    ]
                elif isinstance(value, dict):
                    # Handle nested dictionaries
                    data_to_store[key] = {
                        k: (list(v) if isinstance(v, set) else 
                            str(v) if isinstance(v, (datetime, int, float)) else 
                            v)
                        for k, v in value.items()
                    }
            
            # Store in Redis with expiration
            session_key = self.redis_manager._generate_secure_key("session", session_id)
            self.redis_manager.set(session_key, data_to_store, expire=Config.WS_SESSION_TTL)
            
        except Exception as e:
            raise

    def get_session_data(self, session_id: str) -> Optional[Dict[str, Any]]:
        """Get session data from Redis."""
        try:
            session_key = self.redis_manager._generate_secure_key("session", session_id)
            data = self.redis_manager.get(session_key)
            if data:
                # Create a deep copy to avoid modifying the original data
                data_copy = data.copy()
                
                # Convert lists back to sets for internal use
                if 'rooms' in data_copy:
                    data_copy['rooms'] = set(data_copy['rooms'])
                if 'user_roles' in data_copy:
                    data_copy['user_roles'] = set(data_copy['user_roles'])
                
                # Handle any nested sets in the data
                for key, value in data_copy.items():
                    if isinstance(value, list):
                        # Check if this list should be a set
                        if key in ['rooms', 'user_roles']:
                            data_copy[key] = set(value)
                        else:
                            # Check for nested sets in the list
                            data_copy[key] = [
                                set(item) if isinstance(item, list) and key in ['rooms', 'user_roles'] else
                                item
                                for item in value
                            ]
                    elif isinstance(value, dict):
                        # Handle nested dictionaries
                        for k, v in value.items():
                            if isinstance(v, list) and k in ['rooms', 'user_roles']:
                                value[k] = set(v)
                            elif isinstance(v, list):
                                # Check for nested sets in the list
                                value[k] = [
                                    set(item) if isinstance(item, list) and k in ['rooms', 'user_roles'] else
                                    item
                                    for item in v
                                ]
                
                # Create a copy for client use with lists instead of sets
                client_data = data_copy.copy()
                
                # Convert sets to lists for client use
                if 'rooms' in client_data:
                    client_data['rooms'] = list(client_data['rooms'])
                if 'user_roles' in client_data:
                    client_data['user_roles'] = list(client_data['user_roles'])
                
                return client_data
            return None
        except Exception as e:
            return None

    def get_client_session_data(self, session_id: str) -> Optional[Dict[str, Any]]:
        """Get session data formatted for client use."""
        return self.get_session_data(session_id)

    def cleanup_session_data(self, session_id: str):
        """Clean up session data from Redis."""
        try:
            session_key = self.redis_manager._generate_secure_key("session", session_id)
            self.redis_manager.delete(session_key)
        except Exception as e:
            pass

    def update_session_activity(self, session_id: str):
        """Update session activity timestamp."""
        try:
            session_key = self.redis_manager._generate_secure_key("session", session_id)
            data = self.redis_manager.get(session_key)
            if data:
                data['last_activity'] = datetime.now().isoformat()
                self.redis_manager.set(session_key, data, expire=Config.WS_SESSION_TTL)
        except Exception as e:
            pass

    def initialize(self, app, use_builtin_handlers=True):
        """Initialize the WebSocket manager with the Flask app."""
        self.socketio.init_app(app)
        
        if use_builtin_handlers:
            
            # Register all event listeners through the organized structure
            self.event_listeners.register_all_listeners()

    def set_jwt_manager(self, jwt_manager):
        """Set the JWT manager instance and initialize dependent managers."""
        self._jwt_manager = jwt_manager
        app_manager = getattr(self, '_app_manager', None)
        self.session_manager = WSSessionManager(self.redis_manager, jwt_manager, app_manager)
        self.broadcast_manager = WSBroadcastManager(self)

    def set_room_access_check(self, access_check_func):
        """Set the room access check function."""
        self._room_access_check = access_check_func

    def set_app_manager(self, app_manager):
        """Set the app manager instance for hook triggering."""
        self._app_manager = app_manager
        # Update session manager with app_manager if it's already initialized
        if self.session_manager:
            self.session_manager.set_app_manager(app_manager)

    def trigger_hook(self, hook_name: str, data=None, context=None):
        """Trigger a hook through the app manager."""
        if hasattr(self, '_app_manager') and self._app_manager:
            self._app_manager.trigger_hook(hook_name, data, context)
        else:
            pass

    def _update_room_permissions(self, room_id: str, room_data: Dict[str, Any], session_id: Optional[str] = None):
        """Update room permissions in Redis."""
        try:
            
            # Create room permissions data
            permissions_data = {
                'room_id': room_id,
                'permission': room_data.get('permission', 'public'),
                'owner_id': room_data.get('owner_id'),
                'allowed_users': list(room_data.get('allowed_users', set())),  # Ensure it's a list
                'allowed_roles': list(room_data.get('allowed_roles', set())),  # Ensure it's a list
                'created_at': datetime.now().isoformat(),
                'updated_at': datetime.now().isoformat()
            }
            
            # Store in Redis
            permissions_key = self.redis_manager._generate_secure_key("room_permissions", room_id)
            
            self.redis_manager.set(permissions_key, permissions_data, expire=Config.WS_ROOM_TTL)
            
        except Exception as e:
            import traceback
            raise

    def check_room_access(self, room_id: str, user_id: str, user_roles: List[str], session_id: Optional[str] = None) -> bool:
        """Check if user has access to a room."""
        try:
            # Get room permissions from Redis
            permissions_key = self.redis_manager._generate_secure_key("room_permissions", room_id)
            permissions = self.redis_manager.get(permissions_key)
            
            if not permissions:
                return True
            
            permission_type = permissions.get('permission', 'public')
            owner_id = permissions.get('owner_id')
            allowed_users = set(permissions.get('allowed_users', []))
            allowed_roles = set(permissions.get('allowed_roles', []))
            
            # Owner always has access
            if owner_id and str(owner_id) == str(user_id):
                return True
            
            # Check permission type
            if permission_type == 'public':
                return True
            elif permission_type == 'private':
                # Check if user is in allowed users or has allowed role
                if user_id in allowed_users:
                    return True
                
                if any(role in allowed_roles for role in user_roles):
                    return True
                return False
            else:
                return False
                
        except Exception as e:
            return False

    def requires_auth(self, handler: Callable) -> Callable:
        """Decorator to require authentication for WebSocket handlers."""
        @wraps(handler)
        def wrapper(data=None):
            session_id = request.sid
            
            # Get session data
            session_data = self.get_session_data(session_id)
            if not session_data:
                self.socketio.emit('error', {'error': 'Authentication required'})
                return
            
            # Validate JWT token if JWT manager is available
            if self._jwt_manager:
                token = request.args.get('token') or request.headers.get('Authorization')
                if token:
                    # Remove 'Bearer ' prefix if present
                    if token.startswith('Bearer '):
                        token = token[7:]
                    
                    try:
                        # Validate token
                        payload = self._jwt_manager.validate_token(token, TokenType.ACCESS)
                        if not payload:
                            self.socketio.emit('error', {'error': 'Invalid token'})
                            return
                        
                        # Update session data with user info
                        session_data['user_id'] = payload.get('user_id')
                        session_data['user_roles'] = set(payload.get('roles', []))
                        session_data['last_activity'] = datetime.now().isoformat()
                        
                        # Store updated session data
                        self.store_session_data(session_id, session_data)
                        
                    except Exception as e:
                        self.socketio.emit('error', {'error': 'Token validation failed'})
                        return
                else:
                    self.socketio.emit('error', {'error': 'No token provided'})
                    return
            
            # Call the original handler
            return handler(data)
        
        return wrapper

    def register_handler(self, event: str, handler: Callable):
        """Register a WebSocket event handler without authentication."""

    def register_authenticated_handler(self, event: str, handler: Callable):
        """Register a WebSocket event handler with authentication."""

    def create_room(self, room_id: str, permission: str = "public", owner_id: Optional[str] = None, allowed_users: Optional[Set[str]] = None, allowed_roles: Optional[Set[str]] = None, password: Optional[str] = None) -> bool:
        """Create a new room."""
        # Use lock to prevent race conditions in room creation
        with self._room_creation_lock:
            try:
                # Validate permission value
                valid_permissions = ['public', 'private']
                if permission not in valid_permissions:
                    return False
                
                # Check if room already exists
                if room_id in self.rooms:
                    return True
            
                # Prepare room data for Redis storage (convert sets to lists for JSON serialization)
                room_data = {
                    'room_id': room_id,
                    'permission': permission,
                    'owner_id': owner_id,
                    'allowed_users': list(allowed_users or set()),  # Convert set to list for JSON serialization
                    'allowed_roles': list(allowed_roles or set()),  # Convert set to list for JSON serialization
                    'created_at': datetime.now().isoformat(),
                    'size': 0,
                    'max_size': Config.WS_ROOM_SIZE_LIMIT,  # Single fallback for room size
                    'min_players': 2,  # Default minimum players
                    'password': password if permission == 'private' else None  # Store password for private rooms
                }
                
                # Store room data in Redis with proper key generation
                self.redis_manager.set("room", room_data, Config.WS_ROOM_TTL, room_id)
                # Ensure TTL is enforced through room manager policy as well
                try:
                    self.room_manager.reinstate_room_ttl(room_id)
                except Exception as e:
                    pass
                
                # Update room permissions
                self._update_room_permissions(room_id, room_data)
                
                # Initialize room in memory
                self.rooms[room_id] = set()
                
                # Store room metadata in memory for fast access
                self.room_data[room_id] = {
                    'creator_id': owner_id,
                    'permission': permission,
                    'created_at': datetime.now().isoformat(),
                    'size': 0,
                    'max_size': Config.WS_ROOM_SIZE_LIMIT,  # Single fallback for room size
                    'min_players': 2,  # Default minimum players
                    'allowed_users': list(allowed_users or set()),  # Convert set to list for consistency
                    'allowed_roles': list(allowed_roles or set()),   # Convert set to list for consistency
                    'password': password if permission == 'private' else None  # Store password for private rooms
                }
                return True
                
            except Exception as e:
                import traceback
                return False

    def get_room_size(self, room_id: str) -> int:
        """Get the current size of a room."""
        return len(self.rooms.get(room_id, set()))

    def update_room_size(self, room_id: str, delta: int):
        """Update room size counter."""
        # Update Redis
        room_key = self.redis_manager._generate_secure_key("room", room_id)
        room_data = self.redis_manager.get(room_key)
        if room_data:
            room_data['size'] = max(0, room_data.get('size', 0) + delta)
            self.redis_manager.set(room_key, room_data, expire=Config.WS_ROOM_TTL)
        
        # Update memory metadata
        if room_id in self.room_data:
            current_size = self.room_data[room_id].get('size', 0)
            self.room_data[room_id]['size'] = max(0, current_size + delta)

    def check_room_size_limit(self, room_id: str) -> bool:
        """Check if room has reached size limit."""
        current_size = self.get_room_size(room_id)
        return current_size < self._room_size_limit

    def get_session_info(self, session_id: str) -> Optional[Dict[str, Any]]:
        """Get session information."""
        return self.get_session_data(session_id)

    def update_user_presence(self, session_id: str, status: str = 'online'):
        """Update user presence status."""
        try:
            session_data = self.get_session_data(session_id)
            if session_data:
                user_id = session_data.get('user_id')
                if user_id:
                    presence_data = {
                        'user_id': user_id,
                        'session_id': session_id,
                        'status': status,
                        'last_seen': datetime.now().isoformat(),
                        'rooms': list(session_data.get('rooms', set()))
                    }
                    
                    # Store presence data
                    presence_key = self.redis_manager._generate_secure_key("presence", user_id)
                    self.redis_manager.set(presence_key, presence_data, expire=Config.WS_PRESENCE_TTL)
                    
        except Exception as e:
            pass

    def get_user_presence(self, user_id: str) -> Optional[Dict[str, Any]]:
        """Get user presence information."""
        try:
            presence_key = self.redis_manager._generate_secure_key("presence", user_id)
            presence_data = self.redis_manager.get(presence_key)
            
            if presence_data:
                # Convert rooms back to set for internal use
                if 'rooms' in presence_data:
                    presence_data['rooms'] = set(presence_data['rooms'])
                
                return presence_data
            return None
            
        except Exception as e:
            return None

    def get_room_presence(self, room_id: str) -> List[Dict[str, Any]]:
        """Get presence information for all users in a room."""
        try:
            room_members = self.rooms.get(room_id, set())
            presence_list = []
            
            for session_id in room_members:
                session_data = self.get_session_data(session_id)
                if session_data:
                    user_id = session_data.get('user_id')
                    if user_id:
                        presence_data = self.get_user_presence(user_id)
                        if presence_data:
                            presence_list.append(presence_data)
            
            return presence_list
            
        except Exception as e:
            return []

    def cleanup_stale_presence(self):
        """Clean up stale presence data."""
        try:
            pass
        except Exception as e:
            pass

    def _join_room_internal(self, room_id: str, session_id: str, user_id: Optional[str] = None, user_roles: Optional[Set[str]] = None) -> bool:
        """Internal method to join a room."""
        try:
            
            # Check if room exists
            room_key = self.redis_manager._generate_secure_key("room", room_id)
            room_data = self.redis_manager.get(room_key)
            
            if not room_data:
                # Check if room already exists in memory to prevent duplicate creation
                if room_id in self.rooms:
                    room_data = {
                        'room_id': room_id,
                        'permission': 'public',
                        'owner_id': user_id,
                        'allowed_users': [],
                        'allowed_roles': [],
                        'created_at': datetime.now().isoformat(),
                        'size': len(self.rooms[room_id])
                    }
                else:
                    self.create_room(room_id, "public", owner_id=user_id)
                    room_data = self.redis_manager.get(room_key)
            else:
                # Room exists in Redis but might not be in memory - initialize memory metadata
                if room_id not in self.room_data:
                    # Convert lists back to sets for internal use
                    allowed_users = room_data.get('allowed_users', [])
                    allowed_roles = room_data.get('allowed_roles', [])
                    
                    self.room_data[room_id] = {
                        'creator_id': room_data.get('owner_id'),
                        'permission': room_data.get('permission', 'public'),
                        'created_at': room_data.get('created_at'),
                        'size': room_data.get('size', 0),
                        'allowed_users': set(allowed_users) if isinstance(allowed_users, list) else allowed_users,
                        'allowed_roles': set(allowed_roles) if isinstance(allowed_roles, list) else allowed_roles,
                        'password': room_data.get('password')  # Include password from Redis
                    }
            
            # Check room access if access check function is available
            if self._room_access_check and user_id and user_roles:
                if not self._room_access_check(room_id, user_id, list(user_roles), session_id):
                    return False
            
            # Check room size limit
            if not self.check_room_size_limit(room_id):
                return False
            
            # Check if user is already in the room
            if session_id in self.session_rooms and room_id in self.session_rooms[session_id]:
                return "already_joined"  # Return special status for already joined
            
            # Check if room exists and session is already in it
            if room_id in self.rooms and session_id in self.rooms[room_id]:
                return "already_joined"  # Return special status for already joined
            
            # Join room using Socket.IO
            join_room(room_id)
            
            # Update room membership in memory
            if room_id not in self.rooms:
                self.rooms[room_id] = set()
            self.rooms[room_id].add(session_id)
            
            # Update session room membership
            if session_id not in self.session_rooms:
                self.session_rooms[session_id] = set()
            self.session_rooms[session_id].add(room_id)
            
            # Update room size
            self.update_room_size(room_id, 1)
            # Reinstate room TTL on each successful join
            try:
                self.room_manager.reinstate_room_ttl(room_id)
            except Exception as e:
                pass
            
            # Update session data
            session_data = self.get_session_data(session_id)
            if session_data:
                if 'rooms' not in session_data:
                    session_data['rooms'] = set()
                # Ensure rooms is a set for internal operations
                if isinstance(session_data['rooms'], list):
                    session_data['rooms'] = set(session_data['rooms'])
                session_data['rooms'].add(room_id)
                session_data['last_activity'] = datetime.now().isoformat()
                # Convert sets to lists before storing
                session_data_copy = session_data.copy()
                if isinstance(session_data_copy['rooms'], set):
                    session_data_copy['rooms'] = list(session_data_copy['rooms'])
                self.store_session_data(session_id, session_data_copy)
            
            # Update user presence
            self.update_user_presence(session_id, 'online')
            return True
            
        except Exception as e:
            return False

    def join_room(self, room_id: str, session_id: str, user_id: Optional[str] = None, user_roles: Optional[Set[str]] = None) -> bool:
        """Join a room."""
        return self._join_room_internal(room_id, session_id, user_id, user_roles)

    def leave_room(self, room_id: str, session_id: str) -> bool:
        """Leave a room."""
        try:
            
            # Leave room using Socket.IO
            leave_room(room_id)
            
            # Update room membership in memory
            if room_id in self.rooms:
                self.rooms[room_id].discard(session_id)
            
            # Update session room membership
            if session_id in self.session_rooms:
                self.session_rooms[session_id].discard(room_id)
                # Remove session if no rooms
                if not self.session_rooms[session_id]:
                    del self.session_rooms[session_id]
            
            # Update room size
            self.update_room_size(room_id, -1)
            
            # Update session data
            session_data = self.get_session_data(session_id)
            if session_data and 'rooms' in session_data:
                # Convert to set if it's a list, then remove the room
                rooms_set = set(session_data['rooms']) if isinstance(session_data['rooms'], list) else session_data['rooms']
                rooms_set.discard(room_id)
                session_data['rooms'] = list(rooms_set)  # Convert back to list for storage
                session_data['last_activity'] = datetime.now().isoformat()
                self.store_session_data(session_id, session_data)
            
            # Update user presence
            self.update_user_presence(session_id, 'online')
            return True
            
        except Exception as e:
            return False

    def broadcast_to_room(self, room_id: str, event: str, data: Any):
        """Broadcast message to a specific room."""
        try:
            # Use socketio.emit instead of direct emit to work from background threads
            self.socketio.emit(event, data, room=room_id)
            custom_log("Broadcasted event: " + event + " to room: " + room_id + " data: " + str(data), isOn=LOGGING_SWITCH)
        except Exception as e:
            custom_log(f"Error broadcasting to room {room_id}: {e}", isOn=LOGGING_SWITCH)

    async def send_to_session(self, session_id: str, event: str, data: Any):
        """Send message to a specific session."""
        try:
            # Use socketio.emit instead of direct emit to work from background threads
            self.socketio.emit(event, data, room=session_id)
        except Exception as e:
            pass

    def broadcast_to_all(self, event: str, data: Dict[str, Any]):
        """Broadcast message to all connected clients."""
        try:
            # Use socketio.emit instead of direct emit to work from background threads
            self.socketio.emit(event, data)
        except Exception as e:
            pass

    def send_to_session(self, session_id: str, event: str, data: Any):
        """Send message to a specific session."""
        try:
            # Use socketio.emit instead of direct emit to work from background threads
            self.socketio.emit(event, data, room=session_id)
        except Exception as e:
            pass

    def get_room_members(self, room_id: str) -> set:
        """Get all members in a room."""
        return self.rooms.get(room_id, set()).copy()

    def get_rooms_for_session(self, session_id: str) -> set:
        """Get all rooms for a session."""
        return self.session_rooms.get(session_id, set()).copy()

    def get_room_creator(self, room_id: str) -> Optional[str]:
        """Get the creator user ID for a room."""
        # Try memory first for fast access
        if room_id in self.room_data:
            return self.room_data[room_id].get('creator_id')
        
        # Fallback to Redis
        room_key = self.redis_manager._generate_secure_key("room", room_id)
        room_data = self.redis_manager.get(room_key)
        return room_data.get('owner_id') if room_data else None

    def is_room_creator(self, room_id: str, user_id: str) -> bool:
        """Check if user is the creator of the room."""
        creator_id = self.get_room_creator(room_id)
        return creator_id == user_id

    def get_room_metadata(self, room_id: str) -> Optional[Dict[str, Any]]:
        """Get room metadata from memory."""
        return self.room_data.get(room_id)

    def update_room_metadata(self, room_id: str, updates: Dict[str, Any]) -> bool:
        """Update room metadata in memory."""
        try:
            if room_id in self.room_data:
                self.room_data[room_id].update(updates)
                return True
            return False
        except Exception as e:
            return False

    def get_rooms_by_creator(self, creator_id: str) -> List[str]:
        """Get all room IDs created by a specific user."""
        rooms = []
        for room_id, metadata in self.room_data.items():
            if metadata.get('creator_id') == creator_id:
                rooms.append(room_id)
        return rooms

    def get_room_info(self, room_id: str) -> Optional[Dict[str, Any]]:
        """Get comprehensive room information including creator, members, and metadata."""
        try:
            # Get memory metadata
            metadata = self.room_data.get(room_id)
            if not metadata:
                # Fallback to Redis
                room_key = self.redis_manager._generate_secure_key("room", room_id)
                room_data = self.redis_manager.get(room_key)
                if not room_data:
                    return None
                
                metadata = {
                    'creator_id': room_data.get('owner_id'),
                    'permission': room_data.get('permission', 'public'),
                    'created_at': room_data.get('created_at'),
                    'size': room_data.get('size', 0),
                    'allowed_users': set(room_data.get('allowed_users', [])),
                    'allowed_roles': set(room_data.get('allowed_roles', [])),
                    'password': room_data.get('password')  # Include password from Redis
                }
            
            # Get current members
            members = self.rooms.get(room_id, set())
            
            return {
                'room_id': room_id,
                'creator_id': metadata.get('creator_id'),
                'permission': metadata.get('permission'),
                'created_at': metadata.get('created_at'),
                'size': len(members),
                'max_size': self._room_size_limit,
                'members': list(members),
                'allowed_users': list(metadata.get('allowed_users', set())),
                'allowed_roles': list(metadata.get('allowed_roles', set())),
                'password': metadata.get('password')  # Include password in room info
            }
            
        except Exception as e:
            return None

    def reset_room_sizes(self):
        """Reset room size counters."""
        try:
            # Get all room keys
            room_keys = self.redis_manager.get_keys("room:*")
            
            for room_key in room_keys:
                room_data = self.redis_manager.get(room_key)
                if room_data:
                    room_id = room_data.get('room_id')
                    if room_id:
                        # Update size based on actual members
                        actual_size = len(self.rooms.get(room_id, set()))
                        room_data['size'] = actual_size
                        self.redis_manager.set(room_key, room_data, expire=Config.WS_ROOM_TTL)
            
        except Exception as e:
            pass

    def _cleanup_stale_rooms(self):
        """Clean up stale room data."""
        try:
            # Get all room keys
            room_keys = self.redis_manager.get_keys("room:*")
            
            for room_key in room_keys:
                room_data = self.redis_manager.get(room_key)
                if room_data:
                    room_id = room_data.get('room_id')
                    if room_id:
                        # Check if room is empty and old
                        room_members = self.rooms.get(room_id, set())
                        if not room_members:
                            # Room is empty, check if it's old enough to clean up
                            created_at = room_data.get('created_at')
                            if created_at:
                                try:
                                    created_time = datetime.fromisoformat(created_at)
                                    age = datetime.now() - created_time
                                    if age.total_seconds() > Config.WS_ROOM_CLEANUP_AGE:
                                        self._cleanup_room_data(room_id)
                                except Exception as e:
                                    pass
            
        except Exception as e:
            pass

    def _cleanup_room_data(self, room_id: str):
        """Clean up all data for a specific room."""
        try:
            # Remove from memory
            if room_id in self.rooms:
                del self.rooms[room_id]
            
            # Remove room metadata from memory
            if room_id in self.room_data:
                del self.room_data[room_id]
            
            # Remove from Redis
            room_key = self.redis_manager._generate_secure_key("room", room_id)
            permissions_key = self.redis_manager._generate_secure_key("room_permissions", room_id)
            
            self.redis_manager.delete(room_key)
            self.redis_manager.delete(permissions_key)
            
        except Exception as e:
            pass

    def cleanup_session(self, session_id: str):
        """Clean up all data for a specific session."""
        try:
            # Get session data
            session_data = self.get_session_data(session_id)
            
            # Clean up room memberships
            self._cleanup_room_memberships(session_id, session_data)
            
            # Clean up session data
            self.cleanup_session_data(session_id)
            
            # Remove from memory
            if session_id in self.session_rooms:
                del self.session_rooms[session_id]
            
        except Exception as e:
            pass

    def _cleanup_room_memberships(self, session_id: str, session_data: Optional[Dict] = None):
        """Clean up room memberships for a session."""
        try:
            if not session_data:
                session_data = self.get_session_data(session_id)
            
            if session_data and 'rooms' in session_data:
                # Convert to set if it's a list to ensure proper iteration
                rooms = set(session_data['rooms']) if isinstance(session_data['rooms'], list) else session_data['rooms']
                for room_id in rooms:
                    # Remove from room
                    if room_id in self.rooms:
                        self.rooms[room_id].discard(session_id)
                    
                    # Update room size
                    self.update_room_size(room_id, -1)
            
            # Remove from session rooms
            if session_id in self.session_rooms:
                del self.session_rooms[session_id]
                
        except Exception as e:
            pass

    def run(self, app, **kwargs):
        """Run the WebSocket server."""
        # Allow Werkzeug in debug/development mode
        if kwargs.get('debug', False):
            kwargs['allow_unsafe_werkzeug'] = True
        self.socketio.run(app, **kwargs)

    def _handle_message(self, sid: str, message: str):
        """Handle incoming WebSocket messages."""
        try:
            
            # Parse message
            try:
                data = json.loads(message)
                event = data.get('event')
                payload = data.get('payload')
                
                # Validate event
                error = self.validator.validate_event(event)
                if error:
                    self.socketio.emit('error', {'message': error}, room=sid)
                    return
                    
                # Validate payload
                error = self.validator.validate_payload(payload)
                if error:
                    self.socketio.emit('error', {'message': error}, room=sid)
                    return
                    
                # Handle specific events
                if event == 'join_room':
                    room_id = payload.get('room_id')
                    if room_id:
                        self.join_room(room_id, sid)
                elif event == 'leave_room':
                    room_id = payload.get('room_id')
                    if room_id:
                        self.leave_room(room_id, sid)
                elif event == 'message':
                    room_id = payload.get('room_id')
                    message_content = payload.get('message')
                    if room_id and message_content:
                        self.broadcast_message(room_id, message_content, sid)
                        
            except json.JSONDecodeError:
                pass
        except Exception as e:
            self.socketio.emit('error', {'message': 'Internal server error'}, room=sid)

    def broadcast_message(self, room_id: str, message: str, sender_id: str = None):
        """Broadcast a message to all users in a room."""
        try:
            # Handle special messages
            if message == 'get_public_rooms':
                self._handle_get_public_rooms_request(sender_id, room_id)
                return
            
            # Get sender info
            sender_info = {}
            if sender_id:
                session_data = self.get_session_data(sender_id)
                if session_data:
                    sender_info = {
                        'user_id': session_data.get('user_id'),
                        'username': session_data.get('username'),
                        'session_id': sender_id
                    }
            
            # Prepare message data
            message_data = {
                'room_id': room_id,
                'message': message,
                'sender': sender_info,
                'timestamp': datetime.now().isoformat()
            }
            
            # Broadcast to room
            self.socketio.emit('message', message_data, room=room_id)
            
        except Exception as e:
            pass
    
    def _handle_get_public_rooms_request(self, session_id: str, room_id: str):
        """Handle get_public_rooms message request"""
        try:
            if not session_id:
                return
            
            # Get all public rooms from the room manager
            if hasattr(self, 'room_manager'):
                all_rooms = self.room_manager.get_all_rooms()
                
                # Filter for public rooms only
                public_rooms = []
                for room_id, room_info in all_rooms.items():
                    if room_info.get('permission') == 'public':
                        # Only include rooms that have complete data
                        if room_info.get('max_size') and room_info.get('min_size'):
                            public_rooms.append({
                                'room_id': room_id,
                                'owner_id': room_info.get('owner_id'),
                                'permission': room_info.get('permission'),
                                'current_size': room_info.get('current_size', 0),
                                'max_size': room_info.get('max_size'),  # No fallback - must exist
                                'min_size': room_info.get('min_size'),  # No fallback - must exist
                                'created_at': room_info.get('created_at'),
                                'game_type': room_info.get('game_type', 'classic'),
                                'turn_time_limit': room_info.get('turn_time_limit', 30),
                                'auto_start': room_info.get('auto_start', True)
                            })
                
                # Send response
                self.send_to_session(session_id, 'get_public_rooms_success', {
                    'success': True,
                    'data': public_rooms,
                    'count': len(public_rooms),
                    'timestamp': time.time()
                })
            else:
                # Fallback: return empty list if room manager not available
                self.send_to_session(session_id, 'get_public_rooms_success', {
                    'success': True,
                    'data': [],
                    'count': 0,
                    'timestamp': time.time()
                })
        
        except Exception as e:
            self.send_to_session(session_id, 'get_public_rooms_error', {
                'error': f'Error getting public rooms: {str(e)}'
            }) 