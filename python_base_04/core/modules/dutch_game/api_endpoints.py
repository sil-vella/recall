import json
import os
from datetime import datetime, timedelta, timezone
from typing import Dict, Any, Optional, Tuple, List
from pathlib import Path
from urllib.parse import unquote
from flask import Blueprint, request, jsonify, send_file
from core.managers.jwt_manager import JWTManager, TokenType
from core.modules.user_management_module import tier_rank_level_matcher as matcher
from tools.logger.custom_logging import custom_log
from bson import ObjectId
from pymongo.errors import DuplicateKeyError
import time
import random
import re
import uuid

from . import dutch_notifications
from . import table_tiers_catalog as ttc
from . import consumables_catalog as cc
from .wins_level_rank_matcher import WinsLevelRankMatcher
from .dutch_achievement_catalog import (
    achievements_unlocked_ids_sorted,
    compute_new_unlocks,
    next_win_streak,
    parse_stored_streak,
    unlocked_achievement_ids_from_dutch_game,
)

dutch_api = Blueprint('dutch_api', __name__)

# Logging switch for this module
LOGGING_SWITCH = True  # Dutch API + leaderboards (period-wins, snapshots, match_win_outcomes) — see .cursor/rules/enable-logging-switch.mdc

# Prometheus/Grafana not used – game events do not update metrics
METRICS_SWITCH = False

# Per-match win facts for time-bounded leaderboards (insert-only; idempotent via unique index).
MATCH_WIN_OUTCOMES_COLL = "dutch_match_win_outcomes"
CONSUMABLE_TX_COLL = "dutch_consumable_transactions"

BOOSTER_MULTIPLIER = 1.5
BOOSTER_ITEM_ID = cc.primary_win_booster_key()

# Store app_manager reference (will be set by module)
_app_manager = None
SPONSORS_MEDIA_DIR = Path(__file__).resolve().parents[4] / "sponsors" / "media"

# Packaged tier back-graphics (WebP preferred). Served at /public/dutch/table-tier-back/<filename>.
TABLE_TIER_BACKGRAPHICS_DIR = Path(__file__).resolve().parent / "static" / "table_backgraphics"
_BG_EXT_TO_MIME = {
    ".webp": "image/webp",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
}


def _resolve_public_api_base() -> str:
    """HTTPS origin clients use when downloading tier images — set behind reverse proxy via DUTCH_PUBLIC_API_BASE."""
    env = (
        (os.getenv("DUTCH_PUBLIC_API_BASE") or "").strip().rstrip("/")
        or (os.getenv("PUBLIC_APP_URL") or "").strip().rstrip("/")
    )
    if env:
        return env
    return (request.url_root or "").rstrip("/")


def _table_design_overlay_path_from_skin_id(skin_id: str) -> Optional[Path]:
    """
    New media layout:
    sponsors/media/table_design/<pack_name>/table_design_overlay_<pack_name>.webp
    """
    sid = (skin_id or "").strip()
    if not sid.startswith("table_design_"):
        return None
    pack_name = sid.replace("table_design_", "", 1).strip().lower()
    if not pack_name:
        return None
    return SPONSORS_MEDIA_DIR / "table_design" / pack_name / f"table_design_overlay_{pack_name}.webp"


def _card_back_path_from_skin_id(skin_id: str) -> Optional[Path]:
    """
    New media layout:
    sponsors/media/card_back/<pack_name>/card_back_<pack_name>.webp
    """
    sid = (skin_id or "").strip()
    if not sid.startswith("card_back_"):
        return None
    pack_name = sid.replace("card_back_", "", 1).strip().lower()
    if not pack_name:
        return None
    return SPONSORS_MEDIA_DIR / "card_back" / pack_name / f"card_back_{pack_name}.webp"


def set_app_manager(app_manager):
    """Set app manager for database access"""
    global _app_manager
    _app_manager = app_manager


def _ensure_consumable_indexes(db_manager) -> None:
    """Create minimal consumable transaction indexes (idempotent)."""
    try:
        coll = db_manager.db[CONSUMABLE_TX_COLL]
        coll.create_index([("user_id", 1), ("created_at", -1)])
        coll.create_index([("idempotency_key", 1)], unique=True, sparse=True)
    except Exception as e:
        custom_log(f"📊 DutchGame: consumable index ensure (non-fatal): {e}", level="WARNING", isOn=LOGGING_SWITCH)


def _default_inventory() -> Dict[str, Any]:
    boosters = {k: 0 for k in cc.booster_inventory_keys()}
    return {
        "boosters": boosters,
        "cosmetics": {
            "owned_card_backs": [],
            "owned_table_designs": [],
            "equipped": {"card_back_id": "", "table_design_id": ""},
        },
    }


def _normalize_inventory(raw: Any) -> Dict[str, Any]:
    inv = _default_inventory()
    if not isinstance(raw, dict):
        return inv
    boosters = raw.get("boosters")
    if isinstance(boosters, dict):
        for bkey in cc.booster_inventory_keys():
            try:
                inv["boosters"][bkey] = max(0, int(boosters.get(bkey, 0) or 0))
            except Exception:
                inv["boosters"][bkey] = 0
    cosmetics = raw.get("cosmetics")
    if isinstance(cosmetics, dict):
        backs = cosmetics.get("owned_card_backs")
        tables = cosmetics.get("owned_table_designs")
        eq = cosmetics.get("equipped")
        if isinstance(backs, list):
            inv["cosmetics"]["owned_card_backs"] = [str(x) for x in backs if str(x).strip()]
        if isinstance(tables, list):
            inv["cosmetics"]["owned_table_designs"] = [str(x) for x in tables if str(x).strip()]
        if isinstance(eq, dict):
            inv["cosmetics"]["equipped"]["card_back_id"] = str(eq.get("card_back_id", "") or "")
            inv["cosmetics"]["equipped"]["table_design_id"] = str(eq.get("table_design_id", "") or "")
    return inv


def _dutch_game_with_inventory(user: Dict[str, Any]) -> Dict[str, Any]:
    modules = user.get("modules", {})
    dutch_game = dict(modules.get("dutch_game", {}) or {})
    dutch_game["inventory"] = _normalize_inventory(dutch_game.get("inventory"))
    return dutch_game


def _find_catalog_item(item_id: str) -> Optional[Dict[str, Any]]:
    return cc.find_item(item_id, active_only=True)


def _insert_consumable_tx(db_manager, *, user_id: ObjectId, tx_type: str, payload: Dict[str, Any], idempotency_key: Optional[str] = None) -> Dict[str, Any]:
    _ensure_consumable_indexes(db_manager)
    doc = {
        "user_id": user_id,
        "tx_type": tx_type,
        "payload": payload,
        "created_at": datetime.utcnow(),
    }
    if idempotency_key:
        doc["idempotency_key"] = idempotency_key
    try:
        res = db_manager.db[CONSUMABLE_TX_COLL].insert_one(doc)
        return {"ok": True, "tx_id": str(res.inserted_id)}
    except DuplicateKeyError:
        return {"ok": True, "duplicate": True}


def _compute_boosted_win_amount(base_win_coins: int, has_booster: bool) -> Tuple[int, float, int]:
    """Return (final_win_coins, multiplier, bonus_from_booster)."""
    base = max(0, int(base_win_coins or 0))
    if not has_booster or base <= 0:
        return base, 1.0, 0
    final_total = int(round(base * BOOSTER_MULTIPLIER))
    bonus = max(0, final_total - base)
    return base + bonus, BOOSTER_MULTIPLIER, bonus


def _enrich_td_out_from_tournament_doc(db_manager, tournament_oid: ObjectId, td_out: Dict[str, Any]) -> Dict[str, Any]:
    """Merge type, format, and matches[] from DB into rematch / snapshot tournament_data for clients."""
    doc = db_manager.find_one("tournaments", {"_id": tournament_oid})
    if not doc:
        return td_out
    full = _tournament_doc_to_json(doc)
    out = dict(td_out)
    out["type"] = full.get("type")
    out["format"] = full.get("format")
    out["matches"] = full.get("matches") or []
    return out


def _tournament_doc_to_json(doc: Dict[str, Any]) -> Dict[str, Any]:
    """Return a JSON-serializable copy of a tournament document (ObjectId -> str)."""
    if not doc:
        return {}
    out = {}
    for k, v in doc.items():
        if isinstance(v, ObjectId):
            out[k] = str(v)
        elif isinstance(v, dict):
            out[k] = _tournament_doc_to_json(v)
        elif isinstance(v, list):
            out[k] = []
            for x in v:
                if isinstance(x, ObjectId):
                    out[k].append(str(x))
                elif isinstance(x, dict):
                    out[k].append(_tournament_doc_to_json(x))
                else:
                    out[k].append(x)
        else:
            out[k] = v
    return out


def _tournament_json_for_public(obj: Any) -> Any:
    """Strip PII from serialized tournament trees for unauthenticated clients (e.g. match player emails)."""
    if isinstance(obj, dict):
        return {
            k: _tournament_json_for_public(v)
            for k, v in obj.items()
            if k != "email"
        }
    if isinstance(obj, list):
        return [_tournament_json_for_public(x) for x in obj]
    return obj


def _require_admin():
    """If current user is not admin, return (response, status_code). Else return (None, None)."""
    if not request.user_id:
        return jsonify({"success": False, "error": "Not authenticated"}), 401
    if not _app_manager:
        return jsonify({"success": False, "error": "Server not initialized"}), 503
    db_manager = _app_manager.get_db_manager(role="read_only")
    if not db_manager:
        return jsonify({"success": False, "error": "Database unavailable"}), 503
    try:
        user_oid = ObjectId(request.user_id) if isinstance(request.user_id, str) else request.user_id
        user = db_manager.find_one("users", {"_id": user_oid})
    except Exception:
        user = None
    if not user or user.get("role") != "admin":
        return jsonify({"success": False, "error": "Admin role required"}), 403
    return None, None


@dutch_api.route('/service/auth/validate', methods=['POST'])
def service_validate_token():
    """Validate JWT from Dart backend. Requires X-Service-Key (enforced by app_manager). Same body/response as public endpoint."""
    return _validate_token_impl()

@dutch_api.route('/api/auth/validate', methods=['POST'])
def validate_token():
    """Validate JWT token (legacy public). Prefer /service/auth/validate with X-Service-Key for Dart backend."""
    return _validate_token_impl()

def _validate_token_impl():
    """Shared JWT validation logic. POST body: { token: userJwt }. Returns JSON response."""
    custom_log("🔐 API: Token validation request received", level="INFO", isOn=LOGGING_SWITCH)
    custom_log("🔐 API: Blueprint loaded and endpoint hit!", level="INFO", isOn=LOGGING_SWITCH)
    
    try:
        data = request.get_json()
        custom_log(f"📦 API: Request data: {data}", level="DEBUG", isOn=LOGGING_SWITCH)
        
        token = data.get('token')
        
        if not token:
            custom_log("❌ API: No token provided in request", level="WARNING", isOn=LOGGING_SWITCH)
            return jsonify({
                'valid': False,
                'error': 'No token provided'
            }), 400
        
        custom_log(f"🔍 API: Validating token: {token[:20]}...", level="INFO", isOn=LOGGING_SWITCH)
        
        jwt_manager = JWTManager()
        # When Dart backend calls with valid X-Service-Key, skip Redis revoke check (token may not be in Redis)
        skip_revoke = getattr(request, 'service_authenticated', False)
        if skip_revoke:
            custom_log("🔐 API: Service-authenticated request, skipping Redis revoke check", level="INFO", isOn=LOGGING_SWITCH)
        try:
            payload = jwt_manager.verify_token(token, skip_revoke=skip_revoke)
            
            if payload is None:
                custom_log("❌ API: Token validation returned None (invalid/expired/revoked)", level="WARNING", isOn=LOGGING_SWITCH)
                return jsonify({
                    'valid': False,
                    'error': 'Invalid or expired token'
                }), 401
            
            user_id = payload.get('user_id')
            
            custom_log(f"✅ API: Token validation successful for user: {user_id}", level="INFO", isOn=LOGGING_SWITCH)
            
            # Fetch user rank, level, account_type, and role from database
            rank = None
            level = None
            account_type = None
            username = None
            user_role = None
            if _app_manager and user_id:
                try:
                    db_manager = _app_manager.get_db_manager(role="read_only")
                    if db_manager:
                        try:
                            user_data = db_manager.find_one("users", {"_id": ObjectId(user_id)})
                        except Exception:
                            # If ObjectId conversion fails, try with string
                            user_data = db_manager.find_one("users", {"_id": user_id})
                        
                        if user_data:
                            # Get account type, username, and role
                            account_type = user_data.get('account_type', 'regular')
                            username = user_data.get('username', 'unknown')
                            user_role = user_data.get('role', 'player')
                            custom_log(f"✅ API: Fetched user info - userId={user_id}, username={username}, account_type={account_type}", level="INFO", isOn=LOGGING_SWITCH)
                            
                            # Get rank and level from dutch_game module
                            if user_data.get("modules", {}).get("dutch_game"):
                                dutch_game_data = user_data['modules']['dutch_game']
                                rank = dutch_game_data.get('rank') or matcher.DEFAULT_RANK
                                level = dutch_game_data.get('level', matcher.DEFAULT_LEVEL)
                                custom_log(f"✅ API: Fetched rank={rank}, level={level} for user {user_id}", level="INFO", isOn=LOGGING_SWITCH)
                except Exception as e:
                    custom_log(f"⚠️ API: Error fetching user data for user {user_id}: {e}", level="WARNING", isOn=LOGGING_SWITCH)
            
            return jsonify({
                'valid': True,
                'user_id': user_id,
                'rank': rank,
                'level': level,
                'account_type': account_type,  # Include account type for registration differences testing
                'username': username,  # Include username for logging
                'role': user_role or 'player',  # User role (default: player)
                'payload': payload
            })
        except Exception as e:
            custom_log(f"❌ API: Token validation failed: {str(e)}", level="ERROR", isOn=LOGGING_SWITCH)
            return jsonify({
                'valid': False,
                'error': 'Invalid or expired token'
            }), 401
            
    except Exception as e:
        custom_log(f"❌ API: Unexpected error in validate_token: {str(e)}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({
            'valid': False,
            'error': str(e)
        }), 500


def create_tournament_in_db(creator_id, data, db_manager):
    """Shared logic: create a tournament document and insert into DB.
    Does not add participants; that will be a separate endpoint. DB accepts optional username/email
    alongside user_id (e.g. participants list, match players, scores) for when add-participants is implemented.
    creator_id: user ObjectId or string. data: dict with optional name, start_date, user_ids, matches, status.
    db_manager: read_write DatabaseManager.
    Returns (tournament_id, created_at, error_msg). On success error_msg is None; on failure first two are None."""
    try:
        creator_id_raw = creator_id
        if not creator_id_raw:
            return (None, None, "creator_id is required")
        try:
            creator_oid = ObjectId(creator_id_raw) if isinstance(creator_id_raw, str) else creator_id_raw
        except Exception:
            return (None, None, "creator_id must be a valid ObjectId string")
        now = datetime.utcnow()
        created_at = now.isoformat() + "Z"
        user_ids_raw = data.get("user_ids") or []
        user_ids = []
        for uid in user_ids_raw:
            try:
                user_ids.append(ObjectId(uid) if isinstance(uid, str) else uid)
            except Exception:
                pass
        # Unique index tournament_id_1: inserts without tournament_id collide as duplicate null — set before insert.
        new_oid = ObjectId()
        tid_str = str(new_oid)
        doc = {
            "_id": new_oid,
            "tournament_id": tid_str,
            "creator_id": creator_oid,
            "user_ids": user_ids,
            "matches": data.get("matches") or [],
            "status": data.get("status") or "active",
            "created_at": created_at,
            "updated_at": created_at,
        }
        if data.get("name") is not None:
            doc["name"] = data["name"]
        if data.get("type") is not None:
            doc["type"] = str(data["type"]).strip().lower()
        if data.get("format") is not None:
            doc["format"] = str(data["format"]).strip().lower()
        start_date = data.get("start_date")
        if start_date is not None and isinstance(start_date, str) and start_date.strip():
            doc["start_date"] = start_date.strip()
        tournament_id = db_manager.insert("tournaments", doc)
        if not tournament_id:
            return (None, None, "Failed to create tournament")
        return (tournament_id, created_at, None)
    except Exception as e:
        custom_log(f"❌ Dutch: create_tournament_in_db error: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return (None, None, str(e))


@dutch_api.route('/service/dutch/create-tournaments', methods=['POST'])
def create_tournaments():
    """Create a tournament in the DB (service endpoint: PHP dashboard, X-Service-Key auth).
    Does not add participants (separate endpoint later). POST body: creator_id (required), optional: name, start_date, user_ids, matches, status.
    Returns tournament id and created_at."""
    try:
        data = request.get_json() or {}
        custom_log("📋 Dutch: create-tournaments request received", level="INFO", isOn=LOGGING_SWITCH)
        creator_id_raw = data.get("creator_id")
        if not creator_id_raw:
            return jsonify({"success": False, "error": "creator_id is required"}), 400
        if not _app_manager:
            custom_log("❌ Dutch: create_tournaments - app_manager not set", level="ERROR", isOn=LOGGING_SWITCH)
            return jsonify({"success": False, "error": "Server not initialized"}), 503
        db_manager = _app_manager.get_db_manager(role="read_write")
        if not db_manager:
            return jsonify({"success": False, "error": "Database unavailable"}), 503
        tournament_id, created_at, err = create_tournament_in_db(creator_id_raw, data, db_manager)
        if err:
            status = 400 if "required" in err or "valid" in err else 500
            return jsonify({"success": False, "error": err}), status
        custom_log(f"📋 Dutch: tournament created id={tournament_id} creator_id={creator_id_raw}", level="INFO", isOn=LOGGING_SWITCH)
        return jsonify({"success": True, "tournament_id": tournament_id, "created_at": created_at}), 200
    except Exception as e:
        custom_log(f"❌ Dutch: create_tournaments error: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "error": str(e)}), 500


# --- Handlers for routes registered via DutchGameMain._register_route_helper (use _app_manager) ---


def get_tournaments_service():
    """Load all tournaments and their data. Service endpoint: requires X-Service-Key (PHP dashboard / Dart backend)."""
    try:
        if not _app_manager:
            return jsonify({"success": False, "error": "Server not initialized"}), 503
        db_manager = _app_manager.get_db_manager(role="read_only")
        if not db_manager:
            return jsonify({"success": False, "error": "Database unavailable"}), 503
        raw = db_manager.find("tournaments", {})
        tournaments = list(raw) if raw else []
        out = []
        for d in tournaments:
            j = _tournament_doc_to_json(d)
            j["id"] = str(d.get("_id", ""))
            out.append(j)
        return jsonify({"success": True, "tournaments": out}), 200
    except Exception as e:
        custom_log(f"DutchGame: get_tournaments_service error: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "error": str(e), "tournaments": []}), 500


def get_tournaments_public():
    """Public (no auth): same listing and shape as get_tournaments_service (all tournaments, full JSON), with email keys stripped recursively."""
    try:
        if not _app_manager:
            return jsonify({"success": False, "error": "Server not initialized"}), 503
        db_manager = _app_manager.get_db_manager(role="read_only")
        if not db_manager:
            return jsonify({"success": False, "error": "Database unavailable"}), 503
        raw = db_manager.find("tournaments", {})
        tournaments = list(raw) if raw else []
        out = []
        for d in tournaments:
            j = _tournament_doc_to_json(d)
            j["id"] = str(d.get("_id", ""))
            out.append(_tournament_json_for_public(j))
        custom_log(
            f"DutchGame: get_tournaments_public ok count={len(out)}",
            level="INFO",
            isOn=LOGGING_SWITCH,
        )
        return jsonify({"success": True, "tournaments": out}), 200
    except Exception as e:
        custom_log(f"DutchGame: get_tournaments_public error: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "error": str(e), "tournaments": []}), 500


def get_available_games():
    """Get all available games that can be joined (JWT protected endpoint)."""
    try:
        auth_header = request.headers.get('Authorization')
        if not auth_header:
            return jsonify({"success": False, "message": "No Authorization header provided", "error": "Missing JWT token"}), 401
        token = auth_header[7:] if auth_header.startswith('Bearer ') else auth_header
        if not _app_manager:
            return jsonify({"success": False, "message": "Server not initialized", "error": "App manager not set"}), 503
        jwt_manager = _app_manager.jwt_manager
        payload = jwt_manager.verify_token(token, TokenType.ACCESS)
        if not payload:
            return jsonify({"success": False, "message": "Invalid or expired JWT token", "error": "Token validation failed"}), 401
        available_games = []
        return jsonify({
            "success": True,
            "message": "Game management moved to Dart backend - no games available via Python API",
            "games": available_games,
            "count": len(available_games),
            "timestamp": time.time()
        }), 200
    except Exception as e:
        return jsonify({"success": False, "message": "Failed to retrieve available games", "error": str(e)}), 500


def find_room():
    """Find a specific room by room ID (JWT protected endpoint)."""
    try:
        auth_header = request.headers.get('Authorization')
        if not auth_header:
            return jsonify({"success": False, "message": "No Authorization header provided", "error": "Missing JWT token"}), 401
        token = auth_header[7:] if auth_header.startswith('Bearer ') else auth_header
        if not _app_manager:
            return jsonify({"success": False, "message": "Server not initialized"}), 503
        jwt_manager = _app_manager.jwt_manager
        payload = jwt_manager.verify_token(token, TokenType.ACCESS)
        if not payload:
            return jsonify({"success": False, "message": "Invalid or expired JWT token", "error": "Token validation failed"}), 401
        data = request.get_json()
        if not data or 'room_id' not in data:
            return jsonify({"success": False, "message": "Room ID is required", "error": "Missing room_id in request body"}), 400
        room_id = data['room_id']
        websocket_manager = _app_manager.get_websocket_manager()
        if not websocket_manager:
            return jsonify({"success": False, "message": "WebSocket manager unavailable"}), 503
        room_info = websocket_manager.get_room_info(room_id)
        if not room_info:
            return jsonify({"success": False, "message": f"Room '{room_id}' not found", "error": "Room does not exist"}), 404
        return jsonify({
            "success": True,
            "message": "Game info is managed by Dart backend - use WebSocket connection",
            "room_id": room_id,
            "room_permission": room_info.get('permission', 'public'),
            "requires_password": False,
            "timestamp": time.time()
        }), 200
    except Exception as e:
        return jsonify({"success": False, "message": "Failed to find game", "error": str(e)}), 500


def _winner_str_from_game_results(game_results: list) -> str:
    """Comma-separated user_ids for winners (Dart sends one row per player with is_winner)."""
    winner_user_ids = [r.get("user_id") for r in game_results if r.get("is_winner") and r.get("user_id")]
    return ",".join(str(uid) for uid in winner_user_ids) if winner_user_ids else ""


def _ordered_user_id_strs_from_game_results(game_results: list) -> list:
    """Preserve order, de-dupe user_ids from game_results."""
    out = []
    seen = set()
    for r in game_results:
        uid = (r.get("user_id") or "").strip()
        if not uid or uid in seen:
            continue
        try:
            ObjectId(uid)
        except Exception:
            continue
        seen.add(uid)
        out.append(uid)
    return out


def _int_from_game_result_row(r: Dict[str, Any], *keys: str, default: int = 0) -> int:
    for k in keys:
        v = r.get(k)
        if v is None:
            continue
        try:
            return int(v)
        except (TypeError, ValueError):
            continue
    return default


def _stats_by_user_from_game_results(game_results: list) -> Dict[str, Tuple[int, int]]:
    """Map user_id str -> (total_end_points, end_card_count) from Dart game_results."""
    out: Dict[str, Tuple[int, int]] = {}
    for r in game_results:
        if not isinstance(r, dict):
            continue
        uid = (r.get("user_id") or "").strip()
        if not uid:
            continue
        tp = _int_from_game_result_row(r, "total_end_points", "totalEndPoints")
        ec = _int_from_game_result_row(r, "end_card_count", "endCardCount")
        out[uid] = (tp, ec)
    return out


def _insert_initial_completed_match_single_room_league(
    db_manager,
    tournament_oid: ObjectId,
    tournament_id: str,
    room_id: str,
    roster_user_id_strs: list,
    game_results: list,
) -> bool:
    """After creating a new tournament, push match_index=1 completed row for the casual game that just ended.

    roster_user_id_strs: participant order from store snapshot (fallback if game_results omits ids)."""
    user_id_strs = _ordered_user_id_strs_from_game_results(game_results)
    if not user_id_strs:
        user_id_strs = [str(u).strip() for u in (roster_user_id_strs or []) if u]
    if not user_id_strs:
        custom_log(
            "📊 Python: _insert_initial_completed_match no user_ids",
            level="WARNING",
            isOn=LOGGING_SWITCH,
        )
        return False

    user_oids = []
    for uid_str in user_id_strs:
        try:
            user_oids.append(ObjectId(uid_str))
        except Exception:
            return False

    now = datetime.utcnow()
    updated_at = now.isoformat() + "Z"
    match_date = now.date().isoformat() if hasattr(now, "date") else updated_at[:10]
    match_id_str = now.strftime("%Y%m%d%H%M%S") + "_" + uuid.uuid4().hex[:8]
    winner_str = _winner_str_from_game_results(game_results)
    stats_by_uid = _stats_by_user_from_game_results(game_results)

    players = []
    for uid_str in user_id_strs:
        tp, ec = stats_by_uid.get(uid_str, (0, 0))
        entry = {
            "user_id": uid_str,
            "username": "",
            "email": "",
            "points": tp,
            "number_of_cards_left": ec,
        }
        try:
            u = db_manager.find_one("users", {"_id": ObjectId(uid_str)})
            if u:
                entry["username"] = (u.get("username") or "").strip() or ("user_%s" % uid_str[:8])
                entry["email"] = (u.get("email") or "").strip()
                entry["is_comp_player"] = u.get("is_comp_player") is True
        except Exception:
            pass
        players.append(entry)
    scores = [
        {
            "user_id": uid,
            "end_card_count": stats_by_uid.get(uid, (0, 0))[1],
            "total_end_points": stats_by_uid.get(uid, (0, 0))[0],
        }
        for uid in user_id_strs
    ]

    new_match = {
        "match_id": match_id_str,
        "match_index": 1,
        "status": "completed",
        "room_id": (room_id or "").strip(),
        "winner": winner_str,
        "user_ids": user_oids,
        "match_date": match_date,
        "start_date": match_date,
        "players": players,
        "scores": scores,
    }

    try:
        result = db_manager.db["tournaments"].update_one(
            {"_id": tournament_oid},
            {"$push": {"matches": new_match}, "$set": {"updated_at": updated_at}},
        )
    except Exception as db_err:
        custom_log(
            f"📊 Python: _insert_initial_completed_match db error: {db_err}",
            level="ERROR",
            isOn=LOGGING_SWITCH,
        )
        return False

    if not result or result.modified_count == 0:
        custom_log(
            "📊 Python: _insert_initial_completed_match failed (no document modified)",
            level="WARNING",
            isOn=LOGGING_SWITCH,
        )
        return False

    custom_log(
        f"📊 Python: single_room_league — inserted initial completed match tournament_id={tournament_id} "
        f"match_id={match_id_str} match_index=1 room_id={room_id} winner={winner_str}",
        level="INFO",
        isOn=LOGGING_SWITCH,
    )
    return True


def _append_single_room_league_completed_match(
    db_manager,
    tournament_oid: ObjectId,
    tournament_id: str,
    tournament_doc: Dict[str, Any],
    room_id: str,
    game_results: list,
) -> bool:
    """Append a new matches[] row (new match_id / match_index) with status=completed and winner.

    Used when the same physical room_id is reused across rematches so we do not overwrite the prior row
    found by room_id."""
    user_id_strs = _ordered_user_id_strs_from_game_results(game_results)
    if not user_id_strs:
        for u in tournament_doc.get("user_ids") or []:
            s = str(u).strip() if u is not None else ""
            if not s:
                continue
            try:
                ObjectId(s)
            except Exception:
                continue
            if s not in user_id_strs:
                user_id_strs.append(s)
    if not user_id_strs:
        custom_log(
            "📊 Python: _append_single_room_league_completed_match no user_ids from game_results or tournament",
            level="WARNING",
            isOn=LOGGING_SWITCH,
        )
        return False

    user_oids = []
    for uid_str in user_id_strs:
        try:
            user_oids.append(ObjectId(uid_str))
        except Exception:
            return False

    matches = tournament_doc.get("matches") or []
    next_index = 1
    if matches:
        indices = [m.get("match_index") for m in matches if isinstance(m, dict) and m.get("match_index") is not None]
        next_index = max(indices, default=0) + 1

    now = datetime.utcnow()
    updated_at = now.isoformat() + "Z"
    match_date = now.date().isoformat() if hasattr(now, "date") else updated_at[:10]
    match_id_str = now.strftime("%Y%m%d%H%M%S") + "_" + uuid.uuid4().hex[:8]
    winner_str = _winner_str_from_game_results(game_results)
    stats_by_uid = _stats_by_user_from_game_results(game_results)

    players = []
    for uid_str in user_id_strs:
        tp, ec = stats_by_uid.get(uid_str, (0, 0))
        entry = {
            "user_id": uid_str,
            "username": "",
            "email": "",
            "points": tp,
            "number_of_cards_left": ec,
        }
        try:
            u = db_manager.find_one("users", {"_id": ObjectId(uid_str)})
            if u:
                entry["username"] = (u.get("username") or "").strip() or ("user_%s" % uid_str[:8])
                entry["email"] = (u.get("email") or "").strip()
                entry["is_comp_player"] = u.get("is_comp_player") is True
        except Exception:
            pass
        players.append(entry)
    scores = [
        {
            "user_id": uid,
            "end_card_count": stats_by_uid.get(uid, (0, 0))[1],
            "total_end_points": stats_by_uid.get(uid, (0, 0))[0],
        }
        for uid in user_id_strs
    ]

    new_match = {
        "match_id": match_id_str,
        "match_index": next_index,
        "status": "completed",
        "room_id": (room_id or "").strip(),
        "winner": winner_str,
        "user_ids": user_oids,
        "match_date": match_date,
        "start_date": match_date,
        "players": players,
        "scores": scores,
    }

    rid = (room_id or "").strip()
    # Rematch pre-appends a pending row for this room; remove it so we do not keep pending + completed for the same game.
    pull_spec = {"room_id": rid, "status": "pending"}

    # MongoDB forbids $pull and $push on the same array path in a single update (path conflict).
    try:
        db_manager.db["tournaments"].update_one(
            {"_id": tournament_oid},
            {"$pull": {"matches": pull_spec}, "$set": {"updated_at": updated_at}},
        )
    except Exception as db_err:
        custom_log(f"📊 Python: _append_single_room_league_completed_match pull db error: {db_err}", level="ERROR", isOn=LOGGING_SWITCH)
        return False

    try:
        result = db_manager.db["tournaments"].update_one(
            {"_id": tournament_oid},
            {"$push": {"matches": new_match}, "$set": {"updated_at": updated_at}},
        )
    except Exception as db_err:
        custom_log(f"📊 Python: _append_single_room_league_completed_match push db error: {db_err}", level="ERROR", isOn=LOGGING_SWITCH)
        return False

    if not result or result.modified_count == 0:
        custom_log(
            "📊 Python: _append_single_room_league_completed_match failed (no document modified)",
            level="WARNING",
            isOn=LOGGING_SWITCH,
        )
        return False

    custom_log(
        f"📊 Python: single_room_league — appended completed match tournament_id={tournament_id} "
        f"match_id={match_id_str} match_index={next_index} room_id={room_id} winner={winner_str}",
        level="INFO",
        isOn=LOGGING_SWITCH,
    )
    return True


def _record_tournament_match_result(
    db_manager,
    game_results: list,
    tournament_data: Dict[str, Any],
    room_id: Optional[str] = None,
) -> None:
    """Update tournament match in DB when a tournament match ends: set status=completed and winner.

    For format ``single_room_league``, appends a **new** matches[] row (new match_id) with completed data,
    because the same ``room_id`` is reused across rematches and updating by room_id would overwrite the same row.

    Other formats: match is found by tournament_id + room_id (room_id was set on the match at creation/attach).
    Winner is the user_id of game_result rows with is_winner=True; if multiple winners, comma-separated."""
    if not room_id:
        custom_log("📊 Python: _record_tournament_match_result skipped - no room_id", level="WARNING", isOn=LOGGING_SWITCH)
        return
    tournament_id = (tournament_data.get("tournament_id") or "").strip()
    if not tournament_id:
        custom_log("📊 Python: _record_tournament_match_result skipped - no tournament_id in tournament_data", level="WARNING", isOn=LOGGING_SWITCH)
        return
    try:
        tournament_oid = ObjectId(tournament_id)
    except Exception:
        custom_log(f"📊 Python: _record_tournament_match_result invalid tournament_id format: {tournament_id}", level="WARNING", isOn=LOGGING_SWITCH)
        return
    tournament = db_manager.find_one("tournaments", {"_id": tournament_oid})
    if not tournament:
        custom_log(f"📊 Python: _record_tournament_match_result tournament not found: {tournament_id}", level="WARNING", isOn=LOGGING_SWITCH)
        return

    fmt = (tournament.get("format") or "").strip().lower()
    if fmt == "single_room_league":
        _append_single_room_league_completed_match(
            db_manager, tournament_oid, tournament_id, tournament, room_id, game_results
        )
        return

    matches = list(tournament.get("matches") or [])
    match_idx = None
    for i, m in enumerate(matches):
        if isinstance(m, dict) and (m.get("room_id") or "").strip() == room_id:
            match_idx = i
            break
    if match_idx is None:
        custom_log(f"📊 Python: _record_tournament_match_result no match with room_id={room_id} in tournament {tournament_id}", level="WARNING", isOn=LOGGING_SWITCH)
        return
    winner_str = _winner_str_from_game_results(game_results)
    matches[match_idx] = dict(matches[match_idx])
    matches[match_idx]["status"] = "completed"
    matches[match_idx]["winner"] = winner_str
    stats_by_uid = _stats_by_user_from_game_results(game_results)
    uid_order: List[str] = []
    for u in matches[match_idx].get("user_ids") or []:
        uid_order.append(str(u))
    if not uid_order:
        uid_order = list(_ordered_user_id_strs_from_game_results(game_results))
    if uid_order and stats_by_uid:
        matches[match_idx]["scores"] = [
            {
                "user_id": u,
                "total_end_points": stats_by_uid.get(u, (0, 0))[0],
                "end_card_count": stats_by_uid.get(u, (0, 0))[1],
            }
            for u in uid_order
        ]
        pl_existing = matches[match_idx].get("players")
        if isinstance(pl_existing, list):
            new_players = []
            for p in pl_existing:
                if not isinstance(p, dict):
                    continue
                pu = (p.get("user_id") or "").strip()
                if not pu:
                    continue
                q = dict(p)
                tp, ec = stats_by_uid.get(pu, (0, 0))
                q["points"] = tp
                q["number_of_cards_left"] = ec
                new_players.append(q)
            if new_players:
                matches[match_idx]["players"] = new_players
    now = datetime.utcnow()
    updated_at = now.isoformat() + "Z"
    try:
        db_manager.db["tournaments"].update_one(
            {"_id": tournament_oid},
            {"$set": {"matches": matches, "updated_at": updated_at}},
        )
        custom_log(
            f"📊 Python: Tournament match updated - tournament_id={tournament_id} room_id={room_id} winner={winner_str}",
            level="INFO",
            isOn=LOGGING_SWITCH,
        )
    except Exception as db_err:
        custom_log(f"📊 Python: _record_tournament_match_result db error: {db_err}", level="ERROR", isOn=LOGGING_SWITCH)


def _ensure_match_win_outcomes_indexes(db_manager) -> None:
    """Idempotent indexes: range queries on ended_at; unique (room_id, user_id) for insert-only idempotency."""
    try:
        coll = db_manager.db[MATCH_WIN_OUTCOMES_COLL]
        coll.create_index([("ended_at", 1)])
        coll.create_index(
            [("room_id", 1), ("user_id", 1)],
            unique=True,
            name="room_user_unique",
        )
    except Exception as e:
        custom_log(f"📊 Python: match_win_outcomes index ensure (non-fatal): {e}", level="WARNING", isOn=LOGGING_SWITCH)


def _insert_match_win_outcome_additive(
    db_manager,
    *,
    room_id: str,
    user_id: ObjectId,
    ended_at_utc,
    is_tournament: bool,
    tournament_id: Optional[str],
    game_mode: Optional[str],
) -> None:
    """Single additive insert for one match win. Duplicate (room_id, user_id) is ignored (no races, no double count)."""
    doc = {
        "room_id": room_id,
        "user_id": user_id,
        "ended_at": ended_at_utc,
        "is_tournament": is_tournament,
        "tournament_id": tournament_id,
        "game_mode": game_mode,
    }
    try:
        db_manager.db[MATCH_WIN_OUTCOMES_COLL].insert_one(doc)
        custom_log(
            f"📊 Python: match_win_outcome inserted room_id={room_id} user_id={user_id} ended_at={ended_at_utc.isoformat()}",
            level="INFO",
            isOn=LOGGING_SWITCH,
        )
    except DuplicateKeyError:
        custom_log(
            f"📊 Python: match_win_outcome duplicate skip room_id={room_id} user_id={user_id}",
            level="DEBUG",
            isOn=LOGGING_SWITCH,
        )


def _utc_bounds_calendar_month(now_utc: datetime) -> Tuple[datetime, datetime]:
    """Inclusive start, exclusive end for the calendar month containing now_utc (UTC)."""
    if now_utc.tzinfo is None:
        now_utc = now_utc.replace(tzinfo=timezone.utc)
    first = now_utc.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    if first.month == 12:
        nxt = first.replace(year=first.year + 1, month=1)
    else:
        nxt = first.replace(month=first.month + 1)
    return first, nxt


def _utc_bounds_calendar_year(now_utc: datetime) -> Tuple[datetime, datetime]:
    """Inclusive start, exclusive end for the calendar year containing now_utc (UTC)."""
    if now_utc.tzinfo is None:
        now_utc = now_utc.replace(tzinfo=timezone.utc)
    first = datetime(now_utc.year, 1, 1, tzinfo=timezone.utc)
    nxt = datetime(now_utc.year + 1, 1, 1, tzinfo=timezone.utc)
    return first, nxt


def update_game_stats():
    """Update user game statistics after a game ends (service endpoint: Dart backend only, X-Service-Key auth).

    Optional body ``is_coin_required`` / ``isCoinRequired`` (default true): when false, winner pot credits are
    skipped for all players; combined with subscription tier in ``should_skip_match_coin_economy``.

    Winners (human and comp) get an **insert-only** row in ``dutch_match_win_outcomes`` (UTC ``ended_at``,
    unique ``(room_id, user_id)``) so period leaderboards can aggregate without races or double counts.
    """
    try:
        custom_log("📊 Python: Received game statistics update request", level="INFO", isOn=LOGGING_SWITCH)
        data = request.get_json()
        if not data:
            return jsonify({"success": False, "message": "Request body is required", "error": "Missing request body"}), 400
        game_results = data.get('game_results')
        if not game_results or not isinstance(game_results, list):
            return jsonify({"success": False, "message": "game_results array is required", "error": "Missing or invalid game_results"}), 400
        if len(game_results) == 0:
            return jsonify({"success": False, "message": "game_results array cannot be empty", "error": "No game results provided"}), 400
        custom_log(f"📊 Python: Processing {len(game_results)} player result(s)", level="INFO", isOn=LOGGING_SWITCH)

        _raw_coin_req = data.get("is_coin_required", data.get("isCoinRequired"))
        game_coin_required = True if _raw_coin_req is None else bool(_raw_coin_req)

        if not _app_manager:
            return jsonify({"success": False, "message": "Server not initialized"}), 503
        db_manager = _app_manager.get_db_manager(role="read_write")
        if not db_manager:
            return jsonify({"success": False, "message": "Database connection unavailable", "error": "Database manager not initialized"}), 500

        is_tournament = data.get('is_tournament', False) is True
        tournament_data = data.get('tournament_data') if isinstance(data.get('tournament_data'), dict) else {}
        room_id = data.get('room_id') or data.get('game_id')
        if is_tournament:
            _record_tournament_match_result(db_manager, game_results, tournament_data, room_id=room_id)

        _ensure_match_win_outcomes_indexes(db_manager)
        current_time = datetime.utcnow()
        current_timestamp = current_time.isoformat()
        ended_at_utc = datetime.now(timezone.utc)
        updated_players = []
        errors = []
        for player_result in game_results:
            try:
                user_id_str = player_result.get('user_id')
                if not user_id_str:
                    errors.append(f"Missing user_id in game result: {player_result}")
                    continue
                try:
                    user_id = ObjectId(user_id_str)
                except Exception as e:
                    errors.append(f"Invalid user_id format '{user_id_str}': {str(e)}")
                    continue
                user = db_manager.find_one("users", {"_id": user_id})
                if not user:
                    errors.append(f"User not found: {user_id_str}")
                    continue
                modules = user.get('modules', {})
                dutch_game = modules.get('dutch_game', {})
                current_wins = dutch_game.get('wins', 0)
                current_losses = dutch_game.get('losses', 0)
                current_total_matches = dutch_game.get('total_matches', 0)
                current_coins = dutch_game.get('coins', 0)
                subscription_tier = dutch_game.get('subscription_tier') or matcher.TIER_PROMOTIONAL
                inventory = _normalize_inventory(dutch_game.get("inventory"))
                is_winner = player_result.get('is_winner', False)
                pot = player_result.get('pot', 0)
                coins_to_add = 0
                base_win_coins = 0
                booster_multiplier = 1.0
                bonus_from_booster = 0
                should_consume_booster = False
                # game_coin_required = room-wide; subscription_tier = this user's DB (promo skips credit only for them).
                if is_winner and pot > 0 and not matcher.should_skip_match_coin_economy(
                    subscription_tier, is_coin_required=game_coin_required
                ):
                    base_win_coins = int(pot)
                    coins_to_add = base_win_coins
                    available_boosters = int(inventory.get("boosters", {}).get(BOOSTER_ITEM_ID, 0) or 0)
                    if available_boosters > 0:
                        coins_to_add, booster_multiplier, bonus_from_booster = _compute_boosted_win_amount(
                            base_win_coins,
                            has_booster=True,
                        )
                        should_consume_booster = True
                new_total_matches = current_total_matches + 1
                new_wins = current_wins + (1 if is_winner else 0)
                new_losses = current_losses + (0 if is_winner else 1)
                new_coins = current_coins + coins_to_add
                new_win_rate = float(new_wins) / float(new_total_matches) if new_total_matches > 0 else 0.0

                # Progression: 10 wins → +1 user level; 5 user levels → +1 rank tier (no demotion by wins).
                target_user_level = WinsLevelRankMatcher.wins_to_user_level(new_wins)
                target_rank = WinsLevelRankMatcher.user_level_to_rank(target_user_level)
                stored_rank = dutch_game.get("rank") or matcher.DEFAULT_RANK
                idx_target = matcher.get_rank_index(target_rank)
                idx_stored = matcher.get_rank_index(stored_rank)
                if idx_stored < 0:
                    idx_stored = 0
                if idx_target < 0:
                    idx_target = 0
                rank_should_increase = idx_target > idx_stored

                raw_level = dutch_game.get("level", matcher.DEFAULT_LEVEL)
                try:
                    current_user_level = int(raw_level)
                except (TypeError, ValueError):
                    current_user_level = matcher.DEFAULT_LEVEL
                if current_user_level < 1:
                    current_user_level = matcher.DEFAULT_LEVEL
                level_changed = target_user_level != current_user_level

                streak_before = parse_stored_streak(dutch_game.get("win_streak_current"))
                new_win_streak = next_win_streak(streak_before, bool(is_winner))
                already_unlocked = unlocked_achievement_ids_from_dutch_game(dutch_game)
                newly_unlocked_achievements = compute_new_unlocks(new_win_streak, already_unlocked)
                raw_best = dutch_game.get("win_streak_best", 0)
                try:
                    prev_best = max(0, int(raw_best))
                except (TypeError, ValueError):
                    prev_best = 0
                new_win_streak_best = max(prev_best, new_win_streak)

                set_fields = {
                    'modules.dutch_game.total_matches': new_total_matches,
                    'modules.dutch_game.wins': new_wins,
                    'modules.dutch_game.losses': new_losses,
                    'modules.dutch_game.win_rate': new_win_rate,
                    'modules.dutch_game.level': target_user_level,
                    'modules.dutch_game.win_streak_current': new_win_streak,
                    'modules.dutch_game.win_streak_best': new_win_streak_best,
                    'modules.dutch_game.last_match_date': current_timestamp,
                    'modules.dutch_game.last_updated': current_timestamp,
                    'updated_at': current_timestamp
                }
                if rank_should_increase:
                    set_fields['modules.dutch_game.rank'] = target_rank
                for ach_id in newly_unlocked_achievements:
                    set_fields[f"modules.dutch_game.achievements.unlocked.{ach_id}"] = {
                        "unlocked_at": current_timestamp,
                    }
                if should_consume_booster:
                    next_qty = max(0, int(inventory.get("boosters", {}).get(BOOSTER_ITEM_ID, 0) or 0) - 1)
                    inventory["boosters"][BOOSTER_ITEM_ID] = next_qty
                    set_fields["modules.dutch_game.inventory"] = inventory

                update_operation = {'$set': set_fields}
                if coins_to_add > 0:
                    update_operation['$inc'] = {'modules.dutch_game.coins': coins_to_add}
                result = db_manager.db["users"].update_one({"_id": user_id}, update_operation)
                modified_count = result.modified_count if result else 0
                if modified_count > 0:
                    updated_players.append({
                        "user_id": user_id_str,
                        "wins": new_wins,
                        "losses": new_losses,
                        "total_matches": new_total_matches,
                        "coins": new_coins,
                        "coins_added": coins_to_add,
                        "base_win_coins": base_win_coins,
                        "booster_multiplier": booster_multiplier,
                        "bonus_from_booster": bonus_from_booster,
                        "final_win_coins": coins_to_add if is_winner else 0,
                        "win_rate": new_win_rate,
                        "win_streak_current": new_win_streak,
                        "newly_unlocked_achievements": newly_unlocked_achievements,
                        **({"rank": target_rank} if rank_should_increase else {}),
                        **({"level": target_user_level} if level_changed else {}),
                    })
                    if should_consume_booster:
                        _insert_consumable_tx(
                            db_manager,
                            user_id=user_id,
                            tx_type="consume_win_booster",
                            payload={
                                "room_id": room_id,
                                "base_win_coins": base_win_coins,
                                "bonus_from_booster": bonus_from_booster,
                                "multiplier": booster_multiplier,
                            },
                        )
                    room_key = str(room_id).strip() if room_id else ""
                    if is_winner and room_key:
                        tid_out = (tournament_data.get("tournament_id") or "").strip() or None
                        _insert_match_win_outcome_additive(
                            db_manager,
                            room_id=room_key,
                            user_id=user_id,
                            ended_at_utc=ended_at_utc,
                            is_tournament=is_tournament,
                            tournament_id=tid_out,
                            game_mode=player_result.get("game_mode"),
                        )
                    analytics_service = _app_manager.services_manager.get_service('analytics_service') if _app_manager else None
                    if analytics_service:
                        game_mode = player_result.get('game_mode', 'multiplayer')
                        analytics_service.track_event(
                            user_id=user_id_str,
                            event_type='game_completed',
                            event_data={'game_mode': game_mode, 'result': 'win' if is_winner else 'loss', 'duration': player_result.get('duration', 0)},
                            metrics_enabled=METRICS_SWITCH
                        )
                        if coins_to_add > 0:
                            analytics_service.track_event(
                                user_id=user_id_str,
                                event_type='coin_transaction',
                                event_data={'transaction_type': 'game_reward', 'direction': 'credit', 'amount': coins_to_add},
                                metrics_enabled=METRICS_SWITCH
                            )
                else:
                    errors.append(f"Failed to update user: {user_id_str}")
            except Exception as e:
                errors.append(f"Error processing player result {player_result.get('user_id', 'unknown')}: {str(e)}")
        if len(updated_players) > 0:
            response_data = {"success": True, "message": f"Game statistics updated successfully for {len(updated_players)} player(s)", "updated_players": updated_players}
            if errors:
                response_data["warnings"] = errors
            if is_tournament:
                tid = (tournament_data.get("tournament_id") or "").strip()
                if tid:
                    try:
                        tdoc = db_manager.find_one("tournaments", {"_id": ObjectId(tid)})
                        if tdoc:
                            tj = _tournament_doc_to_json(tdoc)
                            response_data["tournament_data"] = {
                                "tournament_id": tid,
                                "type": tj.get("type"),
                                "format": tj.get("format"),
                                "matches": tj.get("matches") or [],
                            }
                    except Exception as e_td:
                        custom_log(f"📊 Python: update_game_stats tournament_data attach skipped: {e_td}", level="DEBUG", isOn=LOGGING_SWITCH)
            return jsonify(response_data), 200
        return jsonify({"success": False, "message": "Failed to update any player statistics", "error": "All updates failed", "errors": errors}), 500
    except Exception as e:
        custom_log(f"❌ Python: Error in update_game_stats: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "message": "Failed to update game statistics", "error": str(e)}), 500


def _leaderboard_period_key_monthly(now_utc: datetime) -> str:
    """Calendar month immediately before now_utc (YYYY-MM). E.g. cron on 2026-03-01 -> '2026-02'."""
    first_this = now_utc.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    last_prev = first_this - timedelta(days=1)
    return last_prev.strftime("%Y-%m")


def _leaderboard_period_key_yearly(now_utc: datetime) -> str:
    """Calendar year immediately before now_utc (YYYY). E.g. cron on 2026-01-01 -> '2025'."""
    return str(now_utc.year - 1)


def _ensure_leaderboards_indexes(db_manager) -> None:
    """Create leaderboards indexes if missing (idempotent)."""
    try:
        coll = db_manager.db["leaderboards"]
        coll.create_index([("leaderboard_type", 1), ("date_time", -1)])
        coll.create_index([("period_key", 1), ("leaderboard_type", 1)])
        coll.create_index(
            [
                ("leaderboard_type", 1),
                ("tournament_type", 1),
                ("tournament_format", 1),
                ("date_time", -1),
            ]
        )
        coll.create_index([("date_time", -1)])
    except Exception as e:
        custom_log(f"📊 Python: leaderboards index ensure (non-fatal): {e}", level="WARNING", isOn=LOGGING_SWITCH)


def snapshot_wins_leaderboard_service():
    """Service: record top player(s) by cumulative ``modules.dutch_game.wins`` into ``leaderboards``.

    Includes all active users with a ``dutch_game`` module (human and comp players).

    POST JSON: ``leaderboard_type`` required: ``monthly`` | ``yearly``.
    Optional ``period_key`` (e.g. ``2026-02`` or ``2025``) — default derived from UTC now (previous month / year).

    Idempotent: one document per `(leaderboard_type, period_key)` for non-tournament snapshots (skips if exists).
    **Note:** Wins are lifetime totals at snapshot time, not wins earned only inside the period (until per-period stats exist).
    """
    try:
        data = request.get_json() or {}
        lb_type = (data.get("leaderboard_type") or data.get("leaderboardType") or "").strip().lower()
        if lb_type not in ("monthly", "yearly"):
            return (
                jsonify(
                    {
                        "success": False,
                        "error": "leaderboard_type must be 'monthly' or 'yearly'",
                    }
                ),
                400,
            )
        if not _app_manager:
            return jsonify({"success": False, "message": "Server not initialized"}), 503
        db_manager = _app_manager.get_db_manager(role="read_write")
        if not db_manager:
            return jsonify({"success": False, "message": "Database connection unavailable"}), 500

        now_utc = datetime.now(timezone.utc)
        period_key = (data.get("period_key") or data.get("periodKey") or "").strip()
        if not period_key:
            period_key = (
                _leaderboard_period_key_monthly(now_utc)
                if lb_type == "monthly"
                else _leaderboard_period_key_yearly(now_utc)
            )

        _ensure_leaderboards_indexes(db_manager)
        coll = db_manager.db["leaderboards"]

        existing = coll.find_one(
            {
                "leaderboard_type": lb_type,
                "period_key": period_key,
                "tournament_type": {"$exists": False},
                "tournament_format": {"$exists": False},
            }
        )
        if existing:
            custom_log(
                f"📊 Python: snapshot_wins_leaderboard skip (exists) type={lb_type} period={period_key}",
                level="INFO",
                isOn=LOGGING_SWITCH,
            )
            return (
                jsonify(
                    {
                        "success": True,
                        "skipped": True,
                        "reason": "already_recorded",
                        "leaderboard_type": lb_type,
                        "period_key": period_key,
                        "existing_id": str(existing.get("_id")),
                    }
                ),
                200,
            )

        match_user = {
            "status": "active",
            "modules.dutch_game": {"$exists": True},
        }
        top = db_manager.db["users"].find_one(match_user, sort=[("modules.dutch_game.wins", -1)])
        if not top:
            win_count = None
            winners_rows = []
        else:
            max_w = (top.get("modules") or {}).get("dutch_game", {}).get("wins", 0) or 0
            win_count = int(max_w)
            cursor = db_manager.db["users"].find(
                {**match_user, "modules.dutch_game.wins": win_count},
                {"username": 1, "modules.dutch_game.wins": 1},
            )
            winners_rows = []
            rank = 1
            for u in cursor:
                uid = u.get("_id")
                winners_rows.append(
                    {
                        "user_id": str(uid),
                        "username": u.get("username") or "",
                        "rank": rank,
                        "wins": win_count,
                    }
                )

        doc = {
            "leaderboard_type": lb_type,
            "period_key": period_key,
            "date_time": now_utc,
            "winners": winners_rows,
            "metric": "cumulative_wins_snapshot",
            "metric_note": "modules.dutch_game.wins at snapshot time; not wins-only-within-period",
        }
        ins = coll.insert_one(doc)
        custom_log(
            f"📊 Python: snapshot_wins_leaderboard inserted type={lb_type} period={period_key} id={ins.inserted_id}",
            level="INFO",
            isOn=LOGGING_SWITCH,
        )
        return (
            jsonify(
                {
                    "success": True,
                    "leaderboard_type": lb_type,
                    "period_key": period_key,
                    "inserted_id": str(ins.inserted_id),
                    "winners": winners_rows,
                    "top_wins": win_count,
                }
            ),
            200,
        )
    except Exception as e:
        custom_log(f"❌ Python: snapshot_wins_leaderboard: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "message": "Failed to snapshot leaderboard", "error": str(e)}), 500


def get_user_stats():
    """Get current user's dutch game statistics (JWT protected endpoint)."""
    try:
        user_id = request.user_id
        if not user_id:
            return jsonify({"success": False, "error": "User not authenticated", "message": "No user ID found in request"}), 401
        if not _app_manager:
            return jsonify({"success": False, "error": "Server not initialized"}), 503
        db_manager = _app_manager.get_db_manager(role="read_write")
        if not db_manager:
            return jsonify({"success": False, "error": "Database connection unavailable", "message": "Failed to connect to database"}), 500
        user = db_manager.find_one("users", {"_id": ObjectId(user_id)})
        if not user:
            return jsonify({"success": False, "error": "User not found", "message": f"User with ID {user_id} not found in database"}), 404
        modules = user.get('modules', {})
        dutch_game = modules.get('dutch_game', {})
        if not dutch_game:
            stats_data = {
                "enabled": False,
                "wins": 0,
                "losses": 0,
                "total_matches": 0,
                "points": 0,
                "coins": 0,
                "level": matcher.DEFAULT_LEVEL,
                "rank": matcher.DEFAULT_RANK,
                "win_rate": 0.0,
                "subscription_tier": matcher.TIER_PROMOTIONAL,
                "last_match_date": None,
                "last_updated": None,
                "win_streak_current": parse_stored_streak(None),
                "win_streak_best": parse_stored_streak(None),
                "achievements_unlocked_ids": [],
                "inventory": _normalize_inventory(None),
                "dutch_module_initialized": False,
            }
        else:
            stats_data = {
                "enabled": dutch_game.get('enabled', True),
                "wins": dutch_game.get('wins', 0),
                "losses": dutch_game.get('losses', 0),
                "total_matches": dutch_game.get('total_matches', 0),
                "points": dutch_game.get('points', 0),
                "coins": dutch_game.get('coins', 0),
                "level": dutch_game.get('level', matcher.DEFAULT_LEVEL),
                "rank": dutch_game.get('rank') or matcher.DEFAULT_RANK,
                "win_rate": dutch_game.get('win_rate', 0.0),
                "subscription_tier": dutch_game.get('subscription_tier') or matcher.TIER_PROMOTIONAL,
                "last_match_date": dutch_game.get('last_match_date'),
                "last_updated": dutch_game.get('last_updated'),
                "win_streak_current": parse_stored_streak(dutch_game.get("win_streak_current")),
                "win_streak_best": parse_stored_streak(dutch_game.get("win_streak_best")),
                "achievements_unlocked_ids": achievements_unlocked_ids_sorted(dutch_game),
                "inventory": _normalize_inventory(dutch_game.get("inventory")),
                "dutch_module_initialized": True,
            }
        if stats_data.get('last_match_date') and isinstance(stats_data['last_match_date'], datetime):
            stats_data['last_match_date'] = stats_data['last_match_date'].isoformat()
        if stats_data.get('last_updated') and isinstance(stats_data['last_updated'], datetime):
            stats_data['last_updated'] = stats_data['last_updated'].isoformat()
        if LOGGING_SWITCH:
            custom_log(
                f"📊 DutchGame: get_user_stats (JWT) user_id={user_id} coins={stats_data.get('coins')} subscription_tier={stats_data.get('subscription_tier')}",
                level="INFO",
                isOn=LOGGING_SWITCH,
            )
        client_rev = (request.args.get("client_table_tiers_revision") or "").strip()
        client_cons_rev = (request.args.get("client_consumables_catalog_revision") or "").strip()
        rev = ttc.TABLE_TIERS_REVISION
        cons_rev = cc.CONSUMABLES_CATALOG_REVISION
        response_body: Dict[str, Any] = {
            "success": True,
            "message": "User statistics retrieved successfully",
            "data": stats_data,
            "user_id": str(user_id),
            "timestamp": datetime.utcnow().isoformat(),
            "table_tiers_revision": rev,
            "consumables_catalog_revision": cons_rev,
        }
        if (not client_rev) or client_rev != rev:
            public_base = _resolve_public_api_base()
            response_body["table_tiers"] = ttc.build_client_table_tiers_payload(public_base)
        if (not client_cons_rev) or client_cons_rev != cons_rev:
            response_body["consumables_catalog"] = cc.build_client_consumables_payload()
        return jsonify(response_body), 200
    except Exception as e:
        custom_log(f"❌ DutchGame: Error in get_user_stats: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "error": "Failed to retrieve user statistics", "message": str(e)}), 500


def get_user_stats_service():
    """Get dutch game stats for a user by user_id (service endpoint: Dart backend, X-Service-Key auth)."""
    try:
        data = request.get_json()
        if not data:
            custom_log("📊 DutchGame: get_user_stats_service missing body", level="WARNING", isOn=LOGGING_SWITCH)
            return jsonify({"success": False, "error": "Request body required", "message": "Missing request body"}), 400
        user_id = (data.get("user_id") or data.get("userid") or "").strip()
        if not user_id:
            custom_log("📊 DutchGame: get_user_stats_service missing user_id", level="WARNING", isOn=LOGGING_SWITCH)
            return jsonify({"success": False, "error": "user_id required", "message": "user_id is required in body"}), 400
        custom_log(f"📊 DutchGame: get_user_stats_service request user_id={user_id}", level="INFO", isOn=LOGGING_SWITCH)
        if not _app_manager:
            return jsonify({"success": False, "error": "Server not initialized"}), 503
        db_manager = _app_manager.get_db_manager(role="read_write")
        if not db_manager:
            return jsonify({"success": False, "error": "Database connection unavailable", "message": "Failed to connect to database"}), 500
        try:
            user_id_obj = ObjectId(user_id)
        except Exception:
            custom_log(f"📊 DutchGame: get_user_stats_service invalid user_id={user_id}", level="WARNING", isOn=LOGGING_SWITCH)
            return jsonify({"success": False, "error": "Invalid user_id", "message": "user_id must be a valid ObjectId"}), 400
        user = db_manager.find_one("users", {"_id": user_id_obj})
        if not user:
            custom_log(f"📊 DutchGame: get_user_stats_service user not found user_id={user_id}", level="INFO", isOn=LOGGING_SWITCH)
            return jsonify({"success": False, "error": "User not found", "message": f"User with ID {user_id} not found", "data": None}), 404
        modules = user.get("modules", {})
        dutch_game = modules.get("dutch_game", {})
        if not dutch_game:
            custom_log(f"📊 DutchGame: get_user_stats_service user_id={user_id} no dutch_game module -> coins=0 tier=promotional", level="INFO", isOn=LOGGING_SWITCH)
            return jsonify({"success": True, "message": "User has no dutch_game module", "data": {"coins": 0, "subscription_tier": matcher.TIER_PROMOTIONAL}, "user_id": user_id, "timestamp": datetime.utcnow().isoformat()}), 200
        stats_data = {
            "coins": dutch_game.get("coins", 0),
            "subscription_tier": dutch_game.get("subscription_tier") or matcher.TIER_PROMOTIONAL,
            "level": dutch_game.get("level", matcher.DEFAULT_LEVEL),
            "rank": dutch_game.get("rank") or matcher.DEFAULT_RANK,
            "win_streak_current": parse_stored_streak(dutch_game.get("win_streak_current")),
            "win_streak_best": parse_stored_streak(dutch_game.get("win_streak_best")),
            "achievements_unlocked_ids": achievements_unlocked_ids_sorted(dutch_game),
            "inventory": _normalize_inventory(dutch_game.get("inventory")),
        }
        custom_log(f"📊 DutchGame: get_user_stats_service user_id={user_id} coins={stats_data['coins']} subscription_tier={stats_data['subscription_tier']}", level="INFO", isOn=LOGGING_SWITCH)
        return jsonify({"success": True, "message": "User statistics retrieved", "data": stats_data, "user_id": user_id, "timestamp": datetime.utcnow().isoformat()}), 200
    except Exception as e:
        custom_log(f"❌ DutchGame: Error in get_user_stats_service: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "error": "Failed to retrieve user statistics", "message": str(e)}), 500


def get_shop_catalog_service():
    """Service endpoint: return MVP Dutch consumables/cosmetics catalog."""
    try:
        return jsonify({
            "success": True,
            "items": cc.get_catalog_items(active_only=True),
            "catalog_revision": cc.CONSUMABLES_CATALOG_REVISION,
            "timestamp": datetime.utcnow().isoformat(),
        }), 200
    except Exception as e:
        custom_log(f"❌ DutchGame: get_shop_catalog_service error: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "error": "Failed to fetch shop catalog", "message": str(e)}), 500


def get_inventory_service():
    """Service endpoint: return Dutch inventory (boosters + cosmetics) for a given user_id."""
    try:
        data = request.get_json() or {}
        user_id = (data.get("user_id") or getattr(request, "user_id", "") or "").strip()
        if not user_id:
            return jsonify({"success": False, "error": "user_id required"}), 400
        if not _app_manager:
            return jsonify({"success": False, "error": "Server not initialized"}), 503
        db_manager = _app_manager.get_db_manager(role="read_write")
        if not db_manager:
            return jsonify({"success": False, "error": "Database connection unavailable"}), 500
        try:
            user_oid = ObjectId(user_id)
        except Exception:
            return jsonify({"success": False, "error": "Invalid user_id"}), 400
        user = db_manager.find_one("users", {"_id": user_oid})
        if not user:
            return jsonify({"success": False, "error": "User not found"}), 404
        dutch_game = _dutch_game_with_inventory(user)
        return jsonify({"success": True, "inventory": dutch_game.get("inventory", _default_inventory()), "user_id": user_id}), 200
    except Exception as e:
        custom_log(f"❌ DutchGame: get_inventory_service error: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "error": "Failed to fetch inventory", "message": str(e)}), 500


def purchase_item_service():
    """Service endpoint: atomic coin spend + item grant (MVP)."""
    try:
        data = request.get_json() or {}
        user_id = (data.get("user_id") or getattr(request, "user_id", "") or "").strip()
        item_id = (data.get("item_id") or "").strip()
        idempotency_key = (data.get("idempotency_key") or "").strip() or None
        if not user_id or not item_id:
            return jsonify({"success": False, "error": "user_id and item_id are required"}), 400
        item = _find_catalog_item(item_id)
        if not item:
            return jsonify({"success": False, "error": "Unknown item_id"}), 400
        if not _app_manager:
            return jsonify({"success": False, "error": "Server not initialized"}), 503
        db_manager = _app_manager.get_db_manager(role="read_write")
        if not db_manager:
            return jsonify({"success": False, "error": "Database connection unavailable"}), 500
        try:
            user_oid = ObjectId(user_id)
        except Exception:
            return jsonify({"success": False, "error": "Invalid user_id"}), 400
        user = db_manager.find_one("users", {"_id": user_oid})
        if not user:
            return jsonify({"success": False, "error": "User not found"}), 404
        dutch_game = _dutch_game_with_inventory(user)
        current_coins = int((dutch_game.get("coins") or 0))
        price = int(item.get("price_coins") or 0)
        if current_coins < price:
            return jsonify({"success": False, "error": "insufficient_coins", "current_coins": current_coins, "price_coins": price}), 400
        inventory = dutch_game.get("inventory") or _default_inventory()
        delta: Dict[str, Any] = {}
        item_type = item.get("item_type")
        if item_type in ("booster", "booster_pack"):
            grant = item.get("grant") if isinstance(item.get("grant"), dict) else {}
            booster_key = str(grant.get("booster_key") or item.get("item_id") or BOOSTER_ITEM_ID).strip() or BOOSTER_ITEM_ID
            qty = int(grant.get("quantity") or item.get("quantity") or 1)
            qty = max(1, qty)
            inventory.setdefault("boosters", {})
            inventory["boosters"][booster_key] = int(inventory["boosters"].get(booster_key, 0) or 0) + qty
            delta["booster_added"] = qty
            delta["booster_key"] = booster_key
        elif item_type == "card_back":
            backs = set(inventory["cosmetics"].get("owned_card_backs", []))
            backs.add(item_id)
            inventory["cosmetics"]["owned_card_backs"] = sorted(list(backs))
            delta["owned_card_backs"] = 1
        elif item_type == "table_design":
            tables = set(inventory["cosmetics"].get("owned_table_designs", []))
            tables.add(item_id)
            inventory["cosmetics"]["owned_table_designs"] = sorted(list(tables))
            delta["owned_table_designs"] = 1
        else:
            return jsonify({"success": False, "error": "Unsupported item_type"}), 400

        update_result = db_manager.db["users"].update_one(
            {
                "_id": user_oid,
                "modules.dutch_game.coins": {"$gte": price},
            },
            {
                "$inc": {"modules.dutch_game.coins": -price},
                "$set": {
                    "modules.dutch_game.inventory": inventory,
                    "modules.dutch_game.last_updated": datetime.utcnow().isoformat(),
                    "updated_at": datetime.utcnow().isoformat(),
                },
            },
        )
        if not update_result or update_result.modified_count <= 0:
            return jsonify({"success": False, "error": "purchase_conflict_retry"}), 409
        refreshed_user = db_manager.find_one("users", {"_id": user_oid}) or {}
        tx_res = _insert_consumable_tx(
            db_manager,
            user_id=user_oid,
            tx_type="purchase_item",
            payload={"item_id": item_id, "price_coins": price, "delta": delta},
            idempotency_key=idempotency_key,
        )
        return jsonify({
            "success": True,
            "new_coin_balance": int((((refreshed_user.get("modules") or {}).get("dutch_game", {}) or {}).get("coins", 0))),
            "granted_item": {"item_id": item_id, "item_type": item_type},
            "inventory_delta": delta,
            "tx_id": tx_res.get("tx_id"),
        }), 200
    except Exception as e:
        custom_log(f"❌ DutchGame: purchase_item_service error: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "error": "Failed to purchase item", "message": str(e)}), 500


def equip_cosmetic_service():
    """Service endpoint: equip owned card_back or table_design cosmetics."""
    try:
        data = request.get_json() or {}
        user_id = (data.get("user_id") or getattr(request, "user_id", "") or "").strip()
        cosmetic_id = (data.get("cosmetic_id") or "").strip()
        slot = (data.get("slot") or "").strip()
        if not user_id or slot not in ("card_back", "table_design"):
            return jsonify({"success": False, "error": "user_id and valid slot required"}), 400
        if not _app_manager:
            return jsonify({"success": False, "error": "Server not initialized"}), 503
        db_manager = _app_manager.get_db_manager(role="read_write")
        if not db_manager:
            return jsonify({"success": False, "error": "Database connection unavailable"}), 500
        try:
            user_oid = ObjectId(user_id)
        except Exception:
            return jsonify({"success": False, "error": "Invalid user_id"}), 400
        user = db_manager.find_one("users", {"_id": user_oid})
        if not user:
            return jsonify({"success": False, "error": "User not found"}), 404
        inv = _dutch_game_with_inventory(user).get("inventory", _default_inventory())
        if slot == "card_back":
            if cosmetic_id == "":
                inv["cosmetics"]["equipped"]["card_back_id"] = ""
                db_manager.db["users"].update_one({"_id": user_oid}, {"$set": {"modules.dutch_game.inventory": inv, "modules.dutch_game.last_updated": datetime.utcnow().isoformat()}})
                _insert_consumable_tx(
                    db_manager,
                    user_id=user_oid,
                    tx_type="unequip_cosmetic",
                    payload={"slot": slot},
                )
                return jsonify({"success": True, "equipped": inv["cosmetics"]["equipped"]}), 200
            owned = set(inv["cosmetics"].get("owned_card_backs", []))
            if cosmetic_id not in owned:
                return jsonify({"success": False, "error": "cosmetic_not_owned"}), 400
            inv["cosmetics"]["equipped"]["card_back_id"] = cosmetic_id
        else:
            if cosmetic_id == "":
                inv["cosmetics"]["equipped"]["table_design_id"] = ""
                db_manager.db["users"].update_one({"_id": user_oid}, {"$set": {"modules.dutch_game.inventory": inv, "modules.dutch_game.last_updated": datetime.utcnow().isoformat()}})
                _insert_consumable_tx(
                    db_manager,
                    user_id=user_oid,
                    tx_type="unequip_cosmetic",
                    payload={"slot": slot},
                )
                return jsonify({"success": True, "equipped": inv["cosmetics"]["equipped"]}), 200
            owned = set(inv["cosmetics"].get("owned_table_designs", []))
            if cosmetic_id not in owned:
                return jsonify({"success": False, "error": "cosmetic_not_owned"}), 400
            inv["cosmetics"]["equipped"]["table_design_id"] = cosmetic_id
        db_manager.db["users"].update_one({"_id": user_oid}, {"$set": {"modules.dutch_game.inventory": inv, "modules.dutch_game.last_updated": datetime.utcnow().isoformat()}})
        _insert_consumable_tx(
            db_manager,
            user_id=user_oid,
            tx_type="equip_cosmetic",
            payload={"slot": slot, "cosmetic_id": cosmetic_id},
        )
        return jsonify({"success": True, "equipped": inv["cosmetics"]["equipped"]}), 200
    except Exception as e:
        custom_log(f"❌ DutchGame: equip_cosmetic_service error: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "error": "Failed to equip cosmetic", "message": str(e)}), 500


def consume_win_booster_service():
    """Service endpoint: consume one win booster (utility endpoint; primary consumption still occurs in update_game_stats)."""
    try:
        data = request.get_json() or {}
        user_id = (data.get("user_id") or getattr(request, "user_id", "") or "").strip()
        if not user_id:
            return jsonify({"success": False, "error": "user_id required"}), 400
        if not _app_manager:
            return jsonify({"success": False, "error": "Server not initialized"}), 503
        db_manager = _app_manager.get_db_manager(role="read_write")
        if not db_manager:
            return jsonify({"success": False, "error": "Database connection unavailable"}), 500
        try:
            user_oid = ObjectId(user_id)
        except Exception:
            return jsonify({"success": False, "error": "Invalid user_id"}), 400
        user = db_manager.find_one("users", {"_id": user_oid})
        if not user:
            return jsonify({"success": False, "error": "User not found"}), 404
        inv = _dutch_game_with_inventory(user).get("inventory", _default_inventory())
        current_qty = int(inv.get("boosters", {}).get(BOOSTER_ITEM_ID, 0) or 0)
        if current_qty <= 0:
            return jsonify({"success": False, "error": "no_booster_available"}), 400
        inv["boosters"][BOOSTER_ITEM_ID] = current_qty - 1
        db_manager.db["users"].update_one({"_id": user_oid}, {"$set": {"modules.dutch_game.inventory": inv}})
        tx = _insert_consumable_tx(
            db_manager,
            user_id=user_oid,
            tx_type="consume_win_booster_manual",
            payload={"remaining": inv["boosters"][BOOSTER_ITEM_ID]},
            idempotency_key=(data.get("idempotency_key") or "").strip() or None,
        )
        return jsonify({"success": True, "remaining": inv["boosters"][BOOSTER_ITEM_ID], "tx_id": tx.get("tx_id")}), 200
    except Exception as e:
        custom_log(f"❌ DutchGame: consume_win_booster_service error: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "error": "Failed to consume booster", "message": str(e)}), 500


def get_table_design_overlay_media():
    """Public media endpoint: map equipped table design skinId -> overlay image file."""
    try:
        skin_id = (request.args.get("skinId") or "").strip()
        media_path = _table_design_overlay_path_from_skin_id(skin_id)
        if media_path is None:
            media_path = SPONSORS_MEDIA_DIR / "table_logo.webp"
        if not media_path.exists():
            fallback_webp = SPONSORS_MEDIA_DIR / "table_logo.webp"
            fallback_png = SPONSORS_MEDIA_DIR / "table_logo.png"
            if fallback_webp.exists():
                if LOGGING_SWITCH:
                    custom_log(
                        f"🖼️ DutchGame: table overlay fallback used skinId={skin_id} missing={media_path}",
                        level="WARNING",
                        isOn=LOGGING_SWITCH,
                    )
                return send_file(fallback_webp, mimetype="image/webp")
            if fallback_png.exists():
                if LOGGING_SWITCH:
                    custom_log(
                        f"🖼️ DutchGame: png table overlay fallback used skinId={skin_id} missing={media_path}",
                        level="WARNING",
                        isOn=LOGGING_SWITCH,
                    )
                return send_file(fallback_png, mimetype="image/png")
            return jsonify({"success": False, "error": "media_not_found", "message": f"Missing media file: {media_path}"}), 404

        if LOGGING_SWITCH:
            custom_log(
                f"🖼️ DutchGame: table overlay served skinId={skin_id} file={media_path}",
                level="INFO",
                isOn=LOGGING_SWITCH,
            )
        if media_path.suffix.lower() == ".webp":
            return send_file(media_path, mimetype="image/webp")
        return send_file(media_path, mimetype="image/png")
    except Exception as e:
        custom_log(f"❌ DutchGame: get_table_design_overlay_media error: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "error": "failed_to_serve_table_overlay", "message": str(e)}), 500


def serve_table_tier_background_public(filename: str):
    """Public: serve packed WebP/PNG tier back-graphic referenced by declarative catalog (supports safe subpaths)."""
    try:
        raw = unquote(str(filename or ""))
        normalized = raw.replace("\\", "/").lstrip("/")
        parts = [p for p in normalized.split("/") if p not in ("", ".")]
        if not parts or any(p == ".." for p in parts):
            return jsonify({"success": False, "error": "bad_filename", "message": "invalid path"}), 400
        if any(not re.match(r"^[A-Za-z0-9._-]+$", p) for p in parts):
            return jsonify({"success": False, "error": "bad_filename", "message": "invalid characters"}), 400
        rel_path = Path(*parts)
        media_path = (TABLE_TIER_BACKGRAPHICS_DIR / rel_path).resolve()
        root = TABLE_TIER_BACKGRAPHICS_DIR.resolve()
        try:
            media_path.relative_to(root)
        except ValueError:
            return jsonify({"success": False, "error": "not_found"}), 404
        if not media_path.exists() or not media_path.is_file():
            return jsonify({"success": False, "error": "media_not_found", "message": str(rel_path)}), 404
        suf = media_path.suffix.lower()
        return send_file(media_path, mimetype=_BG_EXT_TO_MIME.get(suf, "application/octet-stream"))
    except Exception as e:
        custom_log(f"❌ DutchGame: serve_table_tier_background_public error: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "error": "failed_to_serve", "message": str(e)}), 500


def get_card_back_media():
    """Public media endpoint: map equipped card-back skinId -> media file."""
    try:
        skin_id = (request.args.get("skinId") or "").strip()
        media_path = _card_back_path_from_skin_id(skin_id)
        if media_path is None:
            media_path = SPONSORS_MEDIA_DIR / "card_back.webp"

        if not media_path.exists():
            fallback_webp = SPONSORS_MEDIA_DIR / "card_back.webp"
            fallback_png = SPONSORS_MEDIA_DIR / "card_back.png"
            if fallback_webp.exists():
                if LOGGING_SWITCH:
                    custom_log(
                        f"🖼️ DutchGame: card back fallback used skinId={skin_id} missing={media_path}",
                        level="WARNING",
                        isOn=LOGGING_SWITCH,
                    )
                return send_file(fallback_webp, mimetype="image/webp")
            if fallback_png.exists():
                if LOGGING_SWITCH:
                    custom_log(
                        f"🖼️ DutchGame: png card back fallback used skinId={skin_id} missing={media_path}",
                        level="WARNING",
                        isOn=LOGGING_SWITCH,
                    )
                return send_file(fallback_png, mimetype="image/png")
            return jsonify({"success": False, "error": "media_not_found", "message": f"Missing media file: {media_path}"}), 404

        if LOGGING_SWITCH:
            custom_log(
                f"🖼️ DutchGame: card back served skinId={skin_id} file={media_path}",
                level="INFO",
                isOn=LOGGING_SWITCH,
            )
        if media_path.suffix.lower() == ".webp":
            return send_file(media_path, mimetype="image/webp")
        return send_file(media_path, mimetype="image/png")
    except Exception as e:
        custom_log(f"❌ DutchGame: get_card_back_media error: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "error": "failed_to_serve_card_back", "message": str(e)}), 500


def _deduct_game_coins_from_body(data: Dict[str, Any]):
    """Shared body for JWT and Dart service deduct-game-coins routes."""
    _raw_coin_req = data.get("is_coin_required", data.get("isCoinRequired"))
    game_coin_required = True if _raw_coin_req is None else bool(_raw_coin_req)

    game_id = data.get('game_id')
    player_ids = data.get('player_ids')
    if not game_id or not isinstance(game_id, str):
        return jsonify({"success": False, "error": "Invalid game_id", "message": "game_id is required and must be a string"}), 400
    if not player_ids or not isinstance(player_ids, list) or len(player_ids) == 0:
        return jsonify({"success": False, "error": "Invalid player_ids", "message": "player_ids must be a non-empty array"}), 400

    if not game_coin_required:
        if LOGGING_SWITCH:
            custom_log(
                f"📊 DutchGame: deduct_game_coins skipped (is_coin_required=false) game_id={game_id} players={len(player_ids)}",
                level="INFO",
                isOn=LOGGING_SWITCH,
            )
        if not _app_manager:
            return jsonify({"success": False, "error": "Server not initialized"}), 503
        db_manager = _app_manager.get_db_manager(role="read_write")
        if not db_manager:
            return jsonify({"success": False, "error": "Database connection unavailable", "message": "Failed to connect to database"}), 500
        updated_players = []
        errors = []
        for player_id_str in player_ids:
            try:
                if not player_id_str or not isinstance(player_id_str, str):
                    errors.append(f"Invalid player_id format: {player_id_str}")
                    continue
                try:
                    player_id = ObjectId(player_id_str)
                except Exception:
                    errors.append(f"Invalid player_id format '{player_id_str}'")
                    continue
                user = db_manager.find_one("users", {"_id": player_id})
                if not user:
                    errors.append(f"User not found: {player_id_str}")
                    continue
                dutch_game = (user.get("modules") or {}).get("dutch_game", {})
                updated_players.append({
                    "user_id": player_id_str,
                    "coins_deducted": 0,
                    "previous_coins": dutch_game.get("coins", 0),
                    "new_coins": dutch_game.get("coins", 0),
                    "skipped": True,
                    "reason": "coin_match_disabled",
                })
            except Exception as e:
                errors.append(f"Error processing player {player_id_str}: {str(e)}")
        if len(updated_players) > 0:
            response_data = {
                "success": True,
                "message": f"Coin match disabled — recorded {len(updated_players)} player(s) as skipped",
                "game_id": game_id,
                "coins_deducted": 0,
                "updated_players": updated_players,
            }
            if errors:
                response_data["warnings"] = errors
            return jsonify(response_data), 200
        return jsonify({
            "success": False,
            "message": "Failed to record skipped players",
            "error": "All players failed validation",
            "errors": errors,
        }), 500

    # Room table tier (1–4): fee is defined by table, not user progression level.
    game_table_level = data.get('game_table_level')
    coins = data.get('coins')
    # Used for eligibility (user level gate). If game_table_level is missing, we may infer from coins.
    table_level_for_gate: Optional[int] = None
    if game_table_level is not None:
        try:
            gt = int(game_table_level)
        except (TypeError, ValueError):
            return jsonify({"success": False, "error": "Invalid game_table_level", "message": "game_table_level must be an integer"}), 400
        if not matcher.is_valid_level(gt):
            return jsonify({"success": False, "error": "Invalid game_table_level", "message": "game_table_level is not a configured room table tier"}), 400
        fee = matcher.table_level_to_coin_fee(gt, default_fee=25)
        if coins is not None and coins != fee:
            return jsonify({
                "success": False,
                "error": "coins_mismatch",
                "message": f"coins must match table fee ({fee}) for game_table_level={gt}",
            }), 400
        coins = fee
        table_level_for_gate = gt
    if coins is None or not isinstance(coins, int) or coins <= 0:
        return jsonify({"success": False, "error": "Invalid coins amount", "message": "coins must be a positive integer, or send a valid game_table_level"}), 400

    # If caller didn't provide game_table_level, infer it from the coin fee (defensive fallback).
    if table_level_for_gate is None:
        for lvl in matcher.LEVEL_ORDER:
            expected_fee = matcher.table_level_to_coin_fee(lvl, default_fee=25)
            if coins == expected_fee:
                table_level_for_gate = lvl
                break

    if not _app_manager:
        return jsonify({"success": False, "error": "Server not initialized"}), 503
    db_manager = _app_manager.get_db_manager(role="read_write")
    if not db_manager:
        return jsonify({"success": False, "error": "Database connection unavailable", "message": "Failed to connect to database"}), 500
    current_timestamp = datetime.utcnow().isoformat()
    if LOGGING_SWITCH:
        custom_log(
            f"📊 DutchGame: deduct_game_coins start game_id={game_id} fee={coins} game_table_level={table_level_for_gate} players={len(player_ids)}",
            level="INFO",
            isOn=LOGGING_SWITCH,
        )
    updated_players = []
    errors = []
    for player_id_str in player_ids:
        try:
            if not player_id_str or not isinstance(player_id_str, str):
                errors.append(f"Invalid player_id format: {player_id_str}")
                continue
            try:
                player_id = ObjectId(player_id_str)
            except Exception as e:
                errors.append(f"Invalid player_id format '{player_id_str}': {str(e)}")
                continue
            user = db_manager.find_one("users", {"_id": player_id})
            if not user:
                errors.append(f"User not found: {player_id_str}")
                continue
            modules = user.get('modules', {})
            dutch_game = modules.get('dutch_game', {})
            subscription_tier = dutch_game.get('subscription_tier') or matcher.TIER_PROMOTIONAL

            # Eligibility gate: progression level must be high enough for the room table tier.
            # This is a defense-in-depth check; Dart should already have validated on join/create.
            user_level_raw = dutch_game.get('level', matcher.DEFAULT_LEVEL)
            try:
                user_level = int(user_level_raw)
            except (TypeError, ValueError):
                user_level = matcher.DEFAULT_LEVEL
            if table_level_for_gate is not None:
                if not WinsLevelRankMatcher.user_may_join_game_table(user_level, table_level_for_gate):
                    errors.append(
                        f"User level too low for table tier: user {player_id_str} level={user_level} table={table_level_for_gate}"
                    )
                    continue

            if matcher.should_skip_match_coin_economy(subscription_tier, is_coin_required=game_coin_required):
                updated_players.append({"user_id": player_id_str, "coins_deducted": 0, "previous_coins": dutch_game.get('coins', 0), "new_coins": dutch_game.get('coins', 0), "skipped": True, "reason": "promotional_tier"})
                continue
            current_coins = dutch_game.get('coins', 0)
            if current_coins < coins:
                errors.append(f"Insufficient coins for user {player_id_str}: has {current_coins}, needs {coins}")
                continue
            new_coins = current_coins - coins
            update_operation = {'$inc': {'modules.dutch_game.coins': -coins}, '$set': {'modules.dutch_game.last_updated': current_timestamp, 'updated_at': current_timestamp}}
            result = db_manager.db["users"].update_one({"_id": player_id}, update_operation)
            if result.modified_count > 0:
                updated_players.append({"user_id": player_id_str, "coins_deducted": coins, "previous_coins": current_coins, "new_coins": new_coins})
            else:
                errors.append(f"Failed to update coins for user: {player_id_str}")
        except Exception as e:
            errors.append(f"Error processing coin deduction for player {player_id_str}: {str(e)}")
    if len(updated_players) > 0:
        if LOGGING_SWITCH:
            custom_log(
                f"📊 DutchGame: deduct_game_coins ok game_id={game_id} fee={coins} updated={len(updated_players)} error_lines={len(errors)}",
                level="INFO",
                isOn=LOGGING_SWITCH,
            )
        response_data = {"success": True, "message": f"Coins deducted successfully for {len(updated_players)} player(s)", "game_id": game_id, "coins_deducted": coins, "updated_players": updated_players}
        if errors:
            response_data["warnings"] = errors
        return jsonify(response_data), 200
    if LOGGING_SWITCH:
        custom_log(
            f"📊 DutchGame: deduct_game_coins failed game_id={game_id} fee={coins} errors={errors!r}",
            level="WARNING",
            isOn=LOGGING_SWITCH,
        )
    return jsonify({"success": False, "message": "Failed to deduct coins for any player", "error": "All deductions failed", "errors": errors}), 500


def deduct_game_coins():
    """Deduct game coins when a match starts (JWT).

    Fee is defined by room **table** tier (1–4), not user progression level. This endpoint also enforces
    the eligibility gate that a player's progression ``modules.dutch_game.level`` must be >= the room
    ``game_table_level`` tier (table 1 open; tables 2–4 require level >= tier).

    Optional body field ``game_table_level`` (1–4): server sets the deduction to ``table_level_to_coin_fee``;
    if ``coins`` is also sent it must match that fee.

    Optional ``is_coin_required`` / ``isCoinRequired`` (default true): when false, no coin validation and all
    players are recorded as skipped (``coin_match_disabled``); same economy SSOT as ``update_game_stats``.
    """
    try:
        user_id = request.user_id
        if not user_id:
            return jsonify({"success": False, "error": "User not authenticated", "message": "No user ID found in request"}), 401
        data = request.get_json()
        if not data:
            return jsonify({"success": False, "error": "Request body is required", "message": "Missing request body"}), 400
        return _deduct_game_coins_from_body(data)
    except Exception as e:
        custom_log(f"❌ DutchGame: Error in deduct_game_coins: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "message": "Failed to deduct game coins", "error": str(e)}), 500


def deduct_game_coins_service():
    """Dart WebSocket backend: deduct entry coins when a match starts (X-Service-Key). Same rules as [deduct_game_coins]."""
    try:
        data = request.get_json()
        if not data:
            return jsonify({"success": False, "error": "Request body is required", "message": "Missing request body"}), 400
        return _deduct_game_coins_from_body(data)
    except Exception as e:
        custom_log(f"❌ DutchGame: Error in deduct_game_coins_service: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "message": "Failed to deduct game coins", "error": str(e)}), 500


def create_tournament():
    """Create a tournament in the DB (JWT auth). Admin only. Creator is the authenticated user."""
    try:
        err_response, err_status = _require_admin()
        if err_response is not None:
            return err_response, err_status
        creator_id = request.user_id
        data = request.get_json(silent=True) or {}
        if not _app_manager:
            return jsonify({"success": False, "error": "Server not initialized"}), 503
        db_manager = _app_manager.get_db_manager(role="read_write")
        if not db_manager:
            return jsonify({"success": False, "error": "Database unavailable"}), 503
        tournament_id, created_at, err = create_tournament_in_db(creator_id, data, db_manager)
        if err:
            status = 400 if "required" in err or "valid" in err else 500
            return jsonify({"success": False, "error": err}), status
        custom_log(f"DutchGame: create_tournament id={tournament_id} creator_id={creator_id}", level="INFO", isOn=LOGGING_SWITCH)
        return jsonify({"success": True, "tournament_id": tournament_id, "created_at": created_at}), 200
    except Exception as e:
        custom_log(f"DutchGame: create_tournament error: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "error": str(e)}), 500


def get_tournaments():
    """Get all tournaments with full data (JWT auth). Admin only. Used by Admin Tournaments screen."""
    try:
        err_response, err_status = _require_admin()
        if err_response is not None:
            return err_response, err_status
        if not _app_manager:
            return jsonify({"success": False, "error": "Server not initialized"}), 503
        db_manager = _app_manager.get_db_manager(role="read_only")
        if not db_manager:
            return jsonify({"success": False, "error": "Database unavailable"}), 503
        raw = db_manager.find("tournaments", {})
        tournaments = list(raw) if raw else []
        out = []
        for d in tournaments:
            j = _tournament_doc_to_json(d)
            j["id"] = str(d.get("_id", ""))
            out.append(j)
        custom_log(
            f"DutchGame: get_tournaments admin ok count={len(out)}",
            level="INFO",
            isOn=LOGGING_SWITCH,
        )
        return jsonify({"success": True, "tournaments": out}), 200
    except Exception as e:
        custom_log(f"DutchGame: get_tournaments error: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "error": str(e), "tournaments": []}), 500


def _mongo_user_ids_from_store_snapshot(store_snapshot: Dict[str, Any]) -> list:
    """Collect human Mongo user ids from Dart game_state.players (userId / user_id)."""
    out = []
    gs = store_snapshot.get("game_state") if isinstance(store_snapshot, dict) else None
    if not isinstance(gs, dict):
        return out
    players = gs.get("players") or []
    if not isinstance(players, list):
        return out
    for p in players:
        if not isinstance(p, dict):
            continue
        uid = (p.get("userId") or p.get("user_id") or "").strip()
        if not uid:
            continue
        try:
            ObjectId(uid)
        except Exception:
            continue
        if uid not in out:
            out.append(uid)
    return out


def _append_match_row_to_tournament(
    tournament_oid: ObjectId,
    tournament_id_str: str,
    user_id_strs: list,
    db_manager,
    room_id_str: str = "",
    start_date_str: str = "",
) -> tuple[Optional[Dict[str, Any]], Optional[str]]:
    """Append one match row (same schema as add_tournament_match). Returns (result dict, error message)."""
    if not user_id_strs:
        return None, "user_id_strs is empty"
    tournament = db_manager.find_one("tournaments", {"_id": tournament_oid})
    if not tournament:
        return None, "Tournament not found"

    user_oids = []
    for uid_str in user_id_strs:
        try:
            user_oids.append(ObjectId(uid_str))
        except Exception:
            return None, f"Invalid user_id format: {uid_str}"

    matches = tournament.get("matches") or []
    next_index = 1
    if matches:
        indices = [m.get("match_index") for m in matches if isinstance(m, dict) and m.get("match_index") is not None]
        next_index = max(indices, default=0) + 1

    now = datetime.utcnow()
    updated_at = now.isoformat() + "Z"
    match_date = now.date().isoformat() if hasattr(now, "date") else updated_at[:10]
    if start_date_str:
        try:
            datetime.strptime(start_date_str[:10], "%Y-%m-%d")
            match_date = start_date_str[:10]
        except ValueError:
            pass

    match_id_str = now.strftime("%Y%m%d%H%M%S") + "_" + uuid.uuid4().hex[:8]

    players = []
    for uid_str in user_id_strs:
        entry = {"user_id": uid_str, "username": "", "email": "", "points": 0, "number_of_cards_left": []}
        try:
            u = db_manager.find_one("users", {"_id": ObjectId(uid_str)})
            if u:
                entry["username"] = (u.get("username") or "").strip() or ("user_%s" % uid_str[:8])
                entry["email"] = (u.get("email") or "").strip()
                entry["is_comp_player"] = u.get("is_comp_player") is True
        except Exception:
            pass
        players.append(entry)
    scores = [
        {"user_id": uid, "end_card_count": 0, "total_end_points": 0}
        for uid in user_id_strs
    ]

    new_match = {
        "match_id": match_id_str,
        "match_index": next_index,
        "status": "pending",
        "room_id": (room_id_str or "").strip(),
        "winner": "",
        "user_ids": user_oids,
        "match_date": match_date,
        "start_date": match_date,
        "players": players,
        "scores": scores,
    }

    update_op = {
        "$push": {"matches": new_match},
        "$set": {"updated_at": updated_at},
    }
    try:
        result = db_manager.db["tournaments"].update_one(
            {"_id": tournament_oid},
            update_op,
        )
    except Exception as db_err:
        custom_log(f"DutchGame: _append_match_row_to_tournament db error: {db_err}", level="ERROR", isOn=LOGGING_SWITCH)
        return None, "Failed to update tournament"

    if not result or result.modified_count == 0:
        return None, "Failed to add match (no document modified)"

    return {
        "match_id": match_id_str,
        "match_index": next_index,
        "tournament_id": tournament_id_str,
        "user_ids": user_id_strs,
    }, None


def add_tournament_match():
    """Add a match to a tournament (JWT auth, admin only). POST body: tournament_id, user_ids (invited players), start_date (optional).
    Finds the tournament in DB and appends a new match with players (user_id, username, email, points, number_of_cards_left per playbook)."""
    try:
        err_response, err_status = _require_admin()
        if err_response is not None:
            return err_response, err_status
        data = request.get_json(silent=True) or {}
        tournament_id = (data.get("tournament_id") or "").strip()
        selected_players = data.get("user_ids") or data.get("selected_players") or data.get("player_ids") or []
        start_date_str = (data.get("start_date") or data.get("match_date") or "").strip()
        if not tournament_id:
            return jsonify({"success": False, "error": "tournament_id is required"}), 400
        if not isinstance(selected_players, list):
            return jsonify({"success": False, "error": "user_ids must be an array of user_id values"}), 400
        user_id_strs = [str(uid).strip() for uid in selected_players if uid is not None and str(uid).strip()]
        if not user_id_strs:
            return jsonify({"success": False, "error": "At least one player (user_id) is required"}), 400

        try:
            tournament_oid = ObjectId(tournament_id)
        except Exception:
            return jsonify({"success": False, "error": "Invalid tournament_id format"}), 400

        if not _app_manager:
            return jsonify({"success": False, "error": "Server not initialized"}), 503
        db_manager = _app_manager.get_db_manager(role="read_write")
        if not db_manager:
            return jsonify({"success": False, "error": "Database unavailable"}), 503

        res, err = _append_match_row_to_tournament(
            tournament_oid,
            tournament_id,
            user_id_strs,
            db_manager,
            room_id_str="",
            start_date_str=start_date_str,
        )
        if err or not res:
            status = 404 if err == "Tournament not found" else 500
            return jsonify({"success": False, "error": err or "append failed"}), status

        custom_log(
            f"DutchGame: add_tournament_match tournament_id={tournament_id} match_index={res['match_index']} players={len(user_id_strs)}",
            level="INFO",
            isOn=LOGGING_SWITCH,
        )
        return jsonify({
            "success": True,
            "message": "Match added",
            "tournament_id": tournament_id,
            "match_index": res["match_index"],
            "match_id": res["match_id"],
            "user_ids": user_id_strs,
        }), 200
    except Exception as e:
        custom_log(f"DutchGame: add_tournament_match error: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "error": str(e)}), 500


def update_tournament_match():
    """Update a tournament match: add invited users to players and/or set start_date (JWT auth, admin only).
    POST body: tournament_id, match_index, user_ids (to add to players), start_date (optional)."""
    try:
        err_response, err_status = _require_admin()
        if err_response is not None:
            return err_response, err_status
        data = request.get_json(silent=True) or {}
        tournament_id = (data.get("tournament_id") or "").strip()
        match_index = data.get("match_index") if data.get("match_index") is not None else data.get("match_id")
        add_user_ids = data.get("user_ids") or data.get("selected_players") or data.get("player_ids") or []
        start_date_str = (data.get("start_date") or data.get("match_date") or "").strip()
        if not tournament_id:
            return jsonify({"success": False, "error": "tournament_id is required"}), 400
        if match_index is None:
            return jsonify({"success": False, "error": "match_index is required"}), 400
        if not isinstance(add_user_ids, list):
            add_user_ids = []
        user_id_strs = [str(uid).strip() for uid in add_user_ids if uid is not None and str(uid).strip()]

        try:
            tournament_oid = ObjectId(tournament_id)
        except Exception:
            return jsonify({"success": False, "error": "Invalid tournament_id format"}), 400

        if not _app_manager:
            return jsonify({"success": False, "error": "Server not initialized"}), 503
        db_manager = _app_manager.get_db_manager(role="read_write")
        if not db_manager:
            return jsonify({"success": False, "error": "Database unavailable"}), 503

        tournament = db_manager.find_one("tournaments", {"_id": tournament_oid})
        if not tournament:
            return jsonify({"success": False, "error": "Tournament not found"}), 404

        matches = list(tournament.get("matches") or [])
        match_idx = None
        for i, m in enumerate(matches):
            if isinstance(m, dict) and m.get("match_index") == match_index:
                match_idx = i
                break
        if match_idx is None:
            return jsonify({"success": False, "error": "Match not found for match_index"}), 404

        match = dict(matches[match_idx])
        existing_player_ids = {str(p.get("user_id") or p.get("_id") or "") for p in (match.get("players") or []) if p}
        players = list(match.get("players") or [])
        user_ids = list(match.get("user_ids") or [])

        for uid_str in user_id_strs:
            if uid_str in existing_player_ids:
                continue
            try:
                user_oid = ObjectId(uid_str)
            except Exception:
                continue
            entry = {"user_id": uid_str, "username": "", "email": "", "points": 0, "number_of_cards_left": []}
            u = db_manager.find_one("users", {"_id": user_oid})
            if u:
                entry["username"] = (u.get("username") or "").strip() or ("user_%s" % uid_str[:8])
                entry["email"] = (u.get("email") or "").strip()
            players.append(entry)
            user_ids.append(user_oid)
            existing_player_ids.add(uid_str)

        match["players"] = players
        match["user_ids"] = user_ids
        if start_date_str:
            try:
                datetime.strptime(start_date_str[:10], "%Y-%m-%d")
                match["match_date"] = start_date_str[:10]
                match["start_date"] = start_date_str[:10]
            except ValueError:
                pass

        now = datetime.utcnow()
        updated_at = now.isoformat() + "Z"
        matches[match_idx] = match

        update_op = {"$set": {"matches": matches, "updated_at": updated_at}}
        try:
            result = db_manager.db["tournaments"].update_one({"_id": tournament_oid}, update_op)
        except Exception as db_err:
            custom_log(f"DutchGame: update_tournament_match db error: {db_err}", level="ERROR", isOn=LOGGING_SWITCH)
            return jsonify({"success": False, "error": "Failed to update tournament"}), 500

        if not result or result.modified_count == 0:
            return jsonify({"success": False, "error": "Failed to update match (no document modified)"}), 500

        custom_log(f"DutchGame: update_tournament_match tournament_id={tournament_id} match_index={match_index} added={len(user_id_strs)}", level="INFO", isOn=LOGGING_SWITCH)
        return jsonify({
            "success": True,
            "message": "Match updated",
            "tournament_id": tournament_id,
            "match_index": match_index,
            "user_ids_added": user_id_strs,
        }), 200
    except Exception as e:
        custom_log(f"DutchGame: update_tournament_match error: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "error": str(e)}), 500


def start_tournament_match():
    """Start a tournament match (JWT auth, admin only). Loads tournament + match from DB and returns create_room_payload.
    Client (e.g. dashboard) must emit create_room with this payload (WebSocket), then call attach_tournament_match_room
    with the returned room_id so we update the match and send in-place notifications to join (skip accept step).
    POST body: tournament_id, match_index. Optional: user_ids to override match participants."""
    try:
        err_response, err_status = _require_admin()
        if err_response is not None:
            return err_response, err_status
        data = request.get_json(silent=True) or {}
        tournament_id = (data.get("tournament_id") or "").strip()
        match_index = data.get("match_index") or data.get("match_id")
        if not tournament_id:
            return jsonify({"success": False, "error": "tournament_id is required"}), 400
        if match_index is None:
            return jsonify({"success": False, "error": "match_index (or match_id) is required"}), 400
        try:
            tournament_oid = ObjectId(tournament_id)
        except Exception:
            return jsonify({"success": False, "error": "Invalid tournament_id format"}), 400
        if not _app_manager:
            return jsonify({"success": False, "error": "Server not initialized"}), 503
        db_manager = _app_manager.get_db_manager(role="read_only")
        if not db_manager:
            return jsonify({"success": False, "error": "Database unavailable"}), 503
        tournament = db_manager.find_one("tournaments", {"_id": tournament_oid})
        if not tournament:
            return jsonify({"success": False, "error": "Tournament not found"}), 404
        matches = tournament.get("matches") or []
        match = None
        for m in matches:
            if isinstance(m, dict) and m.get("match_index") == match_index:
                match = m
                break
        if not match:
            return jsonify({"success": False, "error": "Match not found for given match_index"}), 404
        # Participant user_ids from match (ObjectId or str)
        match_user_ids = match.get("user_ids") or []
        match_players = match.get("players") or []
        user_id_strs = []
        for uid in match_user_ids:
            user_id_strs.append(str(uid) if uid is not None else None)
        user_id_strs = [u for u in user_id_strs if u]
        if not user_id_strs:
            return jsonify({"success": False, "error": "Match has no participants (user_ids)"}), 400
        # Build accepted_players: [{ user_id, username, is_comp_player }]
        # Prefer is_comp_player from tournament.participants (by user_id) so add_launch_participant / script updates apply
        participants_by_id = {str(p.get("user_id") or p.get("_id") or ""): p for p in (tournament.get("participants") or []) if p}
        accepted_players = []
        for uid in user_id_strs:
            uid_norm = str(uid)
            player_entry = next((p for p in match_players if str(p.get("user_id", p.get("_id", ""))) == uid_norm), None)
            part = participants_by_id.get(uid_norm) or {}
            username = (part.get("username") or (player_entry or {}).get("username") or "").strip()
            # is_comp_player: 1) tournament.participants 2) match.players 3) users table
            is_comp = False
            if part.get("is_comp_player") is True:
                is_comp = True
            elif (player_entry or {}).get("is_comp_player") is True:
                is_comp = True
            u = None
            try:
                u = db_manager.find_one("users", {"_id": ObjectId(uid_norm)})
            except Exception:
                pass
            if u:
                if not username:
                    username = (u.get("username") or "").strip()
                if not is_comp and u.get("is_comp_player") is True:
                    is_comp = True
            if not username:
                username = "user_%s" % uid_norm[:8]
            accepted_players.append({"user_id": uid_norm, "username": username, "is_comp_player": is_comp})
        # Tournament data from DB to pass into game state
        tournament_data = {
            "tournament_id": tournament_id,
            "match_index": match_index,
            "name": tournament.get("name"),
            "start_date": tournament.get("start_date").isoformat() if hasattr(tournament.get("start_date"), "isoformat") else tournament.get("start_date"),
        }
        match_date = match.get("match_date")
        if match_date is not None:
            tournament_data["match_date"] = match_date.isoformat() if hasattr(match_date, "isoformat") else match_date
        scores = match.get("scores") or []
        if scores:
            def _score_item(s):
                out = {}
                for k, v in (s or {}).items():
                    if isinstance(v, ObjectId):
                        out[k] = str(v)
                    elif hasattr(v, "isoformat"):
                        out[k] = v.isoformat()
                    else:
                        out[k] = v
                return out
            tournament_data["scores"] = [_score_item(s) for s in scores if isinstance(s, dict)]
        # Payload for client to emit create_room (same shape as lobby create; in-place notification sent after attach_tournament_match_room)
        create_room_payload = {
            "is_tournament": True,
            "tournament_data": tournament_data,
            "accepted_players": accepted_players,
            "add_creator_to_room": False,
            "auto_start": True,
            "min_players": len(user_id_strs),
            "max_players": 4,
            "game_type": "classic",
            "permission": "private",
            "is_coin_required": False,
        }
        return jsonify({
            "success": True,
            "message": "Use create_room_payload to emit create_room via WebSocket, then call attach_tournament_match_room with room_id",
            "tournament_id": tournament_id,
            "match_index": match_index,
            "create_room_payload": create_room_payload,
        }), 200
    except Exception as e:
        custom_log(f"DutchGame: start_tournament_match error: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "error": str(e)}), 500


def _attach_tournament_match_room_impl(tournament_id, match_index, room_id):
    """Shared logic: set room_id on the tournament match. Returns (response_dict, status_code)."""
    if not tournament_id or not room_id:
        return {"success": False, "error": "tournament_id and room_id are required"}, 400
    if match_index is None:
        return {"success": False, "error": "match_index (or match_id) is required"}, 400
    try:
        tournament_oid = ObjectId(tournament_id)
    except Exception:
        return {"success": False, "error": "Invalid tournament_id format"}, 400
    if not _app_manager:
        return {"success": False, "error": "Server not initialized"}, 503
    db_manager = _app_manager.get_db_manager(role="read_write")
    if not db_manager:
        return {"success": False, "error": "Database unavailable"}, 503
    tournament = db_manager.find_one("tournaments", {"_id": tournament_oid})
    if not tournament:
        return {"success": False, "error": "Tournament not found"}, 404
    matches = list(tournament.get("matches") or [])
    match_idx = None
    for i, m in enumerate(matches):
        if not isinstance(m, dict):
            continue
        # Match by match_index (int) or by match_id (string)
        if m.get("match_index") == match_index:
            match_idx = i
            break
        try:
            if isinstance(match_index, str) and match_index.isdigit() and m.get("match_index") == int(match_index):
                match_idx = i
                break
        except (TypeError, ValueError):
            pass
        if m.get("match_id") == match_index:
            match_idx = i
            break
    if match_idx is None:
        return {"success": False, "error": "Match not found for given match_index/match_id"}, 404
    matches[match_idx] = dict(matches[match_idx])
    matches[match_idx]["room_id"] = room_id
    now = datetime.utcnow()
    updated_at = now.isoformat() + "Z"
    try:
        db_manager.db["tournaments"].update_one(
            {"_id": tournament_oid},
            {"$set": {"matches": matches, "updated_at": updated_at}},
        )
    except Exception as db_err:
        custom_log(f"DutchGame: attach_tournament_match_room db error: {db_err}", level="ERROR", isOn=LOGGING_SWITCH)
        return {"success": False, "error": "Failed to update tournament"}, 500
    custom_log(f"DutchGame: attach_tournament_match_room tournament_id={tournament_id} match_index={match_index} room_id={room_id}", level="INFO", isOn=LOGGING_SWITCH)
    # Enriched roster for Dart: comp vs human so start_match can add tournament comps before random Flask CPUs
    match_row = matches[match_idx]
    players_raw = match_row.get("players") or []
    match_players_out: List[Dict[str, Any]] = []
    for p in players_raw:
        if not isinstance(p, dict):
            continue
        uid = (p.get("user_id") or "").strip()
        if not uid:
            continue
        udoc = None
        try:
            uoid = ObjectId(uid)
            udoc = db_manager.find_one("users", {"_id": uoid})
        except Exception:
            pass
        is_comp = bool(udoc and udoc.get("is_comp_player") is True)
        uname = (p.get("username") or "").strip()
        if not uname and udoc:
            uname = (udoc.get("username") or "").strip()
        if not uname:
            uname = "user_%s" % (uid[:8],)
        match_players_out.append(
            {
                "user_id": uid,
                "username": uname,
                "is_comp_player": is_comp,
                "isHuman": not is_comp,
            }
        )
    return {
        "success": True,
        "message": "Match updated",
        "room_id": room_id,
        "match_players": match_players_out,
    }, 200


def attach_tournament_match_room():
    """After client has created the room via WebSocket, call this to set room_id on the match and send in-place
    notifications to participants to join (skip accept step). JWT auth, admin only.
    POST body: tournament_id, match_index, room_id."""
    try:
        err_response, err_status = _require_admin()
        if err_response is not None:
            return err_response, err_status
        data = request.get_json(silent=True) or {}
        tournament_id = (data.get("tournament_id") or "").strip()
        match_index = data.get("match_index") or data.get("match_id")
        room_id = (data.get("room_id") or "").strip()
        result, status = _attach_tournament_match_room_impl(tournament_id, match_index, room_id)
        return jsonify(result), status
    except Exception as e:
        custom_log(f"DutchGame: attach_tournament_match_room error: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "error": str(e)}), 500


def attach_tournament_match_room_service():
    """Set room_id on a tournament match (service endpoint: Dart backend, X-Service-Key auth).
    POST body: tournament_id, match_index (or match_id), room_id."""
    try:
        data = request.get_json(silent=True) or {}
        tournament_id = (data.get("tournament_id") or "").strip()
        match_index = data.get("match_index") or data.get("match_id")
        room_id = (data.get("room_id") or "").strip()
        custom_log(
            f"DutchGame: attach_tournament_match_room_service request tournament_id={tournament_id!r} match_index={match_index!r} room_id={room_id!r}",
            level="INFO",
            isOn=LOGGING_SWITCH,
        )
        result, status = _attach_tournament_match_room_impl(tournament_id, match_index, room_id)
        return jsonify(result), status
    except Exception as e:
        custom_log(f"DutchGame: attach_tournament_match_room_service error: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "error": str(e)}), 500


def rematch_tournament_snapshot_service():
    """Dart rematch: create or extend `online` / `single_room_league` tournament, append match, set room_id (X-Service-Key).

    POST body: room_id, store_snapshot, room_snapshot.

    Optional ``initial_match_game_results`` (same shape as ``update-game-stats`` ``game_results``): when **creating**
    a new tournament (first rematch after a casual game), rows for the **finished** game are applied as
    ``match_index`` 1 ``completed`` before appending the pending row for the next game."""
    try:
        data = request.get_json(silent=True) or {}
        room_id = (data.get("room_id") or "").strip()
        store_snapshot = data.get("store_snapshot") if isinstance(data.get("store_snapshot"), dict) else {}
        room_snapshot = data.get("room_snapshot") if isinstance(data.get("room_snapshot"), dict) else {}
        initial_match_game_results = data.get("initial_match_game_results")
        if not isinstance(initial_match_game_results, list):
            initial_match_game_results = []
        custom_log(
            f"DutchGame: rematch_tournament_snapshot_service room_id={room_id!r}",
            level="INFO",
            isOn=LOGGING_SWITCH,
        )
        if not room_id:
            return jsonify({"success": False, "error": "room_id is required"}), 400
        if not _app_manager:
            return jsonify({"success": False, "error": "Server not initialized"}), 503
        db_manager = _app_manager.get_db_manager(role="read_write")
        if not db_manager:
            return jsonify({"success": False, "error": "Database unavailable"}), 503

        user_id_strs = _mongo_user_ids_from_store_snapshot(store_snapshot)
        if not user_id_strs:
            return jsonify({"success": False, "error": "no_valid_user_ids_in_store_snapshot"}), 400

        initiator = (room_snapshot.get("rematch_initiator_user_id") or "").strip() or user_id_strs[0]
        try:
            ObjectId(initiator)
        except Exception:
            return jsonify({"success": False, "error": "invalid_rematch_initiator_user_id"}), 400

        td_in = room_snapshot.get("tournament_data") if isinstance(room_snapshot.get("tournament_data"), dict) else {}
        existing_tid = (td_in.get("tournament_id") or "").strip()
        already_tournament = bool(room_snapshot.get("is_tournament")) and bool(existing_tid)

        if already_tournament:
            try:
                tournament_oid = ObjectId(existing_tid)
            except Exception:
                return jsonify({"success": False, "error": "invalid_existing_tournament_id"}), 400
            res, err = _append_match_row_to_tournament(
                tournament_oid,
                existing_tid,
                user_id_strs,
                db_manager,
                room_id_str=room_id,
                start_date_str="",
            )
            if err or not res:
                return jsonify({"success": False, "error": err or "append_match_failed"}), 500
            td_out = {
                "tournament_id": existing_tid,
                "match_id": res["match_id"],
                "match_index": res["match_index"],
            }
            td_out = _enrich_td_out_from_tournament_doc(db_manager, tournament_oid, td_out)
            custom_log(
                f"DutchGame: rematch_tournament_snapshot extended tournament_id={existing_tid} match_index={res['match_index']}",
                level="INFO",
                isOn=LOGGING_SWITCH,
            )
            return jsonify({"success": True, "tournament_id": existing_tid, "tournament_data": td_out}), 200

        create_data = {
            "name": (data.get("tournament_name") or "").strip() or "Rematch %s" % room_id[-16:],
            "user_ids": user_id_strs,
            "matches": [],
            "status": "active",
            "type": "online",
            "format": "single_room_league",
        }
        tournament_id_hex, _created_at, cerr = create_tournament_in_db(initiator, create_data, db_manager)
        if cerr or not tournament_id_hex:
            return jsonify({"success": False, "error": cerr or "create_tournament_failed"}), 500

        try:
            new_oid = ObjectId(tournament_id_hex)
        except Exception:
            return jsonify({"success": False, "error": "invalid_new_tournament_id"}), 500

        tid_str = str(tournament_id_hex)
        if initial_match_game_results:
            ok_initial = _insert_initial_completed_match_single_room_league(
                db_manager,
                new_oid,
                tid_str,
                room_id,
                user_id_strs,
                initial_match_game_results,
            )
            if not ok_initial:
                return jsonify({"success": False, "error": "initial_match_insert_failed"}), 500

        res, err = _append_match_row_to_tournament(
            new_oid,
            tid_str,
            user_id_strs,
            db_manager,
            room_id_str=room_id,
            start_date_str="",
        )
        if err or not res:
            return jsonify({"success": False, "error": err or "append_match_failed"}), 500

        td_out = {
            "tournament_id": tid_str,
            "match_id": res["match_id"],
            "match_index": res["match_index"],
        }
        td_out = _enrich_td_out_from_tournament_doc(db_manager, new_oid, td_out)
        custom_log(
            f"DutchGame: rematch_tournament_snapshot created tournament_id={tid_str} format=single_room_league "
            f"pending_match_index={res['match_index']} initial_completed_sent={bool(initial_match_game_results)}",
            level="INFO",
            isOn=LOGGING_SWITCH,
        )
        return jsonify({"success": True, "tournament_id": tid_str, "tournament_data": td_out}), 200
    except Exception as e:
        custom_log(f"DutchGame: rematch_tournament_snapshot_service error: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "error": str(e)}), 500


def get_tournaments_list_public():
    """Public (no auth): get active tournaments, return id, created_at, name (when present), start_date (when present)."""
    try:
        if not _app_manager:
            return jsonify({"success": False, "error": "Server not initialized", "tournaments": []}), 503
        db_manager = _app_manager.get_db_manager(role="read_only")
        if not db_manager:
            return jsonify({"success": False, "error": "Database unavailable", "tournaments": []}), 503
        raw = db_manager.find("tournaments", {"status": "active"})
        tournaments = list(raw) if raw else []
        out = []
        for d in tournaments:
            created_at = d.get("created_at")
            if hasattr(created_at, "isoformat"):
                created_at = created_at.isoformat()
            item = {"id": str(d.get("_id")), "created_at": created_at}
            if d.get("name") is not None:
                item["name"] = d["name"]
            start_date = d.get("start_date")
            if start_date is not None:
                item["start_date"] = start_date.isoformat() if hasattr(start_date, "isoformat") else start_date
            out.append(item)
        return jsonify({"success": True, "tournaments": out}), 200
    except Exception as e:
        custom_log(f"DutchGame: get_tournaments_list_public error: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "error": str(e), "tournaments": []}), 500


def _aggregate_period_wins_summaries(coll, start: datetime, end: datetime) -> List[Dict[str, Any]]:
    """Full standings for the window: [{ _id: ObjectId, wins: int }, ...] sorted like the leaderboard."""
    pipeline = [
        {"$match": {"ended_at": {"$gte": start, "$lt": end}}},
        {"$group": {"_id": "$user_id", "wins": {"$sum": 1}}},
        {"$sort": {"wins": -1, "_id": 1}},
    ]
    return list(coll.aggregate(pipeline))


def get_period_wins_leaderboard_public():
    """Public (no auth): rank users by win count in the **current UTC** calendar month or year.

    Data comes from insert-only ``dutch_match_win_outcomes``; aggregation runs **on each request** (no precomputed board).

    Query: ``period`` or ``scope`` = ``monthly`` | ``yearly`` (default ``monthly``); ``limit`` default 20, max 50.
    Optional ``user_id`` / ``userId``: include ``viewer`` with that user's rank and wins in the same period (no JWT).
    """
    try:
        if not _app_manager:
            return jsonify({"success": False, "error": "Server not initialized", "rows": []}), 503
        db_manager = _app_manager.get_db_manager(role="read_only")
        if not db_manager:
            return jsonify({"success": False, "error": "Database unavailable", "rows": []}), 503

        raw_period = (request.args.get("period") or request.args.get("scope") or "monthly").strip().lower()
        if raw_period not in ("monthly", "yearly"):
            return jsonify({"success": False, "error": "period must be 'monthly' or 'yearly'", "rows": []}), 400

        try:
            raw_limit = request.args.get("limit", "20")
            limit = min(max(int(raw_limit), 1), 50)
        except (TypeError, ValueError):
            limit = 20

        now_utc = datetime.now(timezone.utc)
        if raw_period == "monthly":
            start, end = _utc_bounds_calendar_month(now_utc)
            period_key = now_utc.strftime("%Y-%m")
        else:
            start, end = _utc_bounds_calendar_year(now_utc)
            period_key = str(now_utc.year)

        coll = db_manager.db[MATCH_WIN_OUTCOMES_COLL]
        summaries = _aggregate_period_wins_summaries(coll, start, end)

        user_ids_top = [d["_id"] for d in summaries[:limit]]
        username_map: Dict[Any, str] = {}
        if user_ids_top:
            for u in db_manager.db["users"].find({"_id": {"$in": user_ids_top}}, {"username": 1}):
                username_map[u["_id"]] = u.get("username") or ""

        rows = []
        for rank, doc in enumerate(summaries[:limit], start=1):
            uid = doc["_id"]
            rows.append(
                {
                    "rank": rank,
                    "user_id": str(uid),
                    "username": username_map.get(uid, ""),
                    "wins": int(doc.get("wins") or 0),
                }
            )

        viewer_out: Optional[Dict[str, Any]] = None
        raw_viewer_uid = (request.args.get("user_id") or request.args.get("userId") or "").strip()
        if raw_viewer_uid:
            try:
                viewer_oid = ObjectId(raw_viewer_uid)
            except Exception:
                viewer_oid = None
            if viewer_oid is not None:
                found_idx: Optional[int] = None
                for idx, doc in enumerate(summaries):
                    if doc["_id"] == viewer_oid:
                        found_idx = idx
                        break
                udoc = db_manager.find_one("users", {"_id": viewer_oid})
                uname = (udoc or {}).get("username") or ""
                if found_idx is not None:
                    doc = summaries[found_idx]
                    viewer_out = {
                        "user_id": raw_viewer_uid,
                        "rank": found_idx + 1,
                        "wins": int(doc.get("wins") or 0),
                        "username": uname,
                        "in_period": True,
                    }
                else:
                    viewer_out = {
                        "user_id": raw_viewer_uid,
                        "rank": None,
                        "wins": 0,
                        "username": uname,
                        "in_period": False,
                    }

        custom_log(
            f"📊 Python: GET leaderboard-period-wins period={raw_period} period_key={period_key} limit={limit} "
            f"row_count={len(rows)} viewer={'yes' if viewer_out else 'no'}",
            level="INFO",
            isOn=LOGGING_SWITCH,
        )
        payload: Dict[str, Any] = {
            "success": True,
            "period": raw_period,
            "period_key": period_key,
            "range_start_utc": start.isoformat(),
            "range_end_exclusive_utc": end.isoformat(),
            "rows": rows,
        }
        if viewer_out is not None:
            payload["viewer"] = viewer_out
        return jsonify(payload), 200
    except Exception as e:
        custom_log(f"DutchGame: get_period_wins_leaderboard_public error: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "error": str(e), "rows": []}), 500


def get_leaderboards_list_public():
    """Public (no auth): list wins snapshot rows from ``leaderboards`` (monthly/yearly, non-tournament).

    Query: ``leaderboard_type`` optional ``monthly`` | ``yearly``; ``limit`` default 20, max 20.
    """
    try:
        if not _app_manager:
            return jsonify({"success": False, "error": "Server not initialized", "leaderboards": []}), 503
        db_manager = _app_manager.get_db_manager(role="read_only")
        if not db_manager:
            return jsonify({"success": False, "error": "Database unavailable", "leaderboards": []}), 503

        _max = 20
        raw_limit = request.args.get("limit", str(_max))
        try:
            limit = min(max(int(raw_limit), 1), _max)
        except (TypeError, ValueError):
            limit = _max

        lb_filter = (request.args.get("leaderboard_type") or request.args.get("leaderboardType") or "").strip().lower()
        query: Dict[str, Any] = {
            "tournament_type": {"$exists": False},
            "tournament_format": {"$exists": False},
        }
        if lb_filter in ("monthly", "yearly"):
            query["leaderboard_type"] = lb_filter

        coll = db_manager.db["leaderboards"]
        cur = coll.find(query).sort("date_time", -1).limit(limit)
        out = []
        for d in cur:
            dt = d.get("date_time")
            if hasattr(dt, "isoformat"):
                dt_s = dt.isoformat()
            else:
                dt_s = None
            item = {
                "id": str(d.get("_id", "")),
                "leaderboard_type": d.get("leaderboard_type"),
                "period_key": d.get("period_key"),
                "date_time": dt_s,
                "metric": d.get("metric"),
                "metric_note": d.get("metric_note"),
                "winners": d.get("winners") or [],
            }
            out.append(item)
        custom_log(
            f"📊 Python: GET leaderboards list type={lb_filter or 'all'} limit={limit} doc_count={len(out)}",
            level="INFO",
            isOn=LOGGING_SWITCH,
        )
        return jsonify({"success": True, "leaderboards": out}), 200
    except Exception as e:
        custom_log(f"DutchGame: get_leaderboards_list_public error: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "error": str(e), "leaderboards": []}), 500


def tournament_signup():
    """Stub: sign up a user for a tournament. POST body: user_id, tournament_id. Not yet implemented."""
    try:
        user_id = request.user_id
        if not user_id:
            return jsonify({"success": False, "error": "Not authenticated"}), 401
        data = request.get_json(silent=True) or {}
        body_user_id = (data.get("user_id") or data.get("userid") or "").strip()
        tournament_id = (data.get("tournament_id") or data.get("tournamentid") or "").strip()
        if not body_user_id:
            return jsonify({"success": False, "error": "user_id is required"}), 400
        if not tournament_id:
            return jsonify({"success": False, "error": "tournament_id is required"}), 400
        return jsonify({
            "success": True,
            "message": "Tournament signup stub (not yet implemented)",
            "user_id": body_user_id,
            "tournament_id": tournament_id,
        }), 200
    except Exception as e:
        custom_log(f"DutchGame: tournament_signup error: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "error": str(e)}), 500


# msg_id -> { action_identifier -> callable(doc, user_id) -> dict }. Modules register per message kind.
_message_handlers = {}


def register_message_handlers(msg_id: str, handlers: dict):
    """Register response handlers for a logical message id. msg_id must match the one passed when creating the notification."""
    if not msg_id or not isinstance(handlers, dict):
        return
    _message_handlers[msg_id.strip()] = {k.strip(): v for k, v in handlers.items() if k and callable(v)}


def _dutch_dispatch(doc, action_identifier: str, user_id: str):
    """Single handler registered with core for source dutch_game. Dispatches by doc["msg_id"] and action_identifier."""
    msg_id = (doc.get("msg_id") or "").strip()
    if not msg_id:
        return {"success": False, "error": "Notification has no msg_id"}
    handlers = _message_handlers.get(msg_id)
    if not handlers:
        return {"success": False, "error": f"No handlers registered for msg_id {msg_id!r}"}
    handler = handlers.get(action_identifier)
    if not handler:
        return {"success": False, "error": f"Unknown action_identifier {action_identifier!r} for this notification"}
    return handler(doc, user_id)


def _dutch_handle_accept(doc, user_id):
    """Handler for accept: match invite only."""
    return {"success": True, "message": "Updated", "action": "accept"}


def _dutch_handle_decline(doc, user_id):
    """Handler for decline: match invite only."""
    return {"success": True, "message": "Updated", "action": "decline"}


def _dutch_handle_join(doc, user_id):
    """Handler for join: match invite only."""
    return {"success": True, "message": "Updated", "action": "join"}


def invite_players_to_match():
    """Create dutch_match_invite notifications for each user_id in the request body. POST body: user_ids (list), optional match_id, room_id, title, body."""
    try:
        if not request.user_id:
            return jsonify({"success": False, "error": "Not authenticated"}), 401
        data = request.get_json(silent=True) or {}
        user_ids = data.get("user_ids")
        if not isinstance(user_ids, list):
            return jsonify({"success": False, "error": "user_ids must be a list"}), 400
        match_id = (data.get("match_id") or "").strip() or None
        room_id = (data.get("room_id") or "").strip() or None
        title = (data.get("title") or "Match invite").strip()
        body = (data.get("body") or "You're invited to a match.").strip()
        custom_log(
            f"DutchGame: invite_players_to_match requested={len(user_ids)} match_id={match_id!r} room_id={room_id!r}",
            level="INFO",
            isOn=LOGGING_SWITCH,
        )
        if not _app_manager:
            return jsonify({"success": False, "error": "Server not initialized"}), 503
        notification_data = {"match_id": match_id}
        if room_id:
            notification_data["room_id"] = room_id
        notified = 0
        for uid in user_ids:
            if not isinstance(uid, str) or not uid.strip():
                continue
            uid = uid.strip()
            nid = dutch_notifications.create_notification(
                _app_manager,
                user_id=uid,
                subtype=dutch_notifications.SUBTYPE_MATCH_INVITE,
                title=title,
                body=body,
                msg_id=dutch_notifications.MSG_ID_MATCH_INVITE,
                data=notification_data,
                responses=dutch_notifications.MATCH_INVITE_RESPONSES,
            )
            if nid:
                notified += 1
        custom_log(
            f"DutchGame: invite_players_to_match ok notified={notified} requested={len(user_ids)}",
            level="INFO",
            isOn=LOGGING_SWITCH,
        )
        return jsonify({"success": True, "notified": notified, "requested": len(user_ids)}), 200
    except Exception as e:
        custom_log(f"DutchGame: invite_players_to_match error: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "error": str(e)}), 500


def register_notification_handlers(notification_module):
    """Register dutch_game response handler with the core (single dispatch); register per-msg_id handlers. Call from DutchGameMain.initialize()."""
    if not notification_module or not hasattr(notification_module, "register_response_handler"):
        return
    # Per-msg_id handlers: only match invite (admin tournaments flow)
    register_message_handlers(dutch_notifications.MSG_ID_MATCH_INVITE, {
        "accept": _dutch_handle_accept,
        "decline": _dutch_handle_decline,
        "join": _dutch_handle_join,
    })
    notification_module.register_response_handler(dutch_notifications.DUTCH_GAME_SOURCE, _dutch_dispatch)


def get_comp_players():
    """Get computer players from database (public endpoint)."""
    try:
        data = request.get_json()
        if not data:
            return jsonify({"success": False, "error": "Request body is required", "message": "Missing request body"}), 400
        count = data.get('count')
        if count is None or not isinstance(count, int) or count <= 0:
            return jsonify({"success": False, "error": "Invalid count parameter", "message": "count must be a positive integer"}), 400
        rank_filter = data.get('rank_filter')
        if rank_filter is not None and not isinstance(rank_filter, list):
            return jsonify({"success": False, "error": "Invalid rank_filter parameter", "message": "rank_filter must be a list of rank strings"}), 400
        if not _app_manager:
            return jsonify({"success": False, "error": "Server not initialized"}), 503
        db_manager = _app_manager.get_db_manager(role="read_write")
        if not db_manager:
            return jsonify({"success": False, "error": "Database connection unavailable", "message": "Failed to connect to database"}), 500
        query = {"is_comp_player": True, "status": "active"}
        if rank_filter and len(rank_filter) > 0:
            normalized_ranks = [matcher.normalize_rank(r) for r in rank_filter if matcher.is_valid_rank(r)]
            if normalized_ranks:
                query["modules.dutch_game.rank"] = {"$in": normalized_ranks}
        comp_players = db_manager.find("users", query)
        if not comp_players:
            if rank_filter and len(rank_filter) > 0:
                fallback_query = {"is_comp_player": True, "status": "active"}
                comp_players = db_manager.find("users", fallback_query)
            if not comp_players:
                return jsonify({"success": True, "comp_players": [], "count": 0, "message": "No comp players available in database"}), 200
        comp_players = list(comp_players) if comp_players else []
        if not comp_players:
            return jsonify({"success": True, "comp_players": [], "count": 0, "message": "No comp players available in database"}), 200
        random.shuffle(comp_players)
        selected_count = min(count, len(comp_players))
        selected_players = random.sample(comp_players, selected_count)
        random.shuffle(selected_players)
        comp_players_list = []
        for player in selected_players:
            dutch_game_data = player.get("modules", {}).get("dutch_game", {})
            profile = player.get("profile", {})
            comp_players_list.append({
                "user_id": str(player.get("_id", "")),
                "username": player.get("username", ""),
                "email": player.get("email", ""),
                "rank": dutch_game_data.get("rank") or matcher.DEFAULT_RANK,
                "level": dutch_game_data.get("level", matcher.DEFAULT_LEVEL),
                "profile_picture": profile.get("picture", ""),
            })
        response_data = {"success": True, "comp_players": comp_players_list, "count": len(comp_players_list), "requested_count": count, "available_count": len(comp_players)}
        if selected_count < count:
            response_data["message"] = f"Only {selected_count} comp player(s) available (requested {count})"
        else:
            response_data["message"] = f"Successfully retrieved {selected_count} comp player(s)"
        return jsonify(response_data), 200
    except Exception as e:
        custom_log(f"❌ DutchGame: Error in get_comp_players: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "error": "Failed to retrieve comp players", "message": str(e)}), 500
