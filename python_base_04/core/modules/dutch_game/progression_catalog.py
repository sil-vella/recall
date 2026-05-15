"""
Declarative Dutch progression — rank hierarchy, wins→level→rank rules, subscription tiers.

Single source of truth:
  - config/progression_config.json
  - optional env override via DUTCH_PROGRESSION_JSON / DUTCH_PROGRESSION_PATH
"""

from __future__ import annotations

import hashlib
import json
import os
from copy import deepcopy
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

_CONFIG_DIR = Path(__file__).resolve().parent / "config"
_DEFAULT_JSON_PATH = _CONFIG_DIR / "progression_config.json"

_DEFAULT_RANK_HIERARCHY = (
    "beginner,novice,apprentice,skilled,advanced,expert,veteran,master,elite,legend"
)
_VALID_DIFFICULTIES = frozenset({"easy", "medium", "hard", "expert"})


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
    raw = (os.getenv("DUTCH_PROGRESSION_JSON") or "").strip()
    if not raw:
        return doc
    try:
        overlay = json.loads(raw)
    except Exception:
        return doc
    if not isinstance(overlay, dict):
        return doc
    out = deepcopy(doc)
    for key in (
        "schema_version",
        "progression",
        "rank_hierarchy",
        "rank_matchmaking",
        "rank_to_difficulty",
        "subscription_tiers",
        "defaults",
    ):
        if key in overlay:
            out[key] = overlay[key]
    return out


def _parse_levels_per_rank_map(
    prog: Dict[str, Any],
    rank_hierarchy: List[str],
    *,
    default_span: int,
) -> Dict[str, int]:
    """Per-rank user-level span before advancing to the next rank tier."""
    raw = prog.get("levels_per_rank")
    out: Dict[str, int] = {}
    if isinstance(raw, dict):
        for rank in rank_hierarchy:
            val = raw.get(rank)
            try:
                span = max(1, int(val)) if val is not None else default_span
            except (TypeError, ValueError):
                span = default_span
            out[rank] = span
        return out
    if isinstance(raw, int):
        span = max(1, int(raw))
        return {rank: span for rank in rank_hierarchy}
    try:
        env_span = max(1, int(os.getenv("DUTCH_LEVELS_PER_RANK", str(default_span))))
    except (TypeError, ValueError):
        env_span = default_span
    return {rank: env_span for rank in rank_hierarchy}


def _parse_rank_hierarchy(raw: Any) -> List[str]:
    if isinstance(raw, list):
        out = [str(x).strip().lower() for x in raw if str(x).strip()]
        return out
    if isinstance(raw, str):
        return [x.strip().lower() for x in raw.split(",") if x.strip()]
    env = (os.getenv("DUTCH_RANK_HIERARCHY") or _DEFAULT_RANK_HIERARCHY).strip()
    return [x.strip().lower() for x in env.split(",") if x.strip()]


def _normalize_document(doc: Dict[str, Any]) -> Dict[str, Any]:
    schema_version = int(doc.get("schema_version") or 1)
    prog = doc.get("progression") if isinstance(doc.get("progression"), dict) else {}

    def _int_prog(key: str, env_key: str, default: int) -> int:
        raw = prog.get(key)
        if raw is not None:
            try:
                return max(0 if key == "user_level_min" else 1, int(raw))
            except (TypeError, ValueError):
                pass
        try:
            return max(0 if key == "user_level_min" else 1, int(os.getenv(env_key, str(default))))
        except (TypeError, ValueError):
            return default

    user_level_min = _int_prog("user_level_min", "DUTCH_USER_LEVEL_MIN", 1)
    wins_per_user_level = _int_prog("wins_per_user_level", "DUTCH_WINS_PER_USER_LEVEL", 10)
    default_levels_per_rank = 5
    try:
        default_levels_per_rank = max(
            1, int(os.getenv("DUTCH_LEVELS_PER_RANK", "5"))
        )
    except (TypeError, ValueError):
        pass

    rank_hierarchy = _parse_rank_hierarchy(doc.get("rank_hierarchy"))
    if not rank_hierarchy:
        rank_hierarchy = _parse_rank_hierarchy(None)

    levels_per_rank_map = _parse_levels_per_rank_map(
        prog, rank_hierarchy, default_span=default_levels_per_rank
    )

    matchmaking = doc.get("rank_matchmaking") if isinstance(doc.get("rank_matchmaking"), dict) else {}
    try:
        max_rank_delta = int(matchmaking.get("max_rank_delta", 1))
    except (TypeError, ValueError):
        max_rank_delta = 1
    max_rank_delta = max(0, max_rank_delta)

    raw_rtd = doc.get("rank_to_difficulty") if isinstance(doc.get("rank_to_difficulty"), dict) else {}
    rank_to_difficulty: Dict[str, str] = {}
    for rank in rank_hierarchy:
        d = str(raw_rtd.get(rank, "medium")).strip().lower()
        if d not in _VALID_DIFFICULTIES:
            d = "medium"
        rank_to_difficulty[rank] = d

    raw_tiers = doc.get("subscription_tiers")
    if isinstance(raw_tiers, list) and raw_tiers:
        subscription_tiers = tuple(str(t).strip().lower() for t in raw_tiers if str(t).strip())
    else:
        subscription_tiers = ("promotional", "regular", "premium")

    defaults = doc.get("defaults") if isinstance(doc.get("defaults"), dict) else {}
    default_rank = str(defaults.get("rank") or "beginner").strip().lower()
    if default_rank not in rank_hierarchy:
        default_rank = rank_hierarchy[0] if rank_hierarchy else "beginner"
    try:
        default_user_level = int(defaults.get("user_level", 1))
    except (TypeError, ValueError):
        default_user_level = 1
    default_sub = str(defaults.get("subscription_tier") or "promotional").strip().lower()
    if default_sub not in subscription_tiers:
        default_sub = subscription_tiers[0] if subscription_tiers else "promotional"

    return {
        "schema_version": schema_version,
        "progression": {
            "user_level_min": user_level_min,
            "wins_per_user_level": wins_per_user_level,
            "levels_per_rank": levels_per_rank_map,
        },
        "rank_hierarchy": rank_hierarchy,
        "rank_matchmaking": {"max_rank_delta": max_rank_delta},
        "rank_to_difficulty": rank_to_difficulty,
        "subscription_tiers": list(subscription_tiers),
        "defaults": {
            "rank": default_rank,
            "user_level": default_user_level,
            "subscription_tier": default_sub,
        },
    }


def _compute_revision(canonical: Dict[str, Any]) -> str:
    blob = json.dumps(canonical, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(blob).hexdigest()


def _load_raw_document() -> Dict[str, Any]:
    path_env = (os.getenv("DUTCH_PROGRESSION_PATH") or "").strip()
    path = Path(path_env) if path_env else _DEFAULT_JSON_PATH
    doc = _read_json_file(path)
    if doc is None:
        doc = _read_json_file(_DEFAULT_JSON_PATH) or {}
    return _merge_env_overlay(doc)


_CANONICAL_DOC = _normalize_document(_load_raw_document())
PROGRESSION_CONFIG_DOCUMENT: Dict[str, Any] = _CANONICAL_DOC
PROGRESSION_CONFIG_REVISION: str = _compute_revision(_CANONICAL_DOC)

_prog = _CANONICAL_DOC["progression"]
USER_LEVEL_MIN: int = int(_prog["user_level_min"])
WINS_PER_USER_LEVEL: int = int(_prog["wins_per_user_level"])
LEVELS_PER_RANK_MAP: Dict[str, int] = dict(_prog["levels_per_rank"])
RANK_HIERARCHY: Tuple[str, ...] = tuple(_CANONICAL_DOC["rank_hierarchy"])
LEVELS_PER_RANK_BY_RANK: Tuple[int, ...] = tuple(
    LEVELS_PER_RANK_MAP.get(rank, 5) for rank in RANK_HIERARCHY
)
# Uniform default span (first tier); env/playbook fallback when only scalar is configured.
LEVELS_PER_RANK: int = LEVELS_PER_RANK_BY_RANK[0] if LEVELS_PER_RANK_BY_RANK else 5
RANK_TO_DIFFICULTY: Dict[str, str] = dict(_CANONICAL_DOC["rank_to_difficulty"])
SUBSCRIPTION_TIERS: Tuple[str, ...] = tuple(_CANONICAL_DOC["subscription_tiers"])
RANK_MATCHMAKING_MAX_DELTA: int = int(_CANONICAL_DOC["rank_matchmaking"]["max_rank_delta"])

_defaults = _CANONICAL_DOC["defaults"]
DEFAULT_RANK: str = str(_defaults["rank"])
DEFAULT_USER_LEVEL: int = int(_defaults["user_level"])
DEFAULT_SUBSCRIPTION_TIER: str = str(_defaults["subscription_tier"])

RANK_VARIATIONS: Dict[str, str] = {r: r for r in RANK_HIERARCHY}


def build_client_progression_payload() -> Dict[str, Any]:
    return deepcopy(PROGRESSION_CONFIG_DOCUMENT)


def rank_to_difficulty(rank: Optional[str], default: str = "medium") -> str:
    n = (rank or "").strip().lower()
    if n in RANK_TO_DIFFICULTY:
        return RANK_TO_DIFFICULTY[n]
    if n in RANK_HIERARCHY:
        return default
    return default


def levels_per_rank_for(rank: Optional[str]) -> int:
    """User levels spent in a given rank tier before advancing (defaults to LEVELS_PER_RANK)."""
    n = (rank or "").strip().lower()
    if n in LEVELS_PER_RANK_MAP:
        return max(1, int(LEVELS_PER_RANK_MAP[n]))
    return LEVELS_PER_RANK


def user_level_to_rank_index(user_level: Optional[int]) -> int:
    """Map user progression level to index in RANK_HIERARCHY using per-rank spans."""
    if user_level is None:
        return 0
    try:
        lv = int(user_level)
    except (TypeError, ValueError):
        return 0
    lv = max(USER_LEVEL_MIN, lv)
    if not RANK_HIERARCHY:
        return 0
    max_idx = len(RANK_HIERARCHY) - 1
    offset = 0
    for i, span in enumerate(LEVELS_PER_RANK_BY_RANK):
        step = max(1, int(span))
        if lv <= offset + step:
            return min(i, max_idx)
        offset += step
    return max_idx


def user_level_to_rank(user_level: Optional[int]) -> str:
    return RANK_HIERARCHY[user_level_to_rank_index(user_level)]
