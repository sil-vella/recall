from typing import Dict, Any, Optional
import re

class WebSocketValidator:
    """Validator for WebSocket operations and data."""
    
    def __init__(self):
        self.max_message_length = 65536  # 64KB
        self.max_room_id_length = 64
        self.max_username_length = 50
        self.allowed_room_id_chars = re.compile(r'^[a-zA-Z0-9_-]+$')
        
    def validate_room_id(self, room_id: str) -> bool:
        """Validate room ID format."""
        if not room_id or not isinstance(room_id, str):
            return False
            
        if len(room_id) > self.max_room_id_length:
            return False
            
        if not self.allowed_room_id_chars.match(room_id):
            return False
            
        return True
    
    def validate_message(self, message: str) -> bool:
        """Validate message content."""
        if not message or not isinstance(message, str):
            return False
            
        if len(message) > self.max_message_length:
            return False
            
        return True
    
    def validate_username(self, username: str) -> bool:
        """Validate username format."""
        if not username or not isinstance(username, str):
            return False
            
        if len(username) > self.max_username_length:
            return False
            
        # Basic username validation - alphanumeric and common symbols
        if not re.match(r'^[a-zA-Z0-9_-]+$', username):
            return False
            
        return True
    
    def validate_session_data(self, session_data: Dict[str, Any]) -> bool:
        """Validate session data structure."""
        required_fields = ['user_id', 'username', 'rooms', 'user_roles']
        
        if not isinstance(session_data, dict):
            return False
            
        for field in required_fields:
            if field not in session_data:
                return False
                
        return True
    
    def validate_room_data(self, room_data: Dict[str, Any]) -> bool:
        """Validate room data structure."""
        required_fields = ['room_id', 'permission', 'owner_id']
        
        if not isinstance(room_data, dict):
            return False
            
        for field in required_fields:
            if field not in room_data:
                return False
                
        return True 