"""
WebSocket Event Handlers
Centralized event handler functions for WebSocket operations
"""

from flask_socketio import emit, join_room, leave_room
from flask import request
from tools.logger.custom_logging import custom_log
from datetime import datetime
import json
import uuid
from core.managers.jwt_manager import TokenType
from utils.config.config import Config

class WSEventHandlers:
    """Centralized WebSocket event handlers"""
    
    def __init__(self, websocket_manager):
        self.websocket_manager = websocket_manager
        self.socketio = websocket_manager.socketio

    def _resolve_user_id(self, session_id: str, data: dict) -> str:
        """Resolve the authenticated user id from backend authentication system.

        Order of precedence:
        1) Explicit user_id in incoming data (if trusted)
        2) Session data (if previously stored)
        3) Backend authentication system (JWT token from request)
        4) Fallback: session_id
        """
        try:
            # 1) From payload
            user_id = (data or {}).get('user_id')
            if user_id:
                return str(user_id)

            # 2) From session storage
            session_data = self.websocket_manager.get_session_data(session_id)
            if session_data and session_data.get('user_id'):
                return str(session_data.get('user_id'))

            # 3) From backend authentication system
            try:
                # Get JWT manager from WebSocket manager
                jwt_manager = getattr(self.websocket_manager, '_jwt_manager', None)
                
                if jwt_manager:
                    # Try to get token from request
                    token = None
                    if hasattr(request, 'args') and request.args:
                        token = request.args.get('token')
                    if not token and hasattr(request, 'headers') and request.headers:
                        auth_header = request.headers.get('Authorization')
                        if auth_header and auth_header.startswith('Bearer '):
                            token = auth_header[7:]
                    
                    if token:
                        payload = jwt_manager.validate_token(token, TokenType.ACCESS)
                        if payload and payload.get('user_id'):
                            user_id = str(payload.get('user_id'))
                            
                            # Persist back into session
                            session_data = session_data or {}
                            session_data['user_id'] = user_id
                            if payload.get('username'):
                                session_data['username'] = payload.get('username')
                            self.websocket_manager.store_session_data(session_id, session_data)
                            
                            return user_id
                        else:
                            pass
                    else:
                        pass
                else:
                    pass
            except Exception as e:
                import traceback

            # 4) Fallback: use session_id as user_id (for backward compatibility)
            # BUT: If we have session data with a real user_id, use that instead
            if session_data and session_data.get('user_id'):
                real_user_id = session_data.get('user_id')
                return str(real_user_id)
            return str(session_id)
        except Exception as e:
            # Try to get user_id from session data as last resort
            try:
                session_data = self.websocket_manager.get_session_data(session_id)
                if session_data and session_data.get('user_id'):
                    real_user_id = session_data.get('user_id')
                    return str(real_user_id)
            except:
                pass
            return str(session_id)

    def _emit_user_joined_rooms(self, session_id: str):
        """Emit user_joined_rooms event with all rooms the user is currently in."""
        try:
            # Get all rooms for this session
            user_rooms = self.websocket_manager.get_rooms_for_session(session_id)
            
            # Get detailed room info for each room
            rooms_info = []
            for room_id in user_rooms:
                room_info = self.websocket_manager.get_room_info(room_id)
                if room_info:
                    rooms_info.append(room_info)
            
            # Emit the event to the client
            self.socketio.emit('user_joined_rooms', {
                'session_id': session_id,
                'rooms': rooms_info,
                'total_rooms': len(rooms_info),
                'timestamp': datetime.now().isoformat()
            })
            
        except Exception as e:
            pass

    def handle_unified_event(self, event_name, event_type, data):
        """Unified event handler that routes to specific handlers"""
        
        # Route to appropriate handler based on event name
        handler_map = {
            'connect': self.handle_connect,
            'disconnect': self.handle_disconnect,
            'join_room': self.handle_join_room,
            'create_room': self.handle_create_room,
            'leave_room': self.handle_leave_room,
            'get_public_rooms': self.handle_get_public_rooms,
            'send_message': self.handle_send_message,
            'broadcast': self.handle_broadcast,
            'message': self.handle_message,  # Legacy support
        }
        
        handler = handler_map.get(event_name)
        if handler:
            session_id = request.sid
            return handler(session_id, data)
        else:
            return False

    def handle_connect(self, session_id, data=None):
        """Handle client connection"""
        try:
            
            # Generate a simple client ID for rate limiting
            client_id = f"client_{session_id}"
            
            # Check rate limits (skip for now to allow connections)
            # if not self.websocket_manager.check_rate_limit(client_id, 'connections'):
            #     custom_log(f"Rate limit exceeded for connection: {client_id}")
            #     return False
            
            # Update rate limit
            self.websocket_manager.update_rate_limit(client_id, 'connections')
            
            # Extract actual user ID from JWT token during connection
            user_id = None
            try:
                # Get JWT manager from WebSocket manager
                jwt_manager = getattr(self.websocket_manager, '_jwt_manager', None)
                
                if jwt_manager:
                    # Try to get token from Socket.IO connection context
                    token = None
                    
                    # Socket.IO stores auth data in the connection context
                    if hasattr(request, 'sid'):
                        # Get token from Socket.IO auth data
                        try:
                            # In Socket.IO, auth data is passed during connection
                            # Check if we can get it from the connection context
                            if hasattr(request, 'environ'):
                                # Try to get from environment variables
                                token = request.environ.get('HTTP_AUTHORIZATION')
                                if token and token.startswith('Bearer '):
                                    token = token[7:]
                        except Exception as e:
                            pass
                    
                    # If no token found, try to get from query parameters
                    if not token and hasattr(request, 'args') and request.args:
                        token = request.args.get('token')
                        if token:
                            pass
                    
                    if token:
                        payload = jwt_manager.validate_token(token, TokenType.ACCESS)
                        if payload and payload.get('user_id'):
                            user_id = str(payload.get('user_id'))
                        else:
                            pass
                    else:
                        pass
                else:
                    pass
            except Exception as e:
                import traceback
            
            # Fallback to session_id if no user_id found
            if not user_id:
                user_id = session_id
            
            # Create session data
            session_data = {
                'session_id': session_id,
                'user_id': user_id,
                'connected_at': datetime.now().isoformat(),
                'client_id': client_id,
                'rooms': [],  # Use empty list instead of set for Redis storage
                'user_roles': [],  # Use empty list instead of set for Redis storage
                'last_activity': datetime.now().isoformat()
            }
            
            # Store session data
            self.websocket_manager.store_session_data(session_id, session_data)
            
            # Emit connection success
            self.socketio.emit('connect_success', {
                'session_id': session_id,
                'status': 'connected',
                'timestamp': datetime.now().isoformat()
            })
            return True
            
        except Exception as e:
            return False

    def handle_disconnect(self, session_id, data=None):
        """Handle client disconnection"""
        try:
            
            # Get session data
            session_data = self.websocket_manager.get_session_data(session_id)
            if session_data:
                # Clean up room memberships
                self.websocket_manager._cleanup_room_memberships(session_id, session_data)
                
                # Clean up session data
                self.websocket_manager.cleanup_session_data(session_id)
            else:
                pass
            
            return True
            
        except Exception as e:
            return False

    def handle_join_room(self, session_id, data):
        """Handle room join requests"""
        try:
            room_id = data.get('room_id')
            password = data.get('password')  # Get password from join request
            
            if not room_id:
                self.socketio.emit('join_room_error', {'error': 'No room_id provided'})
                return False
            
            # Check if room exists and get room info
            room_info = self.websocket_manager.get_room_info(room_id)
            if not room_info:
                self.socketio.emit('join_room_error', {'error': f'Room {room_id} not found'})
                return False
            
            # Validate password for private rooms
            if room_info.get('permission') == 'private':
                stored_password = room_info.get('password')
                if not stored_password:
                    self.socketio.emit('join_room_error', {'error': 'Room access configuration error'})
                    return False
                
                if not password:
                    self.socketio.emit('join_room_error', {'error': 'Password required for private room'})
                    return False
                
                if password != stored_password:
                    self.socketio.emit('join_room_error', {'error': 'Invalid password for private room'})
                    return False
            
            # Get session data
            session_data = self.websocket_manager.get_session_data(session_id)
            if not session_data:
                self.socketio.emit('join_room_error', {'error': 'Session not found'})
                return False
            
            # Resolve user id using backend auth/JWT if available
            user_id = self._resolve_user_id(session_id, data)
            
            # Join the room
            join_result = self.websocket_manager.join_room(room_id, session_id, user_id)
            
            # Get room owner information from memory storage
            room_owner_id = self.websocket_manager.get_room_creator(room_id)
            
            # Get actual room data from memory storage
            room_info = self.websocket_manager.get_room_info(room_id) or {}
            current_size = self.websocket_manager.get_room_size(room_id)
            
            # Ensure we have the required room data
            if not room_info.get('max_size'):
                self.socketio.emit('join_room_error', {'error': 'Room data incomplete'})
                return False
            
            max_size = room_info.get('max_size')  # Get actual max_size from room data
            
            if join_result == "already_joined":
                
                # Emit already_joined event with same room data as room_joined
                self.socketio.emit('already_joined', {
                    'room_id': room_id,
                    'session_id': session_id,
                    'user_id': user_id,
                    'owner_id': room_owner_id,  # Include owner_id in response
                    'timestamp': datetime.now().isoformat(),
                    'current_size': current_size,
                    'max_size': max_size  # Use actual max_size from room data
                })
                
                # 🎣 Trigger room_joined hook for game creation logic (same as normal join)
                room_data = {
                    'room_id': room_id,
                    'session_id': session_id,
                    'user_id': user_id,
                    'owner_id': room_owner_id,
                    'current_size': current_size,
                    'max_size': max_size,  # Use actual max_size from room data
                    'joined_at': datetime.now().isoformat()
                }
                self.websocket_manager.trigger_hook('room_joined', room_data)
                
                return True
            elif join_result:
                
                # Emit success to client (matching Flutter expectations)
                self.socketio.emit('join_room_success', {
                    'room_id': room_id,
                    'session_id': session_id,
                    'user_id': user_id,
                    'owner_id': room_owner_id,  # Include owner_id in response
                    'timestamp': datetime.now().isoformat(),
                    'current_size': current_size,
                    'max_size': max_size  # Use actual max_size from room data
                })
                
                # 🎣 Trigger room_joined hook for game creation logic
                room_data = {
                    'room_id': room_id,
                    'session_id': session_id,
                    'user_id': user_id,
                    'owner_id': room_owner_id,
                    'current_size': current_size,
                    'max_size': max_size,  # Use actual max_size from room data
                    'joined_at': datetime.now().isoformat()
                }
                self.websocket_manager.trigger_hook('room_joined', room_data)
                
                # 📡 Emit user_joined_rooms event after manual join
                self._emit_user_joined_rooms(session_id)
                
                return True
            else:
                self.socketio.emit('join_room_error', {'error': 'Failed to join room'})
                return False
                
        except Exception as e:
            return False

    def handle_create_room(self, session_id, data):
        """Handle room creation requests"""
        try:
            import uuid
            from datetime import datetime
            
            room_id = data.get('room_id')
            permission = data.get('permission', 'public')
            
            # Validate permission value
            valid_permissions = ['public', 'private']
            if permission not in valid_permissions:
                self.socketio.emit('create_room_error', {'error': f'Invalid permission value: {permission}. Must be one of: {valid_permissions}'})
                return False
            
            # Resolve user id using backend auth/JWT if available
            user_id = self._resolve_user_id(session_id, data)
            
            # Generate room_id if not provided - use consistent UUID method
            if not room_id:
                room_id = f"room_{uuid.uuid4().hex[:8]}"
            
            # Get password from data if provided
            password = data.get('password')
            
            # Create the room with owner_id and password
            success = self.websocket_manager.create_room(room_id, permission, owner_id=user_id, password=password)
            
            if success:
                # Join the room after creation
                join_success = self.websocket_manager.join_room(room_id, session_id, user_id)
                
                if join_success:
                    # Get owner_id from memory storage
                    owner_id = self.websocket_manager.get_room_creator(room_id)
                    
                    # Emit success events to client (matching Flutter expectations)
                    self.socketio.emit('create_room_success', {
                        'success': True,
                        'room_id': room_id,
                        'owner_id': owner_id,
                        'max_size': data.get('max_players') or Config.WS_ROOM_SIZE_LIMIT,  # Use frontend value or config fallback
                        'min_players': data.get('min_players') or 2,  # Use frontend value or default fallback
                        'timestamp': datetime.now().isoformat(),
                    })
                    
                    self.socketio.emit('room_joined', {
                        'room_id': room_id,
                        'session_id': session_id,
                        'user_id': user_id,
                        'owner_id': owner_id,  # Get owner_id from memory
                        'timestamp': datetime.now().isoformat(),
                        'current_size': 1,
                        'max_size': data.get('max_players') or Config.WS_ROOM_SIZE_LIMIT,  # Use frontend value or config fallback
                        'min_players': data.get('min_players') or 2  # Use frontend value or default fallback
                    })
                    
                    # 🎣 Trigger room_created hook for game creation logic
                    room_data = {
                        'room_id': room_id,
                        'owner_id': owner_id,
                        'permission': permission,
                        'max_players': data.get('max_players') or Config.WS_ROOM_SIZE_LIMIT,  # Use frontend value or config fallback
                        'min_players': data.get('min_players') or 2,  # Use frontend value or default fallback
                        'game_type': data.get('game_type', 'classic'),
                        'turn_time_limit': data.get('turn_time_limit', 30),
                        'auto_start': data.get('auto_start', True),
                        'created_at': datetime.now().isoformat(),
                        'current_size': 1
                    }
                    self.websocket_manager.trigger_hook('room_created', room_data)
                    
                    # 🎣 Trigger room_joined hook for adding owner to game
                    join_room_data = {
                        'room_id': room_id,
                        'session_id': session_id,
                        'user_id': user_id,
                        'owner_id': owner_id,
                        'current_size': 1,
                        'max_size': data.get('max_players') or Config.WS_ROOM_SIZE_LIMIT,
                        'min_players': data.get('min_players') or 2,
                        'joined_at': datetime.now().isoformat()
                    }
                    self.websocket_manager.trigger_hook('room_joined', join_room_data)
                    
                    # 📡 Emit user_joined_rooms event after auto-join
                    self._emit_user_joined_rooms(session_id)
                    return True
                else:
                    return False
            else:
                self.socketio.emit('create_room_error', {'error': 'Failed to create room'})
                return False
                
        except Exception as e:
            return False

    def handle_leave_room(self, session_id, data):
        """Handle room leave requests"""
        try:
            room_id = data.get('room_id')
            
            if not room_id:
                self.socketio.emit('leave_room_error', {'error': 'No room_id provided'})
                return False
            
            # Leave the room
            success = self.websocket_manager.leave_room(room_id, session_id)
            
            if success:
                
                # Emit success to client
                self.socketio.emit('leave_room_success', {
                    'room_id': room_id,
                    'session_id': session_id,
                    'timestamp': datetime.now().isoformat()
                })
                
                # 🎣 Trigger leave_room hook for game state updates
                room_data = {
                    'room_id': room_id,
                    'session_id': session_id,
                    'timestamp': datetime.now().isoformat()
                }
                self.websocket_manager.trigger_hook('leave_room', room_data)
                
                # 📡 Emit user_joined_rooms event after leaving room
                self._emit_user_joined_rooms(session_id)
                
                return True
            else:
                self.socketio.emit('leave_room_error', {'error': 'Failed to leave room'})
                return False
                
        except Exception as e:
            return False

    def handle_join_game(self, session_id, data):
        """Handle game join requests"""
        try:
            game_id = data.get('game_id')
            
            if not game_id:
                self.socketio.emit('join_game_error', {'error': 'No game_id provided'})
                return False
            
            # Get session data
            session_data = self.websocket_manager.get_session_data(session_id)
            if not session_data:
                self.socketio.emit('join_game_error', {'error': 'Session not found'})
                return False
            
            # Join the game (implement game-specific logic here)
            # For now, just emit success
            self.socketio.emit('join_game_success', {
                'game_id': game_id,
                'session_id': session_id,
                'timestamp': datetime.now().isoformat()
            })
            return True
                
        except Exception as e:
            return False

    def handle_send_message(self, session_id, data):
        """Handle send_message events (from Flutter)"""
        try:
            room_id = data.get('room_id')
            message = data.get('message')
            
            if not room_id or not message:
                self.socketio.emit('message_error', {'error': 'Missing room_id or message'})
                return False
            
            # Handle special messages
            if message == 'get_public_rooms':
                return self.handle_get_public_rooms(session_id, data)
            
            # Get session data
            session_data = self.websocket_manager.get_session_data(session_id)
            if not session_data:
                self.socketio.emit('message_error', {'error': 'Session not found'})
                return False
            
            # Broadcast message to room
            self.socketio.emit('message', {
                'room_id': room_id,
                'message': message,
                'sender': session_id,
                'timestamp': datetime.now().isoformat()
            }, room=room_id)
            return True
                
        except Exception as e:
            return False

    def handle_broadcast(self, session_id, data):
        """Handle broadcast events (from Flutter)"""
        try:
            message = data.get('message')
            
            if not message:
                self.socketio.emit('broadcast_error', {'error': 'Missing message'})
                return False
            
            # Get session data
            session_data = self.websocket_manager.get_session_data(session_id)
            if not session_data:
                self.socketio.emit('broadcast_error', {'error': 'Session not found'})
                return False
            
            # Broadcast message to all clients
            self.socketio.emit('message', {
                'message': message,
                'sender': session_id,
                'timestamp': datetime.now().isoformat()
            })
            return True
                
        except Exception as e:
            return False

    def handle_message(self, session_id, data):
        """Handle legacy message events"""
        try:
            room_id = data.get('room_id')
            message = data.get('message')
            
            if not room_id or not message:
                self.socketio.emit('message_error', {'error': 'Missing room_id or message'})
                return False
            
            # Get session data
            session_data = self.websocket_manager.get_session_data(session_id)
            if not session_data:
                self.socketio.emit('message_error', {'error': 'Session not found'})
                return False
            
            # Broadcast message to room
            self.socketio.emit('message', {
                'room_id': room_id,
                'message': message,
                'sender': session_id,
                'timestamp': datetime.now().isoformat()
            }, room=room_id)
            return True
                
        except Exception as e:
            return False

    def handle_custom_event(self, event_name, session_id, data):
        """Handle custom events"""
        try:
            
            # Get session data
            session_data = self.websocket_manager.get_session_data(session_id)
            if not session_data:
                return False
            
            # Emit custom event response
            self.socketio.emit(f'{event_name}_response', {
                'event_name': event_name,
                'session_id': session_id,
                'data': data,
                'timestamp': datetime.now().isoformat()
            })
            return True
                
        except Exception as e:
            return False

    def handle_get_public_rooms(self, session_id, data):
        """Handle get public rooms request"""
        try:
            
            # Get session data
            session_data = self.websocket_manager.get_session_data(session_id)
            if not session_data:
                self.socketio.emit('get_public_rooms_error', {'error': 'Session not found'}, room=session_id)
                return False
            
            # Get all public rooms from room manager
            try:
                all_rooms = self.websocket_manager.room_manager.get_all_rooms()
                public_rooms = []
                
                for room_id, room_info in all_rooms.items():
                    if room_info.get('permission') == 'public':
                        # Only include rooms that have complete data
                        if room_info.get('max_size') and room_info.get('min_size'):
                            public_rooms.append({
                                'room_id': room_id,
                                'room_name': room_info.get('room_name', room_id),
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
                
                # Emit public rooms response to the specific session
                self.socketio.emit('get_public_rooms_success', {
                    'success': True,
                    'data': public_rooms,
                    'count': len(public_rooms),
                    'timestamp': datetime.now().isoformat()
                }, room=session_id)
                return True
                
            except Exception as e:
                self.socketio.emit('get_public_rooms_error', {'error': 'Failed to get public rooms'}, room=session_id)
                return False
                
        except Exception as e:
            return False 