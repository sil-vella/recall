from typing import Dict, Any, Optional, Set, List
from tools.logger.custom_logging import custom_log
from datetime import datetime
from enum import Enum
from system.managers.redis_manager import RedisManager
from utils.config.config import Config

class RoomPermission(Enum):
    """Room permission types."""
    PUBLIC = "public"
    PRIVATE = "private"

class WSRoomManager:
    """WebSocket Room Manager - Handles room creation, permissions, and management."""
    
    def __init__(self):
        self.redis_manager = RedisManager()
        custom_log("WSRoomManager initialized")

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
            
            # Store room data in Redis
            room_key = self.redis_manager._generate_secure_key("room", room_id)
            self.redis_manager.set(room_key, room_data, expire=Config.WS_ROOM_TTL)
            
            custom_log(f"✅ Room created: {room_id} with permission: {permission.value}")
            return {
                'success': True,
                'room_id': room_id,
                'permission': permission.value,
                'owner_id': owner_id
            }
            
        except Exception as e:
            custom_log(f"❌ Error creating room {room_id}: {str(e)}")
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
            custom_log(f"Error getting room permissions: {str(e)}")
            return None

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
            
            custom_log(f"✅ Room permissions updated: {room_id}")
            return {
                'success': True,
                'room_id': room_id,
                'permission': room_data['permission']
            }
            
        except Exception as e:
            custom_log(f"❌ Error updating room permissions: {str(e)}")
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
            
            custom_log(f"✅ Room deleted: {room_id}")
            return {
                'success': True,
                'room_id': room_id
            }
            
        except Exception as e:
            custom_log(f"❌ Error deleting room {room_id}: {str(e)}")
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
                custom_log(f"No permissions found for room {room_id}, allowing access")
                return True
            
            permission_type = room_data.get('permission', 'public')
            owner_id = room_data.get('owner_id')
            allowed_users = set(room_data.get('allowed_users', []))
            allowed_roles = set(room_data.get('allowed_roles', []))
            
            # Owner always has access
            if owner_id and str(owner_id) == str(user_id):
                custom_log(f"User {user_id} is owner of room {room_id}, allowing access")
                return True
            
            # Check permission type
            if permission_type == 'public':
                custom_log(f"Room {room_id} is public, allowing access for user {user_id}")
                return True
            elif permission_type == 'private':
                # Check if user is in allowed users or has allowed role
                if user_id in allowed_users:
                    custom_log(f"User {user_id} is in allowed users for room {room_id}")
                    return True
                
                if any(role in allowed_roles for role in user_roles):
                    custom_log(f"User {user_id} has allowed role for room {room_id}")
                    return True
                
                custom_log(f"User {user_id} denied access to private room {room_id}")
                return False
            else:
                custom_log(f"Unknown permission type {permission_type} for room {room_id}")
                return False
                
        except Exception as e:
            custom_log(f"Error checking room access: {str(e)}")
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
            custom_log(f"Error getting all rooms: {str(e)}")
            return []

    def get_rooms_for_user(self, user_id: str) -> List[Dict[str, Any]]:
        """Get all rooms accessible to a user."""
        try:
            all_rooms = self.get_all_rooms()
            accessible_rooms = []
            
            for room in all_rooms:
                room_id = room.get('room_id')
                if room_id:
                    # Check if user has access to this room
                    if self.check_room_access(room_id, user_id, [], None):
                        accessible_rooms.append(room)
            
            return accessible_rooms
            
        except Exception as e:
            custom_log(f"Error getting rooms for user: {str(e)}")
            return []

    def get_room_owner(self, room_id: str) -> Optional[str]:
        """Get the owner of a room."""
        try:
            room_data = self.get_room_permissions(room_id)
            if room_data:
                return room_data.get('owner_id')
            return None
            
        except Exception as e:
            custom_log(f"Error getting room owner: {str(e)}")
            return None

    def is_room_owner(self, room_id: str, user_id: str) -> bool:
        """Check if user is the owner of a room."""
        try:
            owner_id = self.get_room_owner(room_id)
            return owner_id and str(owner_id) == str(user_id)
            
        except Exception as e:
            custom_log(f"Error checking room ownership: {str(e)}")
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
            custom_log(f"Error getting room stats: {str(e)}")
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
                            custom_log(f"Cleaned up stale room: {room_id}")
                            
                    except Exception as e:
                        custom_log(f"Error parsing room update time: {str(e)}")
            
            custom_log(f"Cleaned up {cleaned_count} stale rooms")
            return cleaned_count
            
        except Exception as e:
            custom_log(f"Error cleaning up stale rooms: {str(e)}")
            return 0 