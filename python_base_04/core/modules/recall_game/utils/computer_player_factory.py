"""
Factory for creating computer player behavior based on YAML configuration

Provides declarative AI decision making for computer players in the backend.
"""

import random
import threading
from typing import Dict, Any, List, Optional
from tools.logger.custom_logging import custom_log
from .computer_player_config_loader import ComputerPlayerConfigLoader

LOGGING_SWITCH = True

class ComputerPlayerFactory:
    """Factory for creating computer player behavior based on YAML configuration"""
    
    def __init__(self, config_loader: ComputerPlayerConfigLoader):
        self.config = config_loader
        self._random = random.Random()
    
    @classmethod
    def from_file(cls, config_path: str) -> 'ComputerPlayerFactory':
        """Create factory from YAML file"""
        config_loader = ComputerPlayerConfigLoader.from_file(config_path)
        return cls(config_loader)
    
    @classmethod
    def from_string(cls, yaml_string: str) -> 'ComputerPlayerFactory':
        """Create factory from YAML string"""
        config_loader = ComputerPlayerConfigLoader.from_string(yaml_string)
        return cls(config_loader)
    
    def get_draw_card_decision(self, difficulty: str, game_state: Dict[str, Any]) -> Dict[str, Any]:
        """Get computer player decision for draw card event"""
        decision_delay = self.config.get_decision_delay(difficulty)
        draw_from_discard_prob = self.config.get_draw_from_discard_probability(difficulty)
        
        # Simulate decision making with delay
        should_draw_from_discard = self._random.random() < draw_from_discard_prob
        
        return {
            'action': 'draw_card',
            'source': 'discard' if should_draw_from_discard else 'deck',
            'delay_seconds': decision_delay,
            'difficulty': difficulty,
            'reasoning': f"Drawing from {'discard pile' if should_draw_from_discard else 'deck'} ({draw_from_discard_prob * 100:.1f}% probability)"
        }
    
    def get_play_card_decision(self, difficulty: str, game_state: Dict[str, Any], available_cards: List[str]) -> Dict[str, Any]:
        """Get computer player decision for play card event"""
        decision_delay = self.config.get_decision_delay(difficulty)
        card_selection = self.config.get_card_selection_strategy(difficulty)
        evaluation_weights = self.config.get_card_evaluation_weights()
        
        if not available_cards:
            return {
                'action': 'play_card',
                'card_id': None,
                'delay_seconds': decision_delay,
                'difficulty': difficulty,
                'reasoning': 'No cards available to play'
            }
        
        # Select card based on strategy
        selected_card = self._select_card(available_cards, card_selection, evaluation_weights, game_state)
        
        return {
            'action': 'play_card',
            'card_id': selected_card,
            'delay_seconds': decision_delay,
            'difficulty': difficulty,
            'reasoning': f"Selected card using {card_selection.get('strategy', 'random')} strategy"
        }
    
    def get_same_rank_play_decision(self, difficulty: str, game_state: Dict[str, Any], available_cards: List[str]) -> Dict[str, Any]:
        """Get computer player decision for same rank play event"""
        decision_delay = self.config.get_decision_delay(difficulty)
        play_probability = self.config.get_same_rank_play_probability(difficulty)
        
        should_play = self._random.random() < play_probability
        
        if not should_play or not available_cards:
            return {
                'action': 'same_rank_play',
                'play': False,
                'card_id': None,
                'delay_seconds': decision_delay,
                'difficulty': difficulty,
                'reasoning': f"Decided not to play same rank ({(1 - play_probability) * 100:.1f}% probability)"
            }
        
        # Select a card to play
        selected_card = self._random.choice(available_cards)
        
        return {
            'action': 'same_rank_play',
            'play': True,
            'card_id': selected_card,
            'delay_seconds': decision_delay,
            'difficulty': difficulty,
            'reasoning': f"Playing same rank card ({play_probability * 100:.1f}% probability)"
        }
    
    def get_jack_swap_decision(self, difficulty: str, game_state: Dict[str, Any], player_id: str) -> Dict[str, Any]:
        """Get computer player decision for Jack swap event"""
        decision_delay = self.config.get_decision_delay(difficulty)
        jack_swap_config = self.config.get_special_card_config(difficulty, 'jack_swap')
        use_probability = jack_swap_config.get('use_probability', 0.8)
        target_strategy = jack_swap_config.get('target_strategy', 'random')
        
        should_use = self._random.random() < use_probability
        
        if not should_use:
            return {
                'action': 'jack_swap',
                'use': False,
                'delay_seconds': decision_delay,
                'difficulty': difficulty,
                'reasoning': f"Decided not to use Jack swap ({(1 - use_probability) * 100:.1f}% probability)"
            }
        
        # Select targets based on strategy
        targets = self._select_jack_swap_targets(game_state, player_id, target_strategy)
        
        return {
            'action': 'jack_swap',
            'use': True,
            'first_card_id': targets['first_card_id'],
            'first_player_id': targets['first_player_id'],
            'second_card_id': targets['second_card_id'],
            'second_player_id': targets['second_player_id'],
            'delay_seconds': decision_delay,
            'difficulty': difficulty,
            'reasoning': f"Using Jack swap with {target_strategy} strategy ({use_probability * 100:.1f}% probability)"
        }
    
    def get_queen_peek_decision(self, difficulty: str, game_state: Dict[str, Any], player_id: str) -> Dict[str, Any]:
        """Get computer player decision for Queen peek event"""
        decision_delay = self.config.get_decision_delay(difficulty)
        queen_peek_config = self.config.get_special_card_config(difficulty, 'queen_peek')
        use_probability = queen_peek_config.get('use_probability', 0.8)
        target_strategy = queen_peek_config.get('target_strategy', 'random')
        
        should_use = self._random.random() < use_probability
        
        if not should_use:
            return {
                'action': 'queen_peek',
                'use': False,
                'delay_seconds': decision_delay,
                'difficulty': difficulty,
                'reasoning': f"Decided not to use Queen peek ({(1 - use_probability) * 100:.1f}% probability)"
            }
        
        # Select target based on strategy
        target = self._select_queen_peek_target(game_state, player_id, target_strategy)
        
        return {
            'action': 'queen_peek',
            'use': True,
            'target_card_id': target['card_id'],
            'target_player_id': target['player_id'],
            'delay_seconds': decision_delay,
            'difficulty': difficulty,
            'reasoning': f"Using Queen peek with {target_strategy} strategy ({use_probability * 100:.1f}% probability)"
        }
    
    def _select_card(self, available_cards: List[str], card_selection: Dict[str, Any], 
                    evaluation_weights: Dict[str, float], game_state: Dict[str, Any]) -> str:
        """Select a card based on strategy and evaluation weights"""
        strategy = card_selection.get('strategy', 'random')
        
        if strategy == 'random':
            return self._random.choice(available_cards)
        elif strategy == 'points_low':
            # TODO: Implement points-based selection
            return self._random.choice(available_cards)
        elif strategy == 'points_high':
            # TODO: Implement points-based selection
            return self._random.choice(available_cards)
        elif strategy == 'special_power':
            # TODO: Implement special power preference
            return self._random.choice(available_cards)
        elif strategy == 'strategic':
            # TODO: Implement complex strategic evaluation
            return self._random.choice(available_cards)
        elif strategy == 'optimal':
            # TODO: Implement optimal selection
            return self._random.choice(available_cards)
        else:
            return self._random.choice(available_cards)
    
    def _select_jack_swap_targets(self, game_state: Dict[str, Any], player_id: str, target_strategy: str) -> Dict[str, str]:
        """Select Jack swap targets based on strategy"""
        # TODO: Implement target selection logic based on strategy
        # For now, return placeholder values
        return {
            'first_card_id': 'placeholder_first_card',
            'first_player_id': player_id,
            'second_card_id': 'placeholder_second_card',
            'second_player_id': 'placeholder_target_player'
        }
    
    def _select_queen_peek_target(self, game_state: Dict[str, Any], player_id: str, target_strategy: str) -> Dict[str, str]:
        """Select Queen peek target based on strategy"""
        # TODO: Implement target selection logic based on strategy
        # For now, return placeholder values
        return {
            'card_id': 'placeholder_target_card',
            'player_id': 'placeholder_target_player'
        }
    
    def get_summary(self) -> Dict[str, Any]:
        """Get configuration summary"""
        return self.config.get_summary()
    
    def validate_config(self) -> Dict[str, Any]:
        """Validate configuration"""
        return self.config.validate_config()
