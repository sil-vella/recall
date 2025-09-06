from typing import Dict, Any, Optional, Set, List
from tools.logger.custom_logging import custom_log
from datetime import datetime
from core.managers.redis_manager import RedisManager
from core.managers.jwt_manager import JWTManager, TokenType
from utils.config.config import Config

class WSSessionManager:
    """WebSocket Session Manager - Handles session data, authentication, and session lifecycle."""
    
    def __init__(self, redis_manager: RedisManager, jwt_manager: JWTManager):
        self.redis_manager = redis_manager
        self.jwt_manager = jwt_manager
        custom_log("WSSessionManager initialized")

    def create_session(self, session_id: str, user_id: str, username: str, token: str, 
                      client_id: str = None, origin: str = None) -> Dict[str, Any]:
        """Create a new session."""
        try:
            session_data = {
                'session_id': session_id,
                'user_id': str(user_id),
                'username': username,
                'token': token,
                'client_id': client_id or session_id,
                'origin': origin or 'unknown',
                'connected_at': datetime.now().isoformat(),
                'last_activity': datetime.now().isoformat(),
                'rooms': set(),
                'user_roles': set(),
                'status': 'active'
            }
            
            # Store session data
            self.store_session_data(session_id, session_data)
            
            custom_log(f"✅ Session created: {session_id} for user {user_id}")
            return {
                'success': True,
                'session_id': session_id,
                'user_id': user_id
            }
            
        except Exception as e:
            custom_log(f"❌ Error creating session {session_id}: {str(e)}")
            return {
                'success': False,
                'error': f'Failed to create session: {str(e)}'
            }

    def store_session_data(self, session_id: str, session_data: Dict[str, Any]) -> None:
        """Store session data in Redis."""
        try:
            # Create a deep copy for storage
            data_to_store = session_data.copy()
            
            # Convert sets to lists for JSON serialization
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
            
            custom_log(f"✅ Session data stored for session {session_id}")
            
        except Exception as e:
            custom_log(f"❌ Error storing session data: {str(e)}")
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
                
                return data_copy
            return None
            
        except Exception as e:
            custom_log(f"❌ Error getting session data: {str(e)}")
            return None

    def get_client_session_data(self, session_id: str) -> Optional[Dict[str, Any]]:
        """Get session data formatted for client use."""
        try:
            data = self.get_session_data(session_id)
            if data:
                # Create a copy for client use with lists instead of sets
                client_data = data.copy()
                
                # Convert sets to lists for client use
                if 'rooms' in client_data:
                    client_data['rooms'] = list(client_data['rooms'])
                if 'user_roles' in client_data:
                    client_data['user_roles'] = list(client_data['user_roles'])
                
                return client_data
            return None
            
        except Exception as e:
            custom_log(f"❌ Error getting client session data: {str(e)}")
            return None

    def update_session_activity(self, session_id: str) -> None:
        """Update session activity timestamp."""
        try:
            session_data = self.get_session_data(session_id)
            if session_data:
                session_data['last_activity'] = datetime.now().isoformat()
                self.store_session_data(session_id, session_data)
                custom_log(f"✅ Updated session activity for session: {session_id}")
        except Exception as e:
            custom_log(f"❌ Error updating session activity: {str(e)}")

    def add_room_to_session(self, session_id: str, room_id: str) -> bool:
        """Add a room to a session."""
        try:
            session_data = self.get_session_data(session_id)
            if session_data:
                if 'rooms' not in session_data:
                    session_data['rooms'] = set()
                session_data['rooms'].add(room_id)
                session_data['last_activity'] = datetime.now().isoformat()
                self.store_session_data(session_id, session_data)
                custom_log(f"✅ Added room {room_id} to session {session_id}")
                return True
            return False
        except Exception as e:
            custom_log(f"❌ Error adding room to session: {str(e)}")
            return False

    def remove_room_from_session(self, session_id: str, room_id: str) -> bool:
        """Remove a room from a session."""
        try:
            session_data = self.get_session_data(session_id)
            if session_data and 'rooms' in session_data:
                session_data['rooms'].discard(room_id)
                session_data['last_activity'] = datetime.now().isoformat()
                self.store_session_data(session_id, session_data)
                custom_log(f"✅ Removed room {room_id} from session {session_id}")
                return True
            return False
        except Exception as e:
            custom_log(f"❌ Error removing room from session: {str(e)}")
            return False

    def update_user_roles(self, session_id: str, roles: Set[str]) -> bool:
        """Update user roles in session."""
        try:
            session_data = self.get_session_data(session_id)
            if session_data:
                session_data['user_roles'] = roles
                session_data['last_activity'] = datetime.now().isoformat()
                self.store_session_data(session_id, session_data)
                custom_log(f"✅ Updated user roles for session {session_id}: {roles}")
                return True
            return False
        except Exception as e:
            custom_log(f"❌ Error updating user roles: {str(e)}")
            return False

    def validate_session(self, session_id: str) -> bool:
        """Validate if a session exists and is active."""
        try:
            session_data = self.get_session_data(session_id)
            if session_data:
                status = session_data.get('status', 'active')
                return status == 'active'
            return False
        except Exception as e:
            custom_log(f"❌ Error validating session: {str(e)}")
            return False

    def cleanup_session(self, session_id: str) -> None:
        """Clean up session data."""
        try:
            session_key = self.redis_manager._generate_secure_key("session", session_id)
            self.redis_manager.delete(session_key)
            custom_log(f"✅ Cleaned up session: {session_id}")
        except Exception as e:
            custom_log(f"❌ Error cleaning up session: {str(e)}")

    def get_all_sessions(self) -> List[Dict[str, Any]]:
        """Get all active sessions."""
        try:
            session_keys = self.redis_manager.get_keys("session:*")
            sessions = []
            
            for session_key in session_keys:
                session_data = self.redis_manager.get(session_key)
                if session_data:
                    sessions.append(session_data)
            
            return sessions
        except Exception as e:
            custom_log(f"❌ Error getting all sessions: {str(e)}")
            return []

    def get_sessions_for_user(self, user_id: str) -> List[Dict[str, Any]]:
        """Get all sessions for a specific user."""
        try:
            all_sessions = self.get_all_sessions()
            user_sessions = []
            
            for session in all_sessions:
                if session.get('user_id') == str(user_id):
                    user_sessions.append(session)
            
            return user_sessions
        except Exception as e:
            custom_log(f"❌ Error getting sessions for user: {str(e)}")
            return []

    def get_session_count(self) -> int:
        """Get the total number of active sessions."""
        try:
            session_keys = self.redis_manager.get_keys("session:*")
            return len(session_keys)
        except Exception as e:
            custom_log(f"❌ Error getting session count: {str(e)}")
            return 0

    def cleanup_stale_sessions(self, max_inactive_hours: int = 24) -> int:
        """Clean up stale sessions that haven't been active recently."""
        try:
            all_sessions = self.get_all_sessions()
            cleaned_count = 0
            max_inactive = max_inactive_hours * 3600  # Convert to seconds
            
            for session in all_sessions:
                session_id = session.get('session_id')
                last_activity = session.get('last_activity')
                
                if last_activity:
                    try:
                        last_activity_time = datetime.fromisoformat(last_activity)
                        inactive_time = datetime.now() - last_activity_time
                        
                        if inactive_time.total_seconds() > max_inactive:
                            self.cleanup_session(session_id)
                            cleaned_count += 1
                            custom_log(f"Cleaned up stale session: {session_id}")
                            
                    except Exception as e:
                        custom_log(f"Error parsing session activity time: {str(e)}")
            
            custom_log(f"Cleaned up {cleaned_count} stale sessions")
            return cleaned_count
            
        except Exception as e:
            custom_log(f"❌ Error cleaning up stale sessions: {str(e)}")
            return 0

    def authenticate_session(self, session_id: str, token: str) -> bool:
        """Authenticate a session using JWT token."""
        try:
            # Validate token
            payload = self.jwt_manager.verify_token(token, TokenType.ACCESS) or \
                     self.jwt_manager.verify_token(token, TokenType.WEBSOCKET)
            
            if not payload:
                custom_log(f"❌ Invalid token for session {session_id}")
                return False
            
            # Get session data
            session_data = self.get_session_data(session_id)
            if not session_data:
                custom_log(f"❌ No session data found for session {session_id}")
                return False
            
            # Update session with user info
            session_data['user_id'] = str(payload.get('user_id'))
            session_data['username'] = payload.get('username', '')
            session_data['user_roles'] = set(payload.get('roles', []))
            session_data['last_activity'] = datetime.now().isoformat()
            
            # Store updated session data
            self.store_session_data(session_id, session_data)
            
            custom_log(f"✅ Authenticated session {session_id} for user {session_data['user_id']}")
            return True
            
        except Exception as e:
            custom_log(f"❌ Error authenticating session: {str(e)}")
            return False

    def get_session_stats(self, session_id: str) -> Dict[str, Any]:
        """Get session statistics."""
        try:
            session_data = self.get_session_data(session_id)
            if not session_data:
                return {}
            
            stats = {
                'session_id': session_id,
                'user_id': session_data.get('user_id'),
                'username': session_data.get('username'),
                'connected_at': session_data.get('connected_at'),
                'last_activity': session_data.get('last_activity'),
                'room_count': len(session_data.get('rooms', set())),
                'role_count': len(session_data.get('user_roles', set())),
                'status': session_data.get('status', 'unknown')
            }
            
            return stats
            
        except Exception as e:
            custom_log(f"❌ Error getting session stats: {str(e)}")
            return {} 