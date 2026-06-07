"""Production runtime helpers (logging guards, metrics access control)."""

from __future__ import annotations

import ipaddress
import os
from typing import Optional


def slow_request_threshold_ms() -> int:
    raw = (os.environ.get("SLOW_REQUEST_THRESHOLD_MS") or "5000").strip()
    try:
        return int(raw)
    except ValueError:
        return 5000


def log_tracebacks_enabled() -> bool:
    return (os.environ.get("LOG_TRACEBACKS") or "false").strip().lower() in (
        "1",
        "true",
        "yes",
    )


def metrics_allowed_cidrs_raw() -> str:
    return (
        os.environ.get("METRICS_ALLOWED_CIDRS") or "127.0.0.1,172.16.0.0/12"
    ).strip()


def client_allowed_for_metrics(remote_addr: Optional[str]) -> bool:
    if not remote_addr:
        return False
    try:
        ip = ipaddress.ip_address(remote_addr)
    except ValueError:
        return False
    for part in metrics_allowed_cidrs_raw().split(","):
        part = part.strip()
        if not part:
            continue
        try:
            if "/" in part:
                if ip in ipaddress.ip_network(part, strict=False):
                    return True
            elif ip == ipaddress.ip_address(part):
                return True
        except ValueError:
            continue
    return False
