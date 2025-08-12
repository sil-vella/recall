"""
Recall WebSockets Manager

Listens to ALL WebSocket events via the centralized WSEventManager and
emits Recall-game-specific events when relevant.

This lives strictly under recall_game/ and does not modify core managers.
"""

from typing import Dict, Any, Optional
from tools.logger.custom_logging import custom_log
from .recall_message_system import RecallMessageSystem


class RecallWebSocketsManager:
    """Bridges core WebSocket events to Recall-specific logic."""

    def __init__(self):
        self.app_manager = None
        self.websocket_manager = None
        self.event_manager = None
        self._registered = False
        self.message_system: Optional[RecallMessageSystem] = None

    def initialize(self, app_manager) -> bool:
        try:
            self.app_manager = app_manager
            self.websocket_manager = getattr(app_manager, 'get_websocket_manager', lambda: None)()
            if not self.websocket_manager:
                custom_log("RecallWS: WebSocketManager not available", level="ERROR")
                return False

            # Access the centralized WSEventManager for subscribe capability
            self.event_manager = getattr(self.websocket_manager, 'event_manager', None)
            if not self.event_manager:
                custom_log("RecallWS: WSEventManager not available on WebSocketManager", level="ERROR")
                return False

            # Subscribe to ALL events by registering a generic handler per event name
            # We'll register to already-known types and also a generic hook for custom events
            self._wire_event_subscriptions()
            # Also register a Socket.IO catch-all so we don't depend on core forwarding
            self._wire_socketio_catch_all()
            # Hook to message system so handlers can publish easily
            self.message_system = RecallMessageSystem()
            self.message_system.initialize(self.app_manager)
            self._registered = True
            custom_log("✅ RecallWS: Subscribed to WebSocket event bus")
            return True
        except Exception as e:
            custom_log(f"❌ RecallWS: initialization failed: {e}", level="ERROR")
            return False

    def _wire_event_subscriptions(self):
        """Register handlers on event manager for key event channels."""
        try:
            # Known core channels
            channels = [
                'connection',  # connection status updates
                'room',        # room events joined/left/created
                'message',     # generic messages
                'session',     # session updates
                'error',       # errors
            ]

            for ch in channels:
                self.event_manager.register_handler(ch, lambda evt, _ch=ch: self._handle_event(_ch, evt))

            # Also listen to any custom events by name; we can attach a lightweight multiplexer
            # Use the event manager's generic custom hook capability by registering on a wildcard-like name.
            # Since we don't have wildcard support, rely on explicit recall-prefixed events routed by ws handlers.
            recall_customs = [
                'room_closed',         # emitted by core on TTL expiry
                'recall_event',        # recall payloads already broadcasted
                'get_public_rooms_success',
                'get_public_rooms_error'
            ]
            for ev in recall_customs:
                self.event_manager.register_handler(ev, lambda evt, _ev=ev: self._handle_custom(_ev, evt))

        except Exception as e:
            custom_log(f"RecallWS: subscription error: {e}")

    def _wire_socketio_catch_all(self):
        """Register a catch-all listener directly on Socket.IO to observe every event."""
        try:
            socketio = getattr(self.websocket_manager, 'socketio', None)
            if not socketio:
                return

            def _catch_all(event, data=None):
                try:
                    # Forward as a generic message for recall routing
                    self._on_socketio_event(event, data or {})
                except Exception as e:
                    custom_log(f"RecallWS: catch-all error: {e}")

            # Dynamically attach
            socketio.on('*')(_catch_all)
            custom_log("✅ RecallWS: Socket.IO catch-all listener attached")
        except Exception as e:
            custom_log(f"RecallWS: failed to attach catch-all: {e}")

    # ==== Dispatchers ====
    def _handle_event(self, channel: str, event_data: Dict[str, Any]):
        try:
            # Switch by channel then by action/name
            if channel == 'room':
                action = (event_data.get('data') or {}).get('action')
                room_id = (event_data.get('data') or {}).get('room_id')
                if action == 'created':
                    self._on_room_created(room_id, event_data)
                elif action == 'joined':
                    self._on_room_joined(room_id, event_data)
                elif action == 'left':
                    self._on_room_left(room_id, event_data)
            elif channel == 'message':
                self._on_message(event_data)
            elif channel == 'connection':
                self._on_connection(event_data)
            elif channel == 'session':
                self._on_session(event_data)
            elif channel == 'error':
                self._on_error(event_data)
        except Exception as e:
            custom_log(f"RecallWS: error in _handle_event[{channel}]: {e}")

    def _handle_custom(self, event_name: str, event_data: Dict[str, Any]):
        try:
            if event_name == 'room_closed':
                data = event_data.get('data') or {}
                room_id = data.get('room_id') or (event_data.get('room_id'))
                reason = data.get('reason') or 'unknown'
                # Emit Recall’s own routed event on the message channel to room
                self._emit_recall_notice(
                    room_id,
                    {
                        'type': 'recall_event',
                        'event_type': 'room_closed',
                        'reason': reason,
                    }
                )
            elif event_name == 'recall_event':
                # Already recall payload — can forward or enrich if needed
                pass
        except Exception as e:
            custom_log(f"RecallWS: error in _handle_custom[{event_name}]: {e}")

    # ==== Handlers for channels ====
    def _on_room_created(self, room_id: Optional[str], evt: Dict[str, Any]):
        # Example: could initialize per-room recall state
        pass

    def _on_room_joined(self, room_id: Optional[str], evt: Dict[str, Any]):
        # Example: announce welcome via recall channel
        pass

    def _on_room_left(self, room_id: Optional[str], evt: Dict[str, Any]):
        # Example: cleanup per-room recall cache
        pass

    def _on_message(self, evt: Dict[str, Any]):
        # Inspect generic message payloads if needed
        pass

    def _on_connection(self, evt: Dict[str, Any]):
        # Track connection state if the recall game needs it
        pass

    def _on_session(self, evt: Dict[str, Any]):
        # Session changes can map to recall state
        pass

    def _on_error(self, evt: Dict[str, Any]):
        # Route errors to recall diagnostics if needed
        pass

    # ==== Emit helpers ====
    def _emit_recall_notice(self, room_id: Optional[str], payload: Dict[str, Any]):
        try:
            if not room_id:
                return
            # Relay via the same broadcast_message channel Recall frontend uses
            self.websocket_manager.broadcast_message(room_id, payload)
            custom_log(f"RecallWS: emitted recall notice to room {room_id}: {payload.get('event_type')}")
        except Exception as e:
            custom_log(f"RecallWS: failed to emit recall notice: {e}")

    # ==== Raw socket event hook ====
    def _on_socketio_event(self, event_name: str, data: Dict[str, Any]):
        """Handle raw Socket.IO events and route Recall-specific logic by name."""
        try:
            # Example cases — extend as needed
            if event_name == 'room_closed':
                room_id = (data or {}).get('room_id')
                reason = (data or {}).get('reason', 'unknown')
                self._emit_recall_notice(room_id, {
                    'type': 'recall_event',
                    'event_type': 'room_closed',
                    'reason': reason,
                })
            # Add more cases:
            # elif event_name == 'join_room_success': ...
        except Exception as e:
            custom_log(f"RecallWS: error in _on_socketio_event[{event_name}]: {e}")


