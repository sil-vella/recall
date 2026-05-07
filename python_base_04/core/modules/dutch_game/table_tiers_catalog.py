"""
Declarative Dutch room table tiers — single SSOT JSON + optional env overlay.

Top-level keys:
  - ``tiers``: standard room table tiers (levels, fees, styles).
  - ``special_events``: optional special-event / match presets (distinct string ``id``, not tier levels).
    Optional ``metadata.rewards`` is surfaced as ``rewards_parsed`` after placeholder normalization.

Produces maps used by tier_rank_level_matcher and a stable revision/hash for Flutter sync.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
from copy import deepcopy
from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Tuple
from urllib.parse import quote


def coerce_reward_entry_placeholder(raw: Any) -> Optional[Dict[str, Any]]:
    """
    Placeholder: coerce one reward blob from declarative JSON for downstream use.

    Future: enforce a schema (e.g. coin amount int, achievement id whitelist), localize labels.
    """
    if isinstance(raw, dict):
        # Shallow normalized copy — extend with typed fields later.
        return {str(k): v for k, v in raw.items()}
    return None


def normalize_special_event_rewards_payload(raw: Any) -> List[Dict[str, Any]]:
    """
    Placeholder: expand ``metadata.rewards`` shapes into a list of homogeneous dicts.

    Accepts:

    - A single object (common): ``{"coins": "100", "achievement": "..."}``.
    - A list of objects: ``[{"type": "coins", "amount": 100}, ...]``.
    """
    out: List[Dict[str, Any]] = []
    if raw is None:
        return out
    if isinstance(raw, dict):
        rd = coerce_reward_entry_placeholder(raw)
        if rd is not None:
            out.append(rd)
        return out
    if isinstance(raw, list):
        for entry in raw:
            rd = coerce_reward_entry_placeholder(entry)
            if rd is not None:
                out.append(rd)
    return out


def extract_rewards_from_event_metadata_placeholder(
    metadata: Optional[Mapping[str, Any]],
) -> List[Dict[str, Any]]:
    """Reads ``metadata[\"rewards\"]`` and delegates to ``normalize_special_event_rewards_payload``."""
    if not isinstance(metadata, Mapping):
        return []
    raw = metadata.get("rewards")
    return normalize_special_event_rewards_payload(raw)


_CONFIG_DIR = Path(__file__).resolve().parent / "config"
_DEFAULT_JSON_PATH = _CONFIG_DIR / "table_tiers.json"

_EVENT_ID_RE = re.compile(r"^[A-Za-z0-9_-]+$")


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
    raw = (os.getenv("DUTCH_TABLES_JSON") or "").strip()
    if not raw:
        return doc
    try:
        overlay = json.loads(raw)
        if not isinstance(overlay, dict):
            return doc
    except Exception:
        return doc

    out = deepcopy(doc)
    tiers_list: List[Dict[str, Any]] = list(out.get("tiers") or [])
    if not isinstance(out.get("tiers"), list):
        tiers_list = []

    level_index: Dict[int, int] = {}
    for i, row in enumerate(tiers_list):
        if isinstance(row, dict) and isinstance(row.get("level"), int):
            level_index[row["level"]] = i

    for k, v in overlay.items():
        try:
            lvl = int(k)
        except (TypeError, ValueError):
            continue
        if not isinstance(v, dict):
            continue
        title = str(v.get("title", "")).strip()
        fee_raw = v.get("coin_fee")
        try:
            fee = int(fee_raw)
        except (TypeError, ValueError):
            continue
        try:
            min_ul = int(v.get("min_user_level", lvl))
        except (TypeError, ValueError):
            min_ul = lvl
        if not title:
            continue
        merged = {"level": lvl, "title": title, "coin_fee": fee, "min_user_level": min_ul}
        if isinstance(v.get("style"), dict):
            merged["style"] = v["style"]
        if lvl in level_index:
            idx = level_index[lvl]
            prev = tiers_list[idx]
            if isinstance(prev.get("style"), dict) and "style" not in merged:
                merged["style"] = deepcopy(prev["style"])
            tiers_list[idx] = merged
        else:
            tiers_list.append(merged)
            level_index[lvl] = len(tiers_list) - 1

    out["tiers"] = tiers_list
    return out


def _finalize_row_style(level: int, raw_style: Any) -> Dict[str, Any]:
    """Ensures packaged table back-graphic filenames are present when omitted from declarative JSON."""
    defaults: Dict[int, str] = {
        1: "home-table-backgraphic_002.webp",
        2: "local-table-backgraphic.webp",
        3: "town-table-backgraphic.webp",
        4: "city-table-backgraphic.webp",
    }
    st = dict(raw_style) if isinstance(raw_style, dict) else {}
    st.setdefault("back_graphic_file", defaults.get(level, ""))
    return st


def _finalize_event_style(raw_style: Any) -> Dict[str, Any]:
    """Optional ``style`` for a special-event row (same ``back_graphic_file`` URLs as tiers; no tier-level defaults)."""
    if isinstance(raw_style, dict):
        return dict(raw_style)
    return {}


def _normalize_special_events(raw: Any) -> List[Dict[str, Any]]:
    """Decl. list keyed by stable string ``id`` (``event_id`` accepted as alias); optional fee, gates, nested ``metadata``."""
    if not isinstance(raw, list):
        return []
    out: List[Dict[str, Any]] = []
    seen: set[str] = set()
    for item in raw:
        if not isinstance(item, dict):
            continue
        eid_raw = item.get("id")
        if eid_raw is None or str(eid_raw).strip() == "":
            eid_raw = item.get("event_id")
        eid = str(eid_raw or "").strip()
        if not eid or not _EVENT_ID_RE.match(eid) or eid in seen:
            continue
        title = str(item.get("title") or "").strip()
        if not title:
            continue
        seen.add(eid)
        row: Dict[str, Any] = {"id": eid, "title": title}
        desc = str(item.get("description") or "").strip()
        if desc:
            row["description"] = desc
        if "coin_fee" in item:
            try:
                cf = int(item["coin_fee"])
            except (TypeError, ValueError):
                cf = None
            if cf is not None and cf >= 0:
                row["coin_fee"] = cf
        if "min_user_level" in item:
            try:
                mul = int(item["min_user_level"])
            except (TypeError, ValueError):
                mul = None
            if mul is not None and mul >= 1:
                row["min_user_level"] = mul
        meta = item.get("metadata")
        if isinstance(meta, dict):
            row["metadata"] = deepcopy(meta)
            rewards_parsed = extract_rewards_from_event_metadata_placeholder(meta)
            if rewards_parsed:
                row["rewards_parsed"] = rewards_parsed
        style = _finalize_event_style(item.get("style"))
        if style:
            row["style"] = style
        out.append(row)
    return out


def _normalize_document(doc: Dict[str, Any]) -> Tuple[Dict[str, Any], List[int]]:
    """Returns (canonical_doc, ordered_levels preserving tiers array order)."""
    schema_v = int(doc.get("schema_version") or 1)
    special_events_out = _normalize_special_events(doc.get("special_events"))
    tiers_in = doc.get("tiers")
    if not isinstance(tiers_in, list):
        return {"schema_version": schema_v, "tiers": [], "special_events": special_events_out}, []
    tiers_out: List[Dict[str, Any]] = []
    order: List[int] = []
    seen: Dict[int, int] = {}
    for raw in tiers_in:
        if not isinstance(raw, dict):
            continue
        try:
            lvl = int(raw["level"])
        except (KeyError, TypeError, ValueError):
            continue
        title = str(raw.get("title", "")).strip()
        try:
            fee = int(raw["coin_fee"])
        except (KeyError, TypeError, ValueError):
            continue
        try:
            min_ul = int(raw.get("min_user_level", lvl))
        except (TypeError, ValueError):
            min_ul = lvl
        if not title or fee < 1 or lvl < 1 or min_ul < 1:
            continue
        if lvl in seen:
            tiers_out[seen[lvl]] = {
                "level": lvl,
                "title": title,
                "coin_fee": fee,
                "min_user_level": min_ul,
                "style": _finalize_row_style(lvl, raw.get("style")),
            }
            continue
        seen[lvl] = len(tiers_out)
        order.append(lvl)
        row: Dict[str, Any] = {
            "level": lvl,
            "title": title,
            "coin_fee": fee,
            "min_user_level": min_ul,
        }
        row["style"] = _finalize_row_style(lvl, raw.get("style"))
        tiers_out.append(row)

    return {"schema_version": schema_v, "tiers": tiers_out, "special_events": special_events_out}, order


def _compute_revision(canonical: Dict[str, Any]) -> str:
    blob = json.dumps(canonical, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(blob).hexdigest()


def load_raw_document() -> Dict[str, Any]:
    """
    Load table tiers document: file (DUTCH_TABLE_TIERS_PATH or package default), then DUTCH_TABLES_JSON overlay.
    """
    path_env = (os.getenv("DUTCH_TABLE_TIERS_PATH") or "").strip()
    path = Path(path_env) if path_env else _DEFAULT_JSON_PATH
    doc = _read_json_file(path)
    if doc is None:
        doc = _read_json_file(_DEFAULT_JSON_PATH) or {
            "schema_version": 1,
            "tiers": [],
            "special_events": [],
        }
    return _merge_env_overlay(doc)


_CANONICAL_DOC, _LEVEL_ORDER_LIST = _normalize_document(load_raw_document())
TABLE_TIERS_DOCUMENT: Dict[str, Any] = _CANONICAL_DOC
TABLE_TIERS_REVISION: str = _compute_revision(_CANONICAL_DOC)
LEVEL_ORDER: Tuple[int, ...] = tuple(_LEVEL_ORDER_LIST)
LEVEL_TO_TITLE: Dict[int, str] = {t["level"]: t["title"] for t in _CANONICAL_DOC.get("tiers", []) if isinstance(t, dict)}
LEVEL_TO_COIN_FEE: Dict[int, int] = {t["level"]: t["coin_fee"] for t in _CANONICAL_DOC.get("tiers", []) if isinstance(t, dict)}
LEVEL_TO_MIN_USER_LEVEL: Dict[int, int] = {
    t["level"]: t["min_user_level"] for t in _CANONICAL_DOC.get("tiers", []) if isinstance(t, dict)
}


def _inject_style_back_graphic_url(style: Dict[str, Any], base: str) -> None:
    existing = str(style.get("back_graphic_url") or "").strip()
    if existing.startswith(("http://", "https://")):
        return
    b = base.strip().rstrip("/")
    if not b:
        return
    fn = str(style.get("back_graphic_file") or "").strip()
    if not fn:
        return
    slug = quote(Path(fn).name, safe=".")
    style["back_graphic_url"] = f"{b}/public/dutch/table-tier-back/{slug}"
    style.pop("back_graphic_file", None)


def _inject_end_match_modal_background_url(modal: Dict[str, Any], base: str) -> None:
    """Adds ``background_image_url`` from packaged filename (same public path as tier back-graphics)."""
    existing = str(modal.get("background_image_url") or "").strip()
    if existing.startswith(("http://", "https://")):
        return
    b = base.strip().rstrip("/")
    if not b:
        return
    fn = str(modal.get("background_image_file") or "").strip()
    if not fn:
        return
    slug = quote(Path(fn).name, safe=".")
    modal["background_image_url"] = f"{b}/public/dutch/table-tier-back/{slug}"
    modal.pop("background_image_file", None)


def build_client_table_tiers_payload(public_base_url: str) -> Dict[str, Any]:
    """
    Payload for Flutter (includes absolute back_graphic_url), without mutating SERVER canonical revision.

    - Resolves filenames from canonical style.back_graphic_file (or CDN back_graphic_url if already absolute).
    - Applies to ``special_events[].metadata.end_match_modal`` (``background_image_file`` → URL).
    - Set DUTCH_PUBLIC_API_BASE (or PUBLIC_APP_URL) when Flask is behind a reverse proxy where request.url_root is wrong.
    """
    doc = deepcopy(TABLE_TIERS_DOCUMENT)
    base = public_base_url.strip().rstrip("/")
    for t in doc.get("tiers") or []:
        if not isinstance(t, dict):
            continue
        st = t.get("style")
        if not isinstance(st, dict):
            continue
        _inject_style_back_graphic_url(st, base)
    for ev in doc.get("special_events") or []:
        if not isinstance(ev, dict):
            continue
        est = ev.get("style")
        if isinstance(est, dict):
            _inject_style_back_graphic_url(est, base)
        meta = ev.get("metadata")
        if isinstance(meta, dict):
            em = meta.get("end_match_modal")
            if isinstance(em, dict):
                _inject_end_match_modal_background_url(em, base)
    return doc
