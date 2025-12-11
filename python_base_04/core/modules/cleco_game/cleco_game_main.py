"""
Cleco Game Main Entry Point

This module serves as the main entry point for the Cleco game backend,
initializing all components and integrating with the main system.
"""

from typing import Optional, Dict, Any, List
from tools.logger.custom_logging import custom_log
from core.modules.base_module import BaseModule
from core.managers.jwt_manager import JWTManager, TokenType
# Game logic moved to Dart backend - imports removed
# from .game_logic.game_state import GameStateManager
# from .game_logic.game_event_coordinator import GameEventCoordinator
from flask import request, jsonify
from datetime import datetime
from bson import ObjectId
import time

# Logging switch for this module
LOGGING_SWITCH = True


class ClecoGameMain(BaseModule):
    """Main orchestrator for the Cleco game backend"""
    
    def __init__(self, app_manager=None):
        super().__init__(app_manager)
        self.websocket_manager = None
        self.game_state_manager = None
        self.game_event_coordinator = None
    
    def initialize(self, app_manager) -> bool:
        """Initialize the Cleco game backend with the main app_manager"""
        try:
            # Call parent class initialize
            super().initialize(app_manager)
            
            # Set Flask app reference for route registration
            self.app = app_manager.flask_app
            
            self.websocket_manager = app_manager.get_websocket_manager()
            
            if not self.websocket_manager:
                return False
            
            # Game logic moved to Dart backend - no longer initializing GameStateManager or GameEventCoordinator
            # self.game_state_manager = GameStateManager()
            # self.game_state_manager.initialize(self.app_manager, None)
            # self.game_event_coordinator = GameEventCoordinator(self.game_state_manager, self.websocket_manager)
            # setattr(self.app_manager, 'game_event_coordinator', self.game_event_coordinator)
            # setattr(self.app_manager, 'game_state_manager', self.game_state_manager)
            # self.game_event_coordinator.register_game_event_listeners()
            
            # Register routes now that Flask app is available
            self.register_routes()
            
            self._initialized = True
            return True
            
        except Exception as e:
            return False
    
    def register_routes(self):
        """Register all Cleco game routes."""
        try:
            custom_log("🔐 ClecoGame: Starting route registration", level="INFO", isOn=LOGGING_SWITCH)
            
            # Import and register API blueprint
            from .api_endpoints import cleco_api
            custom_log("🔐 ClecoGame: Imported API blueprint", level="INFO", isOn=LOGGING_SWITCH)
            
            self.app.register_blueprint(cleco_api)
            custom_log("🔐 ClecoGame: API blueprint registered successfully", level="INFO", isOn=LOGGING_SWITCH)
            
            # Register the get-available-games endpoint with JWT authentication
            self._register_route_helper("/userauth/cleco/get-available-games", self.get_available_games, methods=["GET"], auth="jwt")
            
            # Register the find-room endpoint with JWT authentication
            self._register_route_helper("/userauth/cleco/find-room", self.find_room, methods=["POST"], auth="jwt")

            # Register the update-game-stats endpoint as public (no authentication)
            self._register_route_helper("/public/cleco/update-game-stats", self.update_game_stats, methods=["POST"])

            # Register the get-user-stats endpoint with JWT authentication
            self._register_route_helper("/userauth/cleco/get-user-stats", self.get_user_stats, methods=["GET"], auth="jwt")

            # Register the deduct-game-coins endpoint with JWT authentication
            self._register_route_helper("/userauth/cleco/deduct-game-coins", self.deduct_game_coins, methods=["POST"], auth="jwt")

            custom_log("🔐 ClecoGame: All routes registered successfully", level="INFO", isOn=LOGGING_SWITCH)
            return True
        except Exception as e:
            custom_log(f"❌ ClecoGame: Error registering routes: {e}", level="ERROR", isOn=LOGGING_SWITCH)
            return False
    

    
    def get_available_games(self):
        """Get all available games that can be joined (JWT protected endpoint)"""
        try:
            # Verify JWT token
            auth_header = request.headers.get('Authorization')
            
            if not auth_header:
                return jsonify({
                    "success": False,
                    "message": "No Authorization header provided",
                    "error": "Missing JWT token"
                }), 401
            
            # Extract token from Authorization header
            if auth_header.startswith('Bearer '):
                token = auth_header[7:]  # Remove 'Bearer ' prefix
            else:
                token = auth_header
            
            # Get JWT manager from app_manager
            jwt_manager = self.app_manager.jwt_manager
            
            # Verify the token
            payload = jwt_manager.verify_token(token, TokenType.ACCESS)
            
            if not payload:
                return jsonify({
                    "success": False,
                    "message": "Invalid or expired JWT token",
                    "error": "Token validation failed"
                }), 401
            
            # Game logic moved to Dart backend - return empty list
            # Games are now managed by the Dart backend WebSocket server
            available_games = []
            
            # Return success response with empty games list (Dart backend handles game management)
            response_data = {
                "success": True,
                "message": "Game management moved to Dart backend - no games available via Python API",
                "games": available_games,
                "count": len(available_games),
                "timestamp": time.time()
            }
            return jsonify(response_data), 200
            
        except Exception as e:
            return jsonify({
                "success": False,
                "message": "Failed to retrieve available games",
                "error": str(e)
            }), 500
    
    def find_room(self):
        """Find a specific room by room ID (JWT protected endpoint)"""
        try:
            # Verify JWT token
            auth_header = request.headers.get('Authorization')
            
            if not auth_header:
                return jsonify({
                    "success": False,
                    "message": "No Authorization header provided",
                    "error": "Missing JWT token"
                }), 401
            
            # Extract token from Authorization header
            if auth_header.startswith('Bearer '):
                token = auth_header[7:]  # Remove 'Bearer ' prefix
            else:
                token = auth_header
            
            # Get JWT manager from app_manager
            jwt_manager = self.app_manager.jwt_manager
            
            # Verify the token
            payload = jwt_manager.verify_token(token, TokenType.ACCESS)
            
            if not payload:
                return jsonify({
                    "success": False,
                    "message": "Invalid or expired JWT token",
                    "error": "Token validation failed"
                }), 401
            
            # Get room ID from request body
            data = request.get_json()
            if not data or 'room_id' not in data:
                return jsonify({
                    "success": False,
                    "message": "Room ID is required",
                    "error": "Missing room_id in request body"
                }), 400
            
            room_id = data['room_id']
            
            # Game logic moved to Dart backend - return error indicating Dart backend should be used
            # Get room info from WebSocket manager to check if room exists
            room_info = self.websocket_manager.get_room_info(room_id)
            if not room_info:
                return jsonify({
                    "success": False,
                    "message": f"Room '{room_id}' not found",
                    "error": "Room does not exist"
                }), 404
            
            # Return response indicating game info is managed by Dart backend
            response_data = {
                "success": True,
                "message": "Game info is managed by Dart backend - use WebSocket connection",
                "room_id": room_id,
                "room_permission": room_info.get('permission', 'public'),
                "requires_password": room_info.get('permission') == 'private',
                "timestamp": time.time()
            }
            return jsonify(response_data), 200
            
        except Exception as e:
            return jsonify({
                "success": False,
                "message": "Failed to find game",
                "error": str(e)
            }), 500
    
    def update_game_stats(self):
        """Update user game statistics after a game ends (public endpoint)"""
        try:
            custom_log("📊 Python: Received game statistics update request", level="INFO", isOn=LOGGING_SWITCH)
            
            # Get game results from request body
            data = request.get_json()
            if not data:
                custom_log("❌ Python: Missing request body", level="ERROR", isOn=LOGGING_SWITCH)
                return jsonify({
                    "success": False,
                    "message": "Request body is required",
                    "error": "Missing request body"
                }), 400
            
            game_results = data.get('game_results')
            if not game_results or not isinstance(game_results, list):
                custom_log("❌ Python: Missing or invalid game_results in request body", level="ERROR", isOn=LOGGING_SWITCH)
                return jsonify({
                    "success": False,
                    "message": "game_results array is required",
                    "error": "Missing or invalid game_results in request body"
                }), 400
            
            if len(game_results) == 0:
                custom_log("❌ Python: Empty game_results array", level="ERROR", isOn=LOGGING_SWITCH)
                return jsonify({
                    "success": False,
                    "message": "game_results array cannot be empty",
                    "error": "No game results provided"
                }), 400
            
            custom_log(f"📊 Python: Processing {len(game_results)} player result(s)", level="INFO", isOn=LOGGING_SWITCH)
            
            # Get database manager
            db_manager = self.app_manager.get_db_manager(role="read_write")
            if not db_manager:
                return jsonify({
                    "success": False,
                    "message": "Database connection unavailable",
                    "error": "Database manager not initialized"
                }), 500
            
            # Get current timestamp
            current_time = datetime.utcnow()
            current_timestamp = current_time.isoformat()
            
            # Process each player's game results
            updated_players = []
            errors = []
            
            for player_result in game_results:
                try:
                    user_id_str = player_result.get('user_id')
                    if not user_id_str:
                        error_msg = f"Missing user_id in game result: {player_result}"
                        errors.append(error_msg)
                        custom_log(f"❌ Python: {error_msg}", level="ERROR", isOn=LOGGING_SWITCH)
                        continue
                    
                    # Convert user_id to ObjectId
                    try:
                        user_id = ObjectId(user_id_str)
                    except Exception as e:
                        error_msg = f"Invalid user_id format '{user_id_str}': {str(e)}"
                        errors.append(error_msg)
                        custom_log(f"❌ Python: {error_msg}", level="ERROR", isOn=LOGGING_SWITCH)
                        continue
                    
                    custom_log(f"📊 Python: Processing stats update for user_id: {user_id_str}", level="INFO", isOn=LOGGING_SWITCH)
                    
                    # Get current user data
                    user = db_manager.find_one("users", {"_id": user_id})
                    if not user:
                        error_msg = f"User not found: {user_id_str}"
                        errors.append(error_msg)
                        custom_log(f"❌ Python: {error_msg}", level="ERROR", isOn=LOGGING_SWITCH)
                        continue
                    
                    # Get current cleco_game module data
                    modules = user.get('modules', {})
                    cleco_game = modules.get('cleco_game', {})
                    
                    # Get current statistics
                    current_wins = cleco_game.get('wins', 0)
                    current_losses = cleco_game.get('losses', 0)
                    current_total_matches = cleco_game.get('total_matches', 0)
                    current_coins = cleco_game.get('coins', 0)
                    
                    custom_log(f"📊 Python: Current stats for {user_id_str} - wins: {current_wins}, losses: {current_losses}, matches: {current_total_matches}, coins: {current_coins}", level="INFO", isOn=LOGGING_SWITCH)
                    
                    # Get new values from game result
                    is_winner = player_result.get('is_winner', False)
                    pot = player_result.get('pot', 0)  # Pot amount for this player (already split if multiple winners)
                    
                    custom_log(f"📊 Python: Game result for {user_id_str} - is_winner: {is_winner}, pot: {pot}", level="INFO", isOn=LOGGING_SWITCH)
                    
                    # Calculate new statistics
                    new_total_matches = current_total_matches + 1
                    new_wins = current_wins + (1 if is_winner else 0)
                    new_losses = current_losses + (0 if is_winner else 1)
                    new_coins = current_coins + pot  # Add pot to winner's coins
                    
                    # Calculate win rate (wins / total_matches)
                    new_win_rate = float(new_wins) / float(new_total_matches) if new_total_matches > 0 else 0.0
                    
                    custom_log(f"📊 Python: New stats for {user_id_str} - wins: {new_wins}, losses: {new_losses}, matches: {new_total_matches}, coins: {new_coins} (added {pot}), win_rate: {new_win_rate:.2f}", level="INFO", isOn=LOGGING_SWITCH)
                    
                    # Prepare update data using MongoDB dot notation
                    # Use $inc for coins (atomic operation) and $set for other fields
                    # Note: db_manager.update() automatically wraps in $set, so we need raw MongoDB operation for $inc
                    update_operation = {
                        '$set': {
                            'modules.cleco_game.total_matches': new_total_matches,
                            'modules.cleco_game.wins': new_wins,
                            'modules.cleco_game.losses': new_losses,
                            'modules.cleco_game.win_rate': new_win_rate,
                            'modules.cleco_game.last_match_date': current_timestamp,
                            'modules.cleco_game.last_updated': current_timestamp,
                            'updated_at': current_timestamp
                        }
                    }
                    
                    # Add coin reward for winners using $inc (atomic operation)
                    if is_winner and pot > 0:
                        update_operation['$inc'] = {'modules.cleco_game.coins': pot}
                        custom_log(f"💰 Python: Awarding {pot} coins to winner {user_id_str} (current: {current_coins}, new: {new_coins})", level="INFO", isOn=LOGGING_SWITCH)
                    
                    # Update user in database using raw MongoDB operation (for $inc support)
                    custom_log(f"📊 Python: Updating database for user_id: {user_id_str}", level="INFO", isOn=LOGGING_SWITCH)
                    result = db_manager.db["users"].update_one(
                        {"_id": user_id},
                        update_operation
                    )
                    modified_count = result.modified_count if result else 0
                    
                    if modified_count > 0:
                        custom_log(f"✅ Python: Successfully updated database for user_id: {user_id_str} (modified_count: {modified_count})", level="INFO", isOn=LOGGING_SWITCH)
                        updated_players.append({
                            "user_id": user_id_str,
                            "wins": new_wins,
                            "losses": new_losses,
                            "total_matches": new_total_matches,
                            "coins": new_coins,
                            "coins_added": pot if is_winner else 0,
                            "win_rate": new_win_rate
                        })
                    else:
                        error_msg = f"Failed to update user: {user_id_str}"
                        errors.append(error_msg)
                        custom_log(f"❌ Python: {error_msg} (modified_count: {modified_count})", level="ERROR", isOn=LOGGING_SWITCH)
                        
                except Exception as e:
                    error_msg = f"Error processing player result {player_result.get('user_id', 'unknown')}: {str(e)}"
                    errors.append(error_msg)
                    custom_log(f"❌ Python: {error_msg}", level="ERROR", isOn=LOGGING_SWITCH)
            
            # Return response
            if len(updated_players) > 0:
                custom_log(f"✅ Python: Successfully updated {len(updated_players)} player(s)", level="INFO", isOn=LOGGING_SWITCH)
                if errors:
                    custom_log(f"⚠️ Python: {len(errors)} error(s) occurred during update", level="WARNING", isOn=LOGGING_SWITCH)
                
                response_data = {
                    "success": True,
                    "message": f"Game statistics updated successfully for {len(updated_players)} player(s)",
                    "updated_players": updated_players
                }
                
                if errors:
                    response_data["warnings"] = errors
                    response_data["message"] += f" ({len(errors)} error(s) occurred)"
                
                return jsonify(response_data), 200
            else:
                custom_log(f"❌ Python: Failed to update any player statistics. Errors: {errors}", level="ERROR", isOn=LOGGING_SWITCH)
                return jsonify({
                    "success": False,
                    "message": "Failed to update any player statistics",
                    "error": "All updates failed",
                    "errors": errors
                }), 500
            
        except Exception as e:
            custom_log(f"❌ Python: Error in update_game_stats: {e}", level="ERROR", isOn=LOGGING_SWITCH)
            return jsonify({
                "success": False,
                "message": "Failed to update game statistics",
                "error": str(e)
            }), 500
    
    def get_user_stats(self):
        """Get current user's cleco game statistics (JWT protected endpoint)"""
        try:
            # User ID is set by JWT middleware
            user_id = request.user_id
            if not user_id:
                return jsonify({
                    "success": False,
                    "error": "User not authenticated",
                    "message": "No user ID found in request"
                }), 401
            
            # Get database manager
            db_manager = self.app_manager.get_db_manager(role="read_write")
            if not db_manager:
                return jsonify({
                    "success": False,
                    "error": "Database connection unavailable",
                    "message": "Failed to connect to database"
                }), 500
            
            # Get user from database
            user = db_manager.find_one("users", {"_id": ObjectId(user_id)})
            if not user:
                return jsonify({
                    "success": False,
                    "error": "User not found",
                    "message": f"User with ID {user_id} not found in database"
                }), 404
            
            # Extract cleco_game module data
            modules = user.get('modules', {})
            cleco_game = modules.get('cleco_game', {})
            
            # Check if cleco_game module exists
            if not cleco_game:
                return jsonify({
                    "success": False,
                    "error": "Cleco game module not found",
                    "message": "User does not have cleco_game module initialized",
                    "data": None
                }), 404
            
            # Prepare response data with all cleco_game fields
            stats_data = {
                "enabled": cleco_game.get('enabled', True),
                "wins": cleco_game.get('wins', 0),
                "losses": cleco_game.get('losses', 0),
                "total_matches": cleco_game.get('total_matches', 0),
                "points": cleco_game.get('points', 0),
                "coins": cleco_game.get('coins', 0),
                "level": cleco_game.get('level', 1),
                "rank": cleco_game.get('rank', 'beginner'),
                "win_rate": cleco_game.get('win_rate', 0.0),
                "subscription_tier": cleco_game.get('subscription_tier', 'promotional'),
                "last_match_date": cleco_game.get('last_match_date'),
                "last_updated": cleco_game.get('last_updated')
            }
            
            # Convert datetime objects to ISO format strings
            if stats_data.get('last_match_date') and isinstance(stats_data['last_match_date'], datetime):
                stats_data['last_match_date'] = stats_data['last_match_date'].isoformat()
            if stats_data.get('last_updated') and isinstance(stats_data['last_updated'], datetime):
                stats_data['last_updated'] = stats_data['last_updated'].isoformat()
            
            custom_log(f"✅ ClecoGame: Successfully retrieved stats for user {user_id}", level="INFO", isOn=LOGGING_SWITCH)
            
            return jsonify({
                "success": True,
                "message": "User statistics retrieved successfully",
                "data": stats_data,
                "user_id": str(user_id),
                "timestamp": datetime.utcnow().isoformat()
            }), 200
            
        except Exception as e:
            custom_log(f"❌ ClecoGame: Error in get_user_stats: {e}", level="ERROR", isOn=LOGGING_SWITCH)
            return jsonify({
                "success": False,
                "error": "Failed to retrieve user statistics",
                "message": str(e)
            }), 500
    
    def deduct_game_coins(self):
        """Deduct game coins from multiple players when game starts (JWT protected endpoint)"""
        try:
            # User ID is set by JWT middleware
            user_id = request.user_id
            if not user_id:
                return jsonify({
                    "success": False,
                    "error": "User not authenticated",
                    "message": "No user ID found in request"
                }), 401
            
            # Get request body
            data = request.get_json()
            if not data:
                return jsonify({
                    "success": False,
                    "error": "Request body is required",
                    "message": "Missing request body"
                }), 400
            
            # Validate required fields
            coins = data.get('coins')
            game_id = data.get('game_id')
            player_ids = data.get('player_ids')
            
            if coins is None or not isinstance(coins, int) or coins <= 0:
                return jsonify({
                    "success": False,
                    "error": "Invalid coins amount",
                    "message": "coins must be a positive integer"
                }), 400
            
            if not game_id or not isinstance(game_id, str):
                return jsonify({
                    "success": False,
                    "error": "Invalid game_id",
                    "message": "game_id is required and must be a string"
                }), 400
            
            if not player_ids or not isinstance(player_ids, list) or len(player_ids) == 0:
                return jsonify({
                    "success": False,
                    "error": "Invalid player_ids",
                    "message": "player_ids must be a non-empty array"
                }), 400
            
            custom_log(f"💰 ClecoGame: Deducting {coins} coins for game {game_id} from {len(player_ids)} player(s)", level="INFO", isOn=LOGGING_SWITCH)
            
            # Get database manager
            db_manager = self.app_manager.get_db_manager(role="read_write")
            if not db_manager:
                return jsonify({
                    "success": False,
                    "error": "Database connection unavailable",
                    "message": "Failed to connect to database"
                }), 500
            
            # Get current timestamp
            current_time = datetime.utcnow()
            current_timestamp = current_time.isoformat()
            
            # Process each player's coin deduction
            updated_players = []
            errors = []
            
            for player_id_str in player_ids:
                try:
                    if not player_id_str or not isinstance(player_id_str, str):
                        error_msg = f"Invalid player_id format: {player_id_str}"
                        errors.append(error_msg)
                        custom_log(f"❌ ClecoGame: {error_msg}", level="ERROR", isOn=LOGGING_SWITCH)
                        continue
                    
                    # Convert player_id to ObjectId
                    try:
                        player_id = ObjectId(player_id_str)
                    except Exception as e:
                        error_msg = f"Invalid player_id format '{player_id_str}': {str(e)}"
                        errors.append(error_msg)
                        custom_log(f"❌ ClecoGame: {error_msg}", level="ERROR", isOn=LOGGING_SWITCH)
                        continue
                    
                    custom_log(f"💰 ClecoGame: Processing coin deduction for player_id: {player_id_str}", level="INFO", isOn=LOGGING_SWITCH)
                    
                    # Get current user data
                    user = db_manager.find_one("users", {"_id": player_id})
                    if not user:
                        error_msg = f"User not found: {player_id_str}"
                        errors.append(error_msg)
                        custom_log(f"❌ ClecoGame: {error_msg}", level="ERROR", isOn=LOGGING_SWITCH)
                        continue
                    
                    # Get current cleco_game module data
                    modules = user.get('modules', {})
                    cleco_game = modules.get('cleco_game', {})
                    
                    # Check subscription tier - skip deduction for promotional tier (free play)
                    subscription_tier = cleco_game.get('subscription_tier', 'promotional')
                    if subscription_tier == 'promotional':
                        custom_log(f"💰 ClecoGame: Skipping coin deduction for player {player_id_str} - promotional tier (free play)", level="INFO", isOn=LOGGING_SWITCH)
                        updated_players.append({
                            "user_id": player_id_str,
                            "coins_deducted": 0,
                            "previous_coins": cleco_game.get('coins', 0),
                            "new_coins": cleco_game.get('coins', 0),
                            "skipped": True,
                            "reason": "promotional_tier"
                        })
                        continue
                    
                    # Get current coins
                    current_coins = cleco_game.get('coins', 0)
                    
                    custom_log(f"💰 ClecoGame: Current coins for {player_id_str}: {current_coins}, subscription_tier: {subscription_tier}", level="INFO", isOn=LOGGING_SWITCH)
                    
                    # Check if user has enough coins (defense in depth - frontend should have checked already)
                    if current_coins < coins:
                        error_msg = f"Insufficient coins for user {player_id_str}: has {current_coins}, needs {coins}"
                        errors.append(error_msg)
                        custom_log(f"❌ ClecoGame: {error_msg}", level="ERROR", isOn=LOGGING_SWITCH)
                        continue
                    
                    # Calculate new coins
                    new_coins = current_coins - coins
                    
                    # Use $inc for atomic coin deduction
                    # Note: db_manager.update() automatically wraps in $set, so we need to use raw MongoDB operation
                    update_operation = {
                        '$inc': {'modules.cleco_game.coins': -coins},
                        '$set': {
                            'modules.cleco_game.last_updated': current_timestamp,
                            'updated_at': current_timestamp
                        }
                    }
                    
                    custom_log(f"💰 ClecoGame: Updating database for player_id: {player_id_str} (deducting {coins} coins)", level="INFO", isOn=LOGGING_SWITCH)
                    
                    # Use raw MongoDB update with $inc for atomic operation
                    # Access db directly since db_manager.update() only supports $set
                    result = db_manager.db["users"].update_one(
                        {"_id": player_id},
                        update_operation
                    )
                    
                    if result.modified_count > 0:
                        custom_log(f"✅ ClecoGame: Successfully deducted {coins} coins for player_id: {player_id_str} (new balance: {new_coins})", level="INFO", isOn=LOGGING_SWITCH)
                        updated_players.append({
                            "user_id": player_id_str,
                            "coins_deducted": coins,
                            "previous_coins": current_coins,
                            "new_coins": new_coins
                        })
                    else:
                        error_msg = f"Failed to update coins for user: {player_id_str} (modified_count: {result.modified_count})"
                        errors.append(error_msg)
                        custom_log(f"❌ ClecoGame: {error_msg}", level="ERROR", isOn=LOGGING_SWITCH)
                        
                except Exception as e:
                    error_msg = f"Error processing coin deduction for player {player_id_str}: {str(e)}"
                    errors.append(error_msg)
                    custom_log(f"❌ ClecoGame: {error_msg}", level="ERROR", isOn=LOGGING_SWITCH)
            
            # Return response
            if len(updated_players) > 0:
                custom_log(f"✅ ClecoGame: Successfully deducted coins for {len(updated_players)} player(s)", level="INFO", isOn=LOGGING_SWITCH)
                if errors:
                    custom_log(f"⚠️ ClecoGame: {len(errors)} error(s) occurred during coin deduction", level="WARNING", isOn=LOGGING_SWITCH)
                
                response_data = {
                    "success": True,
                    "message": f"Coins deducted successfully for {len(updated_players)} player(s)",
                    "game_id": game_id,
                    "coins_deducted": coins,
                    "updated_players": updated_players
                }
                
                if errors:
                    response_data["warnings"] = errors
                    response_data["message"] += f" ({len(errors)} error(s) occurred)"
                
                return jsonify(response_data), 200
            else:
                custom_log(f"❌ ClecoGame: Failed to deduct coins for any player. Errors: {errors}", level="ERROR", isOn=LOGGING_SWITCH)
                return jsonify({
                    "success": False,
                    "message": "Failed to deduct coins for any player",
                    "error": "All deductions failed",
                    "errors": errors
                }), 500
            
        except Exception as e:
            custom_log(f"❌ ClecoGame: Error in deduct_game_coins: {e}", level="ERROR", isOn=LOGGING_SWITCH)
            return jsonify({
                "success": False,
                "message": "Failed to deduct game coins",
                "error": str(e)
            }), 500
    
    
    def get_game_event_coordinator(self) -> Optional[None]:
        """Get the game event coordinator (deprecated - game logic moved to Dart backend)"""
        return None
    
    def is_initialized(self) -> bool:
        """Check if the Cleco game backend is initialized"""
        return self._initialized
    
    def health_check(self) -> dict:
        """Perform health check on Cleco game components"""
        if not self._initialized:
            return {
                'status': 'not_initialized',
                'component': 'cleco_game',
                'details': 'Cleco game backend not initialized'
            }
        
        try:
            websocket_health = 'healthy' if self.websocket_manager else 'unhealthy'
            # Game logic moved to Dart backend - no longer checking game_state_manager or event_coordinator
            
            return {
                'status': 'healthy' if websocket_health == 'healthy' else 'degraded',
                'component': 'cleco_game',
                'details': {
                    'websocket_manager': websocket_health,
                    'game_logic': 'moved_to_dart_backend'
                }
            }
            
        except Exception as e:
            return {
                'status': 'unhealthy',
                'component': 'cleco_game',
                'details': f'Health check failed: {str(e)}'
            }
    
    def cleanup(self):
        """Clean up Cleco game resources"""
        try:
            pass
        except Exception as e:
            pass


# Global instance for easy access
_cleco_game_main = None


def initialize_cleco_game(app_manager) -> Optional[ClecoGameMain]:
    """Initialize the Cleco game backend"""
    global _cleco_game_main
    
    try:
        _cleco_game_main = ClecoGameMain()
        success = _cleco_game_main.initialize(app_manager)
        
        if success:
            return _cleco_game_main
        else:
            return None
            
    except Exception as e:
        return None


def get_cleco_game_main() -> Optional[ClecoGameMain]:
    """Get the global Cleco game main instance"""
    return _cleco_game_main
