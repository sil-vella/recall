"""
YAML Configuration Parser for Deck Factory

Reads deck configuration from YAML file and provides
structured access to deck composition settings.
"""

import yaml
import time
from typing import Dict, List, Any, Optional
from ..models.card import Card


class DeckConfig:
    """YAML Configuration Parser for Deck Factory"""
    
    def __init__(self, config: Dict[str, Any]):
        self._config = config
    
    @classmethod
    def from_file(cls, file_path: str) -> 'DeckConfig':
        """Load configuration from YAML file"""
        try:
            with open(file_path, 'r', encoding='utf-8') as file:
                yaml_data = yaml.safe_load(file)
                return cls(yaml_data)
        except Exception as e:
            raise Exception(f"Failed to load deck config from {file_path}: {e}")
    
    @classmethod
    def from_string(cls, yaml_string: str) -> 'DeckConfig':
        """Load configuration from YAML string"""
        try:
            yaml_data = yaml.safe_load(yaml_string)
            return cls(yaml_data)
        except Exception as e:
            raise Exception(f"Failed to parse deck config from string: {e}")
    
    @property
    def deck_settings(self) -> Dict[str, Any]:
        """Get deck settings"""
        return self._config.get('deck_settings', {})
    
    @property
    def is_testing_mode(self) -> bool:
        """Check if testing mode is enabled"""
        return self.deck_settings.get('testing_mode', False)
    
    @property
    def include_jokers(self) -> bool:
        """Check if jokers should be included"""
        return self.deck_settings.get('include_jokers', True)
    
    @property
    def standard_deck(self) -> Dict[str, Any]:
        """Get standard deck configuration"""
        return self._config.get('standard_deck', {})
    
    @property
    def testing_deck(self) -> Dict[str, Any]:
        """Get testing deck configuration"""
        return self._config.get('testing_deck', {})
    
    @property
    def current_deck(self) -> Dict[str, Any]:
        """Get current deck configuration (standard or testing)"""
        return self.testing_deck if self.is_testing_mode else self.standard_deck
    
    @property
    def suits(self) -> List[str]:
        """Get suits for current deck"""
        return self.current_deck.get('suits', [])
    
    @property
    def ranks(self) -> Dict[str, Any]:
        """Get ranks configuration for current deck"""
        return self.current_deck.get('ranks', {})
    
    @property
    def jokers(self) -> Dict[str, Any]:
        """Get jokers configuration for current deck"""
        return self.current_deck.get('jokers', {})
    
    @property
    def card_display(self) -> Dict[str, Any]:
        """Get card display configuration"""
        return self._config.get('card_display', {})
    
    @property
    def suit_symbols(self) -> Dict[str, str]:
        """Get suit symbols"""
        symbols = self.card_display.get('suits', {})
        return dict(symbols)
    
    @property
    def rank_symbols(self) -> Dict[str, str]:
        """Get rank symbols"""
        symbols = self.card_display.get('ranks', {})
        return dict(symbols)
    
    @property
    def rank_names(self) -> Dict[str, str]:
        """Get rank names"""
        names = self.card_display.get('names', {})
        return dict(names)
    
    @property
    def special_powers(self) -> Dict[str, Any]:
        """Get special powers configuration"""
        return self._config.get('special_powers', {})
    
    @property
    def deck_stats(self) -> Dict[str, Any]:
        """Get deck statistics"""
        return self._config.get('deck_stats', {})
    
    @property
    def current_deck_stats(self) -> Dict[str, Any]:
        """Get current deck statistics"""
        stats = self.deck_stats
        return stats.get('testing' if self.is_testing_mode else 'standard', {})
    
    def build_cards(self, game_id: str) -> List[Card]:
        """Build cards from configuration"""
        cards = []
        
        # Add cards for each suit and rank
        for suit in self.suits:
            for rank, rank_config in self.ranks.items():
                points = rank_config.get('points', 0)
                special_power = rank_config.get('special_power')
                quantity_per_suit = rank_config.get('quantity_per_suit', 1)
                
                # Add the specified quantity of this rank for this suit
                for i in range(quantity_per_suit):
                    card_id = self._generate_card_id(game_id, rank, suit, i)
                    card = Card(
                        card_id=card_id,
                        rank=rank,
                        suit=suit,
                        points=points,
                        special_power=special_power
                    )
                    cards.append(card)
        
        # Add jokers if enabled
        if self.include_jokers:
            for joker_type, joker_config in self.jokers.items():
                points = joker_config.get('points', 0)
                special_power = joker_config.get('special_power')
                quantity_total = joker_config.get('quantity_total', 0)
                suit = joker_config.get('suit', 'joker')
                
                for i in range(quantity_total):
                    card_id = self._generate_card_id(game_id, joker_type, suit, i)
                    card = Card(
                        card_id=card_id,
                        rank=joker_type,
                        suit=suit,
                        points=points,
                        special_power=special_power
                    )
                    cards.append(card)
        
        return cards
    
    def _generate_card_id(self, game_id: str, rank: str, suit: str, index: int) -> str:
        """Generate unique card ID"""
        timestamp = str(int(time.time() * 1000000))
        random_part = str(abs(hash(f"{game_id}_{rank}_{suit}_{index}_{timestamp}")))
        return f"card_{game_id}_{rank}_{suit}_{index}_{random_part}"
    
    def validate_config(self) -> Dict[str, Any]:
        """Validate deck configuration"""
        errors = []
        warnings = []
        
        # Check if required sections exist
        if 'deck_settings' not in self._config:
            errors.append('Missing deck_settings section')
        
        if 'standard_deck' not in self._config:
            errors.append('Missing standard_deck section')
        
        if 'testing_deck' not in self._config:
            errors.append('Missing testing_deck section')
        
        # Validate current deck configuration
        current_deck = self.current_deck
        if not current_deck:
            errors.append('Current deck configuration is empty')
        else:
            # Check suits
            suits = self.suits
            if not suits:
                errors.append('No suits defined in current deck')
            
            # Check ranks
            ranks = self.ranks
            if not ranks:
                errors.append('No ranks defined in current deck')
            
            # Check jokers if enabled
            if self.include_jokers and not self.jokers:
                warnings.append('Jokers enabled but no joker configuration found')
        
        return {
            'valid': len(errors) == 0,
            'errors': errors,
            'warnings': warnings,
        }
    
    def get_summary(self) -> Dict[str, Any]:
        """Get configuration summary"""
        current_deck = self.current_deck
        stats = self.current_deck_stats
        
        return {
            'testing_mode': self.is_testing_mode,
            'include_jokers': self.include_jokers,
            'suits': self.suits,
            'ranks_count': len(self.ranks),
            'jokers_count': len(self.jokers),
            'expected_total_cards': stats.get('total_cards', 0),
            'special_cards': stats.get('special_cards', 0),
        }
