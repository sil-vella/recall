from typing import Dict, Any, List, Callable, Optional
from datetime import datetime
import json
from enum import Enum

class EventType(Enum):
    """WebSocket event types."""
    CONNECTION = "connection"
    ROOM = "room"
    MESSAGE = "message"
    SESSION = "session"
    ERROR = "error"
    CUSTOM = "custom"

class ConnectionStatus(Enum):
    """Connection status types."""
    CONNECTING = "connecting"
    CONNECTED = "connected"
    DISCONNECTED = "disconnected"
    ERROR = "error"
    RECONNECTING = "reconnecting"

class WSEventManager:
    """WebSocket Event Manager - Centralized event handling for WebSocket operations."""
    
    def __init__(self):
        self._event_handlers: Dict[str, List[Callable]] = {}
        self._one_time_handlers: Dict[str, List[Callable]] = {}
        self._state = {
            'is_connected': False,
            'current_room_id': None,
            'current_room_info': None,
            'session_data': None,
            'connection_status': ConnectionStatus.DISCONNECTED
        }
        def register_handler(self, event_type: str, handler: Callable) -> None:
        """Register a handler for a specific event type."""
        if event_type not in self._event_handlers:
            self._event_handlers[event_type] = []
        self._event_handlers[event_type].append(handler)
        def unregister_handler(self, event_type: str, handler: Callable) -> None:
        """Unregister a handler for a specific event type."""
        if event_type in self._event_handlers:
            if handler in self._event_handlers[event_type]:
                self._event_handlers[event_type].remove(handler)
                def register_one_time_handler(self, event_type: str, handler: Callable) -> None:
        """Register a one-time handler for a specific event type."""
        if event_type not in self._one_time_handlers:
            self._one_time_handlers[event_type] = []
        self._one_time_handlers[event_type].append(handler)
        def emit_event(self, event_type: str, data: Dict[str, Any]) -> None:
        """Emit an event to all registered handlers."""
        try:
            # Add timestamp to event data
            event_data = {
                'type': event_type,
                'data': data,
                'timestamp': datetime.now().isoformat()
            }
            
            # Call regular handlers
            if event_type in self._event_handlers:
                for handler in self._event_handlers[event_type]:
                    try:
                        handler(event_data)
                    except Exception as e:
                        }")
            
            # Call one-time handlers and remove them
            if event_type in self._one_time_handlers:
                handlers_to_remove = []
                for handler in self._one_time_handlers[event_type]:
                    try:
                        handler(event_data)
                        handlers_to_remove.append(handler)
                    except Exception as e:
                        }")
                        handlers_to_remove.append(handler)
                
                # Remove called handlers
                for handler in handlers_to_remove:
                    self._one_time_handlers[event_type].remove(handler)
            
            # Update state based on event type
            self._update_state(event_type, data)
            
        except Exception as e:
            }")

    def _update_state(self, event_type: str, data: Dict[str, Any]) -> None:
        """Update internal state based on event type."""
        try:
            if event_type == EventType.CONNECTION.value:
                status = data.get('status')
                if status:
                    self._state['connection_status'] = ConnectionStatus(status)
                    self._state['is_connected'] = (status == ConnectionStatus.CONNECTED.value)
                    
            elif event_type == EventType.ROOM.value:
                action = data.get('action')
                room_id = data.get('room_id')
                room_data = data.get('room_data')
                
                if action == 'joined':
                    self._state['current_room_id'] = room_id
                    self._state['current_room_info'] = room_data
                elif action == 'left':
                    if self._state['current_room_id'] == room_id:
                        self._state['current_room_id'] = None
                        self._state['current_room_info'] = None
                        
            elif event_type == EventType.SESSION.value:
                self._state['session_data'] = data
                
        except Exception as e:
            }")

    def get_state(self) -> Dict[str, Any]:
        """Get current state."""
        return self._state.copy()

    def get_connection_status(self) -> ConnectionStatus:
        """Get current connection status."""
        return self._state['connection_status']

    def is_connected(self) -> bool:
        """Check if currently connected."""
        return self._state['is_connected']

    def get_current_room_id(self) -> Optional[str]:
        """Get current room ID."""
        return self._state['current_room_id']

    def get_current_room_info(self) -> Optional[Dict[str, Any]]:
        """Get current room info."""
        return self._state['current_room_info']

    def get_session_data(self) -> Optional[Dict[str, Any]]:
        """Get current session data."""
        return self._state['session_data']

    def clear_handlers(self, event_type: Optional[str] = None) -> None:
        """Clear all handlers or handlers for a specific event type."""
        if event_type:
            if event_type in self._event_handlers:
                del self._event_handlers[event_type]
            if event_type in self._one_time_handlers:
                del self._one_time_handlers[event_type]
            else:
            self._event_handlers.clear()
            self._one_time_handlers.clear()
            def get_handler_count(self, event_type: str) -> int:
        """Get the number of handlers for a specific event type."""
        regular_count = len(self._event_handlers.get(event_type, []))
        one_time_count = len(self._one_time_handlers.get(event_type, []))
        return regular_count + one_time_count

    def list_registered_events(self) -> List[str]:
        """List all registered event types."""
        events = set()
        events.update(self._event_handlers.keys())
        events.update(self._one_time_handlers.keys())
        return list(events)

    def handle_connection_event(self, status: str, session_id: Optional[str] = None, error: Optional[str] = None) -> None:
        """Handle connection status events."""
        event_data = {
            'status': status,
            'session_id': session_id,
            'error': error
        }
        self.emit_event(EventType.CONNECTION.value, event_data)

    def handle_room_event(self, action: str, room_id: str, room_data: Optional[Dict[str, Any]] = None) -> None:
        """Handle room events."""
        event_data = {
            'action': action,
            'room_id': room_id,
            'room_data': room_data or {}
        }
        self.emit_event(EventType.ROOM.value, event_data)

    def handle_message_event(self, room_id: str, message: str, sender: str, additional_data: Optional[Dict[str, Any]] = None) -> None:
        """Handle message events."""
        event_data = {
            'room_id': room_id,
            'message': message,
            'sender': sender,
            'additional_data': additional_data or {}
        }
        self.emit_event(EventType.MESSAGE.value, event_data)

    def handle_session_event(self, session_data: Dict[str, Any]) -> None:
        """Handle session events."""
        self.emit_event(EventType.SESSION.value, session_data)

    def handle_error_event(self, error: str, details: Optional[str] = None) -> None:
        """Handle error events."""
        event_data = {
            'error': error,
            'details': details
        }
        self.emit_event(EventType.ERROR.value, event_data)

    def handle_custom_event(self, event_name: str, data: Dict[str, Any]) -> None:
        """Handle custom events."""
        event_data = {
            'event_name': event_name,
            'data': data
        }
        self.emit_event(event_name, event_data)

    def create_room_event(self, room_id: str, room_data: Dict[str, Any]) -> Dict[str, Any]:
        """Create a room event data structure."""
        return {
            'action': 'created',
            'room_id': room_id,
            'room_data': room_data,
            'timestamp': datetime.now().isoformat()
        }

    def create_join_room_event(self, room_id: str, room_data: Dict[str, Any]) -> Dict[str, Any]:
        """Create a join room event data structure."""
        return {
            'action': 'joined',
            'room_id': room_id,
            'room_data': room_data,
            'timestamp': datetime.now().isoformat()
        }

    def create_leave_room_event(self, room_id: str) -> Dict[str, Any]:
        """Create a leave room event data structure."""
        return {
            'action': 'left',
            'room_id': room_id,
            'timestamp': datetime.now().isoformat()
        }

    def create_message_event(self, room_id: str, message: str, sender: str, additional_data: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """Create a message event data structure."""
        return {
            'room_id': room_id,
            'message': message,
            'sender': sender,
            'additional_data': additional_data or {},
            'timestamp': datetime.now().isoformat()
        }

    def create_connection_event(self, status: str, session_id: Optional[str] = None, error: Optional[str] = None) -> Dict[str, Any]:
        """Create a connection event data structure."""
        return {
            'status': status,
            'session_id': session_id,
            'error': error,
            'timestamp': datetime.now().isoformat()
        }

    def create_error_event(self, error: str, details: Optional[str] = None) -> Dict[str, Any]:
        """Create an error event data structure."""
        return {
            'error': error,
            'details': details,
            'timestamp': datetime.now().isoformat()
        }

    def create_custom_event(self, event_name: str, data: Dict[str, Any]) -> Dict[str, Any]:
        """Create a custom event data structure."""
        return {
            'event_name': event_name,
            'data': data,
            'timestamp': datetime.now().isoformat()
        }

    def validate_event_data(self, event_type: str, data: Dict[str, Any]) -> bool:
        """Validate event data structure."""
        try:
            if event_type == EventType.CONNECTION.value:
                return 'status' in data
            elif event_type == EventType.ROOM.value:
                return 'action' in data and 'room_id' in data
            elif event_type == EventType.MESSAGE.value:
                return 'room_id' in data and 'message' in data and 'sender' in data
            elif event_type == EventType.SESSION.value:
                return isinstance(data, dict)
            elif event_type == EventType.ERROR.value:
                return 'error' in data
            else:
                # Custom event
                return isinstance(data, dict)
        except Exception as e:
            }")
            return False

    def get_event_statistics(self) -> Dict[str, Any]:
        """Get statistics about registered events."""
        stats = {
            'total_events': len(self.list_registered_events()),
            'regular_handlers': {},
            'one_time_handlers': {},
            'state': self._state
        }
        
        for event_type in self._event_handlers:
            stats['regular_handlers'][event_type] = len(self._event_handlers[event_type])
            
        for event_type in self._one_time_handlers:
            stats['one_time_handlers'][event_type] = len(self._one_time_handlers[event_type])
            
        return stats

    def reset_state(self) -> None:
        """Reset the internal state."""
        self._state = {
            'is_connected': False,
            'current_room_id': None,
            'current_room_info': None,
            'session_data': None,
            'connection_status': ConnectionStatus.DISCONNECTED
        }
        def cleanup(self) -> None:
        """Clean up the event manager."""
        self.clear_handlers()
        self.reset_state()
        