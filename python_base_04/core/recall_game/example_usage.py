"""
Example Usage of Recall Game System

This file demonstrates how to use the Recall game system with declarative rules
and proper integration with the existing WebSocket architecture.
"""

from models.game_state import GameState, GameStateManager
from models.player import HumanPlayer, ComputerPlayer
from models.card import CardDeck
from game_logic.game_logic_engine import GameLogicEngine
from websocket_handlers.game_websocket_manager import RecallGameWebSocketManager


def example_basic_game():
    """Example of a basic game setup and play"""
    
    # Initialize components
    game_state_manager = GameStateManager()
    game_logic_engine = GameLogicEngine()
    
    # Create a new game
    game_id = game_state_manager.create_game(max_players=4)
    game_state = game_state_manager.get_game(game_id)
    
    # Add players
    human_player = HumanPlayer("player_1", "Alice")
    computer_player1 = ComputerPlayer("player_2", "Bob", difficulty="medium")
    computer_player2 = ComputerPlayer("player_3", "Charlie", difficulty="easy")
    
    game_state.add_player(human_player)
    game_state.add_player(computer_player1)
    game_state.add_player(computer_player2)
    
    # Start the game
    game_state.start_game()
    
    print(f"Game started with {len(game_state.players)} players")
    print(f"Current player: {game_state.current_player_id}")
    
    # Example: Human player plays a card
    if human_player.hand:
        card_to_play = human_player.hand[0]
        action_data = {
            'action_type': 'play_card',
            'player_id': human_player.player_id,
            'card_id': card_to_play.card_id,
            'game_id': game_id
        }
        
        # Process through declarative rules
        result = game_logic_engine.process_player_action(game_state, action_data)
        
        if result.get('success'):
            print(f"Card played successfully: {card_to_play}")
            print(f"Next player: {game_state.current_player_id}")
        else:
            print(f"Error playing card: {result.get('error')}")
    
    return game_state


def example_websocket_integration():
    """Example of WebSocket integration with app_manager"""
    
    # This would typically be done in a module initialization
    # where app_manager is available
    
    # Initialize WebSocket manager with app_manager
    # websocket_manager = RecallGameWebSocketManager(app_manager)
    # websocket_manager.initialize(app_manager)
    
    # Simulate WebSocket events
    join_data = {
        'session_id': 'session_123',
        'game_id': 'game_456',
        'player_name': 'Alice',
        'player_type': 'human'
    }
    
    # In a real WebSocket environment, this would be handled by the event handler
    print(f"Player would join game: {join_data['game_id']}")
    
    # Simulate player action
    action_data = {
        'session_id': 'session_123',
        'game_id': 'game_456',
        'action_type': 'play_card',
        'card_id': 'ace_hearts_1234'
    }
    
    print(f"Player action would be processed: {action_data}")
    
    return "WebSocket integration example completed"


def example_module_integration():
    """Example of how to integrate Recall game into a module"""
    
    # This would be in a module's initialize method
    class RecallGameModule:
        def __init__(self, app_manager):
            self.app_manager = app_manager
            self.websocket_manager = None
            self.game_logic_engine = GameLogicEngine()
        
        def initialize(self):
            """Initialize the Recall game module"""
            # Get WebSocket manager from app_manager
            self.websocket_manager = RecallGameWebSocketManager(self.app_manager)
            self.websocket_manager.initialize(self.app_manager)
            
            print("Recall game module initialized with app_manager")
        
        def create_game(self, max_players=4):
            """Create a new game"""
            game_id = self.websocket_manager.game_state_manager.create_game(max_players)
            return game_id
        
        def get_game_state(self, game_id):
            """Get game state"""
            return self.websocket_manager.get_game_state(game_id)
    
    # Usage
    # module = RecallGameModule(app_manager)
    # module.initialize()
    # game_id = module.create_game()
    
    print("Module integration example completed")
    return "Module integration example"


def example_special_power_usage():
    """Example of using special power cards"""
    
    game_logic_engine = GameLogicEngine()
    
    # Create a game state
    game_state = GameState("example_game", max_players=2)
    
    # Add a player with a queen (special power card)
    player = HumanPlayer("player_1", "Alice")
    game_state.add_player(player)
    
    # Simulate playing a queen
    action_data = {
        'action_type': 'play_card',
        'player_id': player.player_id,
        'card_id': 'queen_hearts_1234',
        'game_id': 'example_game'
    }
    
    # Process through declarative rules
    result = game_logic_engine.process_player_action(game_state, action_data)
    
    print(f"Special power result: {result}")
    
    return result


def example_ai_decision():
    """Example of AI decision making"""
    
    from game_logic.computer_player_logic import ComputerPlayerLogic
    
    # Create AI logic
    ai_logic = ComputerPlayerLogic(difficulty="medium")
    
    # Create game state
    game_state = GameState("ai_game", max_players=2)
    computer_player = ComputerPlayer("ai_player", "AI_Bob", difficulty="medium")
    game_state.add_player(computer_player)
    
    # Simulate AI decision
    player_state = computer_player.to_dict()
    decision = ai_logic.make_decision(game_state, player_state)
    
    print(f"AI decision: {decision}")
    
    return decision


def example_declarative_rules():
    """Example of how declarative rules work"""
    
    game_logic_engine = GameLogicEngine()
    
    # Load rules
    action_rules = game_logic_engine.yaml_loader.load_action_rules()
    card_rules = game_logic_engine.yaml_loader.load_card_rules()
    special_power_rules = game_logic_engine.yaml_loader.load_special_power_rules()
    
    print("Loaded declarative rules:")
    print(f"- Action rules: {list(action_rules.keys())}")
    print(f"- Card rules: {list(card_rules.keys())}")
    print(f"- Special power rules: {list(special_power_rules.keys())}")
    
    return {
        'action_rules': action_rules,
        'card_rules': card_rules,
        'special_power_rules': special_power_rules
    }


def example_websocket_events():
    """Example of WebSocket event flow"""
    
    events = [
        {
            'event': 'recall_join_game',
            'data': {
                'session_id': 'session_123',
                'game_id': 'game_456',
                'player_name': 'Alice',
                'player_type': 'human'
            }
        },
        {
            'event': 'recall_player_action',
            'data': {
                'session_id': 'session_123',
                'game_id': 'game_456',
                'action_type': 'play_card',
                'card_id': 'ace_hearts_1234'
            }
        },
        {
            'event': 'recall_call_recall',
            'data': {
                'session_id': 'session_123',
                'game_id': 'game_456'
            }
        }
    ]
    
    print("WebSocket event flow:")
    for event in events:
        print(f"- {event['event']}: {event['data']}")
    
    return events


if __name__ == "__main__":
    print("=== Recall Game System Examples ===\n")
    
    print("1. Basic Game Setup:")
    game_state = example_basic_game()
    print()
    
    print("2. WebSocket Integration:")
    websocket_result = example_websocket_integration()
    print()
    
    print("3. Module Integration:")
    module_result = example_module_integration()
    print()
    
    print("4. Special Power Usage:")
    special_result = example_special_power_usage()
    print()
    
    print("5. AI Decision Making:")
    ai_decision = example_ai_decision()
    print()
    
    print("6. Declarative Rules:")
    rules = example_declarative_rules()
    print()
    
    print("7. WebSocket Events:")
    events = example_websocket_events()
    print()
    
    print("=== Examples Complete ===")
    print("\nKey Integration Points:")
    print("- Use app_manager.get_websocket_manager() to access WebSocket manager")
    print("- Register handlers with websocket_manager.register_handler()")
    print("- Use session_id from WebSocket events for player tracking")
    print("- Broadcast events using _broadcast_to_game() method")
    print("- Follow existing WebSocket architecture patterns") 