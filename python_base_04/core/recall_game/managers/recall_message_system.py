"""
Recall Message System

Central messaging facade for the Recall game. All Recall-related messages
to rooms or individual sessions should pass through this manager.

Responsibilities:
- Publish typed messages to rooms or sessions (info, warning, error, success)
- Optionally persist a rolling history per room/session (Redis lists)
- Provide retrieval helpers for message boards on the frontend (optional)

This code lives under recall_game/ and does not modify core managers.
"""

from typing import Dict, Any, Optional
from tools.logger.custom_logging import custom_log
from datetime import datetime


class RecallMessageSystem:
    def __init__(self):
        self.app_manager = None
        self.websocket_manager = None
        self.redis_manager = None
        self._initialized = False

    def initialize(self, app_manager) -> bool:
        try:
            self.app_manager = app_manager
            self.websocket_manager = getattr(app_manager, 'get_websocket_manager', lambda: None)()
            self.redis_manager = getattr(app_manager, 'get_redis_manager', lambda: None)()
            if not self.websocket_manager:
                custom_log("RecallMsg: WebSocketManager not available", level="ERROR")
                return False
            self._initialized = True
            custom_log("✅ RecallMsg: Initialized")
            return True
        except Exception as e:
            custom_log(f"❌ RecallMsg: init failed: {e}", level="ERROR")
            return False

    # ====== Public API ======
    def publish_room_message(self, room_id: str, message: Dict[str, Any], event_name: str = 'recall_message') -> bool:
        """Publish a message payload to a room, and store optional history."""
        try:
            if not room_id:
                return False
            payload = self._normalize_message(message, scope='room', target_id=room_id)
            # Send via Socket.IO directly to preserve custom event name
            self.websocket_manager.socketio.emit(event_name, payload, room=room_id)
            self._persist_message(scope='room', target_id=room_id, payload=payload)
            custom_log(f"RecallMsg: sent to room {room_id} [{payload.get('level')}] {payload.get('title')}")
            return True
        except Exception as e:
            custom_log(f"RecallMsg: room publish error: {e}")
            return False

    def publish_session_message(self, session_id: str, message: Dict[str, Any], event_name: str = 'recall_message') -> bool:
        """Publish a message payload to a single session, and store optional history."""
        try:
            if not session_id:
                return False
            payload = self._normalize_message(message, scope='session', target_id=session_id)
            # Use manager helper for sessions
            self.websocket_manager.send_to_session(session_id, event_name, payload)
            self._persist_message(scope='session', target_id=session_id, payload=payload)
            custom_log(f"RecallMsg: sent to session {session_id} [{payload.get('level')}] {payload.get('title')}")
            return True
        except Exception as e:
            custom_log(f"RecallMsg: session publish error: {e}")
            return False

    # ====== Internals ======
    def _normalize_message(self, msg: Dict[str, Any], scope: str, target_id: str) -> Dict[str, Any]:
        level = (msg.get('level') or 'info').lower()
        return {
            'id': msg.get('id'),
            'level': level if level in ['info', 'warning', 'error', 'success'] else 'info',
            'title': msg.get('title') or 'Notice',
            'message': msg.get('message') or '',
            'data': msg.get('data') or {},
            'scope': scope,
            'target_id': target_id,
            'timestamp': datetime.utcnow().isoformat(),
        }

    def _persist_message(self, scope: str, target_id: str, payload: Dict[str, Any]):
        try:
            if not self.redis_manager:
                return
            key = self._history_key(scope, target_id)
            # Store JSON-serializable dict; RedisManager handles serialization
            self.redis_manager.rpush(key, payload)
            # Cap list length
            self.redis_manager.ltrim(key, -200, -1)
            # Set TTL aligned with session/room TTLs
            self.redis_manager.expire(key, 3600)
        except Exception as e:
            custom_log(f"RecallMsg: persist failed for {scope}:{target_id}: {e}")

    def _history_key(self, scope: str, target_id: str) -> str:
        return self.redis_manager._generate_secure_key('recall_msg_history', scope, target_id)


