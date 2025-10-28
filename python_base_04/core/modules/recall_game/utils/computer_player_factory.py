"""
Factory for creating computer player behavior based on YAML configuration

Provides declarative AI decision making for computer players in the backend.
"""

import random
import threading
from typing import Dict, Any, List, Optional
from tools.logger.custom_logging import custom_log
from .computer_player_config_loader import ComputerPlayerConfigLoader
from .yaml_rules_engine import YamlRulesEngine

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
        
        # Filter out null cards from available cards
        filtered_cards = [card for card in available_cards if card and str(card) != 'null']
        
        should_play = self._random.random() < play_probability
        
        if not should_play or not filtered_cards:
            return {
                'action': 'same_rank_play',
                'play': False,
                'card_id': None,
                'delay_seconds': decision_delay,
                'difficulty': difficulty,
                'reasoning': f"Decided not to play same rank ({(1 - play_probability) * 100:.1f}% probability)"
            }
        
        # Select a card to play from filtered cards
        selected_card = self._random.choice(filtered_cards)
        
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
        
        # Get current player from game state
        current_player_data = game_state.get('current_player')
        if not current_player_data:
            return self._random.choice(available_cards)
        
        # Prepare game data for YAML rules engine
        game_data = self._prepare_game_data_for_yaml(available_cards, current_player_data, game_state)
        
        # Get YAML rules from config
        play_card_config = self.config.get_event_config('play_card')
        strategy_rules = play_card_config.get('strategy_rules', [])
        
        if not strategy_rules:
            # Fallback to old logic if no YAML rules defined
            return self._select_card_legacy(available_cards, card_selection, evaluation_weights, game_state)
        
        # Determine if we should play optimally
        optimal_play_prob = self._get_optimal_play_probability(strategy)
        should_play_optimal = self._random.random() < optimal_play_prob
        
        # Execute YAML rules
        rules_engine = YamlRulesEngine()
        return rules_engine.execute_rules(strategy_rules, game_data, should_play_optimal)
    
    def _prepare_game_data_for_yaml(self, available_cards: List[str], 
                                    current_player_data: Dict[str, Any], 
                                    game_state: Dict[str, Any]) -> Dict[str, Any]:
        """Prepare game data for YAML rules engine"""
        # Get player's known_cards and collection_rank_cards
        known_cards = current_player_data.get('known_cards', {})
        collection_rank_cards = current_player_data.get('collection_rank_cards', [])
        collection_card_ids = {
            card.get('card_id') or card.get('cardId') or card.get('id') 
            for card in collection_rank_cards 
            if isinstance(card, dict) and (card.get('card_id') or card.get('cardId') or card.get('id'))
        }
        
        # Filter out null cards and collection rank cards from all lists
        available_cards = [card for card in available_cards if card and str(card) != 'null']
        playable_cards = [card_id for card_id in available_cards if card_id not in collection_card_ids]
        
        # Extract known card IDs using card-ID-based structure (player_id -> card_id -> card_data)
        known_card_ids = set()
        player_id = current_player_data.get('player_id') or current_player_data.get('id')
        if player_id and player_id in known_cards:
            player_known_cards = known_cards[player_id]
            if isinstance(player_known_cards, dict):
                # Card-ID-based structure: card_id -> card_data
                for card_id in player_known_cards.keys():
                    if card_id and str(card_id) != 'null':
                        known_card_ids.add(str(card_id))
        
        # Filter out null cards from all lists
        playable_cards = [card for card in playable_cards if card and str(card) != 'null']
        known_card_ids = {card_id for card_id in known_card_ids if card_id and str(card_id) != 'null'}
        
        # Get unknown cards
        unknown_cards = [card_id for card_id in playable_cards if card_id not in known_card_ids]
        
        # Get known playable cards
        known_playable_cards = [card_id for card_id in playable_cards if card_id in known_card_ids]
        
        # Get all cards data for filters
        all_cards_data = []
        players = game_state.get('players', [])
        for player in players:
            hand = player.get('hand', [])
            for card in hand:
                if isinstance(card, dict):
                    all_cards_data.append(card)
        
        # Return comprehensive game data
        return {
            'available_cards': available_cards,
            'playable_cards': playable_cards,
            'unknown_cards': unknown_cards,
            'known_cards': known_playable_cards,
            'collection_cards': list(collection_card_ids),
            'all_cards_data': all_cards_data,
            'current_player': current_player_data,
            'game_state': game_state,
        }
    
    def _select_card_legacy(self, available_cards: List[str], card_selection: Dict[str, Any], 
                           evaluation_weights: Dict[str, float], game_state: Dict[str, Any]) -> str:
        """Legacy card selection (fallback if YAML rules not defined)"""
        strategy = card_selection.get('strategy', 'random')
        
        # Get current player from game state
        current_player_data = game_state.get('current_player')
        if not current_player_data:
            return self._random.choice(available_cards)
        
        # Get player's known_cards and collection_rank_cards
        known_cards = current_player_data.get('known_cards', {})
        collection_rank_cards = current_player_data.get('collection_rank_cards', [])
        collection_card_ids = {
            card.get('card_id') or card.get('cardId') or card.get('id') 
            for card in collection_rank_cards 
            if isinstance(card, dict) and (card.get('card_id') or card.get('cardId') or card.get('id'))
        }
        
        # Filter out collection rank cards
        playable_cards = [card_id for card_id in available_cards if card_id not in collection_card_ids]
        
        if not playable_cards:
            return self._random.choice(available_cards)
        
        # Extract known card IDs
        known_card_ids = set()
        for player_known_cards in known_cards.values():
            if isinstance(player_known_cards, dict):
                if player_known_cards.get('card1'):
                    known_card_ids.add(player_known_cards['card1'])
                if player_known_cards.get('card2'):
                    known_card_ids.add(player_known_cards['card2'])
        
        # Strategy 1: Unknown cards
        unknown_cards = [card_id for card_id in playable_cards if card_id not in known_card_ids]
        
        # Strategy 2: Known cards
        known_playable_cards = [card_id for card_id in playable_cards if card_id in known_card_ids]
        
        # Determine optimal play probability
        optimal_play_prob = self._get_optimal_play_probability(strategy)
        should_play_optimal = self._random.random() < optimal_play_prob
        
        if should_play_optimal:
            # Best option: Random unknown card
            if unknown_cards:
                return self._random.choice(unknown_cards)
            
            # Fallback: Highest points from known cards (exclude Jacks)
            if known_playable_cards:
                return self._select_highest_points_card(known_playable_cards, game_state)
        
        # Random fallback
        return self._random.choice(playable_cards)
    
    def _get_optimal_play_probability(self, difficulty: str) -> float:
        """Get probability of playing optimally based on difficulty"""
        probabilities = {
            'easy': 0.6,
            'medium': 0.8,
            'hard': 0.95,
            'expert': 1.0
        }
        return probabilities.get(difficulty.lower(), 0.8)
    
    def _select_highest_points_card(self, card_ids: List[str], game_state: Dict[str, Any]) -> str:
        """Select card with highest points from given card IDs, excluding Jacks"""
        # Get all cards from game state
        all_cards = []
        
        # Extract cards from players' hands
        players = game_state.get('players', [])
        for player in players:
            hand = player.get('hand', [])
            for card in hand:
                if isinstance(card, dict):
                    all_cards.append(card)
        
        # Filter to candidate cards
        candidate_cards = [card for card in all_cards if card.get('card_id') or card.get('cardId') or card.get('id') in card_ids]
        
        if not candidate_cards:
            return self._random.choice(card_ids)
        
        # Filter out Jacks
        non_jack_cards = [card for card in candidate_cards if card.get('rank') != 'jack']
        
        if not non_jack_cards:
            return self._random.choice(card_ids)
        
        # Find highest points
        highest_card = max(non_jack_cards, key=lambda c: c.get('points', 0))
        
        return highest_card.get('card_id') or highest_card.get('cardId') or highest_card.get('id', self._random.choice(card_ids))
    
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
