"""
Operations module: deploy drain mode, readiness polling, and HTTP admission control.
"""

from __future__ import annotations

from typing import Any, Dict, Optional

from flask import jsonify, request

from core.managers.state_manager import StateManager
from core.modules.base_module import BaseModule
from core.modules.ops_module.dart_drain_client import fetch_dart_drain_status, set_dart_drain_mode
from core.modules.ops_module.drain_gate import path_allowed_during_drain

# Shared across Gunicorn workers; no TTL (unlike state:main_state cache entries).
DRAIN_MODE_REDIS_KEY = "dutch:ops:drain_mode"


class OpsModule(BaseModule):
    """Drain / maintenance coordination for deploy and disaster recovery."""

    def __init__(self, app_manager=None):
        super().__init__(app_manager)
        self.dependencies = []
        self._state_manager: Optional[StateManager] = None

    def initialize(self, app_manager):
        self.app_manager = app_manager
        self.app = app_manager.flask_app
        self._state_manager = app_manager.get_state_manager()
        self.register_routes()
        self._register_drain_gate()
        self._initialized = True

    def register_routes(self):
        self._register_route_helper(
            "/service/ops/enter-drain",
            self.enter_drain,
            methods=["POST"],
            auth="service",
        )
        self._register_route_helper(
            "/service/ops/exit-drain",
            self.exit_drain,
            methods=["POST"],
            auth="service",
        )
        self._register_route_helper(
            "/service/ops/drain-status",
            self.drain_status,
            methods=["GET"],
            auth="service",
        )

    def _register_drain_gate(self):
        if not self.app:
            return

        @self.app.before_request
        def ops_drain_gate():
            if not self._is_drain_mode():
                return None
            path = request.path or ""
            if path_allowed_during_drain(path):
                return None
            return jsonify({
                "error": "service_unavailable",
                "message": "Server is draining for maintenance. Try again later.",
                "code": "DRAIN_MODE",
            }), 503

    def _is_drain_mode(self) -> bool:
        redis_manager = self._drain_redis_manager()
        if not redis_manager:
            return False
        value = redis_manager.get(DRAIN_MODE_REDIS_KEY)
        return value is True or value == 1 or value == "1"

    def _set_drain_state(self, enabled: bool) -> bool:
        redis_manager = self._drain_redis_manager()
        if not redis_manager:
            return False
        return bool(redis_manager.set(DRAIN_MODE_REDIS_KEY, enabled, expire=None))

    def _drain_redis_manager(self):
        if not self._state_manager:
            return None
        return getattr(self._state_manager, "redis_manager", None)

    def _count_store_in_flight(self) -> int:
        try:
            dbm = self.app_manager.get_db_manager(role="read_write")
            if not dbm or not getattr(dbm, "db", None):
                return 0
            return int(
                dbm.db["play_coin_purchases"].count_documents({"status": "processing"})
            )
        except Exception:
            return 0

    def _build_drain_status(self) -> Dict[str, Any]:
        dart = fetch_dart_drain_status() or {}
        active_matches = int(dart.get("active_matches") or 0)
        store_in_flight = self._count_store_in_flight()
        dart_connections = int(dart.get("dart_connections") or 0)
        matches_clear = active_matches == 0
        store_clear = store_in_flight == 0
        drain_mode = self._is_drain_mode()
        return {
            "drain_mode": drain_mode,
            "active_matches": active_matches,
            "store_in_flight": store_in_flight,
            "dart_connections": dart_connections,
            "room_count": int(dart.get("room_count") or 0),
            "checks": {
                "matches_clear": matches_clear,
                "store_clear": store_clear,
            },
            "ready": drain_mode and matches_clear and store_clear,
            "dart_reachable": dart.get("ok") is True or "active_matches" in dart,
        }

    def enter_drain(self):
        try:
            if not self._set_drain_state(True):
                return jsonify({"ok": False, "error": "failed_to_set_drain_state"}), 500
            try:
                dart_result = set_dart_drain_mode(True)
            except Exception as exc:
                self._set_drain_state(False)
                return jsonify({
                    "ok": False,
                    "error": "dart_drain_mode_failed",
                    "message": str(exc),
                }), 502
            status = self._build_drain_status()
            return jsonify({
                "ok": True,
                "dart": dart_result,
                **status,
            }), 200
        except Exception as exc:
            return jsonify({"ok": False, "error": str(exc)}), 500

    def exit_drain(self):
        try:
            dart_result: Dict[str, Any] = {}
            try:
                dart_result = set_dart_drain_mode(False)
            except Exception:
                dart_result = {"ok": False, "warning": "dart_exit_drain_failed"}
            if not self._set_drain_state(False):
                return jsonify({"ok": False, "error": "failed_to_clear_drain_state"}), 500
            return jsonify({
                "ok": True,
                "drain_mode": False,
                "dart": dart_result,
            }), 200
        except Exception as exc:
            return jsonify({"ok": False, "error": str(exc)}), 500

    def drain_status(self):
        try:
            return jsonify(self._build_drain_status()), 200
        except Exception as exc:
            return jsonify({"ok": False, "error": str(exc)}), 500

    def health_check(self) -> Dict[str, Any]:
        base = super().health_check()
        base["details"] = f"drain_mode={self._is_drain_mode()}"
        return base
