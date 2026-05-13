"""
Dutch Game Main Entry Point

This module serves as the main entry point for the Dutch game backend,
initializing all components and integrating with the main system.
All endpoint handlers live in api_endpoints.py; this module registers routes and lifecycle.
"""

from typing import Optional
from core.modules.base_module import BaseModule

# Logging switch for route registration (see .cursor/rules/enable-logging-switch.mdc)


class DutchGameMain(BaseModule):
    """Main orchestrator for the Dutch game backend"""
    
    def __init__(self, app_manager=None):
        super().__init__(app_manager)
        self.websocket_manager = None
        self.game_state_manager = None
        self.game_event_coordinator = None
    
    def initialize(self, app_manager) -> bool:
        """Initialize the Dutch game backend with the main app_manager"""
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
        """Register all Dutch game routes. Handlers live in api_endpoints.py."""
        try:
            from . import api_endpoints
            api_endpoints.set_app_manager(self.app_manager)
            self.app.register_blueprint(api_endpoints.dutch_api)

            self._register_route_helper("/userauth/dutch/get-available-games", api_endpoints.get_available_games, methods=["GET"], auth="jwt")
            self._register_route_helper("/userauth/dutch/find-room", api_endpoints.find_room, methods=["POST"], auth="jwt")
            self._register_route_helper("/service/dutch/update-game-stats", api_endpoints.update_game_stats, methods=["POST"])
            self._register_route_helper("/service/dutch/get-user-stats", api_endpoints.get_user_stats_service, methods=["POST"])
            self._register_route_helper("/service/dutch/deduct-game-coins", api_endpoints.deduct_game_coins_service, methods=["POST"])
            self._register_route_helper("/service/dutch/get-shop-catalog", api_endpoints.get_shop_catalog_service, methods=["POST"])
            self._register_route_helper("/service/dutch/get-inventory", api_endpoints.get_inventory_service, methods=["POST"])
            self._register_route_helper("/service/dutch/purchase-item", api_endpoints.purchase_item_service, methods=["POST"])
            self._register_route_helper("/service/dutch/equip-cosmetic", api_endpoints.equip_cosmetic_service, methods=["POST"])
            self._register_route_helper("/service/dutch/consume-win-booster", api_endpoints.consume_win_booster_service, methods=["POST"])
            self._register_route_helper("/service/dutch/attach-tournament-match-room", api_endpoints.attach_tournament_match_room_service, methods=["POST"])
            self._register_route_helper("/service/dutch/rematch-tournament-snapshot", api_endpoints.rematch_tournament_snapshot_service, methods=["POST"])
            self._register_route_helper("/service/dutch/get-tournaments", api_endpoints.get_tournaments_service, methods=["GET"])
            self._register_route_helper("/userauth/dutch/create-tournament", api_endpoints.create_tournament, methods=["POST"], auth="jwt")
            self._register_route_helper("/userauth/dutch/get-tournaments", api_endpoints.get_tournaments, methods=["GET"], auth="jwt")
            self._register_route_helper("/userauth/dutch/add-tournament-match", api_endpoints.add_tournament_match, methods=["POST"], auth="jwt")
            self._register_route_helper("/userauth/dutch/update-tournament-match", api_endpoints.update_tournament_match, methods=["POST"], auth="jwt")
            self._register_route_helper("/userauth/dutch/start-tournament-match", api_endpoints.start_tournament_match, methods=["POST"], auth="jwt")
            self._register_route_helper("/userauth/dutch/attach-tournament-match-room", api_endpoints.attach_tournament_match_room, methods=["POST"], auth="jwt")
            self._register_route_helper("/userauth/dutch/get-user-stats", api_endpoints.get_user_stats, methods=["GET"], auth="jwt")
            self._register_route_helper("/userauth/dutch/deduct-game-coins", api_endpoints.deduct_game_coins, methods=["POST"], auth="jwt")
            self._register_route_helper("/userauth/dutch/get-shop-catalog", api_endpoints.get_shop_catalog_service, methods=["POST"], auth="jwt")
            self._register_route_helper("/userauth/dutch/get-inventory", api_endpoints.get_inventory_service, methods=["POST"], auth="jwt")
            self._register_route_helper("/userauth/dutch/purchase-item", api_endpoints.purchase_item_service, methods=["POST"], auth="jwt")
            self._register_route_helper("/userauth/dutch/equip-cosmetic", api_endpoints.equip_cosmetic_service, methods=["POST"], auth="jwt")
            self._register_route_helper("/userauth/dutch/consume-win-booster", api_endpoints.consume_win_booster_service, methods=["POST"], auth="jwt")
            self._register_route_helper("/userauth/dutch/invite-players-to-match", api_endpoints.invite_players_to_match, methods=["POST"], auth="jwt")
            notification_module = self.app_manager.module_manager.get_module("notification_module")
            api_endpoints.register_notification_handlers(notification_module)
            self._register_route_helper("/public/dutch/get-comp-players", api_endpoints.get_comp_players, methods=["POST"])
            self._register_route_helper("/public/dutch/get-tournaments-list", api_endpoints.get_tournaments_list_public, methods=["GET"])
            self._register_route_helper("/sponsors/media/card_back.webp", api_endpoints.get_card_back_media, methods=["GET"])
            self._register_route_helper("/sponsors/media/table_design_overlay.webp", api_endpoints.get_table_design_overlay_media, methods=["GET"])
            self._register_route_helper(
                "/public/dutch/leaderboard-period-wins",
                api_endpoints.get_period_wins_leaderboard_public,
                methods=["GET"],
            )
            self._register_route_helper(
                "/public/dutch/leaderboard-period-wins-bundle",
                api_endpoints.get_period_wins_leaderboard_bundle_public,
                methods=["GET"],
            )
            self._register_route_helper("/public/dutch/get-tournaments", api_endpoints.get_tournaments_public, methods=["GET"])
            self._register_route_helper(
                "/public/dutch/table-tier-back/<path:filename>",
                api_endpoints.serve_table_tier_background_public,
                methods=["GET"],
            )
            self._register_route_helper("/userauth/dutch/tournament-signup", api_endpoints.tournament_signup, methods=["POST"], auth="jwt")

            return True
        except Exception as e:
            return False

    def get_game_event_coordinator(self) -> Optional[None]:
        """Get the game event coordinator (deprecated - game logic moved to Dart backend)"""
        return None
    
    def is_initialized(self) -> bool:
        """Check if the Dutch game backend is initialized"""
        return self._initialized
    
    def health_check(self) -> dict:
        """Perform health check on Dutch game components"""
        if not self._initialized:
            return {
                'status': 'not_initialized',
                'component': 'dutch_game',
                'details': 'Dutch game backend not initialized'
            }
        
        try:
            websocket_health = 'healthy' if self.websocket_manager else 'unhealthy'
            # Game logic moved to Dart backend - no longer checking game_state_manager or event_coordinator
            
            return {
                'status': 'healthy' if websocket_health == 'healthy' else 'degraded',
                'component': 'dutch_game',
                'details': {
                    'websocket_manager': websocket_health,
                    'game_logic': 'moved_to_dart_backend'
                }
            }
            
        except Exception as e:
            return {
                'status': 'unhealthy',
                'component': 'dutch_game',
                'details': f'Health check failed: {str(e)}'
            }
    
    def cleanup(self):
        """Clean up Dutch game resources"""
        try:
            pass
        except Exception as e:
            pass


# Global instance for easy access
_dutch_game_main = None


def initialize_dutch_game(app_manager) -> Optional[DutchGameMain]:
    """Initialize the Dutch game backend"""
    global _dutch_game_main
    
    try:
        _dutch_game_main = DutchGameMain()
        success = _dutch_game_main.initialize(app_manager)
        
        if success:
            return _dutch_game_main
        else:
            return None
            
    except Exception as e:
        return None


def get_dutch_game_main() -> Optional[DutchGameMain]:
    """Get the global Dutch game main instance"""
    return _dutch_game_main
