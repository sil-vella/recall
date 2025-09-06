from typing import Dict, Any, Optional, Set, List, Callable
from datetime import datetime
from enum import Enum
from core.managers.redis_manager import RedisManager
from utils.config.config import Config
import threading
import re

class RoomPermission(Enum):
    """Room permission types."""
    PUBLIC = "public"
    PRIVATE = "private"

class WSRoomManager:
    """WebSocket Room Manager - Handles room creation, permissions, and management."""
    
    def __init__(self):
        self.redis_manager = RedisManager()
        # TTL monitor for room lifetime (optional, best-effort)
        self._ttl_monitor_started = False
        self._start_ttl_monitor()
        # Optional callback set by WebSocketManager to react on TTL expiry
        self.on_room_ttl_expired: Optional[Callable[[str], None]] = None

    # --- TTL utilities ----------------------------------------------------
    def _get_room_ttl_seconds(self) -> int:
        """Resolve room TTL from configuration (seconds)."""
        try:
            ttl = int(getattr(Config, 'WS_ROOM_TTL', 3600))
            return max(1, ttl)
        except Exception:
            return 3600

    def _room_secure_key_expire(self, room_id: str, seconds: int) -> bool:
        """Set expiry on the secured room hash key managed by RedisManager."""
        # Fix parameter alignment: use same parameters as room creation
        ok = self.redis_manager.expire("room", seconds, room_id)
        if ok:
            else:
            return ok

    def _room_plain_ttl_key(self, room_id: str) -> str:
        """Plain key for keyspace notifications (human-readable)."""
        return f"ws:room_ttl:{room_id}"

    def _set_plain_ttl_marker(self, room_id: str, seconds: int) -> None:
        client = self.redis_manager.get_client()
        client.setex(self._room_plain_ttl_key(room_id), seconds, "1")
        def reinstate_room_ttl(self, room_id: str, seconds: int = None) -> None:
        """Reinstate/extend the room TTL (call on each join)."""
        ttl = seconds or self._get_room_ttl_seconds()
        self._room_secure_key_expire(room_id, ttl)
        self._set_plain_ttl_marker(room_id, ttl)
        def _ensure_keyspace_notifications(self) -> None:
        """Try enabling keyspace notifications for expirations (best-effort)."""
        try:
            client = self.redis_manager.get_client()
            current = client.config_get("notify-keyspace-events").get("notify-keyspace-events", "")
            if "E" not in current or "x" not in current.lower():
                # enable Ex (Expired events)
                client.config_set("notify-keyspace-events", (current + "Ex").strip())
                ")
        except Exception as e:
            def _start_ttl_monitor(self) -> None:
        if self._ttl_monitor_started:
            return
        self._ttl_monitor_started = True
        self._ensure_keyspace_notifications()

        def _worker():
            try:
                client = self.redis_manager.get_client()
                pubsub = client.pubsub()
                # Subscribe to expiry events for our plain marker keys
                pattern = "__keyevent@*__:expired"
                pubsub.psubscribe(pattern)
                ")
                room_ttl_re = re.compile(r"ws:room_ttl:(.+)$")
                for message in pubsub.listen():
                    if message.get("type") not in ("pmessage", "message"):
                        continue
                    raw = message.get("data")
                    expired_key = raw.decode() if isinstance(raw, (bytes, bytearray)) else str(raw)
                    m = room_ttl_re.search(expired_key)
                    if m:
                        room_id = m.group(1)
                        # Notify owner if callback is wired
                        try:
                            if self.on_room_ttl_expired:
                                self.on_room_ttl_expired(room_id)
                        except Exception as e:
                            except Exception as e:
                t = threading.Thread(target=_worker, name="ws-room-ttl-monitor", daemon=True)
        t.start()

    def create_room(self, room_id: str, permission: RoomPermission, owner_id: str, 
                   allowed_users: Set[str] = None, allowed_roles: Set[str] = None) -> Dict[str, Any]:
        """Create a new room with specified permissions."""
        try:
            # Check if room already exists
            existing_room = self.get_room_permissions(room_id)
            if existing_room:
                return {
                    'success': False,
                    'error': f'Room {room_id} already exists'
                }
            
            # Create room data
            room_data = {
                'room_id': room_id,
                'permission': permission.value,
                'owner_id': owner_id,
                'allowed_users': list(allowed_users or set()),
                'allowed_roles': list(allowed_roles or set()),
                'created_at': datetime.now().isoformat(),
                'updated_at': datetime.now().isoformat(),
                'max_size': Config.WS_ROOM_SIZE_LIMIT
            }
            
            # Store room data in Redis with configured TTL
            room_key = self.redis_manager._generate_secure_key("room", room_id)
            ttl_seconds = self._get_room_ttl_seconds()
            self.redis_manager.set(room_key, room_data, expire=ttl_seconds)
            self._set_plain_ttl_marker(room_id, ttl_seconds)
            return {
                'success': True,
                'room_id': room_id,
                'permission': permission.value,
                'owner_id': owner_id
            }
            
        except Exception as e:
            }")
            return {
                'success': False,
                'error': f'Failed to create room: {str(e)}'
            }

    def get_room_permissions(self, room_id: str) -> Optional[Dict[str, Any]]:
        """Get room permissions from Redis."""
        try:
            room_key = self.redis_manager._generate_secure_key("room", room_id)
            room_data = self.redis_manager.get(room_key)
            
            if room_data:
                # Convert lists back to sets for internal use
                if 'allowed_users' in room_data:
                    room_data['allowed_users'] = set(room_data['allowed_users'])
                if 'allowed_roles' in room_data:
                    room_data['allowed_roles'] = set(room_data['allowed_roles'])
                
                return room_data
            return None
            
        except Exception as e:
            }")
            return None

    def touch_room(self, room_id: str) -> None:
        """Extend room TTL (called on join or activity)."""
        try:
            self.reinstate_room_ttl(room_id)
        except Exception as e:
            def update_room_permissions(self, room_id: str, permission: RoomPermission = None,
                              allowed_users: Set[str] = None, allowed_roles: Set[str] = None) -> Dict[str, Any]:
        """Update room permissions."""
        try:
            room_data = self.get_room_permissions(room_id)
            if not room_data:
                return {
                    'success': False,
                    'error': f'Room {room_id} not found'
                }
            
            # Update permissions
            if permission:
                room_data['permission'] = permission.value
            if allowed_users is not None:
                room_data['allowed_users'] = list(allowed_users)
            if allowed_roles is not None:
                room_data['allowed_roles'] = list(allowed_roles)
            
            room_data['updated_at'] = datetime.now().isoformat()
            
            # Store updated room data
            room_key = self.redis_manager._generate_secure_key("room", room_id)
            self.redis_manager.set(room_key, room_data, expire=Config.WS_ROOM_TTL)
            
            return {
                'success': True,
                'room_id': room_id,
                'permission': room_data['permission']
            }
            
        except Exception as e:
            }")
            return {
                'success': False,
                'error': f'Failed to update room permissions: {str(e)}'
            }

    def delete_room(self, room_id: str) -> Dict[str, Any]:
        """Delete a room and its permissions."""
        try:
            # Check if room exists
            room_data = self.get_room_permissions(room_id)
            if not room_data:
                return {
                    'success': False,
                    'error': f'Room {room_id} not found'
                }
            
            # Delete room data from Redis
            room_key = self.redis_manager._generate_secure_key("room", room_id)
            self.redis_manager.delete(room_key)
            
            return {
                'success': True,
                'room_id': room_id
            }
            
        except Exception as e:
            }")
            return {
                'success': False,
                'error': f'Failed to delete room: {str(e)}'
            }

    def check_room_access(self, room_id: str, user_id: str, user_roles: List[str], session_id: Optional[str] = None) -> bool:
        """Check if user has access to a room."""
        try:
            # Get room permissions
            room_data = self.get_room_permissions(room_id)
            if not room_data:
                # No permissions found, assume public room
                return True
            
            permission_type = room_data.get('permission', 'public')
            owner_id = room_data.get('owner_id')
            allowed_users = set(room_data.get('allowed_users', []))
            allowed_roles = set(room_data.get('allowed_roles', []))
            
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
            }")
            return False

    def get_all_rooms(self) -> List[Dict[str, Any]]:
        """Get all rooms."""
        try:
            room_keys = self.redis_manager.get_keys("room:*")
            rooms = []
            
            for room_key in room_keys:
                room_data = self.redis_manager.get(room_key)
                if room_data:
                    rooms.append(room_data)
            
            return rooms
            
        except Exception as e:
            }")
            return []



    def get_room_owner(self, room_id: str) -> Optional[str]:
        """Get the owner of a room."""
        try:
            room_data = self.get_room_permissions(room_id)
            if room_data:
                return room_data.get('owner_id')
            return None
            
        except Exception as e:
            }")
            return None

    def is_room_owner(self, room_id: str, user_id: str) -> bool:
        """Check if user is the owner of a room."""
        try:
            owner_id = self.get_room_owner(room_id)
            return owner_id and str(owner_id) == str(user_id)
            
        except Exception as e:
            }")
            return False

    def get_room_stats(self, room_id: str) -> Dict[str, Any]:
        """Get room statistics."""
        try:
            room_data = self.get_room_permissions(room_id)
            if not room_data:
                return {}
            
            # Get room size from WebSocket manager (this would need to be passed in)
            # For now, return basic stats
            stats = {
                'room_id': room_id,
                'permission': room_data.get('permission'),
                'owner_id': room_data.get('owner_id'),
                'created_at': room_data.get('created_at'),
                'updated_at': room_data.get('updated_at'),
                'max_size': room_data.get('max_size', Config.WS_ROOM_SIZE_LIMIT)
            }
            
            return stats
            
        except Exception as e:
            }")
            return {}

    def cleanup_stale_rooms(self, max_age_hours: int = 24) -> int:
        """Clean up stale rooms that haven't been updated recently."""
        try:
            all_rooms = self.get_all_rooms()
            cleaned_count = 0
            max_age = max_age_hours * 3600  # Convert to seconds
            
            for room in all_rooms:
                room_id = room.get('room_id')
                updated_at = room.get('updated_at')
                
                if updated_at:
                    try:
                        updated_time = datetime.fromisoformat(updated_at)
                        age = datetime.now() - updated_time
                        
                        if age.total_seconds() > max_age:
                            self.delete_room(room_id)
                            cleaned_count += 1
                            except Exception as e:
                        }")
            
            return cleaned_count
            
        except Exception as e:
            }")
            return 0 