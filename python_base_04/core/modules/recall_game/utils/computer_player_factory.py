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
        """Get computer player decision for same rank play event with YAML-driven intelligence"""
        decision_delay = self.config.get_decision_delay(difficulty)
        play_probability = self.config.get_same_rank_play_probability(difficulty)
        wrong_rank_probability = self.config.get_wrong_rank_probability(difficulty)
        
        # Check if computer player will attempt to play (miss chance)
        should_attempt = self._random.random() < play_probability
        
        if not should_attempt or not available_cards:
            return {
                'action': 'same_rank_play',
                'play': False,
                'card_id': None,
                'delay_seconds': decision_delay,
                'difficulty': difficulty,
                'reasoning': f"Decided not to play same rank ({(1 - play_probability) * 100:.1f}% miss probability)"
            }
        
        # Check if computer player will play wrong card (accuracy)
        will_play_wrong = self._random.random() < wrong_rank_probability
        
        if will_play_wrong:
            # Get all cards from hand that are NOT the same rank
            current_player_data = game_state.get('current_player')
            if current_player_data:
                hand = current_player_data.get('hand', [])
                # Get last card rank from discard pile
                discard_pile = game_state.get('discard_pile', [])
                if discard_pile:
                    last_card = discard_pile[-1]
                    target_rank = last_card.get('rank') if isinstance(last_card, dict) else None
                    # Get wrong cards (different rank from known_cards)
                    known_cards_list = self._get_known_cards_list(current_player_data)
                    wrong_cards = [c for c in known_cards_list if self._get_card_rank(c, game_state) != target_rank]
                    if wrong_cards:
                        selected_card = self._random.choice(wrong_cards)
                        return {
                            'action': 'same_rank_play',
                            'play': True,
                            'card_id': selected_card,
                            'delay_seconds': decision_delay,
                            'difficulty': difficulty,
                            'reasoning': f"Playing WRONG card (inaccuracy: {wrong_rank_probability * 100:.1f}%)"
                        }
        
        # Play correct card using YAML rules
        card_selection = self.config.get_card_selection_strategy(difficulty)
        evaluation_weights = self.config.get_card_evaluation_weights()
        selected_card = self._select_same_rank_card(available_cards, card_selection, evaluation_weights, game_state)
        
        return {
            'action': 'same_rank_play',
            'play': True,
            'card_id': selected_card,
            'delay_seconds': decision_delay,
            'difficulty': difficulty,
            'reasoning': f"Playing same rank card using YAML strategy ({play_probability * 100:.1f}% play probability)"
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
            card.get('cardId') or card.get('id') 
            for card in collection_rank_cards 
            if isinstance(card, dict) and (card.get('cardId') or card.get('id'))
        }
        
        # Filter out collection rank cards
        playable_cards = [card_id for card_id in available_cards if card_id not in collection_card_ids]
        
        # Extract known card IDs (handles both card objects and card ID strings)
        known_card_ids = set()
        for player_known_cards in known_cards.values():
            if isinstance(player_known_cards, dict):
                card1 = player_known_cards.get('card1')
                card2 = player_known_cards.get('card2')
                
                # Handle card1 (can be dict or string)
                if card1:
                    if isinstance(card1, dict):
                        card_id = card1.get('cardId') or card1.get('id')
                        if card_id:
                            known_card_ids.add(card_id)
                    else:
                        known_card_ids.add(str(card1))
                
                # Handle card2 (can be dict, string, or None)
                if card2:
                    if isinstance(card2, dict):
                        card_id = card2.get('cardId') or card2.get('id')
                        if card_id:
                            known_card_ids.add(card_id)
                    else:
                        known_card_ids.add(str(card2))
        
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
    
    def _select_same_rank_card(self, available_cards: List[str], card_selection: Dict[str, Any],
                               evaluation_weights: Dict[str, float], game_state: Dict[str, Any]) -> str:
        """Select a same rank card using YAML rules engine"""
        # Get current player from game state
        current_player_data = game_state.get('current_player')
        if not current_player_data:
            return self._random.choice(available_cards)
        
        # Prepare game data for YAML rules engine
        game_data = self._prepare_same_rank_game_data(available_cards, current_player_data, game_state)
        
        # Get YAML rules from config
        same_rank_config = self.config.get_event_config('same_rank_play')
        strategy_rules = same_rank_config.get('strategy_rules', [])
        
        if not strategy_rules:
            # Fallback to random if no YAML rules defined
            return self._random.choice(available_cards)
        
        # Determine if we should play optimally
        strategy = card_selection.get('strategy', 'random')
        optimal_play_prob = self._get_optimal_play_probability(strategy)
        should_play_optimal = self._random.random() < optimal_play_prob
        
        # Execute YAML rules
        rules_engine = YamlRulesEngine()
        return rules_engine.execute_rules(strategy_rules, game_data, should_play_optimal)
    
    def _prepare_same_rank_game_data(self, available_cards: List[str],
                                      current_player_data: Dict[str, Any],
                                      game_state: Dict[str, Any]) -> Dict[str, Any]:
        """Prepare game data for same rank play YAML rules"""
        known_cards = current_player_data.get('known_cards', {})
        collection_rank_cards = current_player_data.get('collection_rank_cards', [])
        
        # Extract known card IDs (same as _prepare_game_data_for_yaml)
        known_card_ids = set()
        for player_known_cards in known_cards.values():
            if isinstance(player_known_cards, dict):
                card1 = player_known_cards.get('card1')
                card2 = player_known_cards.get('card2')
                # Handle both card objects and card ID strings
                for card in [card1, card2]:
                    if card:
                        if isinstance(card, dict):
                            known_card_ids.add(card.get('id') or card.get('cardId'))
                        else:
                            known_card_ids.add(str(card))
        
        known_card_ids.discard(None)
        
        # Split available cards into known and unknown
        known_same_rank_cards = [c for c in available_cards if c in known_card_ids]
        unknown_same_rank_cards = [c for c in available_cards if c not in known_card_ids]
        
        # Get all cards data for point calculations
        all_cards_data = []
        players = game_state.get('players', [])
        for player in players:
            hand = player.get('hand', [])
            for card in hand:
                if isinstance(card, dict):
                    all_cards_data.append(card)
        
        return {
            'available_same_rank_cards': available_cards,
            'known_same_rank_cards': known_same_rank_cards,
            'unknown_same_rank_cards': unknown_same_rank_cards,
            'all_cards_data': all_cards_data,
        }
    
    def _get_known_cards_list(self, player_data: Dict[str, Any]) -> List[str]:
        """Get list of known card IDs from player's known_cards"""
        known_card_ids = []
        known_cards = player_data.get('known_cards', {})
        
        for player_known_cards in known_cards.values():
            if isinstance(player_known_cards, dict):
                card1 = player_known_cards.get('card1')
                card2 = player_known_cards.get('card2')
                for card in [card1, card2]:
                    if card:
                        if isinstance(card, dict):
                            card_id = card.get('id') or card.get('cardId')
                            if card_id:
                                known_card_ids.append(card_id)
                        else:
                            known_card_ids.append(str(card))
        
        return known_card_ids
    
    def _get_card_rank(self, card_id: str, game_state: Dict[str, Any]) -> Optional[str]:
        """Get rank of a card by its ID"""
        players = game_state.get('players', [])
        for player in players:
            hand = player.get('hand', [])
            for card in hand:
                if isinstance(card, dict):
                    if (card.get('id') == card_id or card.get('cardId') == card_id):
                        return card.get('rank')
        return None
    
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
            card.get('cardId') or card.get('id') 
            for card in collection_rank_cards 
            if isinstance(card, dict) and (card.get('cardId') or card.get('id'))
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
        candidate_cards = [card for card in all_cards if card.get('id') in card_ids]
        
        if not candidate_cards:
            return self._random.choice(card_ids)
        
        # Filter out Jacks
        non_jack_cards = [card for card in candidate_cards if card.get('rank') != 'jack']
        
        if not non_jack_cards:
            return self._random.choice(card_ids)
        
        # Find highest points
        highest_card = max(non_jack_cards, key=lambda c: c.get('points', 0))
        
        return highest_card.get('id', self._random.choice(card_ids))
    
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
