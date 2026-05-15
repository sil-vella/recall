"""Single-call dev logging; no-op unless ``DUTCH_DEV_LOG`` is truthy in the environment."""

from __future__ import annotations

import os
import sys


def _enabled() -> bool:
    v = (os.environ.get("DUTCH_DEV_LOG") or "").strip().lower()
    return v in ("1", "true", "yes")


def customlog(message: str) -> None:
    """Log [message] to stderr when ``DUTCH_DEV_LOG`` is ``1``/``true``/``yes``; otherwise no-op."""
    if not _enabled():
        return
    print(f"[dev] {message}", file=sys.stderr, flush=True)
