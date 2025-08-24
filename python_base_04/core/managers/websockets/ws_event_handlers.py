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

class WSEventHandlers:
    """Centralized WebSocket event handlers"""
    
    def __init__(self, websocket_manager):
        self.websocket_manager = websocket_manager
        self.socketio = websocket_manager.socketio
        custom_log("WSEventHandlers initialized")

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
                custom_log(f"🔍 [RESOLVE] JWT manager available: {jwt_manager is not None}")
                
                if jwt_manager:
                    # Try to get token from request
                    token = None
                    if hasattr(request, 'args') and request.args:
                        token = request.args.get('token')
                        custom_log(f"🔍 [RESOLVE] Token from args: {token[:20] if token else None}...")
                    if not token and hasattr(request, 'headers') and request.headers:
                        auth_header = request.headers.get('Authorization')
                        custom_log(f"🔍 [RESOLVE] Auth header: {auth_header[:20] if auth_header else None}...")
                        if auth_header and auth_header.startswith('Bearer '):
                            token = auth_header[7:]
                            custom_log(f"🔍 [RESOLVE] Token from header: {token[:20] if token else None}...")
                    
                    if token:
                        custom_log(f"🔍 [RESOLVE] Found JWT token, validating...")
                        payload = jwt_manager.validate_token(token, TokenType.ACCESS)
                        custom_log(f"🔍 [RESOLVE] JWT payload: {payload}")
                        if payload and payload.get('user_id'):
                            user_id = str(payload.get('user_id'))
                            custom_log(f"✅ [RESOLVE] Extracted user_id from JWT: {user_id}")
                            
                            # Persist back into session
                            session_data = session_data or {}
                            session_data['user_id'] = user_id
                            if payload.get('username'):
                                session_data['username'] = payload.get('username')
                            self.websocket_manager.store_session_data(session_id, session_data)
                            
                            return user_id
                        else:
                            custom_log(f"⚠️ [RESOLVE] JWT token invalid or missing user_id")
                    else:
                        custom_log(f"⚠️ [RESOLVE] No JWT token found in request")
                else:
                    custom_log(f"⚠️ [RESOLVE] JWT manager not available")
            except Exception as e:
                custom_log(f"⚠️ [RESOLVE] Error extracting user_id from JWT: {e}")
                import traceback
                custom_log(f"⚠️ [RESOLVE] Traceback: {traceback.format_exc()}")

            # 4) Fallback: use session_id as user_id (for backward compatibility)
            # BUT: If we have session data with a real user_id, use that instead
            if session_data and session_data.get('user_id'):
                real_user_id = session_data.get('user_id')
                custom_log(f"✅ [RESOLVE] Using real user_id from session: {real_user_id}")
                return str(real_user_id)
            
            custom_log(f"⚠️ [RESOLVE] Using session_id as fallback user_id: {session_id}")
            return str(session_id)
        except Exception as e:
            custom_log(f"⚠️ [RESOLVE] Unexpected error resolving user_id: {e}")
            # Try to get user_id from session data as last resort
            try:
                session_data = self.websocket_manager.get_session_data(session_id)
                if session_data and session_data.get('user_id'):
                    real_user_id = session_data.get('user_id')
                    custom_log(f"✅ [RESOLVE] Using real user_id from session (fallback): {real_user_id}")
                    return str(real_user_id)
            except:
                pass
            return str(session_id)

    def handle_unified_event(self, event_name, event_type, data):
        """Unified event handler that routes to specific handlers"""
        custom_log(f"🔧 [UNIFIED] Processing event: '{event_name}' (type: '{event_type}') with data: {data}")
        
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
            custom_log(f"⚠️ [UNIFIED] No handler found for event: '{event_name}'")
            return False

    def handle_connect(self, session_id, data=None):
        """Handle client connection"""
        try:
            custom_log(f"🔧 [HANDLER-CONNECT] Handling connection for session: {session_id}")
            
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
                custom_log(f"🔍 [CONNECT] JWT manager available: {jwt_manager is not None}")
                
                if jwt_manager:
                    # Try to get token from Socket.IO connection context
                    token = None
                    
                    # Debug request object
                    custom_log(f"🔍 [CONNECT] Request object: {type(request)}")
                    custom_log(f"🔍 [CONNECT] Request has args: {hasattr(request, 'args')}")
                    custom_log(f"🔍 [CONNECT] Request has headers: {hasattr(request, 'headers')}")
                    custom_log(f"🔍 [CONNECT] Request has environ: {hasattr(request, 'environ')}")
                    
                    # Socket.IO stores auth data in the connection context
                    if hasattr(request, 'sid'):
                        custom_log(f"🔍 [CONNECT] Request has sid: {request.sid}")
                        # Get token from Socket.IO auth data
                        try:
                            # In Socket.IO, auth data is passed during connection
                            # Check if we can get it from the connection context
                            if hasattr(request, 'environ'):
                                # Try to get from environment variables
                                token = request.environ.get('HTTP_AUTHORIZATION')
                                custom_log(f"🔍 [CONNECT] Token from environ: {token[:20] if token else None}...")
                                if token and token.startswith('Bearer '):
                                    token = token[7:]
                                    custom_log(f"🔍 [CONNECT] Found token in environ: {token[:20]}...")
                        except Exception as e:
                            custom_log(f"⚠️ [CONNECT] Error getting token from environ: {e}")
                    
                    # If no token found, try to get from query parameters
                    if not token and hasattr(request, 'args') and request.args:
                        custom_log(f"🔍 [CONNECT] Request args: {request.args}")
                        token = request.args.get('token')
                        if token:
                            custom_log(f"🔍 [CONNECT] Found token in args: {token[:20]}...")
                    
                    if token:
                        custom_log(f"🔍 [CONNECT] Validating JWT token...")
                        payload = jwt_manager.validate_token(token, TokenType.ACCESS)
                        custom_log(f"🔍 [CONNECT] JWT payload: {payload}")
                        if payload and payload.get('user_id'):
                            user_id = str(payload.get('user_id'))
                            custom_log(f"✅ [CONNECT] Extracted actual user_id from JWT: {user_id}")
                        else:
                            custom_log(f"⚠️ [CONNECT] JWT token invalid or missing user_id")
                    else:
                        custom_log(f"⚠️ [CONNECT] No JWT token found in connection")
                else:
                    custom_log(f"⚠️ [CONNECT] JWT manager not available")
            except Exception as e:
                custom_log(f"⚠️ [CONNECT] Error extracting user_id from JWT: {e}")
                import traceback
                custom_log(f"⚠️ [CONNECT] Traceback: {traceback.format_exc()}")
            
            # Fallback to session_id if no user_id found
            if not user_id:
                user_id = session_id
                custom_log(f"⚠️ [CONNECT] Using session_id as fallback user_id: {user_id}")
            
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
            
            custom_log(f"✅ [CONNECT] Stored session data with user_id: {user_id}")
            
            # Store session data
            self.websocket_manager.store_session_data(session_id, session_data)
            
            # Emit connection success
            self.socketio.emit('connect_success', {
                'session_id': session_id,
                'status': 'connected',
                'timestamp': datetime.now().isoformat()
            })
            
            custom_log(f"✅ Successfully handled connection for session: {session_id}")
            return True
            
        except Exception as e:
            custom_log(f"❌ Error in handle_connect: {str(e)}")
            return False

    def handle_disconnect(self, session_id, data=None):
        """Handle client disconnection"""
        try:
            custom_log(f"🔧 [HANDLER-DISCONNECT] Handling disconnection for session: {session_id}")
            
            # Get session data
            session_data = self.websocket_manager.get_session_data(session_id)
            if session_data:
                # Clean up room memberships
                self.websocket_manager._cleanup_room_memberships(session_id, session_data)
                
                # Clean up session data
                self.websocket_manager.cleanup_session_data(session_id)
                
                custom_log(f"✅ Successfully cleaned up session: {session_id}")
            else:
                custom_log(f"⚠️ No session data found for: {session_id}")
            
            return True
            
        except Exception as e:
            custom_log(f"❌ Error in handle_disconnect: {str(e)}")
            return False

    def handle_join_room(self, session_id, data):
        """Handle room join requests"""
        try:
            room_id = data.get('room_id')
            custom_log(f"🔧 [HANDLER-JOIN] Handling join room: {room_id} for session: {session_id}")
            
            if not room_id:
                custom_log("❌ No room_id provided for join request")
                self.socketio.emit('join_room_error', {'error': 'No room_id provided'})
                return False
            
            # Get session data
            session_data = self.websocket_manager.get_session_data(session_id)
            if not session_data:
                custom_log(f"❌ No session data found for: {session_id}")
                self.socketio.emit('join_room_error', {'error': 'Session not found'})
                return False
            
            # Resolve user id using backend auth/JWT if available
            user_id = self._resolve_user_id(session_id, data)
            
            custom_log(f"🔧 [HANDLER-JOIN] Using user_id: {user_id} for join room: {room_id}")
            
            # Join the room
            success = self.websocket_manager.join_room(room_id, session_id, user_id)
            
            if success:
                custom_log(f"✅ Successfully joined room: {room_id}")
                
                # Get room owner information from memory storage
                room_owner_id = self.websocket_manager.get_room_creator(room_id)
                
                # Get actual room data from memory storage
                room_info = self.websocket_manager.get_room_info(room_id) or {}
                current_size = self.websocket_manager.get_room_size(room_id)
                
                # Ensure we have the required room data
                if not room_info.get('max_size'):
                    custom_log(f"❌ Room {room_id} missing max_size data, cannot proceed with join")
                    self.socketio.emit('join_room_error', {'error': 'Room data incomplete'})
                    return False
                
                max_size = room_info.get('max_size')  # Get actual max_size from room data
                
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
                custom_log(f"🎣 [HOOK] room_joined hook triggered with data: {room_data}")
                
                return True
            else:
                custom_log(f"❌ Failed to join room: {room_id}")
                self.socketio.emit('join_room_error', {'error': 'Failed to join room'})
                return False
                
        except Exception as e:
            custom_log(f"❌ Error in handle_join_room: {str(e)}")
            return False

    def handle_create_room(self, session_id, data):
        """Handle room creation requests"""
        try:
            import uuid
            from datetime import datetime
            
            room_id = data.get('room_id')
            permission = data.get('permission', 'public')
            custom_log(f"🔧 [HANDLER-CREATE] Handling create room: {room_id} with permission: {permission}")
            
            # Resolve user id using backend auth/JWT if available
            user_id = self._resolve_user_id(session_id, data)
            
            # Generate room_id if not provided - use consistent UUID method
            if not room_id:
                room_id = f"room_{uuid.uuid4().hex[:8]}"
                custom_log(f"Generated room_id: {room_id}")
            
            # Create the room with owner_id
            success = self.websocket_manager.create_room(room_id, permission, owner_id=user_id)
            
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
                        'max_size': data.get('max_players'),  # No fallback - must be provided by frontend
                        'min_players': data.get('min_players'),  # No fallback - must be provided by frontend
                        'timestamp': datetime.now().isoformat(),
                    })
                    
                    self.socketio.emit('room_joined', {
                        'room_id': room_id,
                        'session_id': session_id,
                        'user_id': user_id,
                        'owner_id': owner_id,  # Get owner_id from memory
                        'timestamp': datetime.now().isoformat(),
                        'current_size': 1,
                        'max_size': data.get('max_players')  # No fallback - must be provided by frontend
                    })
                    
                    # 🎣 Trigger room_created hook for game creation logic
                    room_data = {
                        'room_id': room_id,
                        'owner_id': owner_id,
                        'permission': permission,
                        'max_players': data.get('max_players'),  # No fallback - must be provided by frontend
                        'min_players': data.get('min_players'),  # No fallback - must be provided by frontend
                        'game_type': data.get('game_type', 'classic'),
                        'turn_time_limit': data.get('turn_time_limit', 30),
                        'auto_start': data.get('auto_start', True),
                        'created_at': datetime.now().isoformat(),
                        'current_size': 1
                    }
                    self.websocket_manager.trigger_hook('room_created', room_data)
                    custom_log(f"🎣 [HOOK] room_created hook triggered with data: {room_data}")
                    
                    custom_log(f"✅ Successfully created and joined room: {room_id} with owner: {user_id}")
                    return True
                else:
                    custom_log(f"❌ Failed to join room after creation: {room_id}")
                    return False
            else:
                custom_log(f"❌ Failed to create room: {room_id}")
                self.socketio.emit('create_room_error', {'error': 'Failed to create room'})
                return False
                
        except Exception as e:
            custom_log(f"❌ Error in handle_create_room: {str(e)}")
            return False

    def handle_leave_room(self, session_id, data):
        """Handle room leave requests"""
        try:
            room_id = data.get('room_id')
            custom_log(f"🔧 [HANDLER-LEAVE] Handling leave room: {room_id} for session: {session_id}")
            
            if not room_id:
                custom_log("❌ No room_id provided for leave request")
                self.socketio.emit('leave_room_error', {'error': 'No room_id provided'})
                return False
            
            # Leave the room
            success = self.websocket_manager.leave_room(room_id, session_id)
            
            if success:
                custom_log(f"✅ Successfully left room: {room_id}")
                
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
                custom_log(f"🎣 [HOOK] leave_room hook triggered with data: {room_data}")
                
                return True
            else:
                custom_log(f"❌ Failed to leave room: {room_id}")
                self.socketio.emit('leave_room_error', {'error': 'Failed to leave room'})
                return False
                
        except Exception as e:
            custom_log(f"❌ Error in handle_leave_room: {str(e)}")
            return False

    def handle_join_game(self, session_id, data):
        """Handle game join requests"""
        try:
            game_id = data.get('game_id')
            custom_log(f"🔧 [HANDLER-JOIN-GAME] Handling join game: {game_id} for session: {session_id}")
            
            if not game_id:
                custom_log("❌ No game_id provided for join game request")
                self.socketio.emit('join_game_error', {'error': 'No game_id provided'})
                return False
            
            # Get session data
            session_data = self.websocket_manager.get_session_data(session_id)
            if not session_data:
                custom_log(f"❌ No session data found for: {session_id}")
                self.socketio.emit('join_game_error', {'error': 'Session not found'})
                return False
            
            # Join the game (implement game-specific logic here)
            # For now, just emit success
            self.socketio.emit('join_game_success', {
                'game_id': game_id,
                'session_id': session_id,
                'timestamp': datetime.now().isoformat()
            })
            
            custom_log(f"✅ Successfully joined game: {game_id}")
            return True
                
        except Exception as e:
            custom_log(f"❌ Error in handle_join_game: {str(e)}")
            return False

    def handle_send_message(self, session_id, data):
        """Handle send_message events (from Flutter)"""
        try:
            room_id = data.get('room_id')
            message = data.get('message')
            custom_log(f"🔧 [HANDLER-SEND_MESSAGE] Handling send_message in room: {room_id} from session: {session_id}")
            
            if not room_id or not message:
                custom_log("❌ Missing room_id or message for send_message event")
                self.socketio.emit('message_error', {'error': 'Missing room_id or message'})
                return False
            
            # Handle special messages
            if message == 'get_public_rooms':
                custom_log(f"🔄 Routing get_public_rooms request to dedicated handler")
                return self.handle_get_public_rooms(session_id, data)
            
            # Get session data
            session_data = self.websocket_manager.get_session_data(session_id)
            if not session_data:
                custom_log(f"❌ No session data found for: {session_id}")
                self.socketio.emit('message_error', {'error': 'Session not found'})
                return False
            
            # Broadcast message to room
            self.socketio.emit('message', {
                'room_id': room_id,
                'message': message,
                'sender': session_id,
                'timestamp': datetime.now().isoformat()
            }, room=room_id)
            
            custom_log(f"✅ Successfully sent message to room: {room_id}")
            return True
                
        except Exception as e:
            custom_log(f"❌ Error in handle_send_message: {str(e)}")
            return False

    def handle_broadcast(self, session_id, data):
        """Handle broadcast events (from Flutter)"""
        try:
            message = data.get('message')
            custom_log(f"🔧 [HANDLER-BROADCAST] Handling broadcast from session: {session_id}")
            
            if not message:
                custom_log("❌ Missing message for broadcast event")
                self.socketio.emit('broadcast_error', {'error': 'Missing message'})
                return False
            
            # Get session data
            session_data = self.websocket_manager.get_session_data(session_id)
            if not session_data:
                custom_log(f"❌ No session data found for: {session_id}")
                self.socketio.emit('broadcast_error', {'error': 'Session not found'})
                return False
            
            # Broadcast message to all clients
            self.socketio.emit('message', {
                'message': message,
                'sender': session_id,
                'timestamp': datetime.now().isoformat()
            })
            
            custom_log(f"✅ Successfully broadcasted message to all clients")
            return True
                
        except Exception as e:
            custom_log(f"❌ Error in handle_broadcast: {str(e)}")
            return False

    def handle_message(self, session_id, data):
        """Handle legacy message events"""
        try:
            room_id = data.get('room_id')
            message = data.get('message')
            custom_log(f"🔧 [HANDLER-MESSAGE] Handling legacy message in room: {room_id} from session: {session_id}")
            
            if not room_id or not message:
                custom_log("❌ Missing room_id or message for message event")
                self.socketio.emit('message_error', {'error': 'Missing room_id or message'})
                return False
            
            # Get session data
            session_data = self.websocket_manager.get_session_data(session_id)
            if not session_data:
                custom_log(f"❌ No session data found for: {session_id}")
                self.socketio.emit('message_error', {'error': 'Session not found'})
                return False
            
            # Broadcast message to room
            self.socketio.emit('message', {
                'room_id': room_id,
                'message': message,
                'sender': session_id,
                'timestamp': datetime.now().isoformat()
            }, room=room_id)
            
            custom_log(f"✅ Successfully sent legacy message to room: {room_id}")
            return True
                
        except Exception as e:
            custom_log(f"❌ Error in handle_message: {str(e)}")
            return False

    def handle_custom_event(self, event_name, session_id, data):
        """Handle custom events"""
        try:
            custom_log(f"🔧 [HANDLER-CUSTOM] Handling custom event: {event_name} for session: {session_id}")
            
            # Get session data
            session_data = self.websocket_manager.get_session_data(session_id)
            if not session_data:
                custom_log(f"❌ No session data found for: {session_id}")
                return False
            
            # Emit custom event response
            self.socketio.emit(f'{event_name}_response', {
                'event_name': event_name,
                'session_id': session_id,
                'data': data,
                'timestamp': datetime.now().isoformat()
            })
            
            custom_log(f"✅ Successfully handled custom event: {event_name}")
            return True
                
        except Exception as e:
            custom_log(f"❌ Error in handle_custom_event: {str(e)}")
            return False

    def handle_get_public_rooms(self, session_id, data):
        """Handle get public rooms request"""
        try:
            custom_log(f"🔧 [HANDLER-GET-PUBLIC-ROOMS] Handling get public rooms for session: {session_id}")
            
            # Get session data
            session_data = self.websocket_manager.get_session_data(session_id)
            if not session_data:
                custom_log(f"❌ No session data found for: {session_id}")
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
                
                custom_log(f"📊 Found {len(public_rooms)} public rooms")
                
                # Emit public rooms response to the specific session
                self.socketio.emit('get_public_rooms_success', {
                    'success': True,
                    'data': public_rooms,
                    'count': len(public_rooms),
                    'timestamp': datetime.now().isoformat()
                }, room=session_id)
                
                custom_log(f"✅ Successfully sent public rooms to session: {session_id}")
                return True
                
            except Exception as e:
                custom_log(f"❌ Error getting public rooms: {str(e)}")
                self.socketio.emit('get_public_rooms_error', {'error': 'Failed to get public rooms'}, room=session_id)
                return False
                
        except Exception as e:
            custom_log(f"❌ Error in handle_get_public_rooms: {str(e)}")
            return False 