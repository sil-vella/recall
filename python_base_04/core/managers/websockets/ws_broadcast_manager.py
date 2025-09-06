from typing import Dict, Any, Set, Optional
from datetime import datetime
from flask_socketio import emit

class WSBroadcastManager:
    """WebSocket Broadcast Manager - Handles message broadcasting and session communication."""
    
    def __init__(self, websocket_manager):
        self.websocket_manager = websocket_manager
        def broadcast_to_room(self, room_id: str, event: str, data: Any) -> bool:
        """Broadcast message to a specific room."""
        try:
            # Add timestamp to broadcast data
            broadcast_data = {
                'event': event,
                'data': data,
                'room_id': room_id,
                'timestamp': datetime.now().isoformat()
            }
            
            # Use WebSocket manager to broadcast
            self.websocket_manager.socketio.emit(event, broadcast_data, room=room_id)
            
            return True
            
        except Exception as e:
            }")
            return False

    def send_to_session(self, session_id: str, event: str, data: Any) -> bool:
        """Send message to a specific session."""
        try:
            # Add timestamp to message data
            message_data = {
                'event': event,
                'data': data,
                'session_id': session_id,
                'timestamp': datetime.now().isoformat()
            }
            
            # Use WebSocket manager to send to session
            self.websocket_manager.socketio.emit(event, message_data, room=session_id)
            
            return True
            
        except Exception as e:
            }")
            return False

    def broadcast_to_all(self, event: str, data: Any) -> bool:
        """Broadcast message to all connected clients."""
        try:
            # Add timestamp to broadcast data
            broadcast_data = {
                'event': event,
                'data': data,
                'timestamp': datetime.now().isoformat()
            }
            
            # Use WebSocket manager to broadcast to all
            self.websocket_manager.socketio.emit(event, broadcast_data)
            
            return True
            
        except Exception as e:
            }")
            return False

    def get_room_members(self, room_id: str) -> Set[str]:
        """Get all members in a room."""
        try:
            return self.websocket_manager.get_room_members(room_id)
        except Exception as e:
            }")
            return set()

    def get_rooms_for_session(self, session_id: str) -> Set[str]:
        """Get all rooms for a session."""
        try:
            return self.websocket_manager.get_rooms_for_session(session_id)
        except Exception as e:
            }")
            return set()

    def broadcast_message(self, room_id: str, message: str, sender_id: str = None, 
                        additional_data: Optional[Dict[str, Any]] = None) -> bool:
        """Broadcast a message to all users in a room."""
        try:
            # Get sender info
            sender_info = {}
            if sender_id:
                session_data = self.websocket_manager.get_session_data(sender_id)
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
                'additional_data': additional_data or {},
                'timestamp': datetime.now().isoformat()
            }
            
            # Broadcast to room
            return self.broadcast_to_room(room_id, 'message', message_data)
            
        except Exception as e:
            }")
            return False

    def broadcast_user_joined(self, room_id: str, user_id: str, username: str) -> bool:
        """Broadcast user joined event to room."""
        try:
            join_data = {
                'room_id': room_id,
                'user_id': user_id,
                'username': username,
                'timestamp': datetime.now().isoformat()
            }
            
            return self.broadcast_to_room(room_id, 'user_joined', join_data)
            
        except Exception as e:
            }")
            return False

    def broadcast_user_left(self, room_id: str, user_id: str, username: str) -> bool:
        """Broadcast user left event to room."""
        try:
            leave_data = {
                'room_id': room_id,
                'user_id': user_id,
                'username': username,
                'timestamp': datetime.now().isoformat()
            }
            
            return self.broadcast_to_room(room_id, 'user_left', leave_data)
            
        except Exception as e:
            }")
            return False

    def broadcast_room_created(self, room_id: str, creator_id: str, room_data: Dict[str, Any]) -> bool:
        """Broadcast room created event."""
        try:
            create_data = {
                'room_id': room_id,
                'creator_id': creator_id,
                'room_data': room_data,
                'timestamp': datetime.now().isoformat()
            }
            
            return self.broadcast_to_all('room_created', create_data)
            
        except Exception as e:
            }")
            return False

    def broadcast_room_deleted(self, room_id: str) -> bool:
        """Broadcast room deleted event."""
        try:
            delete_data = {
                'room_id': room_id,
                'timestamp': datetime.now().isoformat()
            }
            
            return self.broadcast_to_all('room_deleted', delete_data)
            
        except Exception as e:
            }")
            return False

    def send_connection_success(self, session_id: str, session_data: Dict[str, Any]) -> bool:
        """Send connection success message to session."""
        try:
            success_data = {
                'session_id': session_id,
                'session_data': session_data,
                'timestamp': datetime.now().isoformat()
            }
            
            return self.send_to_session(session_id, 'connect_success', success_data)
            
        except Exception as e:
            }")
            return False

    def send_connection_error(self, session_id: str, error: str) -> bool:
        """Send connection error message to session."""
        try:
            error_data = {
                'error': error,
                'timestamp': datetime.now().isoformat()
            }
            
            return self.send_to_session(session_id, 'connect_error', error_data)
            
        except Exception as e:
            }")
            return False

    def send_join_room_success(self, session_id: str, room_id: str, room_data: Dict[str, Any]) -> bool:
        """Send join room success message to session."""
        try:
            # Get owner_id from memory storage
            owner_id = self.websocket_manager.get_room_creator(room_id)
            
            success_data = {
                'room_id': room_id,
                'room_data': room_data,
                'owner_id': owner_id,  # Include owner_id from memory
                'timestamp': datetime.now().isoformat()
            }
            
            return self.send_to_session(session_id, 'join_room_success', success_data)
            
        except Exception as e:
            }")
            return False

    def send_join_room_error(self, session_id: str, error: str) -> bool:
        """Send join room error message to session."""
        try:
            error_data = {
                'error': error,
                'timestamp': datetime.now().isoformat()
            }
            
            return self.send_to_session(session_id, 'join_room_error', error_data)
            
        except Exception as e:
            }")
            return False

    def send_leave_room_success(self, session_id: str, room_id: str) -> bool:
        """Send leave room success message to session."""
        try:
            success_data = {
                'room_id': room_id,
                'timestamp': datetime.now().isoformat()
            }
            
            return self.send_to_session(session_id, 'leave_room_success', success_data)
            
        except Exception as e:
            }")
            return False

    def send_leave_room_error(self, session_id: str, error: str) -> bool:
        """Send leave room error message to session."""
        try:
            error_data = {
                'error': error,
                'timestamp': datetime.now().isoformat()
            }
            
            return self.send_to_session(session_id, 'leave_room_error', error_data)
            
        except Exception as e:
            }")
            return False

    def send_room_state(self, session_id: str, room_id: str, room_data: Dict[str, Any]) -> bool:
        """Send room state to session."""
        try:
            # Get owner_id from memory storage
            owner_id = self.websocket_manager.get_room_creator(room_id)
            
            state_data = {
                'room_id': room_id,
                'room_data': room_data,
                'owner_id': owner_id,  # Include owner_id from memory
                'timestamp': datetime.now().isoformat()
            }
            
            return self.send_to_session(session_id, 'room_state', state_data)
            
        except Exception as e:
            }")
            return False

    def send_error(self, session_id: str, error: str, details: Optional[str] = None) -> bool:
        """Send error message to session."""
        try:
            error_data = {
                'error': error,
                'details': details,
                'timestamp': datetime.now().isoformat()
            }
            
            return self.send_to_session(session_id, 'error', error_data)
            
        except Exception as e:
            }")
            return False

    def get_broadcast_statistics(self) -> Dict[str, Any]:
        """Get broadcast statistics."""
        try:
            stats = {
                'total_rooms': len(self.websocket_manager.rooms),
                'total_sessions': len(self.websocket_manager.session_rooms),
                'connection_status': self.websocket_manager.isConnected,
                'timestamp': datetime.now().isoformat()
            }
            
            return stats
            
        except Exception as e:
            }")
            return {} 