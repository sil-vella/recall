"""
YAML Rules Engine - Generic interpreter for YAML-defined decision rules

Provides declarative AI decision making for computer players.
"""

import random
from typing import List, Dict, Any

class YamlRulesEngine:
    """YAML Rules Engine - Generic interpreter for YAML-defined decision rules"""
    
    def __init__(self):
        self._random = random.Random()
    
    def execute_rules(self, rules: List[Dict[str, Any]], game_data: Dict[str, Any], 
                     should_play_optimal: bool) -> str:
        """Execute YAML rules and return selected card ID"""
        # Sort rules by priority
        sorted_rules = sorted(rules, key=lambda r: r.get('priority', 999))
        
        # If not playing optimally, skip to last rule (random fallback)
        if not should_play_optimal and sorted_rules:
            last_rule = sorted_rules[-1]
            return self._execute_action(last_rule.get('action', {}), game_data)
        
        # Evaluate rules in priority order
        for rule in sorted_rules:
            condition = rule.get('condition')
            if condition and self._evaluate_condition(condition, game_data):
                action = rule.get('action')
                if action:
                    return self._execute_action(action, game_data)
        
        # Ultimate fallback: random from playable cards
        playable_cards = game_data.get('playable_cards', [])
        if playable_cards:
            return self._random.choice(playable_cards)
        
        # Last resort: random from available cards
        available_cards = game_data.get('available_cards', [])
        return self._random.choice(available_cards)
    
    def _evaluate_condition(self, condition: Dict[str, Any], game_data: Dict[str, Any]) -> bool:
        """Evaluate a condition from YAML"""
        cond_type = condition.get('type', 'always')
        
        if cond_type == 'always':
            return True
        elif cond_type == 'and':
            conditions = condition.get('conditions', [])
            return all(self._evaluate_condition(c, game_data) for c in conditions)
        elif cond_type == 'or':
            conditions = condition.get('conditions', [])
            return any(self._evaluate_condition(c, game_data) for c in conditions)
        elif cond_type == 'not':
            sub_condition = condition.get('condition')
            return not self._evaluate_condition(sub_condition, game_data) if sub_condition else False
        else:
            return self._evaluate_field_condition(condition, game_data)
    
    def _evaluate_field_condition(self, condition: Dict[str, Any], game_data: Dict[str, Any]) -> bool:
        """Evaluate a field-based condition"""
        field = condition.get('field')
        operator = condition.get('operator', 'equals')
        value = condition.get('value')
        
        if not field:
            return False
        
        field_value = game_data.get(field)
        
        if operator == 'not_empty':
            if isinstance(field_value, (list, dict)):
                return len(field_value) > 0
            return field_value is not None
        elif operator == 'empty':
            if isinstance(field_value, (list, dict)):
                return len(field_value) == 0
            return field_value is None
        elif operator == 'equals':
            return field_value == value
        elif operator == 'not_equals':
            return field_value != value
        elif operator == 'greater_than':
            return isinstance(field_value, (int, float)) and isinstance(value, (int, float)) and field_value > value
        elif operator == 'less_than':
            return isinstance(field_value, (int, float)) and isinstance(value, (int, float)) and field_value < value
        elif operator == 'contains':
            if isinstance(field_value, list):
                return value in field_value
            if isinstance(field_value, str) and isinstance(value, str):
                return value in field_value
            return False
        
        return False
    
    def _execute_action(self, action: Dict[str, Any], game_data: Dict[str, Any]) -> str:
        """Execute an action from YAML"""
        action_type = action.get('type', 'select_random')
        source = action.get('source', 'playable_cards')
        filters = action.get('filters', [])
        
        # Get source data
        source_data = list(game_data.get(source, []))
        
        # Filter out null cards from source data
        source_data = [card for card in source_data if card and str(card) != 'null']
        
        # Apply filters
        for filter_def in filters:
            if isinstance(filter_def, dict):
                source_data = self._apply_filter(source_data, filter_def, game_data)
        
        if not source_data:
            # Fallback to playable_cards
            source_data = list(game_data.get('playable_cards', []))
            source_data = [card for card in source_data if card and str(card) != 'null']
        
        if not source_data:
            # Fallback to available_cards
            source_data = list(game_data.get('available_cards', []))
            source_data = [card for card in source_data if card and str(card) != 'null']
        
        # Execute action type
        if action_type == 'select_random':
            return self._random.choice(source_data)
        elif action_type == 'select_highest_points':
            return self._select_highest_points(source_data, game_data)
        elif action_type == 'select_lowest_points':
            return self._select_lowest_points(source_data, game_data)
        elif action_type == 'select_first':
            return source_data[0]
        elif action_type == 'select_last':
            return source_data[-1]
        else:
            return self._random.choice(source_data)
    
    def _apply_filter(self, data: List[str], filter_def: Dict[str, Any], 
                     game_data: Dict[str, Any]) -> List[str]:
        """Apply a filter to source data"""
        filter_type = filter_def.get('type')
        value = filter_def.get('value')
        
        all_cards = game_data.get('all_cards_data', [])
        card_ids = set(data)
        
        if filter_type == 'exclude_rank':
            filtered = [card.get('id') for card in all_cards 
                       if card.get('id') in card_ids and card.get('rank') != value]
            return filtered
        elif filter_type == 'exclude_suit':
            filtered = [card.get('id') for card in all_cards 
                       if card.get('id') in card_ids and card.get('suit') != value]
            return filtered
        elif filter_type == 'only_rank':
            filtered = [card.get('id') for card in all_cards 
                       if card.get('id') in card_ids and card.get('rank') == value]
            return filtered
        
        return data
    
    def _select_highest_points(self, card_ids: List[str], game_data: Dict[str, Any]) -> str:
        """Select card with highest points"""
        all_cards = game_data.get('all_cards_data', [])
        card_id_set = set(card_ids)
        
        candidate_cards = [card for card in all_cards if card.get('id') in card_id_set]
        
        if not candidate_cards:
            return self._random.choice(card_ids)
        
        highest_card = max(candidate_cards, key=lambda c: c.get('points', 0))
        return highest_card.get('id', self._random.choice(card_ids))
    
    def _select_lowest_points(self, card_ids: List[str], game_data: Dict[str, Any]) -> str:
        """Select card with lowest points"""
        all_cards = game_data.get('all_cards_data', [])
        card_id_set = set(card_ids)
        
        candidate_cards = [card for card in all_cards if card.get('id') in card_id_set]
        
        if not candidate_cards:
            return self._random.choice(card_ids)
        
        lowest_card = min(candidate_cards, key=lambda c: c.get('points', 999))
        return lowest_card.get('id', self._random.choice(card_ids))

