"""
Shared helpers to credit Dutch game coins on users (Stripe web, Play Billing, etc.).
"""
from __future__ import annotations

from datetime import datetime
from typing import Any, Optional

from bson import ObjectId


def credit_dutch_game_coins(db_manager: Any, user_oid: ObjectId, coins: int, session: Optional[Any] = None) -> None:
    """Increment modules.dutch_game.coins (same field as match economy)."""
    if coins <= 0:
        return
    ts = datetime.utcnow().isoformat()
    kwargs: dict[str, Any] = {}
    if session is not None:
        kwargs["session"] = session
    result = db_manager.db["users"].update_one(
        {"_id": user_oid},
        {
            "$inc": {"modules.dutch_game.coins": coins},
            "$set": {"modules.dutch_game.last_updated": ts, "updated_at": ts},
        },
        **kwargs,
    )
    if result.matched_count == 0:
        raise ValueError(f"user not found: {user_oid}")


def get_dutch_game_coin_balance(db_manager: Any, user_oid: ObjectId) -> int:
    doc = db_manager.find_one("users", {"_id": user_oid}) or {}
    dg = (doc.get("modules") or {}).get("dutch_game") or {}
    return int(dg.get("coins") or 0)
