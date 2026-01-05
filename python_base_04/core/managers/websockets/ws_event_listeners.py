"""
WebSocket Event Listeners
Centralized Socket.IO event listener registration
"""

from flask_socketio import emit, join_room, leave_room
from flask import request
from tools.logger.custom_logging import custom_log
from datetime import datetime
import json

class WSEventListeners:
    """Centralized WebSocket event listeners"""
    
    def __init__(self, websocket_manager, event_handlers):
        self.websocket_manager = websocket_manager
        self.event_handlers = event_handlers
        self.socketio = websocket_manager.socketio

    def register_all_listeners(self):
        """Register all Socket.IO event listeners"""
        
        # Catch-all handler for all events
        @self.socketio.on('*')
        def catch_all(event, data=None):
            # Avoid double-handling for core events which have explicit handlers
            core_events = {
                'connect', 'disconnect', 'join_room', 'create_room',
                'leave_room', 'send_message', 'broadcast', 'message'
            }
            if event in core_events:
                return None
            
            # Allow dutch events to pass through to their custom listeners
            if str(event).startswith('dutch_'):
                return None
            return self.event_handlers.handle_unified_event(event, event, data or {})

        # Connection events
        @self.socketio.on('connect')
        def handle_connect():
            session_id = request.sid
            return self.event_handlers.handle_connect(session_id)

        @self.socketio.on('disconnect')
        def handle_disconnect():
            session_id = request.sid
            return self.event_handlers.handle_disconnect(session_id)

        # Room management events (matching Flutter emit events)
        @self.socketio.on('join_room')
        def handle_join_room(data=None):
            session_id = request.sid
            return self.event_handlers.handle_join_room(session_id, data or {})

        @self.socketio.on('create_room')
        def handle_create_room(data=None):
            session_id = request.sid
            return self.event_handlers.handle_create_room(session_id, data or {})

        @self.socketio.on('leave_room')
        def handle_leave_room(data=None):
            session_id = request.sid
            return self.event_handlers.handle_leave_room(session_id, data or {})

        # Message events (matching Flutter emit events)
        @self.socketio.on('send_message')
        def handle_send_message(data=None):
            session_id = request.sid
            return self.event_handlers.handle_send_message(session_id, data or {})

        @self.socketio.on('broadcast')
        def handle_broadcast(data=None):
            session_id = request.sid
            return self.event_handlers.handle_broadcast(session_id, data or {})

        # Client log ingestion: frontend logs into server.log as [frontend]
        @self.socketio.on('client_log')
        def handle_client_log(data=None):
            try:
                payload = data or {}
                level = str(payload.get('level', ''))
                msg = payload.get('message', '')
                platform = payload.get('platform', '')
                build = payload.get('buildMode', '')
                ts = payload.get('ts', '')
            except Exception as e:
                pass

        # Legacy message event (for compatibility)
        @self.socketio.on('message')
        def handle_message(data=None):
            session_id = request.sid
            return self.event_handlers.handle_message(session_id, data or {})

        # Custom events (dynamically registered)
        def register_custom_event(event_name):
            @self.socketio.on(event_name)
            def handle_custom_event(data=None):
                session_id = request.sid
                return self.event_handlers.handle_custom_event(event_name, session_id, data or {})

    def register_custom_listener(self, event_name, handler_func):
        """Register a custom event listener"""
        @self.socketio.on(event_name)
        def custom_handler(data=None):
            session_id = request.sid
            return handler_func(session_id, data or {})

    def unregister_listener(self, event_name):
        """Unregister an event listener (if needed)"""