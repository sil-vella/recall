"""
Knowledge Manager for Computer Players

Manages updates to players' known_cards based on game events and difficulty levels.
Updates are probability-based:
- Easy: 70% memory
- Medium: 80% memory
- Hard: 90% memory
- Expert: 100% memory (perfect memory)
"""

import random
from typing import Dict, Any
from tools.logger.custom_logging import custom_log
from .computer_player_config_loader import ComputerPlayerConfigLoader

LOGGING_SWITCH = True

class KnowledgeManager:
    """Manages updates to players' known_cards based on game events and difficulty"""
    
    def __init__(self, config: ComputerPlayerConfigLoader):
        self.config = config
    
    def update_after_card_play(self, players: Dict[str, Any], played_card_id: str, event_type: str):
        """Update all players' known_cards after a card play event
        
        Args:
            players: Dictionary of all players in the game
            played_card_id: ID of the card that was played
            event_type: Type of event ('play' or 'same_rank_play')
        """
        custom_log(f"KnowledgeManager: Updating knowledge after {event_type} - card: {played_card_id}", level="INFO", isOn=LOGGING_SWITCH)
        
        for player_id, player in players.items():
            # Skip human players
            if player.player_type.value != 'computer':
                continue
            
            difficulty = player.difficulty or 'medium'
            memory_prob = self.config.get_memory_probability(difficulty)
            
            # Probability check
            if random.random() > memory_prob:
                custom_log(f"KnowledgeManager: Player {player.name} forgot the play ({int(memory_prob * 100)}% memory)", level="INFO", isOn=LOGGING_SWITCH)
                continue
            
            # Update player's known_cards
            self._remove_card_from_known_cards(player, played_card_id)
    
    def update_after_jack_swap(self, players: Dict[str, Any], 
                               card1_id: str, card1_old_owner: str, card1_new_owner: str,
                               card2_id: str, card2_old_owner: str, card2_new_owner: str):
        """Update all players' known_cards after a jack swap event
        
        Args:
            players: Dictionary of all players in the game
            card1_id: ID of first card in swap
            card1_old_owner: Original owner of card1
            card1_new_owner: New owner of card1
            card2_id: ID of second card in swap
            card2_old_owner: Original owner of card2
            card2_new_owner: New owner of card2
        """
        custom_log("KnowledgeManager: Updating knowledge after jack swap", level="INFO", isOn=LOGGING_SWITCH)
        custom_log(f"  Card1: {card1_id} ({card1_old_owner} -> {card1_new_owner})", level="INFO", isOn=LOGGING_SWITCH)
        custom_log(f"  Card2: {card2_id} ({card2_old_owner} -> {card2_new_owner})", level="INFO", isOn=LOGGING_SWITCH)
        
        for player_id, player in players.items():
            # Skip human players
            if player.player_type.value != 'computer':
                continue
            
            difficulty = player.difficulty or 'medium'
            memory_prob = self.config.get_memory_probability(difficulty)
            
            # Probability check
            if random.random() > memory_prob:
                custom_log(f"KnowledgeManager: Player {player.name} forgot the swap ({int(memory_prob * 100)}% memory)", level="INFO", isOn=LOGGING_SWITCH)
                continue
            
            # Update ownership for both cards
            self._update_card_ownership(player, card1_id, card1_old_owner, card1_new_owner)
            self._update_card_ownership(player, card2_id, card2_old_owner, card2_new_owner)
    
    def _remove_card_from_known_cards(self, player, card_id: str):
        """Remove a card from player's known_cards
        
        Args:
            player: Player object
            card_id: ID of the card to remove
        """
        card_removed = False
        
        for owner_player_id, owner_cards in player.known_cards.items():
            if not isinstance(owner_cards, dict):
                continue
            
            # Check card1
            card1 = owner_cards.get('card1')
            if card1:
                card1_id = card1.get('cardId') or card1.get('id') if isinstance(card1, dict) else str(card1)
                if card1_id == card_id:
                    owner_cards['card1'] = None
                    card_removed = True
                    custom_log(f"KnowledgeManager: Removed card {card_id} from {player.name} known_cards[{owner_player_id}].card1", level="INFO", isOn=LOGGING_SWITCH)
            
            # Check card2
            card2 = owner_cards.get('card2')
            if card2:
                card2_id = card2.get('cardId') or card2.get('id') if isinstance(card2, dict) else str(card2)
                if card2_id == card_id:
                    owner_cards['card2'] = None
                    card_removed = True
                    custom_log(f"KnowledgeManager: Removed card {card_id} from {player.name} known_cards[{owner_player_id}].card2", level="INFO", isOn=LOGGING_SWITCH)
        
        if not card_removed:
            custom_log(f"KnowledgeManager: Card {card_id} not found in {player.name} known_cards", level="INFO", isOn=LOGGING_SWITCH)
    
    def _update_card_ownership(self, player, card_id: str, old_owner: str, new_owner: str):
        """Update card ownership in player's known_cards after jack swap
        
        Args:
            player: Player object
            card_id: ID of the card to update
            old_owner: Original owner player ID
            new_owner: New owner player ID
        """
        # Check if card exists in old owner's entry
        old_owner_cards = player.known_cards.get(old_owner)
        if not isinstance(old_owner_cards, dict):
            return
        
        card_to_move = None
        card_position = None
        
        # Find card in old owner's cards
        card1 = old_owner_cards.get('card1')
        if card1:
            card1_id = card1.get('cardId') or card1.get('id') if isinstance(card1, dict) else str(card1)
            if card1_id == card_id:
                card_to_move = card1 if isinstance(card1, dict) else None
                card_position = 'card1'
        
        if not card_to_move:
            card2 = old_owner_cards.get('card2')
            if card2:
                card2_id = card2.get('cardId') or card2.get('id') if isinstance(card2, dict) else str(card2)
                if card2_id == card_id:
                    card_to_move = card2 if isinstance(card2, dict) else None
                    card_position = 'card2'
        
        if not card_to_move or not card_position:
            custom_log(f"KnowledgeManager: Card {card_id} not found in {player.name} known_cards[{old_owner}]", level="INFO", isOn=LOGGING_SWITCH)
            return
        
        # Remove from old owner
        old_owner_cards[card_position] = None
        
        # Add to new owner
        if new_owner not in player.known_cards:
            player.known_cards[new_owner] = {'card1': None, 'card2': None}
        
        new_owner_cards = player.known_cards[new_owner]
        
        # Add to first available slot
        if not new_owner_cards.get('card1'):
            new_owner_cards['card1'] = card_to_move
        elif not new_owner_cards.get('card2'):
            new_owner_cards['card2'] = card_to_move
        else:
            # Both slots full, overwrite card2
            new_owner_cards['card2'] = card_to_move
        
        custom_log(f"KnowledgeManager: Moved card {card_id} in {player.name} known_cards from {old_owner} to {new_owner}", level="INFO", isOn=LOGGING_SWITCH)

