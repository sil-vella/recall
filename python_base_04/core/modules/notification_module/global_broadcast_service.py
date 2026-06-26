"""
Global broadcast messages: rank-targeted announcements not stored per-user in `notifications`.

Collections:
  - global_broadcast_messages: one doc per broadcast
  - global_broadcast_reads: per-user ack (user_id + global_message_id)
"""

from __future__ import annotations

import os
from datetime import datetime
from typing import Any, Dict, List, Optional, Set

from bson import ObjectId

from core.modules.user_management_module import tier_rank_level_matcher as matcher
from tools.dev_logger import customlog

from .notification_service import NOTIFICATION_TYPES_PREDEFINED

# On when ``playbooks/00_local/run_python_app_to_global_log.sh`` / ``DUTCH_DEV_LOG=1`` (same truthy set as customlog).
LOGGING_SWITCH = (os.environ.get("DUTCH_DEV_LOG") or "").strip().lower() in ("1", "true", "yes")

GLOBAL_BROADCAST_MESSAGES_COLL = "global_broadcast_messages"
GLOBAL_BROADCAST_READS_COLL = "global_broadcast_reads"

ALL_RANKS_SENTINEL = "all"
_DEFAULT_FETCH_LIMIT = 40


def _db_ref(db_manager):
    """PyMongo Database does not support truthiness; use `is None` checks."""
    return getattr(db_manager, "db", None) if db_manager else None


def ensure_global_broadcast_indexes(db_manager) -> None:
    """Create indexes once (best-effort; safe to call on each notification module init)."""
    db = _db_ref(db_manager)
    if db is None:
        return
    try:
        db[GLOBAL_BROADCAST_MESSAGES_COLL].create_index(
            [("is_active", 1), ("created_at", -1)],
            name="gbm_active_created",
        )
        db[GLOBAL_BROADCAST_READS_COLL].create_index(
            [("user_id", 1), ("global_message_id", 1)],
            unique=True,
            name="gbr_user_msg",
        )
    except Exception:
        pass


def _normalize_target_ranks(raw: Any) -> List[str]:
    out: List[str] = []
    if not isinstance(raw, list):
        return [ALL_RANKS_SENTINEL]
    for x in raw:
        s = str(x or "").strip().lower()
        if not s:
            continue
        if s == ALL_RANKS_SENTINEL:
            return [ALL_RANKS_SENTINEL]
        n = matcher.normalize_rank(s)
        if n:
            out.append(n)
    return out if out else [ALL_RANKS_SENTINEL]


def _user_matches_targets(user_rank_norm: str, targets: List[str]) -> bool:
    if ALL_RANKS_SENTINEL in targets:
        return True
    if not user_rank_norm:
        return False
    return user_rank_norm in targets


def _within_schedule(doc: Dict[str, Any], now: datetime) -> bool:
    starts = doc.get("starts_at")
    ends = doc.get("ends_at")
    if isinstance(starts, datetime) and starts > now:
        return False
    if isinstance(ends, datetime) and ends < now:
        return False
    return True


def _dedupe_candidates_by_msg_id(candidates: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Keep one document per non-empty msg_id (newest created_at wins). Rows without msg_id are kept."""
    by_msg_id: Dict[str, Dict[str, Any]] = {}
    no_msg_id: List[Dict[str, Any]] = []

    def _created_ts(d: Dict[str, Any]) -> float:
        c = d.get("created_at")
        if isinstance(c, datetime):
            return c.timestamp()
        return 0.0

    for doc in candidates:
        mid = (doc.get("msg_id") or "").strip()
        if not mid:
            no_msg_id.append(doc)
            continue
        prev = by_msg_id.get(mid)
        if prev is None or _created_ts(doc) >= _created_ts(prev):
            by_msg_id[mid] = doc
    return no_msg_id + list(by_msg_id.values())


def _load_user_global_read_ids(db_manager, user_oid: ObjectId, gids: List[ObjectId]) -> Set[str]:
    """Load ack ids using the same raw Mongo path as [mark_global_broadcasts_read]."""
    read_ids: Set[str] = set()
    if not gids:
        return read_ids
    db = _db_ref(db_manager)
    if db is None:
        return read_ids
    try:
        coll = db[GLOBAL_BROADCAST_READS_COLL]
        for doc in coll.find(
            {"user_id": user_oid, "global_message_id": {"$in": gids}},
            projection={"global_message_id": 1},
        ):
            mid = doc.get("global_message_id")
            if mid is not None:
                read_ids.add(str(mid))
    except Exception:
        pass
    return read_ids


def _serialize_global_doc(
    doc: Dict[str, Any],
    *,
    user_read: bool,
) -> Dict[str, Any]:
    """Shape aligned with list_messages + global metadata for Flutter."""
    _id = doc.get("_id")
    oid_str = str(_id) if _id is not None else ""
    created = doc.get("created_at")
    read_at = datetime.utcnow().isoformat() if user_read else None
    responses = doc.get("responses")
    if not isinstance(responses, list):
        responses = []
    responses_out: List[Dict[str, str]] = []
    for r in responses:
        if not isinstance(r, dict):
            continue
        label = (r.get("label") or "").strip()
        action_id = (r.get("action_identifier") or r.get("action") or "").strip()
        if label and action_id:
            responses_out.append({"label": label, "action_identifier": action_id})
    return {
        "id": f"glob_{oid_str}",
        "global_id": oid_str,
        "origin": "global",
        "msg_id": doc.get("msg_id") or "",
        "source": doc.get("source", "") or "global_broadcast",
        "type": doc.get("type", "") or "instant",
        "subtype": doc.get("subtype", "") or "",
        "title": doc.get("title", "") or "",
        "body": doc.get("body", "") or "",
        "data": doc.get("data") if isinstance(doc.get("data"), dict) else {},
        "responses": responses_out,
        "created_at": created.isoformat() if isinstance(created, datetime) else created,
        "read": user_read,
        "read_at": read_at,
        "user_read": user_read,
    }


def load_global_broadcast_payload_for_user(
    db_manager,
    *,
    user_id: str,
    user_rank: Optional[str],
    limit: int = _DEFAULT_FETCH_LIMIT,
) -> List[Dict[str, Any]]:
    """
    Active global broadcasts visible to this user's Dutch rank, with read flags from global_broadcast_reads.
    """
    if not db_manager:
        if LOGGING_SWITCH:
            customlog("global_broadcast: no db_manager")
        return []
    try:
        user_oid = ObjectId(user_id)
    except Exception:
        if LOGGING_SWITCH:
            customlog(f"global_broadcast: invalid user_id={user_id!r}")
        return []
    user_rank_norm = matcher.normalize_rank(user_rank) or matcher.DEFAULT_RANK
    now = datetime.utcnow()
    if LOGGING_SWITCH:
        customlog(f"global_broadcast: load user_id={user_id} rank={user_rank_norm}")
    try:
        raw_docs = db_manager.find(GLOBAL_BROADCAST_MESSAGES_COLL, {"is_active": True})
    except Exception as e:
        if LOGGING_SWITCH:
            customlog(f"global_broadcast: find active failed {type(e).__name__}: {e}")
        return []
    if not isinstance(raw_docs, list):
        if LOGGING_SWITCH:
            customlog(f"global_broadcast: find returned {type(raw_docs).__name__}, expected list")
        return []
    if LOGGING_SWITCH:
        customlog(f"global_broadcast: active docs={len(raw_docs)}")

    candidates: List[Dict[str, Any]] = []
    for doc in raw_docs:
        if not isinstance(doc, dict):
            continue
        if not _within_schedule(doc, now):
            continue
        targets = _normalize_target_ranks(doc.get("target_ranks"))
        if not _user_matches_targets(user_rank_norm, targets):
            continue
        candidates.append(doc)

    candidates = _dedupe_candidates_by_msg_id(candidates)

    def _sort_key(d: Dict[str, Any]) -> float:
        c = d.get("created_at")
        if isinstance(c, datetime):
            return c.timestamp()
        return 0.0

    candidates.sort(key=_sort_key, reverse=True)
    candidates = candidates[: max(1, min(limit, 100))]

    read_ids: Set[str] = set()
    if candidates:
        gids: List[ObjectId] = []
        for d in candidates:
            oid = d.get("_id")
            try:
                if isinstance(oid, ObjectId):
                    gids.append(oid)
                elif isinstance(oid, str) and len(oid) == 24:
                    gids.append(ObjectId(oid))
            except Exception:
                continue
        if gids:
            read_ids = _load_user_global_read_ids(db_manager, user_oid, gids)

    if LOGGING_SWITCH:
        customlog(
            f"global_broadcast: candidates={len(candidates)} "
            f"read_ids={len(read_ids)} db_ok={_db_ref(db_manager) is not None}"
        )

    out: List[Dict[str, Any]] = []
    for doc in candidates:
        oid = doc.get("_id")
        oid_str = str(oid) if oid is not None else ""
        user_read = oid_str in read_ids if oid_str else False
        out.append(_serialize_global_doc(doc, user_read=user_read))
    if LOGGING_SWITCH:
        unread = sum(1 for row in out if not row.get("user_read"))
        customlog(
            f"global_broadcast: payload count={len(out)} unread={unread} "
            f"msg_ids={[row.get('msg_id') for row in out]}"
        )
    return out


def insert_global_broadcast(db_manager, doc: Dict[str, Any]) -> Optional[str]:
    """Insert a new global broadcast document. Returns inserted _id as str or None."""
    if not db_manager:
        return None
    now = datetime.utcnow()
    row = {
        "title": str(doc.get("title") or "").strip(),
        "body": str(doc.get("body") or "").strip(),
        "type": str(doc.get("type") or "instant").strip(),
        "subtype": str(doc.get("subtype") or "").strip(),
        "source": str(doc.get("source") or "global_broadcast").strip(),
        "data": doc.get("data") if isinstance(doc.get("data"), dict) else {},
        "responses": doc.get("responses") if isinstance(doc.get("responses"), list) else [],
        "target_ranks": _normalize_target_ranks(doc.get("target_ranks")),
        "is_active": bool(doc.get("is_active", True)),
        "created_at": now,
        "updated_at": now,
    }
    mid = str(doc.get("msg_id") or "").strip()
    if mid:
        row["msg_id"] = mid
    if row["type"] not in NOTIFICATION_TYPES_PREDEFINED:
        row["type"] = "instant"
    if isinstance(doc.get("starts_at"), datetime):
        row["starts_at"] = doc["starts_at"]
    if isinstance(doc.get("ends_at"), datetime):
        row["ends_at"] = doc["ends_at"]
    if not row["title"] or not row["body"]:
        return None
    try:
        return db_manager.insert(GLOBAL_BROADCAST_MESSAGES_COLL, row)
    except Exception:
        return None


def mark_global_broadcasts_read(db_manager, user_id: str, global_message_ids: List[str]) -> int:
    """
    Upsert read records for the user. Accepts Mongo ObjectId strings or client ids prefixed with glob_.
    Returns count of successfully processed ids.
    """
    db = _db_ref(db_manager)
    if db is None:
        return 0
    try:
        user_oid = ObjectId(user_id)
    except Exception:
        return 0
    now = datetime.utcnow()
    coll = db[GLOBAL_BROADCAST_READS_COLL]
    n = 0
    for raw in global_message_ids[:50]:
        if not raw:
            continue
        s = str(raw).strip()
        if s.startswith("glob_"):
            s = s[5:]
        try:
            gid = ObjectId(s)
        except Exception:
            continue
        try:
            coll.update_one(
                {"user_id": user_oid, "global_message_id": gid},
                {
                    "$set": {"read_at": now},
                    "$setOnInsert": {"user_id": user_oid, "global_message_id": gid},
                },
                upsert=True,
            )
            n += 1
        except Exception:
            continue
    return n
