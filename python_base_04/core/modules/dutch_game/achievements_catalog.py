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
        return {
            "id": ach_id,
            "title": title,
            "description": desc,
            "unlock": {"type": "event_win", "special_event_id": se},
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


def compute_new_unlocks(
    win_streak_after: int,
    already_unlocked: Set[str],
    *,
    is_winner: bool = False,
    special_event_id: Optional[str] = None,
) -> List[str]:
    """Return achievement ids newly earned this match (catalog order)."""
    se = (special_event_id or "").strip()
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
            if need and se == need:
                out.append(eid)
    return out
