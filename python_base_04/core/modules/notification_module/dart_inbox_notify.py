"""
Fire-and-forget HTTP notify to Dart game server so connected clients receive inbox_changed.
Uses same service key as Dart→Python ([DART_BACKEND_SERVICE_KEY]).
"""

from __future__ import annotations

import threading




def notify_dart_inbox_changed_async(user_id: str) -> None:
    """POST /service/notify-inbox on Dart; never raises; does not block the caller."""

    def _run() -> None:
        try:
            from utils.config.config import Config

            base = (getattr(Config, "DART_BACKEND_NOTIFY_URL", None) or "").strip()
            if not base:
                return
            key = (getattr(Config, "DART_BACKEND_SERVICE_KEY", None) or "").strip()
            if not key:
                return
            import requests

            url = f"{base.rstrip('/')}/service/notify-inbox"
            r = requests.post(
                url,
                json={"user_id": user_id},
                headers={"X-Service-Key": key},
                timeout=3,
            )
        except Exception as e:

            pass
    threading.Thread(target=_run, daemon=True).start()
