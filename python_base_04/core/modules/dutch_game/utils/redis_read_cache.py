"""Redis read-through cache for hot Dutch API paths (multi-worker safe)."""

from __future__ import annotations

import json
import os
from typing import Any, Callable, Dict, List, Optional, TypeVar

T = TypeVar("T")

_CACHE_PREFIX = "dutch:cache:"


def _truthy_env(name: str, default: str = "true") -> bool:
    return (os.environ.get(name) or default).strip().lower() in ("1", "true", "yes")


def cache_enabled() -> bool:
    return _truthy_env("DUTCH_REDIS_READ_CACHE_ENABLED", "true")


def _int_env(name: str, default: int) -> int:
    raw = (os.environ.get(name) or "").strip()
    if not raw:
        return default
    try:
        return int(raw)
    except ValueError:
        return default


def init_stats_ttl() -> int:
    return _int_env("DUTCH_CACHE_INIT_STATS_TTL", 30)


def catalog_ttl() -> int:
    return _int_env("DUTCH_CACHE_CATALOG_TTL", 3600)


def broadcast_ttl() -> int:
    return _int_env("DUTCH_CACHE_BROADCAST_TTL", 60)


def _full_key(logical_key: str) -> str:
    return f"{_CACHE_PREFIX}{logical_key}"


def _redis_client(app_manager):
    if not app_manager:
        return None
    redis_manager = app_manager.get_redis_manager()
    if not redis_manager:
        return None
    try:
        return redis_manager.get_client()
    except Exception:
        return None


def get_json(app_manager, logical_key: str) -> Optional[Any]:
    if not cache_enabled():
        return None
    client = _redis_client(app_manager)
    if not client:
        return None
    try:
        raw = client.get(_full_key(logical_key))
        if raw is None:
            return None
        if isinstance(raw, bytes):
            raw = raw.decode("utf-8")
        return json.loads(raw)
    except Exception:
        return None


def set_json(app_manager, logical_key: str, value: Any, ttl_seconds: int) -> None:
    if not cache_enabled() or ttl_seconds <= 0:
        return
    client = _redis_client(app_manager)
    if not client:
        return
    try:
        client.setex(_full_key(logical_key), ttl_seconds, json.dumps(value))
    except Exception:
        pass


def delete_logical_key(app_manager, logical_key: str) -> None:
    client = _redis_client(app_manager)
    if not client:
        return
    try:
        client.delete(_full_key(logical_key))
    except Exception:
        pass


def delete_prefix(app_manager, logical_prefix: str) -> int:
    """Delete all keys under dutch:cache:{logical_prefix}*."""
    client = _redis_client(app_manager)
    if not client:
        return 0
    pattern = _full_key(f"{logical_prefix}*")
    deleted = 0
    try:
        cursor = 0
        while True:
            cursor, keys = client.scan(cursor, match=pattern, count=100)
            if keys:
                deleted += client.delete(*keys)
            if cursor == 0:
                break
    except Exception:
        pass
    return deleted


def invalidate_init_stats(app_manager, user_id: str) -> None:
    uid = str(user_id or "").strip()
    if uid:
        delete_logical_key(app_manager, f"init_stats:{uid}")


def get_init_stats_cached(app_manager, user_id: str) -> Optional[Dict[str, Any]]:
    cached = get_json(app_manager, f"init_stats:{user_id}")
    if isinstance(cached, dict):
        return cached
    return None


def set_init_stats_cached(app_manager, user_id: str, stats: Dict[str, Any]) -> None:
    set_json(app_manager, f"init_stats:{user_id}", stats, init_stats_ttl())


def get_broadcast_cached(app_manager, user_id: str, rank: str) -> Optional[List[Any]]:
    cached = get_json(app_manager, f"broadcast:{user_id}:{rank}")
    if isinstance(cached, list):
        return cached
    return None


def set_broadcast_cached(app_manager, user_id: str, rank: str, payload: List[Any]) -> None:
    set_json(app_manager, f"broadcast:{user_id}:{rank}", payload, broadcast_ttl())


def get_or_build_catalog(
    app_manager,
    cache_type: str,
    revision: str,
    builder: Callable[[], T],
) -> T:
    if not cache_enabled() or not revision:
        return builder()
    logical = f"catalog:{cache_type}:{revision}"
    cached = get_json(app_manager, logical)
    if cached is not None:
        return cached
    payload = builder()
    set_json(app_manager, logical, payload, catalog_ttl())
    return payload
