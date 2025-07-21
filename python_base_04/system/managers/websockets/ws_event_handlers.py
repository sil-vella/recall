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

class WSEventHandlers:
    """Centralized WebSocket event handlers"""
    
    def __init__(self, websocket_manager):
        self.websocket_manager = websocket_manager
        self.socketio = websocket_manager.socketio
        custom_log("WSEventHandlers initialized")

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
            
            # Store basic session data
            session_data = {
                'session_id': session_id,
                'connected_at': datetime.now().isoformat(),
                'client_id': client_id,
                'rooms': set(),
                'user_roles': set(),
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
            user_id = data.get('user_id')
            custom_log(f"🔧 [HANDLER-JOIN] Handling join room: {room_id} for session: {session_id}, user: {user_id}")
            
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
            
            # Join the room
            success = self.websocket_manager.join_room(room_id, session_id, user_id)
            
            if success:
                custom_log(f"✅ Successfully joined room: {room_id}")
                
                # Emit success to client (matching Flutter expectations)
                self.socketio.emit('join_room_success', {
                    'room_id': room_id,
                    'session_id': session_id,
                    'user_id': user_id,
                    'timestamp': datetime.now().isoformat(),
                    'current_size': self.websocket_manager.get_room_size(room_id),
                    'max_size': 10
                })
                
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
            room_id = data.get('room_id')
            permission = data.get('permission', 'public')
            custom_log(f"🔧 [HANDLER-CREATE] Handling create room: {room_id} with permission: {permission}")
            
            # Get session data
            session_data = self.websocket_manager.get_session_data(session_id)
            if not session_data:
                custom_log(f"❌ No session data found for: {session_id}")
                self.socketio.emit('create_room_error', {'error': 'Session not found'})
                return False
            
            # Generate room_id if not provided
            if not room_id:
                room_id = f"room_{uuid.uuid4().hex[:8]}"
                custom_log(f"Generated room_id: {room_id}")
            
            # Create the room
            success = self.websocket_manager.create_room(room_id, permission)
            
            if success:
                # Join the room after creation
                user_id = data.get('user_id')
                join_success = self.websocket_manager.join_room(room_id, session_id, user_id)
                
                if join_success:
                    # Emit success events to client (matching Flutter expectations)
                    self.socketio.emit('create_room_success', {
                        'room_id': room_id,
                        'permission': permission,
                        'session_id': session_id,
                        'user_id': user_id,
                        'timestamp': datetime.now().isoformat(),
                        'current_size': 1,
                        'max_size': 10
                    })
                    
                    self.socketio.emit('room_joined', {
                        'room_id': room_id,
                        'session_id': session_id,
                        'user_id': user_id,
                        'timestamp': datetime.now().isoformat(),
                        'current_size': 1,
                        'max_size': 10
                    })
                    
                    custom_log(f"✅ Successfully created and joined room: {room_id}")
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