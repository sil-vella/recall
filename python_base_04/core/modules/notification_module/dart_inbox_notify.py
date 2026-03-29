"""
Fire-and-forget HTTP notify to Dart game server so connected clients receive inbox_changed.
Uses same service key as Dart→Python ([DART_BACKEND_SERVICE_KEY]).
"""

from __future__ import annotations

import threading

from tools.logger.custom_logging import custom_log

LOGGING_SWITCH = False  # POST Dart /service/notify-inbox (enable-logging-switch.mdc; set False after verify)


def notify_dart_inbox_changed_async(user_id: str) -> None:
    """POST /service/notify-inbox on Dart; never raises; does not block the caller."""

    def _run() -> None:
        try:
            from utils.config.config import Config

            base = (getattr(Config, "DART_BACKEND_NOTIFY_URL", None) or "").strip()
            if not base:
                if LOGGING_SWITCH:
                    custom_log(
                        "notify_dart_inbox_changed: DART_BACKEND_NOTIFY_URL empty, skip",
                        level="DEBUG",
                        isOn=LOGGING_SWITCH,
                    )
                return
            key = (getattr(Config, "DART_BACKEND_SERVICE_KEY", None) or "").strip()
            if not key:
                if LOGGING_SWITCH:
                    custom_log(
                        "notify_dart_inbox_changed: DART_BACKEND_SERVICE_KEY empty, skip",
                        level="WARNING",
                        isOn=LOGGING_SWITCH,
                    )
                return
            import requests

            url = f"{base.rstrip('/')}/service/notify-inbox"
            r = requests.post(
                url,
                json={"user_id": user_id},
                headers={"X-Service-Key": key},
                timeout=3,
            )
            if LOGGING_SWITCH:
                custom_log(
                    f"notify_dart_inbox_changed: POST {url} user_id={user_id} http_status={r.status_code}",
                    level="INFO",
                    isOn=LOGGING_SWITCH,
                )
        except Exception as e:
            custom_log(f"notify_dart_inbox_changed: {e}", level="WARNING", isOn=LOGGING_SWITCH)

    threading.Thread(target=_run, daemon=True).start()
