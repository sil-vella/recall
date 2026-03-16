from datetime import datetime
from typing import Dict, Any, Optional
from flask import Blueprint, request, jsonify
from core.managers.jwt_manager import JWTManager, TokenType
from core.modules.user_management_module import tier_rank_level_matcher as matcher
from tools.logger.custom_logging import custom_log
from bson import ObjectId
import time
import random
import uuid

from . import dutch_notifications

dutch_api = Blueprint('dutch_api', __name__)

# Logging switch for this module
LOGGING_SWITCH = True  # Enabled for get-user-stats + tournament attach flow — see .cursor/rules/enable-logging-switch.mdc

# Prometheus/Grafana not used – game events do not update metrics
METRICS_SWITCH = False

# Store app_manager reference (will be set by module)
_app_manager = None

# In-memory create-match sessions: key = create_match_id (datetime-style id), value = session dict
# Session: { "created_at": datetime, "inviter_user_id": str, "invited": [ {"user_id", "username", "status", ...} ] }
_create_match_sessions = {}

def set_app_manager(app_manager):
    """Set app manager for database access"""
    global _app_manager
    _app_manager = app_manager


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
        doc = {
            "creator_id": creator_oid,
            "user_ids": user_ids,
            "matches": data.get("matches") or [],
            "status": data.get("status") or "active",
            "created_at": created_at,
            "updated_at": created_at,
        }
        if data.get("name") is not None:
            doc["name"] = data["name"]
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
            "requires_password": room_info.get('permission') == 'private',
            "timestamp": time.time()
        }), 200
    except Exception as e:
        return jsonify({"success": False, "message": "Failed to find game", "error": str(e)}), 500


def update_game_stats():
    """Update user game statistics after a game ends (service endpoint: Dart backend only, X-Service-Key auth)."""
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
        if not _app_manager:
            return jsonify({"success": False, "message": "Server not initialized"}), 503
        db_manager = _app_manager.get_db_manager(role="read_write")
        if not db_manager:
            return jsonify({"success": False, "message": "Database connection unavailable", "error": "Database manager not initialized"}), 500
        current_time = datetime.utcnow()
        current_timestamp = current_time.isoformat()
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
                is_winner = player_result.get('is_winner', False)
                pot = player_result.get('pot', 0)
                coins_to_add = 0
                if is_winner and pot > 0 and not matcher.is_free_play_tier(subscription_tier):
                    coins_to_add = pot
                new_total_matches = current_total_matches + 1
                new_wins = current_wins + (1 if is_winner else 0)
                new_losses = current_losses + (0 if is_winner else 1)
                new_coins = current_coins + coins_to_add
                new_win_rate = float(new_wins) / float(new_total_matches) if new_total_matches > 0 else 0.0
                update_operation = {
                    '$set': {
                        'modules.dutch_game.total_matches': new_total_matches,
                        'modules.dutch_game.wins': new_wins,
                        'modules.dutch_game.losses': new_losses,
                        'modules.dutch_game.win_rate': new_win_rate,
                        'modules.dutch_game.last_match_date': current_timestamp,
                        'modules.dutch_game.last_updated': current_timestamp,
                        'updated_at': current_timestamp
                    }
                }
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
                        "win_rate": new_win_rate
                    })
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
            return jsonify(response_data), 200
        return jsonify({"success": False, "message": "Failed to update any player statistics", "error": "All updates failed", "errors": errors}), 500
    except Exception as e:
        custom_log(f"❌ Python: Error in update_game_stats: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "message": "Failed to update game statistics", "error": str(e)}), 500


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
            return jsonify({"success": False, "error": "Dutch game module not found", "message": "User does not have dutch_game module initialized", "data": None}), 404
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
            "last_updated": dutch_game.get('last_updated')
        }
        if stats_data.get('last_match_date') and isinstance(stats_data['last_match_date'], datetime):
            stats_data['last_match_date'] = stats_data['last_match_date'].isoformat()
        if stats_data.get('last_updated') and isinstance(stats_data['last_updated'], datetime):
            stats_data['last_updated'] = stats_data['last_updated'].isoformat()
        return jsonify({"success": True, "message": "User statistics retrieved successfully", "data": stats_data, "user_id": str(user_id), "timestamp": datetime.utcnow().isoformat()}), 200
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
        }
        custom_log(f"📊 DutchGame: get_user_stats_service user_id={user_id} coins={stats_data['coins']} subscription_tier={stats_data['subscription_tier']}", level="INFO", isOn=LOGGING_SWITCH)
        return jsonify({"success": True, "message": "User statistics retrieved", "data": stats_data, "user_id": user_id, "timestamp": datetime.utcnow().isoformat()}), 200
    except Exception as e:
        custom_log(f"❌ DutchGame: Error in get_user_stats_service: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "error": "Failed to retrieve user statistics", "message": str(e)}), 500


def record_game_result():
    """Record current user's single game result (JWT protected; user_id from token)."""
    try:
        user_id = request.user_id
        if not user_id:
            return jsonify({"success": False, "error": "User not authenticated", "message": "No user ID found in request"}), 401
        data = request.get_json()
        if not data:
            return jsonify({"success": False, "message": "Request body is required", "error": "Missing request body"}), 400
        is_winner = data.get('is_winner', False)
        pot = data.get('pot', 0)
        game_mode = data.get('game_mode', 'multiplayer')
        duration = data.get('duration', 0)
        if not _app_manager:
            return jsonify({"success": False, "message": "Server not initialized"}), 503
        db_manager = _app_manager.get_db_manager(role="read_write")
        if not db_manager:
            return jsonify({"success": False, "message": "Database connection unavailable", "error": "Database manager not initialized"}), 500
        try:
            user_id_obj = ObjectId(user_id)
        except Exception as e:
            return jsonify({"success": False, "message": f"Invalid user_id format: {e}", "error": "Invalid user_id"}), 400
        user = db_manager.find_one("users", {"_id": user_id_obj})
        if not user:
            return jsonify({"success": False, "error": "User not found", "message": f"User {user_id} not found"}), 404
        modules = user.get('modules', {})
        dutch_game = modules.get('dutch_game', {})
        current_wins = dutch_game.get('wins', 0)
        current_losses = dutch_game.get('losses', 0)
        current_total_matches = dutch_game.get('total_matches', 0)
        current_coins = dutch_game.get('coins', 0)
        subscription_tier = dutch_game.get('subscription_tier') or matcher.TIER_PROMOTIONAL
        coins_to_add = (pot if (is_winner and pot > 0 and not matcher.is_free_play_tier(subscription_tier)) else 0)
        new_total_matches = current_total_matches + 1
        new_wins = current_wins + (1 if is_winner else 0)
        new_losses = current_losses + (0 if is_winner else 1)
        new_coins = current_coins + coins_to_add
        new_win_rate = float(new_wins) / float(new_total_matches) if new_total_matches > 0 else 0.0
        current_timestamp = datetime.utcnow().isoformat()
        update_operation = {
            '$set': {
                'modules.dutch_game.total_matches': new_total_matches,
                'modules.dutch_game.wins': new_wins,
                'modules.dutch_game.losses': new_losses,
                'modules.dutch_game.win_rate': new_win_rate,
                'modules.dutch_game.last_match_date': current_timestamp,
                'modules.dutch_game.last_updated': current_timestamp,
                'updated_at': current_timestamp
            }
        }
        if coins_to_add > 0:
            update_operation['$inc'] = {'modules.dutch_game.coins': coins_to_add}
        result = db_manager.db["users"].update_one({"_id": user_id_obj}, update_operation)
        if not result or result.modified_count == 0:
            return jsonify({"success": False, "message": "Failed to update user statistics", "error": "Update failed"}), 500
        analytics_service = _app_manager.services_manager.get_service('analytics_service') if _app_manager else None
        if analytics_service:
            analytics_service.track_event(user_id=user_id, event_type='game_completed', event_data={'game_mode': game_mode, 'result': 'win' if is_winner else 'loss', 'duration': duration}, metrics_enabled=METRICS_SWITCH)
            if coins_to_add > 0:
                analytics_service.track_event(user_id=user_id, event_type='coin_transaction', event_data={'transaction_type': 'game_reward', 'direction': 'credit', 'amount': coins_to_add}, metrics_enabled=METRICS_SWITCH)
        return jsonify({"success": True, "message": "Game result recorded", "data": {"user_id": user_id, "wins": new_wins, "losses": new_losses, "total_matches": new_total_matches, "coins": new_coins, "win_rate": new_win_rate}, "timestamp": current_timestamp}), 200
    except Exception as e:
        custom_log(f"❌ DutchGame: Error in record_game_result: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "error": "Failed to record game result", "message": str(e)}), 500


def deduct_game_coins():
    """Deduct game coins from multiple players when game starts (JWT protected endpoint)."""
    try:
        user_id = request.user_id
        if not user_id:
            return jsonify({"success": False, "error": "User not authenticated", "message": "No user ID found in request"}), 401
        data = request.get_json()
        if not data:
            return jsonify({"success": False, "error": "Request body is required", "message": "Missing request body"}), 400
        coins = data.get('coins')
        game_id = data.get('game_id')
        player_ids = data.get('player_ids')
        if coins is None or not isinstance(coins, int) or coins <= 0:
            return jsonify({"success": False, "error": "Invalid coins amount", "message": "coins must be a positive integer"}), 400
        if not game_id or not isinstance(game_id, str):
            return jsonify({"success": False, "error": "Invalid game_id", "message": "game_id is required and must be a string"}), 400
        if not player_ids or not isinstance(player_ids, list) or len(player_ids) == 0:
            return jsonify({"success": False, "error": "Invalid player_ids", "message": "player_ids must be a non-empty array"}), 400
        if not _app_manager:
            return jsonify({"success": False, "error": "Server not initialized"}), 503
        db_manager = _app_manager.get_db_manager(role="read_write")
        if not db_manager:
            return jsonify({"success": False, "error": "Database connection unavailable", "message": "Failed to connect to database"}), 500
        current_timestamp = datetime.utcnow().isoformat()
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
                if matcher.is_free_play_tier(subscription_tier):
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
            response_data = {"success": True, "message": f"Coins deducted successfully for {len(updated_players)} player(s)", "game_id": game_id, "coins_deducted": coins, "updated_players": updated_players}
            if errors:
                response_data["warnings"] = errors
            return jsonify(response_data), 200
        return jsonify({"success": False, "message": "Failed to deduct coins for any player", "error": "All deductions failed", "errors": errors}), 500
    except Exception as e:
        custom_log(f"❌ DutchGame: Error in deduct_game_coins: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "message": "Failed to deduct game coins", "error": str(e)}), 500


def invite_player():
    """Invite a player by username. Uses user search, then creates instant notification (JWT required)."""
    try:
        inviter_user_id = request.user_id
        if not inviter_user_id:
            return jsonify({"success": False, "error": "Not authenticated", "message": "No user ID in request"}), 401
        data = request.get_json(silent=True) or {}
        username = (data.get('username') or '').strip()
        if len(username) < 2:
            return jsonify({"success": False, "error": "username is required and must be at least 2 characters", "message": "Provide a username to invite"}), 400
        if not _app_manager:
            return jsonify({"success": False, "error": "Server not initialized"}), 503
        user_management = _app_manager.module_manager.get_module("user_management_module")
        if not user_management or not hasattr(user_management, 'search_users_by_username'):
            return jsonify({"success": False, "error": "User search unavailable", "message": "Cannot resolve username"}), 503
        users, err = user_management.search_users_by_username(username, limit=10)
        if err:
            return jsonify({"success": False, "error": err, "message": err}), 400
        if not users:
            return jsonify({"success": False, "error": "User not found", "message": f"No user found for username '{username}'"}), 404
        target = users[0]
        target_user_id = target.get('user_id') or str(target.get('_id', ''))
        if not target_user_id or target_user_id == inviter_user_id:
            return jsonify({"success": False, "error": "Invalid target", "message": "Cannot invite yourself"}), 400
        create_match_id = (data.get("create_match_id") or "").strip()
        is_comp_player = target.get("is_comp_player") is True
        if is_comp_player:
            if create_match_id and create_match_id in _create_match_sessions:
                _create_match_sessions[create_match_id]["invited"].append({"user_id": target_user_id, "username": target.get("username") or "", "status": "accepted", "is_comp_player": True})
            return jsonify({"success": True, "message": "Computer player added", "target_user_id": target_user_id, "target_username": target.get("username"), "create_match_id": create_match_id or None, "is_comp_player": True}), 200
        inviter_username = "Someone"
        try:
            db = _app_manager.get_db_manager(role="read_only")
            if db:
                inviter = db.find_one("users", {"_id": ObjectId(inviter_user_id)})
                if inviter:
                    inviter_username = inviter.get("username") or inviter_username
        except Exception:
            pass
        title = "Game invite"
        body = f"{inviter_username} invited you to play Dutch."
        data = {"inviter_user_id": inviter_user_id, "inviter_username": inviter_username, "create_match_id": create_match_id or None}
        msg_id = dutch_notifications.create_notification(
            _app_manager,
            user_id=target_user_id,
            subtype=dutch_notifications.SUBTYPE_INVITE,
            title=title,
            body=body,
            data=data,
            responses=dutch_notifications.INVITE_RESPONSES,
        )
        if not msg_id:
            return jsonify({"success": False, "error": "Notifications unavailable", "message": "Invite could not be sent"}), 503
        if create_match_id and create_match_id in _create_match_sessions:
            _create_match_sessions[create_match_id]["invited"].append({"user_id": target_user_id, "username": target.get("username") or "", "status": "pending", "is_comp_player": False})
        return jsonify({"success": True, "message": "Invite sent", "target_user_id": target_user_id, "target_username": target.get("username"), "notification_id": msg_id, "create_match_id": create_match_id or None}), 200
    except Exception as e:
        custom_log(f"DutchGame: invite_player error: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "error": "Failed to send invite", "message": str(e)}), 500


def create_match_session():
    """Create an in-memory create-match session. Returns create_match_id for use in invite-player and polling."""
    try:
        inviter_user_id = request.user_id
        if not inviter_user_id:
            return jsonify({"success": False, "error": "Not authenticated"}), 401
        create_match_id = datetime.utcnow().strftime("%Y%m%d%H%M%S") + "_" + uuid.uuid4().hex[:8]
        _create_match_sessions[create_match_id] = {"created_at": datetime.utcnow().isoformat(), "inviter_user_id": inviter_user_id, "invited": []}
        return jsonify({"success": True, "create_match_id": create_match_id}), 200
    except Exception as e:
        custom_log(f"DutchGame: create_match_session error: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "error": str(e)}), 500


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
        return jsonify({"success": True, "tournaments": out}), 200
    except Exception as e:
        custom_log(f"DutchGame: get_tournaments error: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "error": str(e), "tournaments": []}), 500


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

        user_oids = []
        for uid_str in user_id_strs:
            try:
                user_oids.append(ObjectId(uid_str))
            except Exception:
                return jsonify({"success": False, "error": f"Invalid user_id format: {uid_str}"}), 400

        if not _app_manager:
            return jsonify({"success": False, "error": "Server not initialized"}), 503
        db_manager = _app_manager.get_db_manager(role="read_write")
        if not db_manager:
            return jsonify({"success": False, "error": "Database unavailable"}), 503

        tournament = db_manager.find_one("tournaments", {"_id": tournament_oid})
        if not tournament:
            return jsonify({"success": False, "error": "Tournament not found"}), 404

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

        # Build players: user_id, username, email, points, number_of_cards_left (playbook schema)
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
            "room_id": "",
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
            custom_log(f"DutchGame: add_tournament_match db error: {db_err}", level="ERROR", isOn=LOGGING_SWITCH)
            return jsonify({"success": False, "error": "Failed to update tournament"}), 500

        if not result or result.modified_count == 0:
            return jsonify({"success": False, "error": "Failed to add match (no document modified)"}), 500

        custom_log(f"DutchGame: add_tournament_match tournament_id={tournament_id} match_index={next_index} players={len(user_id_strs)}", level="INFO", isOn=LOGGING_SWITCH)
        return jsonify({
            "success": True,
            "message": "Match added",
            "tournament_id": tournament_id,
            "match_index": next_index,
            "match_id": match_id_str,
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
    return {"success": True, "message": "Match updated", "room_id": room_id}, 200


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


def get_create_match_session():
    """Get create-match session for polling (invited list with statuses). Query: create_match_id=."""
    try:
        inviter_user_id = request.user_id
        if not inviter_user_id:
            return jsonify({"success": False, "error": "Not authenticated"}), 401
        create_match_id = (request.args.get("create_match_id") or "").strip()
        if not create_match_id:
            return jsonify({"success": False, "error": "create_match_id required"}), 400
        session = _create_match_sessions.get(create_match_id)
        if not session:
            return jsonify({"success": False, "error": "Session not found", "invited": []}), 404
        if session["inviter_user_id"] != inviter_user_id:
            return jsonify({"success": False, "error": "Forbidden"}), 403
        return jsonify({"success": True, "create_match_id": create_match_id, "created_at": session["created_at"], "invited": list(session["invited"])}), 200
    except Exception as e:
        custom_log(f"DutchGame: get_create_match_session error: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "error": str(e)}), 500


def _dutch_handle_accept(doc, user_id):
    """Registered handler: accept game invite. Updates create-match session if present."""
    if doc.get("subtype") == dutch_notifications.SUBTYPE_MATCH_INVITE:
        return {"success": True, "message": "Updated", "action": "accept"}
    create_match_id = (doc.get("data") or {}).get("create_match_id")
    if create_match_id and create_match_id in _create_match_sessions:
        session = _create_match_sessions[create_match_id]
        for inv in session.get("invited") or []:
            if str(inv.get("user_id")) == str(user_id):
                inv["status"] = "accepted"
                break
    return {"success": True, "message": "Updated", "action": "accept"}


def _dutch_handle_decline(doc, user_id):
    """Registered handler: decline game invite. Updates create-match session if present."""
    if doc.get("subtype") == dutch_notifications.SUBTYPE_MATCH_INVITE:
        return {"success": True, "message": "Updated", "action": "decline"}
    create_match_id = (doc.get("data") or {}).get("create_match_id")
    if create_match_id and create_match_id in _create_match_sessions:
        session = _create_match_sessions[create_match_id]
        for inv in session.get("invited") or []:
            if str(inv.get("user_id")) == str(user_id):
                inv["status"] = "declined"
                break
    return {"success": True, "message": "Updated", "action": "decline"}


def _dutch_handle_join(doc, user_id):
    """Registered handler: join room from room-ready notification, or match-invite Join (blank)."""
    if doc.get("subtype") == dutch_notifications.SUBTYPE_MATCH_INVITE:
        return {"success": True, "message": "Updated", "action": "join"}
    if doc.get("subtype") != dutch_notifications.SUBTYPE_ROOM_JOIN:
        return {"success": False, "error": "Invalid notification type"}
    room_id = (doc.get("data") or {}).get("room_id")
    if not room_id:
        return {"success": False, "error": "room_id missing in notification"}
    return {"success": True, "room_id": room_id}


def invite_players_to_match():
    """Create dutch_match_invite notifications for each user_id in the request body. POST body: user_ids (list), optional match_id, title, body."""
    try:
        if not request.user_id:
            return jsonify({"success": False, "error": "Not authenticated"}), 401
        data = request.get_json(silent=True) or {}
        user_ids = data.get("user_ids")
        if not isinstance(user_ids, list):
            return jsonify({"success": False, "error": "user_ids must be a list"}), 400
        match_id = (data.get("match_id") or "").strip() or None
        title = (data.get("title") or "Match invite").strip()
        body = (data.get("body") or "You're invited to a match.").strip()
        if not _app_manager:
            return jsonify({"success": False, "error": "Server not initialized"}), 503
        notified = 0
        for uid in user_ids:
            if not isinstance(uid, str) or not uid.strip():
                continue
            uid = uid.strip()
            msg_id = dutch_notifications.create_notification(
                _app_manager,
                user_id=uid,
                subtype=dutch_notifications.SUBTYPE_MATCH_INVITE,
                title=title,
                body=body,
                data={"match_id": match_id},
                responses=dutch_notifications.MATCH_INVITE_RESPONSES,
            )
            if msg_id:
                notified += 1
        return jsonify({"success": True, "notified": notified, "requested": len(user_ids)}), 200
    except Exception as e:
        custom_log(f"DutchGame: invite_players_to_match error: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "error": str(e)}), 500


def register_notification_handlers(notification_module):
    """Register dutch_game response handlers with the core notification module. Call from DutchGameMain.initialize()."""
    if not notification_module or not hasattr(notification_module, "register_response_handlers"):
        return
    notification_module.register_response_handlers(dutch_notifications.DUTCH_GAME_SOURCE, {
        "accept": _dutch_handle_accept,
        "decline": _dutch_handle_decline,
        "join": _dutch_handle_join,
    })


def notify_room_ready():
    """Stub for room-ready flow. New invite/join logic to be implemented. Body: room_id, accepted_player_user_ids."""
    try:
        if not request.user_id:
            return jsonify({"success": False, "error": "Not authenticated"}), 401
        data = request.get_json(silent=True) or {}
        room_id = (data.get("room_id") or "").strip()
        if not room_id:
            return jsonify({"success": False, "error": "room_id required"}), 400
        return jsonify({"success": True, "notified": 0}), 200
    except Exception as e:
        custom_log(f"DutchGame: notify_room_ready error: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        return jsonify({"success": False, "error": str(e)}), 500


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
