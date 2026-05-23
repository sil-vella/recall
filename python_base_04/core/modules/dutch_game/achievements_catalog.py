"""
Declarative Dutch achievements — titles, descriptions, and unlock rules.

Single source of truth:
  - config/achievements_config.json
  - optional env override via DUTCH_ACHIEVEMENTS_JSON / DUTCH_ACHIEVEMENTS_PATH
"""

from __future__ import annotations

import hashlib
import json
import os
from copy import deepcopy
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

_CONFIG_DIR = Path(__file__).resolve().parent / "config"
_DEFAULT_JSON_PATH = _CONFIG_DIR / "achievements_config.json"


def _read_json_file(path: Path) -> Optional[Dict[str, Any]]:
    try:
        if path.is_file():
            with open(path, "r", encoding="utf-8") as f:
                raw = json.load(f)
                if isinstance(raw, dict):
                    return raw
    except Exception:
        pass
    return None


def _merge_env_overlay(doc: Dict[str, Any]) -> Dict[str, Any]:
    raw = (os.getenv("DUTCH_ACHIEVEMENTS_JSON") or "").strip()
    if not raw:
        return doc
    try:
        overlay = json.loads(raw)
    except Exception:
        return doc
    if not isinstance(overlay, dict):
        return doc
    out = deepcopy(doc)
    if "schema_version" in overlay:
        out["schema_version"] = overlay["schema_version"]
    if isinstance(overlay.get("achievements"), list):
        out["achievements"] = overlay["achievements"]
    return out


def _normalize_achievement_entry(raw: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    ach_id = str(raw.get("id") or "").strip()
    if not ach_id:
        return None
    title = str(raw.get("title") or ach_id).strip()
    desc = str(raw.get("description") or "").strip()
    unlock = raw.get("unlock")
    if not isinstance(unlock, dict):
        return None
    utype = str(unlock.get("type") or "").strip().lower()
    if utype == "win_streak":
        try:
            vmin = max(1, int(unlock.get("min")))
        except (TypeError, ValueError):
            return None
        return {
            "id": ach_id,
            "title": title,
            "description": desc,
            "unlock": {"type": "win_streak", "min": vmin},
        }
    if utype == "event_win":
        se = str(unlock.get("special_event_id") or "").strip()
        if not se:
            return None
        raw_min = unlock.get("min", 1)
        try:
            vmin = max(1, int(raw_min))
        except (TypeError, ValueError):
            vmin = 1
        return {
            "id": ach_id,
            "title": title,
            "description": desc,
            "unlock": {
                "type": "event_win",
                "special_event_id": se,
                "min": vmin,
            },
        }
    if utype == "total_wins":
        try:
            vmin = max(1, int(unlock.get("min")))
        except (TypeError, ValueError):
            return None
        return {
            "id": ach_id,
            "title": title,
            "description": desc,
            "unlock": {"type": "total_wins", "min": vmin},
        }
    if utype == "match_flag":
        flag = str(unlock.get("flag") or "").strip().lower()
        if not flag:
            return None
        requires_win = unlock.get("requires_win", True)
        if not isinstance(requires_win, bool):
            requires_win = True
        return {
            "id": ach_id,
            "title": title,
            "description": desc,
            "unlock": {
                "type": "match_flag",
                "flag": flag,
                "requires_win": requires_win,
            },
        }
    return None


def _normalize_document(doc: Dict[str, Any]) -> Dict[str, Any]:
    try:
        schema_version = int(doc.get("schema_version") or 1)
    except (TypeError, ValueError):
        schema_version = 1
    raw_list = doc.get("achievements")
    achievements: List[Dict[str, Any]] = []
    seen: Set[str] = set()
    if isinstance(raw_list, list):
        for item in raw_list:
            if not isinstance(item, dict):
                continue
            norm = _normalize_achievement_entry(item)
            if norm is None:
                continue
            aid = norm["id"]
            if aid in seen:
                continue
            seen.add(aid)
            achievements.append(norm)
    return {"schema_version": schema_version, "achievements": achievements}


def _compute_revision(canonical: Dict[str, Any]) -> str:
    blob = json.dumps(canonical, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(blob).hexdigest()


def _load_raw_document() -> Dict[str, Any]:
    path_env = (os.getenv("DUTCH_ACHIEVEMENTS_PATH") or "").strip()
    path = Path(path_env) if path_env else _DEFAULT_JSON_PATH
    doc = _read_json_file(path)
    if doc is None:
        doc = _read_json_file(_DEFAULT_JSON_PATH) or {}
    return _merge_env_overlay(doc)


_CANONICAL_DOC = _normalize_document(_load_raw_document())
ACHIEVEMENTS_CONFIG_DOCUMENT: Dict[str, Any] = deepcopy(_CANONICAL_DOC)
ACHIEVEMENTS_CONFIG_REVISION: str = _compute_revision(_CANONICAL_DOC)

_ACHIEVEMENTS_ORDERED: Tuple[Dict[str, Any], ...] = tuple(_CANONICAL_DOC.get("achievements") or [])
_BY_ID: Dict[str, Dict[str, Any]] = {str(a["id"]): dict(a) for a in _ACHIEVEMENTS_ORDERED}


def build_client_achievements_payload() -> Dict[str, Any]:
    return deepcopy(ACHIEVEMENTS_CONFIG_DOCUMENT)


def achievement_by_id(ach_id: str) -> Optional[Dict[str, Any]]:
    if not ach_id:
        return None
    row = _BY_ID.get(str(ach_id).strip())
    return deepcopy(row) if row else None


def unlocked_achievement_ids_from_dutch_game(dutch_game: Dict[str, Any]) -> Set[str]:
    ach = dutch_game.get("achievements") or {}
    if not isinstance(ach, dict):
        return set()
    raw = ach.get("unlocked") or {}
    if not isinstance(raw, dict):
        return set()
    return {str(k) for k in raw.keys()}


def achievements_unlocked_ids_sorted(dutch_game: Dict[str, Any]) -> List[str]:
    return sorted(unlocked_achievement_ids_from_dutch_game(dutch_game))


def next_win_streak(current_streak: int, is_winner: bool) -> int:
    if is_winner:
        return max(0, int(current_streak)) + 1
    return 0


def parse_stored_streak(raw: Any) -> int:
    try:
        v = int(raw)
    except (TypeError, ValueError):
        return 0
    return max(0, v)


def _truthy_flag(raw: Any) -> bool:
    if raw is True:
        return True
    if isinstance(raw, str):
        return raw.strip().lower() in ("1", "true", "yes")
    if isinstance(raw, (int, float)):
        return int(raw) != 0
    return False


def parse_special_event_wins(dutch_game: Dict[str, Any]) -> Dict[str, int]:
    """Lifetime wins per catalog ``special_events`` id from ``modules.dutch_game.special_event_wins``."""
    raw = dutch_game.get("special_event_wins")
    if not isinstance(raw, dict):
        return {}
    out: Dict[str, int] = {}
    for key, val in raw.items():
        eid = str(key).strip()
        if not eid:
            continue
        try:
            out[eid] = max(0, int(val))
        except (TypeError, ValueError):
            continue
    return out


def special_event_win_count_after_match(
    stored: Dict[str, int],
    special_event_id: str,
    *,
    is_winner: bool,
) -> int:
    """Post-match win count for [special_event_id] (increments by 1 when winner in that event)."""
    eid = (special_event_id or "").strip()
    if not eid:
        return 0
    before = max(0, int(stored.get(eid, 0)))
    if is_winner:
        return before + 1
    return before


def match_flags_from_game_result_row(
    row: Dict[str, Any],
    *,
    is_winner: bool,
) -> Set[str]:
    """Derive match-scoped flags from a single Dart ``game_results`` row."""
    flags: Set[str] = set()
    if not isinstance(row, dict):
        return flags
    win_type = str(row.get("win_type") or row.get("winType") or "").strip().lower()
    if is_winner and win_type == "empty_hand":
        flags.add("empty_hand")
    if _truthy_flag(row.get("dutch_called")) or _truthy_flag(row.get("dutchCalled")):
        flags.add("dutch_called")
    return flags


def compute_new_unlocks(
    win_streak_after: int,
    already_unlocked: Set[str],
    *,
    is_winner: bool = False,
    special_event_id: Optional[str] = None,
    special_event_win_count_after: int = 0,
    total_wins_after: int = 0,
    match_flags: Optional[Set[str]] = None,
) -> List[str]:
    """Return achievement ids newly earned this match (catalog order)."""
    se = (special_event_id or "").strip()
    try:
        event_wins_after = max(0, int(special_event_win_count_after))
    except (TypeError, ValueError):
        event_wins_after = 0
    flags = {str(f).strip().lower() for f in (match_flags or set()) if str(f).strip()}
    try:
        wins_after = max(0, int(total_wins_after))
    except (TypeError, ValueError):
        wins_after = 0
    out: List[str] = []
    for entry in _ACHIEVEMENTS_ORDERED:
        eid = str(entry.get("id") or "")
        if not eid or eid in already_unlocked:
            continue
        unlock = entry.get("unlock")
        if not isinstance(unlock, dict):
            continue
        utype = str(unlock.get("type") or "").strip().lower()
        if utype == "win_streak":
            try:
                vmin = int(unlock.get("min"))
            except (TypeError, ValueError):
                continue
            if win_streak_after >= vmin:
                out.append(eid)
        elif utype == "event_win":
            if not is_winner or not se:
                continue
            need = str(unlock.get("special_event_id") or "").strip()
            if not need or need != se:
                continue
            try:
                vmin = max(1, int(unlock.get("min", 1)))
            except (TypeError, ValueError):
                vmin = 1
            if event_wins_after >= vmin:
                out.append(eid)
        elif utype == "total_wins":
            try:
                vmin = int(unlock.get("min"))
            except (TypeError, ValueError):
                continue
            if wins_after >= vmin:
                out.append(eid)
        elif utype == "match_flag":
            need_flag = str(unlock.get("flag") or "").strip().lower()
            if not need_flag or need_flag not in flags:
                continue
            requires_win = unlock.get("requires_win", True)
            if requires_win and not is_winner:
                continue
            out.append(eid)
    return out
