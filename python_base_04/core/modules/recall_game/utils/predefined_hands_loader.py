"""
Predefined Hands Loader for Testing

This module provides functionality to load predefined hands configuration
for testing purposes in the Recall game.
"""

import os
import yaml
from typing import Dict, List, Any, Optional
from utils.logging_utils import custom_log


class PredefinedHandsLoader:
    """Loader for predefined hands configuration"""
    
    def __init__(self):
        self.config_path = os.path.join(
            os.path.dirname(__file__), 
            '..', 
            'config', 
            'predefined_hands.yaml'
        )
    
    def load_config(self) -> Dict[str, Any]:
        """
        Load the predefined hands configuration from YAML file
        
        Returns:
            Dict containing 'enabled' flag and 'hands' data
        """
        try:
            with open(self.config_path, 'r') as file:
                config = yaml.safe_load(file)
                custom_log(f"Loaded predefined hands config: enabled={config.get('enabled', False)}", 
                          level="INFO", isOn=True)
                return config
        except FileNotFoundError:
            custom_log("Predefined hands config file not found, using default (disabled)", 
                      level="WARNING", isOn=True)
            return {'enabled': False, 'hands': {}}
        except Exception as e:
            custom_log(f"Error loading predefined hands config: {e}", 
                      level="ERROR", isOn=True)
            return {'enabled': False, 'hands': {}}
    
    def get_hand_for_player(self, config: Dict[str, Any], player_index: int) -> Optional[List[Dict[str, str]]]:
        """
        Get predefined hand for a specific player
        
        Args:
            config: Configuration dictionary from load_config()
            player_index: Index of the player (0-based)
            
        Returns:
            List of card specifications or None if no predefined hand
        """
        if not config.get('enabled', False):
            return None
        
        hands = config.get('hands', {})
        if not hands:
            return None
        
        player_key = f"player_{player_index}"
        hand = hands.get(player_key)
        
        if hand is None:
            custom_log(f"No predefined hand found for player {player_index}", 
                      level="DEBUG", isOn=True)
            return None
        
        custom_log(f"Found predefined hand for player {player_index}: {len(hand)} cards", 
                  level="DEBUG", isOn=True)
        return hand
