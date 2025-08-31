"""
Game State Models for Recall Game

This module defines the game state management system for the Recall card game,
including game phases, state transitions, game logic, and WebSocket communication.
"""

from typing import List, Dict, Any, Optional
from enum import Enum
from ..models.card import Card, CardDeck
from ..utils.deck_factory import DeckFactory
from ..models.player import Player, HumanPlayer, ComputerPlayer, PlayerType
from tools.logger.custom_logging import custom_log
from datetime import datetime
import time
import uuid


class GamePhase(Enum):
    """Game phases"""
    WAITING_FOR_PLAYERS = "waiting_for_players"
    DEALING_CARDS = "dealing_cards"
    PLAYER_TURN = "player_turn"
    OUT_OF_TURN_PLAY = "out_of_turn_play"
    RECALL_CALLED = "recall_called"
    GAME_ENDED = "game_ended"


class GameState:
    """Represents the current state of a Recall game"""
    
    def __init__(self, game_id: str, max_players: int = 4, min_players: int = 2, permission: str = 'public', app_manager=None):
        self.game_id = game_id
        self.max_players = max_players
        self.min_players = min_players
        self.permission = permission  # 'public' or 'private'
        self.app_manager = app_manager  # Reference to app manager for WebSocket access
        self.players = {}  # player_id -> Player
        self.current_player_id = None
        self.phase = GamePhase.WAITING_FOR_PLAYERS
        self.deck = CardDeck()
        self.discard_pile = []
        self.draw_pile = []
        self.pending_draws = {}  # player_id -> Card (drawn but not placed)
        self.out_of_turn_deadline = None  # timestamp until which out-of-turn is allowed
        self.out_of_turn_timeout_seconds = 5
        self.last_played_card = None
        self.recall_called_by = None
        self.game_start_time = None
        self.last_action_time = None
        self.game_ended = False
        self.winner = None
        self.game_history = []
        
        # Session tracking for individual player messaging
        self.player_sessions = {}  # player_id -> session_id
        self.session_players = {}  # session_id -> player_id
    
    def add_player(self, player: Player, session_id: str = None) -> bool:
        """Add a player to the game"""
        if len(self.players) >= self.max_players:
            return False
        
        self.players[player.player_id] = player
        
        # Track session mapping if session_id provided
        if session_id:
            self.player_sessions[player.player_id] = session_id
            self.session_players[session_id] = player.player_id
        
        return True
    
    def remove_player(self, player_id: str) -> bool:
        """Remove a player from the game"""
        if player_id in self.players:
            # Remove session mapping
            if player_id in self.player_sessions:
                session_id = self.player_sessions[player_id]
                del self.player_sessions[player_id]
                if session_id in self.session_players:
                    del self.session_players[session_id]
            
            del self.players[player_id]
            return True
        return False
    
    def get_player_session(self, player_id: str) -> Optional[str]:
        """Get session ID for a player"""
        return self.player_sessions.get(player_id)
    
    def get_session_player(self, session_id: str) -> Optional[str]:
        """Get player ID for a session"""
        return self.session_players.get(session_id)
    
    def update_player_session(self, player_id: str, session_id: str) -> bool:
        """Update session mapping for a player"""
        if player_id not in self.players:
            return False
        
        # Remove old mapping if exists
        if player_id in self.player_sessions:
            old_session_id = self.player_sessions[player_id]
            if old_session_id in self.session_players:
                del self.session_players[old_session_id]
        
        # Add new mapping
        self.player_sessions[player_id] = session_id
        self.session_players[session_id] = player_id
        return True
    
    def remove_session(self, session_id: str) -> Optional[str]:
        """Remove session mapping and return associated player_id"""
        if session_id in self.session_players:
            player_id = self.session_players[session_id]
            del self.session_players[session_id]
            if player_id in self.player_sessions:
                del self.player_sessions[player_id]
            return player_id
        return None
    

    
    def get_current_player(self) -> Optional[Player]:
        """Get the current player"""
        return self.players.get(self.current_player_id)
    

    
    def get_card_by_id(self, card_id: str) -> Optional[Card]:
        """Find a card by its ID anywhere in the game
        
        Searches through all game locations:
        - All player hands
        - Draw pile
        - Discard pile
        - Pending draws
        
        Args:
            card_id (str): The unique card ID to search for
            
        Returns:
            Optional[Card]: The card object if found, None otherwise
        """
        # Search in all player hands
        for player in self.players.values():
            for card in player.hand:
                if card.card_id == card_id:
                    return card
        
        # Search in draw pile
        for card in self.draw_pile:
            if card.card_id == card_id:
                return card
        
        # Search in discard pile
        for card in self.discard_pile:
            if card.card_id == card_id:
                return card
        
        # Search in pending draws
        for card in self.pending_draws.values():
            if card.card_id == card_id:
                return card
        
        # Card not found anywhere
        return None
    
    def find_card_location(self, card_id: str) -> Optional[Dict[str, Any]]:
        """Find a card and return its location information
        
        Args:
            card_id (str): The unique card ID to search for
            
        Returns:
            Optional[Dict[str, Any]]: Location info with keys:
                - 'card': The Card object
                - 'location_type': 'player_hand', 'draw_pile', 'discard_pile', 'pending_draw'
                - 'player_id': Player ID (if in player's possession)
                - 'index': Position in collection (if applicable)
        """
        # Search in all player hands
        for player_id, player in self.players.items():
            for index, card in enumerate(player.hand):
                if card.card_id == card_id:
                    return {
                        'card': card,
                        'location_type': 'player_hand',
                        'player_id': player_id,
                        'index': index
                    }
        
        # Search in draw pile
        for index, card in enumerate(self.draw_pile):
            if card.card_id == card_id:
                return {
                    'card': card,
                    'location_type': 'draw_pile',
                    'player_id': None,
                    'index': index
                }
        
        # Search in discard pile
        for index, card in enumerate(self.discard_pile):
            if card.card_id == card_id:
                return {
                    'card': card,
                    'location_type': 'discard_pile',
                    'player_id': None,
                    'index': index
                }
        
        # Search in pending draws
        for player_id, card in self.pending_draws.items():
            if card.card_id == card_id:
                return {
                    'card': card,
                    'location_type': 'pending_draw',
                    'player_id': player_id,
                    'index': None
                }
        
        # Card not found anywhere
        return None
    
    def get_round(self):
        """Get the game round handler"""
        from .game_round import GameRound
        return GameRound(self)
    



    

    
    def to_dict(self) -> Dict[str, Any]:
        """Convert game state to dictionary"""
        return {
            "game_id": self.game_id,
            "max_players": self.max_players,
            "players": {pid: player.to_dict() for pid, player in self.players.items()},
            "current_player_id": self.current_player_id,
            "phase": self.phase.value,
            "discard_pile": [card.to_dict() for card in self.discard_pile],
            "draw_pile_count": len(self.draw_pile),
            "last_played_card": self.last_played_card.to_dict() if self.last_played_card else None,
            "recall_called_by": self.recall_called_by,
            "game_start_time": self.game_start_time,
            "last_action_time": self.last_action_time,
            "game_ended": self.game_ended,
            "winner": self.winner,
            # Session tracking data
            "player_sessions": self.player_sessions,
            "session_players": self.session_players
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'GameState':
        """Create game state from dictionary"""
        game_state = cls(data["game_id"], data["max_players"])
        
        # Restore players
        for player_id, player_data in data.get("players", {}).items():
            if player_data["player_type"] == PlayerType.HUMAN.value:
                player = HumanPlayer.from_dict(player_data)
            else:
                player = ComputerPlayer.from_dict(player_data)
            game_state.players[player_id] = player
        
        game_state.current_player_id = data.get("current_player_id")
        game_state.phase = GamePhase(data.get("phase", "waiting_for_players"))
        game_state.recall_called_by = data.get("recall_called_by")
        game_state.game_start_time = data.get("game_start_time")
        game_state.last_action_time = data.get("last_action_time")
        game_state.game_ended = data.get("game_ended", False)
        game_state.winner = data.get("winner")
        
        # Restore session tracking data
        game_state.player_sessions = data.get("player_sessions", {})
        game_state.session_players = data.get("session_players", {})
        
        # Restore cards
        for card_data in data.get("discard_pile", []):
            card = Card.from_dict(card_data)
            game_state.discard_pile.append(card)
        
        if data.get("last_played_card"):
            game_state.last_played_card = Card.from_dict(data["last_played_card"])
        
        return game_state


class GameStateManager:
    """Manages multiple game states with integrated WebSocket communication"""
    
    def __init__(self):
        self.active_games = {}  # game_id -> GameState
        self.app_manager = None
        self.websocket_manager = None
        self.game_logic_engine = None
        self._initialized = False
    
    def initialize(self, app_manager, game_logic_engine) -> bool:
        """Initialize with WebSocket and game engine support"""
        try:
            self.app_manager = app_manager
            self.websocket_manager = app_manager.get_websocket_manager()
            self.game_logic_engine = game_logic_engine
            if not self.websocket_manager:
                custom_log("❌ WebSocket manager not available for GameStateManager", level="ERROR")
                return False
            
            # Register hook callbacks for automatic game creation
            self._register_hook_callbacks()
            
            self._initialized = True
            custom_log("✅ GameStateManager initialized with WebSocket support")
            return True
        except Exception as e:
            custom_log(f"❌ Failed to initialize GameStateManager: {e}", level="ERROR")
            return False
    
    def create_game(self, max_players: int = 4, min_players: int = 2, permission: str = 'public') -> str:
        """Create a new game"""
        game_id = str(uuid.uuid4())
        game_state = GameState(game_id, max_players, min_players, permission, self.app_manager)
        self.active_games[game_id] = game_state
        return game_id
    
    def create_game_with_id(self, game_id: str, max_players: int = 4, min_players: int = 2, permission: str = 'public') -> str:
        """Create a new game using a provided identifier (e.g., room_id).

        This aligns backend game identity with the room identifier used by the
        frontend so join/start flows can address the same id across the stack.
        If a game with this id already exists, it is returned unchanged.
        """
        # If already exists, no-op
        existing = self.active_games.get(game_id)
        if existing is not None:
            return game_id
        game_state = GameState(game_id, max_players, min_players, permission, self.app_manager)
        self.active_games[game_id] = game_state
        return game_id
    
    def get_game(self, game_id: str) -> Optional[GameState]:
        """Get a game by ID"""
        return self.active_games.get(game_id)
    
    def remove_game(self, game_id: str) -> bool:
        """Remove a game"""
        if game_id in self.active_games:
            del self.active_games[game_id]
            return True
        return False
    
    def get_all_games(self) -> Dict[str, GameState]:
        """Get all active games"""
        return self.active_games.copy()
    
    def get_available_games(self) -> List[Dict[str, Any]]:
        """Get all public games that are in the waiting for players phase and can be joined"""
        available_games = []
        total_games = len(self.active_games)
        public_games = 0
        private_games = 0
        
        for game_id, game in self.active_games.items():
            # Log game details for debugging
            custom_log(f"🎮 [DEBUG] Game {game_id}: phase={game.phase.value}, permission={game.permission}, players={len(game.players)}")
            
            # Only include PUBLIC games that are waiting for players
            if game.phase == GamePhase.WAITING_FOR_PLAYERS and game.permission == 'public':
                # Convert to Flutter-compatible format using coordinator
                if hasattr(self, 'app_manager') and self.app_manager:
                    coordinator = getattr(self.app_manager, 'game_event_coordinator', None)
                    if coordinator:
                        game_data = coordinator._to_flutter_game_data(game)
                        available_games.append(game_data)
                    else:
                        custom_log(f"⚠️ Coordinator not available for converting game state")
                else:
                    custom_log(f"⚠️ App manager not available for converting game state")
                public_games += 1
            elif game.permission == 'private':
                private_games += 1
        
        custom_log(f"🎮 Found {len(available_games)} available PUBLIC games out of {total_games} total games ({public_games} public, {private_games} private)")
        return available_games
    
    # ========= WebSocket Event Handlers =========
    
    def on_join_game(self, session_id: str, data: Dict[str, Any]) -> bool:
        """Handle player joining a game (now simplified since games are auto-created via hooks)"""
        try:
            game_id = data.get('game_id')
            player_name = data.get('player_name') or 'Player'
            player_type = data.get('player_type') or 'human'

            # Game should already exist (created via room_created hook)
            game = self.get_game(game_id)
            if not game:
                # Use the coordinator to send error message
                if hasattr(self, 'app_manager') and self.app_manager:
                    coordinator = getattr(self.app_manager, 'game_event_coordinator', None)
                    if coordinator:
                        coordinator._send_error(session_id, f'Game not found: {game_id} - games are auto-created when rooms are created')
                    else:
                        custom_log(f"⚠️ Coordinator not available for sending error message")
                else:
                    custom_log(f"⚠️ App manager not available for sending error message")
                return False

            # Join the room (game and room have same ID)
            self.websocket_manager.join_room(game_id, session_id)

            session_data = self.websocket_manager.get_session_data(session_id) or {}
            user_id = str(session_data.get('user_id') or session_id)

            # Add player if not exists
            if user_id not in game.players:
                player = ComputerPlayer(user_id, player_name) if player_type == 'computer' else HumanPlayer(user_id, player_name)
                game.add_player(player, session_id)
                custom_log(f"✅ Added player {user_id} to game {game_id}")
            else:
                game.update_player_session(user_id, session_id)
                custom_log(f"✅ Updated session for player {user_id} in game {game_id}")

            # Broadcast join event using coordinator
            payload = {
                'event_type': 'game_joined',
                'game_id': game_id,
                'game_state': None,  # Will be set by coordinator
                'player': self._to_flutter_player_data(game.players[user_id], user_id == game.current_player_id),
            }
            
            # Get game state from coordinator
            if hasattr(self, 'app_manager') and self.app_manager:
                coordinator = getattr(self.app_manager, 'game_event_coordinator', None)
                if coordinator:
                    payload['game_state'] = coordinator._to_flutter_game_data(game)
                else:
                    custom_log(f"⚠️ Coordinator not available for converting game state")
            else:
                custom_log(f"⚠️ App manager not available for converting game state")
            
            # Use the coordinator to broadcast the event
            if hasattr(self, 'app_manager') and self.app_manager:
                coordinator = getattr(self.app_manager, 'game_event_coordinator', None)
                if coordinator:
                    coordinator._broadcast_event(game_id, payload)
                else:
                    custom_log(f"⚠️ Coordinator not available for broadcasting game joined event")
            else:
                custom_log(f"⚠️ App manager not available for broadcasting game joined event")
            
            return True
            
        except Exception as e:
            custom_log(f"Error in on_join_game: {e}", level="ERROR")
            # Use the coordinator to send error message
            if hasattr(self, 'app_manager') and self.app_manager:
                coordinator = getattr(self.app_manager, 'game_event_coordinator', None)
                if coordinator:
                    coordinator._send_error(session_id, f'Join game failed: {str(e)}')
                else:
                    custom_log(f"⚠️ Coordinator not available for sending error message")
            else:
                custom_log(f"⚠️ App manager not available for sending error message")
            return False

    def on_start_match(self, session_id: str, data: Dict[str, Any]) -> bool:
        """Handle game start through the game round"""
        try:
            custom_log(f"🎮 [START_MATCH] Starting match for session: {session_id}, data: {data}")
            
            game_id = data.get('game_id') or data.get('room_id')
            if not game_id:
                custom_log(f"❌ [START_MATCH] Missing game_id in data: {data}")
                # Use the coordinator to send error message
                if hasattr(self, 'app_manager') and self.app_manager:
                    coordinator = getattr(self.app_manager, 'game_event_coordinator', None)
                    if coordinator:
                        coordinator._send_error(session_id, 'Missing game_id')
                    else:
                        custom_log(f"⚠️ Coordinator not available for sending error message")
                else:
                    custom_log(f"⚠️ App manager not available for sending error message")
                return False
            
            custom_log(f"🎮 [START_MATCH] Looking for game: {game_id}")
            game = self.get_game(game_id)
            if not game:
                custom_log(f"❌ [START_MATCH] Game not found: {game_id}")
                # Use the coordinator to send error message
                if hasattr(self, 'app_manager') and self.app_manager:
                    coordinator = getattr(self.app_manager, 'game_event_coordinator', None)
                    if coordinator:
                        coordinator._send_error(session_id, f'Game not found: {game_id}')
                    else:
                        custom_log(f"⚠️ Coordinator not available for sending error message")
                else:
                    custom_log(f"⚠️ App manager not available for sending error message")
                return False

            custom_log(f"✅ [START_MATCH] Game found: {game_id}")
            session_data = self.websocket_manager.get_session_data(session_id) or {}
            user_id = str(session_data.get('user_id') or session_id)
            custom_log(f"🎮 [START_MATCH] User ID: {user_id}")
            
            # ========= CONSOLIDATED GAME START LOGIC =========
            custom_log(f"🎮 [START_MATCH] Starting consolidated game start logic...")
            
            # Check if we have enough players, add computer players if needed
            current_players = len(game.players)
            min_players = game.min_players
            
            if current_players < min_players:
                # Add computer players to reach minimum
                players_needed = min_players - current_players
                custom_log(f"🎮 [START_MATCH] Adding {players_needed} computer player(s) to reach minimum of {min_players}")
                
                for i in range(players_needed):
                    computer_id = f"computer_{game.game_id}_{i}"
                    computer_name = f"Computer_{i+1}"
                    from ..models.player import ComputerPlayer
                    computer_player = ComputerPlayer(computer_id, computer_name, difficulty="medium")
                    game.add_player(computer_player)
                    custom_log(f"✅ [START_MATCH] Added computer player: {computer_name} (ID: {computer_id})")
            
            game.phase = GamePhase.DEALING_CARDS
            game.game_start_time = time.time()
            
            # Build deterministic deck from factory, then deal
            from ..utils.deck_factory import DeckFactory
            factory = DeckFactory(game.game_id)
            game.deck.cards = factory.build_deck(
                include_jokers=True,  # Standard deck cards (including jokers, queens, jacks, kings)
            )
            self._deal_cards(game)
            
            # Set up draw and discard piles
            self._setup_piles(game)
            
            # Set first player and update player statuses
            player_ids = list(game.players.keys())
            game.current_player_id = player_ids[0]
            
            # Update player statuses
            for player_id, player in game.players.items():
                if player_id == game.current_player_id:
                    player.set_drawing_card()  # Current player needs to draw a card first
                else:
                    player.set_ready()    # Other players are ready
            
            game.phase = GamePhase.PLAYER_TURN
            game.last_action_time = time.time()
            
            custom_log(f"✅ [START_MATCH] Game start logic completed successfully")
            # ========= END CONSOLIDATED GAME START LOGIC =========
            
            # Get the game round handler
            custom_log(f"🎮 [START_MATCH] Getting game round...")
            game_round = game.get_round()
            
            # Start the first round
            custom_log(f"🎮 [START_MATCH] Starting round...")
            round_result = game_round.start_round()
            custom_log(f"🎮 [START_MATCH] Round start result: {round_result}")
            
            if round_result.get('error'):
                custom_log(f"❌ [START_MATCH] Round start failed: {round_result['error']}")
                # Use the coordinator to send error message
                if hasattr(self, 'app_manager') and self.app_manager:
                    coordinator = getattr(self.app_manager, 'game_event_coordinator', None)
                    if coordinator:
                        coordinator._send_error(session_id, f"Start match failed: {round_result['error']}")
                    else:
                        custom_log(f"⚠️ Coordinator not available for sending error message")
                else:
                    custom_log(f"⚠️ App manager not available for sending error message")
                return False
            
            # Send game started event to all players with full game state
            payload = {
                'event_type': 'game_started',
                'game_id': game_id,
                'started_by': user_id,
                'game_state': self._to_flutter_game_data(game),  # Include full game state
                'timestamp': datetime.now().isoformat(),
                'player_order': list(game.players.keys()),  # List of player IDs in order
                'initial_hands': {pid: len(player.hand) for pid, player in game.players.items()}  # Initial hand sizes
            }
            
            # Use the coordinator to broadcast the event
            if hasattr(self, 'app_manager') and self.app_manager:
                coordinator = getattr(self.app_manager, 'game_event_coordinator', None)
                if coordinator:
                    # Broadcast game started event to all players
                    coordinator._broadcast_event(game_id, payload)
                    
                    # Send turn event to the current player
                    current_player_id = round_result.get('current_player')
                    if current_player_id:
                        # Get current player status
                        current_player = game.players.get(current_player_id)
                        player_status = current_player.status.value if current_player else 'ready'
                        
                        turn_payload = {
                            'event_type': 'turn_started',
                            'game_id': game_id,
                            'player_id': current_player_id,
                            'player_status': player_status,  # ✅ Add missing field
                            'turn_timeout': 30,  # 30 seconds per turn
                            'is_my_turn': True,
                            'game_state': self._to_flutter_game_data(game),  # Include full game state
                            'timestamp': datetime.now().isoformat()
                        }
                        coordinator._send_to_player(game_id, current_player_id, 'turn_started', turn_payload)
                        custom_log(f"🎯 [START_MATCH] Turn event sent to current player {current_player_id}")
                    else:
                        custom_log(f"⚠️ [START_MATCH] No current player found in round result")
                else:
                    custom_log(f"⚠️ Coordinator not available for broadcasting game started event")
            else:
                custom_log(f"⚠️ App manager not available for broadcasting game started event")
            
            custom_log(f"🎮 Game {game_id} started by {user_id}, round {round_result.get('round_number')}")
            return True
            
        except Exception as e:
            custom_log(f"❌ [START_MATCH] Exception in on_start_match: {e}", level="ERROR")
            import traceback
            custom_log(f"❌ [START_MATCH] Traceback: {traceback.format_exc()}", level="ERROR")
            # Use the coordinator to send error message
            if hasattr(self, 'app_manager') and self.app_manager:
                coordinator = getattr(self.app_manager, 'game_event_coordinator', None)
                if coordinator:
                    coordinator._send_error(session_id, f'Start match failed: {str(e)}')
                else:
                    custom_log(f"⚠️ Coordinator not available for sending error message")
            else:
                custom_log(f"⚠️ App manager not available for sending error message")
            return False

    # ========= CONSOLIDATED GAME START HELPER METHODS =========
    
    def _deal_cards(self, game: GameState):
        """Deal 4 cards to each player - moved from GameActions"""
        for player in game.players.values():
            for _ in range(4):
                card = game.deck.draw_card()
                if card:
                    player.add_card_to_hand(card)
        custom_log(f"🎮 [START_MATCH] Dealt 4 cards to each of {len(game.players)} players")
    
    def _setup_piles(self, game: GameState):
        """Set up draw and discard piles - moved from GameActions"""
        # Move remaining cards to draw pile
        game.draw_pile = game.deck.cards.copy()
        game.deck.cards = []
        
        # Start discard pile with first card from draw pile
        if game.draw_pile:
            first_card = game.draw_pile.pop(0)
            game.discard_pile.append(first_card)
            custom_log(f"🎮 [START_MATCH] Set up piles: {len(game.draw_pile)} cards in draw pile, 1 card in discard pile")
        else:
            custom_log(f"⚠️ [START_MATCH] No cards available for pile setup")





    def _to_flutter_card(self, card) -> Dict[str, Any]:
        """Convert card to Flutter format"""
        rank_mapping = {
            '2': 'two', '3': 'three', '4': 'four', '5': 'five',
            '6': 'six', '7': 'seven', '8': 'eight', '9': 'nine', '10': 'ten'
        }
        return {
            'cardId': card.card_id,
            'suit': card.suit,
            'rank': rank_mapping.get(card.rank, card.rank),
            'points': card.points,
            'displayName': str(card),
            'color': 'red' if card.suit in ['hearts', 'diamonds'] else 'black',
        }

    def _to_flutter_player_data(self, player, is_current: bool = False) -> Dict[str, Any]:
        """
        Convert player to Flutter format - SINGLE SOURCE OF TRUTH for player data structure
        
        This method structures ALL player data that will be sent to the frontend.
        The structure MUST match the Flutter frontend schema exactly.
        """
        return {
            'id': player.player_id,
            'name': player.name,
            'type': 'human' if player.player_type.value == 'human' else 'computer',
            'hand': [self._to_flutter_card(c) for c in player.hand],
            'visibleCards': [self._to_flutter_card(c) for c in player.visible_cards],
            'score': int(player.calculate_points()),
            'status': player.status.value,  # Use the player's actual status
            'isCurrentPlayer': is_current,
            'hasCalledRecall': bool(player.has_called_recall),
        }

    def _to_flutter_game_data(self, game: GameState) -> Dict[str, Any]:
        """
        Convert game state to Flutter format - SINGLE SOURCE OF TRUTH for game data structure
        
        This method structures ALL game data that will be sent to the frontend.
        The structure MUST match the Flutter frontend schema exactly.
        """
        phase_mapping = {
            'waiting_for_players': 'waiting',
            'dealing_cards': 'setup',
            'player_turn': 'playing',
            'out_of_turn_play': 'out_of_turn',
            'recall_called': 'recall',
            'game_ended': 'finished',
        }
        
        # Get current player data
        current_player = None
        if game.current_player_id and game.current_player_id in game.players:
            current_player = self._to_flutter_player_data(game.players[game.current_player_id], True)

        # Build complete game data structure matching Flutter schema
        game_data = {
            # Core game identification
            'gameId': game.game_id,
            'gameName': f"Recall Game {game.game_id}",
            
            # Player information
            'players': [self._to_flutter_player_data(player, pid == game.current_player_id) for pid, player in game.players.items()],
            'currentPlayer': current_player,
            'playerCount': len(game.players),
            'maxPlayers': game.max_players,
            'minPlayers': game.min_players,
            'activePlayerCount': len([p for p in game.players.values() if p.is_active]),
            
            # Game state and phase
            'phase': phase_mapping.get(game.phase.value, 'waiting'),
            'status': 'active' if game.phase.value in ['player_turn', 'out_of_turn_play', 'recall_called'] else 'inactive',
            
            # Card piles
            'drawPile': [self._to_flutter_card(card) for card in game.draw_pile],
            'discardPile': [self._to_flutter_card(card) for card in game.discard_pile],
            
            # Game timing
            'gameStartTime': datetime.fromtimestamp(game.game_start_time).isoformat() if game.game_start_time else None,
            'lastActivityTime': datetime.fromtimestamp(game.last_action_time).isoformat() if game.last_action_time else None,
            
            # Game completion
            'winner': game.winner,
            'gameEnded': game.game_ended,
            
            # Room settings
            'permission': game.permission,  # Include room permission
            
            # Additional game metadata
            'recallCalledBy': game.recall_called_by,
            'lastPlayedCard': self._to_flutter_card(game.last_played_card) if game.last_played_card else None,
            'outOfTurnDeadline': game.out_of_turn_deadline,
            'outOfTurnTimeoutSeconds': game.out_of_turn_timeout_seconds,
        }
        
        return game_data

    # ========= DEPRECATED METHODS - REMOVE AFTER MIGRATION =========
    
    def _to_flutter_card(self, card) -> Dict[str, Any]:
        """
        DEPRECATED: Convert card to Flutter format
        This method will be removed after migration to _to_flutter_game_data
        """
        rank_mapping = {
            '2': 'two', '3': 'three', '4': 'four', '5': 'five',
            '6': 'six', '7': 'seven', '8': 'eight', '9': 'nine', '10': 'ten'
        }
        return {
            'cardId': card.card_id,
            'suit': card.suit,
            'rank': rank_mapping.get(card.rank, card.rank),
            'points': card.points,
            'displayName': str(card),
            'color': 'red' if card.suit in ['hearts', 'diamonds'] else 'black',
        }

    def _to_flutter_player(self, player, is_current: bool = False) -> Dict[str, Any]:
        """
        DEPRECATED: Convert player to Flutter format
        This method will be removed after migration to _to_flutter_player_data
        """
        return self._to_flutter_player_data(player, is_current)

    def _to_flutter_game_state(self, game: GameState) -> Dict[str, Any]:
        """
        DEPRECATED: Convert game state to Flutter format
        This method will be removed after migration to _to_flutter_game_data
        """
        return self._to_flutter_game_data(game)

    def cleanup_ended_games(self):
        """Remove games that have ended"""
        ended_games = []
        for game_id, game_state in self.active_games.items():
            if game_state.game_ended:
                ended_games.append(game_id)
        
        for game_id in ended_games:
            del self.active_games[game_id]
    
    def _register_hook_callbacks(self):
        """Register hook callbacks for automatic game creation"""
        try:
            # Register callback for room_created hook
            self.app_manager.register_hook_callback('room_created', self._on_room_created)
            custom_log("🎣 [HOOK] Registered room_created callback in GameStateManager")
            
            # Register callback for room_joined hook
            self.app_manager.register_hook_callback('room_joined', self._on_room_joined)
            custom_log("🎣 [HOOK] Registered room_joined callback in GameStateManager")
            
            # Register callback for room_closed hook
            self.app_manager.register_hook_callback('room_closed', self._on_room_closed)
            custom_log("🎣 [HOOK] Registered room_closed callback in GameStateManager")
            
            # Register callback for leave_room hook
            self.app_manager.register_hook_callback('leave_room', self._on_leave_room)
            custom_log("🎣 [HOOK] Registered leave_room callback in GameStateManager")
            
        except Exception as e:
            custom_log(f"❌ Error registering hook callbacks: {e}", level="ERROR")
    
    def _on_room_created(self, room_data: Dict[str, Any]):
        """Callback for room_created hook - automatically create game"""
        try:
            room_id = room_data.get('room_id')
            max_players = room_data.get('max_players', 4)
            min_players = room_data.get('min_players', 2)
            permission = room_data.get('permission', 'public')  # Extract room permission
            
            custom_log(f"🎮 [HOOK] Room created: {room_id}, creating game automatically with permission: {permission}")
            
            # Create game with room_id as game_id and room permission
            game_id = self.create_game_with_id(room_id, max_players=max_players, min_players=min_players, permission=permission)
            
            # Initialize game state (waiting for players)
            game = self.get_game(game_id)
            if game:
                game.phase = GamePhase.WAITING_FOR_PLAYERS
                custom_log(f"✅ Game {game_id} created and initialized for room {room_id} with permission: {permission}")
            else:
                custom_log(f"❌ Failed to create game for room {room_id}")
                
        except Exception as e:
            custom_log(f"❌ Error in _on_room_created callback: {e}", level="ERROR")
    
    def _on_room_joined(self, room_data: Dict[str, Any]):
        """Callback for room_joined hook - handle player joining existing game"""
        try:
            room_id = room_data.get('room_id')
            user_id = room_data.get('user_id')
            session_id = room_data.get('session_id')  # Get session_id from room_data
            current_size = room_data.get('current_size', 1)
            
            custom_log(f"🎮 [HOOK] Player {user_id} joined room {room_id}, session: {session_id}, current size: {current_size}")
            custom_log(f"🔍 [DEBUG] _on_room_joined callback triggered with room_data: {room_data}")
            
            # Check if game exists for this room
            game = self.get_game(room_id)
            if not game:
                custom_log(f"⚠️ No game found for room {room_id}, this shouldn't happen")
                return
            
            # Add player to the game if they don't exist
            player_added = False
            if user_id not in game.players:
                # Create a human player for the user
                from ..models.player import HumanPlayer
                player = HumanPlayer(user_id, f"Player_{user_id[:8]}")
                game.add_player(player)
                player_added = True
                custom_log(f"✅ Added player {user_id} to game {room_id}")
            else:
                custom_log(f"ℹ️ Player {user_id} already exists in game {room_id}")
            
            # Set up session mapping for the player
            if session_id and user_id:
                game.update_player_session(user_id, session_id)
                custom_log(f"🔗 Session mapping created: session {session_id} -> player {user_id}")
            
            # Update room size in WebSocket manager (if player was newly added)
            if player_added:
                try:
                    from core.managers.websockets.websocket_manager import WebSocketManager
                    ws_manager = WebSocketManager.instance
                    if ws_manager:
                        ws_manager.update_room_size(room_id, 1)  # Increase room size by 1
                        custom_log(f"📊 Updated room {room_id} size after player {user_id} joined")
                except Exception as e:
                    custom_log(f"⚠️ Failed to update room size: {e}")
            
            # Update game state based on player count
            if current_size >= game.min_players and game.phase == GamePhase.WAITING_FOR_PLAYERS:
                custom_log(f"🎮 Room {room_id} has enough players ({current_size}), ready to start")
                # Game is ready but not started yet - will be started manually or via auto-start
            
            # 🎯 NEW: Send recall-specific events after player joins
            custom_log(f"🔍 [DEBUG] About to send recall player joined events for {user_id} in room {room_id}")
            
            # Use the coordinator to send recall player joined events
            if hasattr(self, 'app_manager') and self.app_manager:
                custom_log(f"🔍 [DEBUG] App manager is available")
                coordinator = getattr(self.app_manager, 'game_event_coordinator', None)
                if coordinator:
                    custom_log(f"🔍 [DEBUG] Coordinator is available, calling _send_recall_player_joined_events")
                    coordinator._send_recall_player_joined_events(room_id, user_id, session_id, game)
                    custom_log(f"✅ [DEBUG] _send_recall_player_joined_events called successfully")
                else:
                    custom_log(f"⚠️ Coordinator not available for sending recall player joined events")
            else:
                custom_log(f"⚠️ App manager not available for sending recall player joined events")
            
        except Exception as e:
            custom_log(f"❌ Error in _on_room_joined callback: {e}", level="ERROR")
            import traceback
            custom_log(f"❌ Traceback: {traceback.format_exc()}", level="ERROR")
    
    def _on_room_closed(self, room_data: Dict[str, Any]):
        """Callback for room_closed hook - cleanup game when room is closed"""
        try:
            room_id = room_data.get('room_id')
            reason = room_data.get('reason', 'unknown')
            
            custom_log(f"🎮 [HOOK] Room closed: {room_id}, reason: {reason}, cleaning up game")
            
            # Remove game if it exists
            if room_id in self.active_games:
                del self.active_games[room_id]
                custom_log(f"✅ Game {room_id} removed due to room closure")
            else:
                custom_log(f"ℹ️ No game found for closed room {room_id}")
                
        except Exception as e:
            custom_log(f"❌ Error in _on_room_closed callback: {e}", level="ERROR")
    
    def _on_leave_room(self, room_data: Dict[str, Any]):
        """Callback for leave_room hook - handle player leaving game"""
        try:
            room_id = room_data.get('room_id')
            session_id = room_data.get('session_id')
            user_id = room_data.get('user_id')  # Get user_id from room_data
            
            custom_log(f"🎮 [HOOK] Player left room: {room_id}, session: {session_id}, user: {user_id}")
            
            # Check if game exists for this room
            game = self.get_game(room_id)
            if not game:
                custom_log(f"ℹ️ No game found for room {room_id}")
                return
            
            # Try to find player by session_id first
            player_id = None
            if session_id:
                player_id = game.get_session_player(session_id)
                if player_id:
                    custom_log(f"🔍 Found player {player_id} by session {session_id}")
            
            # Fallback: try to find player by user_id if session lookup failed
            if not player_id and user_id:
                if user_id in game.players:
                    player_id = user_id
                    custom_log(f"🔍 Found player {player_id} by user_id {user_id}")
            
            # Remove player if found
            if player_id:
                game.remove_player(player_id)
                custom_log(f"✅ Player {player_id} removed from game {room_id}")
                
                # Clean up session mapping
                if session_id:
                    game.remove_session(session_id)
                    custom_log(f"🧹 Session mapping cleaned up for session {session_id}")
                
                # Update room size in WebSocket manager
                try:
                    from core.managers.websockets.websocket_manager import WebSocketManager
                    ws_manager = WebSocketManager.instance
                    if ws_manager:
                        ws_manager.update_room_size(room_id, -1)  # Decrease room size by 1
                        custom_log(f"📊 Updated room {room_id} size after player {player_id} left")
                except Exception as e:
                    custom_log(f"⚠️ Failed to update room size: {e}")
                
                # Note: Game phase remains WAITING_FOR_PLAYERS even when empty
                # Games are only cleaned up when rooms are closed (via TTL or stale cleanup)
                custom_log(f"🎮 Game {room_id} now has {len(game.players)} players, but remains available for joining")
            else:
                custom_log(f"⚠️ No player found for session {session_id} or user {user_id} in game {room_id}")
            
        except Exception as e:
            custom_log(f"❌ Error in _on_leave_room callback: {e}", level="ERROR")