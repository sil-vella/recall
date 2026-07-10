"""Route allowlist for Flask requests while drain mode is active."""

from __future__ import annotations

# Service paths Dart may call while finishing in-flight matches.
_ALLOWED_SERVICE_PREFIXES = (
    "/service/health",
    "/service/ops/",
    "/service/auth/validate",
    "/service/dutch/deduct-game-coins",
    "/service/dutch/update-game-stats",
    "/service/dutch/rematch-tournament-snapshot",
    "/service/dutch/attach-tournament-match-room",
    "/service/dutch/get-init-data",
)


def path_allowed_during_drain(path: str) -> bool:
    """Return True when [path] may be served while drain_mode is on."""
    if path == "/health":
        return True
    for prefix in _ALLOWED_SERVICE_PREFIXES:
        if path == prefix or path.startswith(prefix):
            return True
    return False
