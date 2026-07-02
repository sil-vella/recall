"""
Leaderboard placement achievements — period-end batch and all-time band entry.

Monthly/yearly: per rank tier, repeatable each period_key (UTC calendar).
All-time: global board, once per placement band when first entered.
"""

from __future__ import annotations

import threading
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple

from bson import ObjectId

from core.modules.user_management_module import tier_rank_level_matcher as matcher

from . import achievements_catalog as achcat
from . import dutch_notifications as dutch_notif

MATCH_WIN_OUTCOMES_COLL = "dutch_match_win_outcomes"
RUN_LEDGER_COLL = "dutch_leaderboard_achievement_runs"

PERIOD_SCOPES = ("monthly", "yearly")
GAME_TYPES = ("classic", "clear_and_collect")


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _period_grant_field_key(
    period: str,
    period_key: str,
    game_type: str,
    rank_tier: str,
    placement: str,
) -> str:
    return (
        f"modules.dutch_game.leaderboard_period_grants."
        f"{period}.{period_key}.{game_type}.{rank_tier}.{placement}"
    )


def _scope_run_key(period: str, period_key: str, game_type: str, rank_tier: str) -> str:
    return f"{period}|{period_key}|{game_type}|{rank_tier}"


def _rank_user_in_summaries(summaries: List[Dict[str, Any]], user_oid: ObjectId) -> Optional[int]:
    for i, doc in enumerate(summaries):
        if doc.get("_id") == user_oid:
            return i + 1
    return None


def _notify_achievement_unlock(
    app_manager,
    user_id: str,
    achievement_id: str,
    *,
    grant_type: str,
    period_key: Optional[str] = None,
    period: Optional[str] = None,
) -> None:
    entry = achcat.achievement_by_id(achievement_id)
    if not entry:
        return
    title = str(entry.get("title") or achievement_id)
    body = str(entry.get("description") or "")
    if grant_type == "leaderboard_period" and period and period_key:
        label = achcat.format_leaderboard_period_label(period, period_key)
        body = f"{body} ({label})"
    data: Dict[str, Any] = {
        "event": "dutch_achievement",
        "achievement_id": achievement_id,
        "grant_type": grant_type,
    }
    if period_key:
        data["period_key"] = period_key
    if period:
        data["period"] = period
    dutch_notif.create_notification(
        app_manager,
        user_id=user_id,
        subtype=dutch_notif.SUBTYPE_ACHIEVEMENT_UNLOCK,
        title=title,
        body=body,
        msg_id=dutch_notif.MSG_ID_ACHIEVEMENT_UNLOCK,
        data=data,
    )


def _grant_lifetime_unlock(
    db_manager,
    user_oid: ObjectId,
    achievement_id: str,
    timestamp: str,
) -> bool:
    """Set achievements.unlocked if not already present. Returns True when newly set."""
    user = db_manager.db["users"].find_one(
        {"_id": user_oid},
        {"modules.dutch_game.achievements.unlocked": 1},
    )
    if not user:
        return False
    dutch_game = (user.get("modules") or {}).get("dutch_game") or {}
    already = achcat.unlocked_achievement_ids_from_dutch_game(dutch_game)
    if achievement_id in already:
        return False
    db_manager.db["users"].update_one(
        {"_id": user_oid},
        {
            "$set": {
                f"modules.dutch_game.achievements.unlocked.{achievement_id}": {
                    "unlocked_at": timestamp,
                }
            }
        },
    )
    return True


def grant_period_placement(
    app_manager,
    db_manager,
    *,
    user_id: str,
    user_oid: ObjectId,
    achievement_id: str,
    period: str,
    period_key: str,
    game_type: str,
    rank_tier: str,
    placement: str,
    timestamp: str,
) -> bool:
    """
  Grant a repeatable monthly/yearly placement achievement for one period.
  Returns True when a new period grant was created (notification sent).
    """
    grant_key = _period_grant_field_key(period, period_key, game_type, rank_tier, placement)
    existing = db_manager.db["users"].find_one(
        {"_id": user_oid, grant_key: {"$exists": True}},
        {"_id": 1},
    )
    if existing:
        return False
    _grant_lifetime_unlock(db_manager, user_oid, achievement_id, timestamp)
    db_manager.db["users"].update_one(
        {"_id": user_oid},
        {
            "$set": {
                grant_key: {
                    "achievement_id": achievement_id,
                    "granted_at": timestamp,
                    "period": period,
                    "period_key": period_key,
                    "game_type": game_type,
                    "rank_tier": rank_tier,
                    "placement": placement,
                }
            }
        },
    )
    _notify_achievement_unlock(
        app_manager,
        user_id,
        achievement_id,
        grant_type="leaderboard_period",
        period_key=period_key,
        period=period,
    )
    return True


def grant_alltime_placement(
    app_manager,
    db_manager,
    *,
    user_id: str,
    user_oid: ObjectId,
    achievement_id: str,
    timestamp: str,
) -> bool:
    """Grant all-time placement once per band. Returns True when newly granted."""
    user = db_manager.db["users"].find_one(
        {"_id": user_oid},
        {"modules.dutch_game.achievements.unlocked": 1},
    )
    if not user:
        return False
    dutch_game = (user.get("modules") or {}).get("dutch_game") or {}
    already = achcat.unlocked_achievement_ids_from_dutch_game(dutch_game)
    if achievement_id in already:
        return False
    db_manager.db["users"].update_one(
        {"_id": user_oid},
        {
            "$set": {
                f"modules.dutch_game.achievements.unlocked.{achievement_id}": {
                    "unlocked_at": timestamp,
                }
            }
        },
    )
    _notify_achievement_unlock(
        app_manager,
        user_id,
        achievement_id,
        grant_type="leaderboard_alltime",
    )
    return True


def _completed_month_window(now_utc: datetime) -> Tuple[str, datetime, datetime]:
    from .api_endpoints import _next_calendar_month_first, _prev_calendar_month_first

    first_this = now_utc.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    start = _prev_calendar_month_first(first_this)
    end = _next_calendar_month_first(start)
    return start.strftime("%Y-%m"), start, end


def _completed_year_window(now_utc: datetime) -> Tuple[str, datetime, datetime]:
    y = now_utc.year - 1
    start = datetime(y, 1, 1, tzinfo=timezone.utc)
    end = datetime(y + 1, 1, 1, tzinfo=timezone.utc)
    return str(y), start, end


def _is_scope_processed(db_manager, scope_key: str) -> bool:
    return (
        db_manager.db[RUN_LEDGER_COLL].find_one({"scope_key": scope_key}, {"_id": 1}) is not None
    )


def _mark_scope_processed(
    db_manager, scope_key: str, *, users_granted: int
) -> None:
    db_manager.db[RUN_LEDGER_COLL].update_one(
        {"scope_key": scope_key},
        {
            "$set": {
                "scope_key": scope_key,
                "processed_at": _utc_now().isoformat(),
                "users_granted": max(0, int(users_granted)),
            }
        },
        upsert=True,
    )


def process_period_scope(
    app_manager,
    db_manager,
    *,
    period: str,
    period_key: str,
    start: datetime,
    end: datetime,
    game_type: str,
    rank_tier: str,
) -> int:
    """Process one monthly/yearly rank-tier slice. Returns count of new grants."""
    from .api_endpoints import _aggregate_period_wins_summaries_rank_tier

    scope_key = _scope_run_key(period, period_key, game_type, rank_tier)
    if _is_scope_processed(db_manager, scope_key):
        return 0
    coll = db_manager.db[MATCH_WIN_OUTCOMES_COLL]
    summaries = _aggregate_period_wins_summaries_rank_tier(
        coll, start, end, rank_tier, game_type=game_type
    )
    top = summaries[:100]
    ts = _utc_now().isoformat()
    granted = 0
    for rank, doc in enumerate(top, start=1):
        placement = achcat.placement_for_rank(rank)
        if not placement:
            continue
        ach_id = achcat.achievement_id_for_leaderboard_placement(
            period=period,
            game_type=game_type,
            placement=placement,
            rank_tier=rank_tier,
        )
        if not ach_id:
            continue
        uid = doc.get("_id")
        if not isinstance(uid, ObjectId):
            continue
        if grant_period_placement(
            app_manager,
            db_manager,
            user_id=str(uid),
            user_oid=uid,
            achievement_id=ach_id,
            period=period,
            period_key=period_key,
            game_type=game_type,
            rank_tier=rank_tier,
            placement=placement,
            timestamp=ts,
        ):
            granted += 1
    _mark_scope_processed(db_manager, scope_key, users_granted=granted)
    return granted


def process_pending_period_achievements(
    app_manager,
    db_manager,
    *,
    period: Optional[str] = None,
    period_key: Optional[str] = None,
) -> Dict[str, Any]:
    """Scan and process completed monthly/yearly scopes not yet in the run ledger."""
    now = _utc_now()
    scopes: List[Tuple[str, str, datetime, datetime]] = []
    if period_key and period in PERIOD_SCOPES:
        if period == "monthly":
            try:
                year_s, month_s = period_key.split("-", 1)
                start = datetime(int(year_s), int(month_s), 1, tzinfo=timezone.utc)
                from .api_endpoints import _next_calendar_month_first

                end = _next_calendar_month_first(start)
                scopes.append((period, period_key, start, end))
            except (TypeError, ValueError):
                pass
        elif period == "yearly":
            try:
                y = int(period_key)
                start = datetime(y, 1, 1, tzinfo=timezone.utc)
                end = datetime(y + 1, 1, 1, tzinfo=timezone.utc)
                scopes.append((period, period_key, start, end))
            except (TypeError, ValueError):
                pass
    else:
        month_key, month_start, month_end = _completed_month_window(now)
        scopes.append(("monthly", month_key, month_start, month_end))
        year_key, year_start, year_end = _completed_year_window(now)
        scopes.append(("yearly", year_key, year_start, year_end))

    total_granted = 0
    processed_scopes: List[str] = []
    for per, pkey, start, end in scopes:
        if end > now:
            continue
        for game_type in GAME_TYPES:
            for rank_tier in matcher.RANK_HIERARCHY:
                tier = str(rank_tier).strip().lower()
                if not tier:
                    continue
                n = process_period_scope(
                    app_manager,
                    db_manager,
                    period=per,
                    period_key=pkey,
                    start=start,
                    end=end,
                    game_type=game_type,
                    rank_tier=tier,
                )
                if n > 0 or _is_scope_processed(
                    db_manager, _scope_run_key(per, pkey, game_type, tier)
                ):
                    processed_scopes.append(_scope_run_key(per, pkey, game_type, tier))
                total_granted += n

    return {
        "success": True,
        "grants_created": total_granted,
        "scopes_touched": processed_scopes,
    }


def check_alltime_band_entry(
    app_manager,
    db_manager,
    *,
    user_id: str,
    user_oid: ObjectId,
    game_type: Optional[str],
) -> bool:
    """After a win, grant all-time placement band if user newly qualifies. Returns True if granted."""
    from .api_endpoints import _aggregate_period_wins_summaries

    gt = str(game_type or "classic").strip().lower()
    if gt not in GAME_TYPES:
        gt = "classic"
    coll = db_manager.db[MATCH_WIN_OUTCOMES_COLL]
    summaries = _aggregate_period_wins_summaries(coll, None, None, game_type=gt)
    rank = _rank_user_in_summaries(summaries, user_oid)
    if rank is None:
        return False
    placement = achcat.placement_for_rank(rank)
    if not placement:
        return False
    ach_id = achcat.achievement_id_for_leaderboard_placement(
        period="all_time",
        game_type=gt,
        placement=placement,
    )
    if not ach_id:
        return False
    return grant_alltime_placement(
        app_manager,
        db_manager,
        user_id=user_id,
        user_oid=user_oid,
        achievement_id=ach_id,
        timestamp=_utc_now().isoformat(),
    )


def schedule_alltime_leaderboard_achievement_check(
    app_manager,
    db_manager,
    *,
    user_id: str,
    user_oid: ObjectId,
    game_type: Optional[str],
) -> None:
    """Fire-and-forget all-time band check so match stats HTTP is not blocked."""

    def _run() -> None:
        try:
            if app_manager is None or db_manager is None:
                return
            check_alltime_band_entry(
                app_manager,
                db_manager,
                user_id=user_id,
                user_oid=user_oid,
                game_type=game_type,
            )
        except Exception:
            pass

    threading.Thread(target=_run, daemon=True).start()
