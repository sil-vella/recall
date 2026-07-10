"""HTTP client for Dart game server drain-mode ops endpoints."""

from __future__ import annotations

from typing import Any, Dict, Optional

import requests

from utils.config.config import Config


def _base_url() -> str:
    return (getattr(Config, "DART_BACKEND_NOTIFY_URL", None) or "").strip().rstrip("/")


def _service_key() -> str:
    return (getattr(Config, "DART_BACKEND_SERVICE_KEY", None) or "").strip()


def _headers() -> Dict[str, str]:
    key = _service_key()
    if not key:
        return {}
    return {"X-Service-Key": key, "Content-Type": "application/json"}


def set_dart_drain_mode(enabled: bool, timeout: float = 5.0) -> Dict[str, Any]:
    """POST /service/ops/drain-mode on Dart. Raises on HTTP or config errors."""
    base = _base_url()
    key = _service_key()
    if not base:
        raise RuntimeError("DART_BACKEND_NOTIFY_URL is not configured")
    if not key:
        raise RuntimeError("DART_BACKEND_SERVICE_KEY is not configured")

    url = f"{base}/service/ops/drain-mode"
    response = requests.post(
        url,
        json={"enabled": enabled},
        headers=_headers(),
        timeout=timeout,
    )
    response.raise_for_status()
    data = response.json()
    if not isinstance(data, dict):
        raise RuntimeError("Dart drain-mode response was not a JSON object")
    return data


def fetch_dart_drain_status(timeout: float = 5.0) -> Optional[Dict[str, Any]]:
    """GET /service/ops/drain-status on Dart. Returns None when Dart is unreachable."""
    base = _base_url()
    key = _service_key()
    if not base or not key:
        return None
    try:
        url = f"{base}/service/ops/drain-status"
        response = requests.get(url, headers=_headers(), timeout=timeout)
        response.raise_for_status()
        data = response.json()
        return data if isinstance(data, dict) else None
    except Exception:
        return None
