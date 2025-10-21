"""
YAML Configuration Loader for Computer Player Behavior

Reads computer player configuration from YAML file and provides
structured access to AI behavior settings for the backend.
"""

import yaml
import os
from typing import Dict, Any, Optional
from tools.logger.custom_logging import custom_log

LOGGING_SWITCH = True

class ComputerPlayerConfigLoader:
    """Loads and provides access to computer player YAML configuration"""
    
    def __init__(self, config_data: Dict[str, Any]):
        self._config = config_data
    
    @classmethod
    def from_file(cls, file_path: str) -> 'ComputerPlayerConfigLoader':
        """Load configuration from YAML file"""
        try:
            with open(file_path, 'r', encoding='utf-8') as file:
                config_data = yaml.safe_load(file)
            custom_log(f"Computer player config loaded from {file_path}", level="INFO", isOn=LOGGING_SWITCH)
            return cls(config_data)
        except Exception as e:
            custom_log(f"Failed to load computer player config from {file_path}: {e}", level="ERROR", isOn=LOGGING_SWITCH)
            raise
    
    @classmethod
    def from_string(cls, yaml_string: str) -> 'ComputerPlayerConfigLoader':
        """Load configuration from YAML string"""
        try:
            config_data = yaml.safe_load(yaml_string)
            custom_log("Computer player config loaded from string", level="INFO", isOn=LOGGING_SWITCH)
            return cls(config_data)
        except Exception as e:
            custom_log(f"Failed to parse computer player config from string: {e}", level="ERROR", isOn=LOGGING_SWITCH)
            raise
    
    @property
    def computer_settings(self) -> Dict[str, Any]:
        """Get computer player settings"""
        return self._config.get('computer_settings', {})
    
    @property
    def difficulties(self) -> Dict[str, Any]:
        """Get all difficulty levels"""
        return self._config.get('difficulties', {})
    
    @property
    def events(self) -> Dict[str, Any]:
        """Get all events configuration"""
        return self._config.get('events', {})
    
    @property
    def computer_stats(self) -> Dict[str, Any]:
        """Get computer player statistics"""
        return self._config.get('computer_stats', {})
    
    def get_difficulty_config(self, difficulty: str) -> Dict[str, Any]:
        """Get configuration for a specific difficulty level"""
        difficulties = self.difficulties
        if difficulty in difficulties:
            return difficulties[difficulty]
        custom_log(f"Difficulty '{difficulty}' not found, returning empty config", level="WARNING", isOn=LOGGING_SWITCH)
        return {}
    
    def get_event_config(self, event_name: str) -> Dict[str, Any]:
        """Get event configuration for a specific event"""
        events = self.events
        if event_name in events:
            return events[event_name]
        custom_log(f"Event '{event_name}' not found, returning empty config", level="WARNING", isOn=LOGGING_SWITCH)
        return {}
    
    def get_decision_delay(self, difficulty: str) -> float:
        """Get decision delay for a difficulty level"""
        config = self.get_difficulty_config(difficulty)
        return config.get('decision_delay_seconds', 1.5)
    
    def get_error_rate(self, difficulty: str) -> float:
        """Get error rate for a difficulty level"""
        config = self.get_difficulty_config(difficulty)
        return config.get('error_rate', 0.05)
    
    def get_card_selection_strategy(self, difficulty: str) -> Dict[str, Any]:
        """Get card selection strategy for a difficulty level"""
        config = self.get_difficulty_config(difficulty)
        return config.get('card_selection', {})
    
    def get_recall_strategy(self, difficulty: str) -> Dict[str, Any]:
        """Get recall strategy for a difficulty level"""
        config = self.get_difficulty_config(difficulty)
        return config.get('recall_strategy', {})
    
    def get_special_card_config(self, difficulty: str, card_type: str) -> Dict[str, Any]:
        """Get special card configuration for a difficulty level"""
        config = self.get_difficulty_config(difficulty)
        special_cards = config.get('special_cards', {})
        return special_cards.get(card_type, {})
    
    def get_draw_from_discard_probability(self, difficulty: str) -> float:
        """Get draw from discard probability for a difficulty level"""
        draw_card_config = self.get_event_config('draw_card')
        probabilities = draw_card_config.get('draw_from_discard_probability', {})
        return probabilities.get(difficulty, 0.5)
    
    def get_same_rank_play_probability(self, difficulty: str) -> float:
        """Get same rank play probability for a difficulty level"""
        same_rank_config = self.get_event_config('same_rank_play')
        probabilities = same_rank_config.get('play_probability', {})
        return probabilities.get(difficulty, 0.8)
    
    def get_card_evaluation_weights(self) -> Dict[str, float]:
        """Get card evaluation weights for play_card event"""
        play_card_config = self.get_event_config('play_card')
        weights = play_card_config.get('card_evaluation_weights', {})
        return {k: float(v) for k, v in weights.items()}
    
    def get_jack_swap_targets(self) -> Dict[str, Any]:
        """Get Jack swap target strategy"""
        jack_swap_config = self.get_event_config('jack_swap')
        return jack_swap_config.get('swap_targets', {})
    
    def get_queen_peek_targets(self) -> Dict[str, Any]:
        """Get Queen peek target strategy"""
        queen_peek_config = self.get_event_config('queen_peek')
        return queen_peek_config.get('peek_targets', {})
    
    def get_memory_probability(self, difficulty: str) -> float:
        """Get memory probability for difficulty level"""
        difficulty_config = self.get_difficulty_config(difficulty)
        return difficulty_config.get('memory_probability', 0.8)
    
    def get_summary(self) -> Dict[str, Any]:
        """Get configuration summary"""
        return {
            'total_difficulties': len(self.difficulties),
            'supported_events': len(self.events),
            'config_version': self.computer_stats.get('config_version', '1.0'),
            'default_difficulty': self.computer_settings.get('default_difficulty', 'medium'),
            'decision_delay': self.computer_settings.get('decision_delay_seconds', 1.0),
            'error_rate': self.computer_settings.get('error_rate', 0.05),
        }
    
    def validate_config(self) -> Dict[str, Any]:
        """Validate configuration"""
        errors = []
        warnings = []
        
        # Check required sections
        if not self.difficulties:
            errors.append('No difficulty levels defined')
        
        if not self.events:
            errors.append('No events configuration defined')
        
        # Check difficulty levels
        for difficulty in self.difficulties.keys():
            config = self.get_difficulty_config(difficulty)
            if not config:
                errors.append(f'Empty configuration for difficulty: {difficulty}')
                continue
            
            # Check required fields
            if 'decision_delay_seconds' not in config:
                warnings.append(f'Missing decision_delay_seconds for difficulty: {difficulty}')
            
            if 'error_rate' not in config:
                warnings.append(f'Missing error_rate for difficulty: {difficulty}')
            
            if 'card_selection' not in config:
                warnings.append(f'Missing card_selection for difficulty: {difficulty}')
        
        return {
            'valid': len(errors) == 0,
            'errors': errors,
            'warnings': warnings,
            'difficulty_count': len(self.difficulties),
            'event_count': len(self.events),
        }
