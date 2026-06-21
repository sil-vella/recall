"""
Declarative Dutch gameplay rule profiles — reusable presets for special events and practice.

Single source of truth:
  - config/gameplay_profiles.json
  - optional env override via DUTCH_GAMEPLAY_PROFILES_PATH
"""

from __future__ import annotations

import hashlib
import json
import os
from copy import deepcopy
from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Set, Tuple

_CONFIG_DIR = Path(__file__).resolve().parent / "config"
_DEFAULT_JSON_PATH = _CONFIG_DIR / "gameplay_profiles.json"
_PROFILE_ID_RE = __import__("re").compile(r"^[A-Za-z0-9_-]+$")

_DEFAULT_PROFILE_ID = "classic"

_PROFILE_TOP_KEYS = frozenset(
    {"id", "label", "description", "extends", "flags", "deal", "timers", "deck", "scoring", "win_conditions"}
)
_FLAG_KEYS = frozenset(
    {
        "clear_and_collect",
        "same_rank_out_of_turn",
        "queen_peek",
        "jack_swap",
        "dutch_call",
        "discard_take_allowed",
    }
)
_DEAL_KEYS = frozenset({"cards_per_hand", "initial_peek_count"})
_DECK_KEYS = frozenset({"source"})
_SCORING_KEYS = frozenset({"red_king_points"})
_WIN_KEYS = frozenset({"empty_hand", "lowest_points_after_dutch", "four_of_a_kind_collection"})
_VALID_DECK_SOURCES = frozenset({"standard", "demo", "testing"})
_VALID_TIMER_KEYS = frozenset(
    {
        "initial_peek",
        "drawing_card",
        "playing_card",
        "same_rank_window",
        "queen_peek",
        "jack_swap",
        "peeking",
        "waiting",
        "default",
    }
)


class GameplayProfileCatalogError(ValueError):
    """Invalid gameplay profile document."""


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


def _deep_merge_dict(base: Dict[str, Any], override: Dict[str, Any]) -> Dict[str, Any]:
    out = deepcopy(base)
    for key, val in override.items():
        if isinstance(val, dict) and isinstance(out.get(key), dict):
            out[key] = _deep_merge_dict(out[key], val)
        else:
            out[key] = deepcopy(val)
    return out


def _reject_unknown_keys(obj: Mapping[str, Any], allowed: Set[str], path: str) -> None:
    for key in obj:
        if key not in allowed:
            raise GameplayProfileCatalogError(f"Unknown key {path}.{key}")


def _parse_bool(raw: Any, *, default: bool) -> bool:
    if isinstance(raw, bool):
        return raw
    if raw is None:
        return default
    s = str(raw).strip().lower()
    if s in ("1", "true", "yes"):
        return True
    if s in ("0", "false", "no"):
        return False
    return default


def _parse_profile_row(raw: Dict[str, Any], profile_id: str) -> Dict[str, Any]:
    _reject_unknown_keys(raw, _PROFILE_TOP_KEYS, f"profiles.{profile_id}")
    label = str(raw.get("label") or profile_id).strip()
    if not label:
        raise GameplayProfileCatalogError(f"profiles.{profile_id}: label required")
    row: Dict[str, Any] = {
        "id": profile_id,
        "label": label,
        "description": str(raw.get("description") or "").strip(),
        "extends": None,
        "flags": {},
        "deal": {},
        "timers": {},
        "deck": {},
        "scoring": {},
        "win_conditions": {},
    }
    ext = raw.get("extends")
    if ext is not None and str(ext).strip():
        ext_s = str(ext).strip()
        if not _PROFILE_ID_RE.match(ext_s):
            raise GameplayProfileCatalogError(f"profiles.{profile_id}: invalid extends id")
        row["extends"] = ext_s

    flags_raw = raw.get("flags")
    if isinstance(flags_raw, dict):
        _reject_unknown_keys(flags_raw, _FLAG_KEYS, f"profiles.{profile_id}.flags")
        row["flags"] = {k: _parse_bool(v, default=True) for k, v in flags_raw.items()}

    deal_raw = raw.get("deal")
    if isinstance(deal_raw, dict):
        _reject_unknown_keys(deal_raw, _DEAL_KEYS, f"profiles.{profile_id}.deal")
        deal: Dict[str, int] = {}
        if "cards_per_hand" in deal_raw:
            deal["cards_per_hand"] = max(1, int(deal_raw["cards_per_hand"]))
        if "initial_peek_count" in deal_raw:
            deal["initial_peek_count"] = max(0, int(deal_raw["initial_peek_count"]))
        row["deal"] = deal

    timers_raw = raw.get("timers")
    if isinstance(timers_raw, dict):
        timers: Dict[str, int] = {}
        for key, val in timers_raw.items():
            if key not in _VALID_TIMER_KEYS:
                raise GameplayProfileCatalogError(
                    f"profiles.{profile_id}.timers: unknown timer key {key!r}"
                )
            timers[key] = max(0, int(val))
        row["timers"] = timers

    deck_raw = raw.get("deck")
    if isinstance(deck_raw, dict):
        _reject_unknown_keys(deck_raw, _DECK_KEYS, f"profiles.{profile_id}.deck")
        source = str(deck_raw.get("source") or "standard").strip().lower()
        if source not in _VALID_DECK_SOURCES:
            raise GameplayProfileCatalogError(
                f"profiles.{profile_id}.deck.source: invalid {source!r}"
            )
        row["deck"] = {"source": source}

    scoring_raw = raw.get("scoring")
    if isinstance(scoring_raw, dict):
        _reject_unknown_keys(scoring_raw, _SCORING_KEYS, f"profiles.{profile_id}.scoring")
        scoring: Dict[str, int] = {}
        if "red_king_points" in scoring_raw:
            scoring["red_king_points"] = int(scoring_raw["red_king_points"])
        row["scoring"] = scoring

    win_raw = raw.get("win_conditions")
    if isinstance(win_raw, dict):
        _reject_unknown_keys(win_raw, _WIN_KEYS, f"profiles.{profile_id}.win_conditions")
        row["win_conditions"] = {k: _parse_bool(v, default=True) for k, v in win_raw.items()}

    return row


def _resolve_extends_chain(
    profile_id: str,
    raw_profiles: Dict[str, Dict[str, Any]],
    *,
    visiting: Optional[Set[str]] = None,
) -> Dict[str, Any]:
    if profile_id not in raw_profiles:
        raise GameplayProfileCatalogError(f"Unknown profile id: {profile_id!r}")
    visiting = visiting or set()
    if profile_id in visiting:
        raise GameplayProfileCatalogError(f"Circular extends chain at {profile_id!r}")
    visiting.add(profile_id)
    row = deepcopy(raw_profiles[profile_id])
    parent_id = row.get("extends")
    if parent_id:
        parent = _resolve_extends_chain(str(parent_id), raw_profiles, visiting=visiting)
        merged = _deep_merge_dict(parent, row)
        merged["id"] = profile_id
        merged["label"] = row.get("label") or parent.get("label") or profile_id
        desc = str(row.get("description") or "").strip()
        if desc:
            merged["description"] = desc
        elif parent.get("description"):
            merged["description"] = parent["description"]
        merged.pop("extends", None)
        return merged
    row.pop("extends", None)
    return row


def _apply_defaults(resolved: Dict[str, Any]) -> Dict[str, Any]:
    """Fill missing keys after extends merge."""
    out = deepcopy(resolved)
    flags = dict(out.get("flags") or {})
    flags.setdefault("clear_and_collect", False)
    flags.setdefault("same_rank_out_of_turn", True)
    flags.setdefault("queen_peek", True)
    flags.setdefault("jack_swap", True)
    flags.setdefault("dutch_call", True)
    flags.setdefault("discard_take_allowed", True)
    out["flags"] = flags

    deal = dict(out.get("deal") or {})
    deal.setdefault("cards_per_hand", 4)
    deal.setdefault("initial_peek_count", 2)
    out["deal"] = deal

    deck = dict(out.get("deck") or {})
    deck.setdefault("source", "standard")
    out["deck"] = deck

    scoring = dict(out.get("scoring") or {})
    scoring.setdefault("red_king_points", 10)
    out["scoring"] = scoring

    win = dict(out.get("win_conditions") or {})
    win.setdefault("empty_hand", True)
    win.setdefault("lowest_points_after_dutch", True)
    win.setdefault("four_of_a_kind_collection", flags.get("clear_and_collect", False))
    out["win_conditions"] = win

    out.setdefault("timers", {})
    return out


def _normalize_document(doc: Dict[str, Any]) -> Dict[str, Any]:
    schema_v = int(doc.get("schema_version") or 1)
    profiles_in = doc.get("profiles")
    if not isinstance(profiles_in, dict):
        raise GameplayProfileCatalogError("profiles must be an object")

    raw_profiles: Dict[str, Dict[str, Any]] = {}
    for key, val in profiles_in.items():
        pid = str(key).strip()
        if not pid or not _PROFILE_ID_RE.match(pid):
            continue
        if not isinstance(val, dict):
            raise GameplayProfileCatalogError(f"profiles.{pid} must be an object")
        row = _parse_profile_row(val, pid)
        if str(row.get("id") or pid) != pid:
            row["id"] = pid
        raw_profiles[pid] = row

    if _DEFAULT_PROFILE_ID not in raw_profiles:
        raise GameplayProfileCatalogError(f"Default profile {_DEFAULT_PROFILE_ID!r} is required")

    resolved_profiles: Dict[str, Dict[str, Any]] = {}
    for pid in raw_profiles:
        resolved_profiles[pid] = _apply_defaults(_resolve_extends_chain(pid, raw_profiles))

    return {"schema_version": schema_v, "profiles": resolved_profiles}


def _compute_revision(canonical: Dict[str, Any]) -> str:
    blob = json.dumps(canonical, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(blob).hexdigest()


def load_raw_document() -> Dict[str, Any]:
    path_env = (os.getenv("DUTCH_GAMEPLAY_PROFILES_PATH") or "").strip()
    path = Path(path_env) if path_env else _DEFAULT_JSON_PATH
    doc = _read_json_file(path)
    if doc is None:
        doc = _read_json_file(_DEFAULT_JSON_PATH)
    if doc is None:
        raise GameplayProfileCatalogError("gameplay_profiles.json not found")
    return doc


_CANONICAL_DOC = _normalize_document(load_raw_document())
GAMEPLAY_PROFILES_DOCUMENT: Dict[str, Any] = _CANONICAL_DOC
GAMEPLAY_PROFILES_REVISION: str = _compute_revision(_CANONICAL_DOC)
_PROFILES_BY_ID: Dict[str, Dict[str, Any]] = {
    str(p["id"]): dict(p)
    for p in (_CANONICAL_DOC.get("profiles") or {}).values()
    if isinstance(p, dict) and str(p.get("id") or "").strip()
}


def default_profile_id() -> str:
    return _DEFAULT_PROFILE_ID


def profile_ids() -> Tuple[str, ...]:
    return tuple(_PROFILES_BY_ID.keys())


def resolve_profile(profile_id: Optional[str]) -> Dict[str, Any]:
    """Return fully merged profile snapshot (copy). Uses default when id omitted."""
    pid = (profile_id or "").strip() or _DEFAULT_PROFILE_ID
    row = _PROFILES_BY_ID.get(pid)
    if row is None:
        raise GameplayProfileCatalogError(f"Unknown gameplay profile: {pid!r}")
    return deepcopy(row)


def validate_special_event_profile_refs(special_events: List[Dict[str, Any]]) -> None:
    """Raise if any special event references an unknown gameplay_profile_id."""
    for ev in special_events:
        if not isinstance(ev, dict):
            continue
        raw = ev.get("gameplay_profile_id")
        if raw is None or str(raw).strip() == "":
            continue
        pid = str(raw).strip()
        if pid not in _PROFILES_BY_ID:
            raise GameplayProfileCatalogError(
                f"special_events.{ev.get('id')}: unknown gameplay_profile_id {pid!r}"
            )


def build_client_gameplay_profiles_payload() -> Dict[str, Any]:
    """Client-facing document (resolved profiles, no extends)."""
    profiles = _CANONICAL_DOC.get("profiles") or {}
    return {
        "schema_version": _CANONICAL_DOC.get("schema_version", 1),
        "profiles": deepcopy(profiles),
    }


def reload_from_disk() -> Dict[str, Any]:
    """Re-read gameplay_profiles.json and refresh in-process caches."""
    global _CANONICAL_DOC, GAMEPLAY_PROFILES_REVISION

    previous_revision = GAMEPLAY_PROFILES_REVISION
    raw = load_raw_document()
    doc = _normalize_document(raw)
    new_index = {
        str(p["id"]): dict(p)
        for p in (doc.get("profiles") or {}).values()
        if isinstance(p, dict) and str(p.get("id") or "").strip()
    }
    new_revision = _compute_revision(doc)

    GAMEPLAY_PROFILES_DOCUMENT.clear()
    GAMEPLAY_PROFILES_DOCUMENT.update(doc)
    _CANONICAL_DOC = GAMEPLAY_PROFILES_DOCUMENT
    GAMEPLAY_PROFILES_REVISION = new_revision
    _PROFILES_BY_ID.clear()
    _PROFILES_BY_ID.update(new_index)

    from . import table_tiers_catalog as ttc

    ttc.validate_special_event_profile_refs()

    return {
        "reloaded": previous_revision != new_revision,
        "previous_revision": previous_revision,
        "revision": new_revision,
        "profile_count": len(_PROFILES_BY_ID),
    }
