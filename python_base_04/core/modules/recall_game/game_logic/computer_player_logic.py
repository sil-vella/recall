"""
Computer Player Logic for AI decision making in Recall game
"""

from typing import Dict, Any, List
from tools.logger.custom_logging import custom_log


class ComputerPlayerLogic:
    """Simple AI logic for computer players"""
    
    def __init__(self, difficulty: str = "medium"):
        self.difficulty = difficulty
        custom_log(f"🤖 ComputerPlayerLogic initialized with difficulty: {difficulty}")
    
    def make_decision(self, game_state: Dict[str, Any], player_data: Dict[str, Any]) -> Dict[str, Any]:
        """Make AI decision based on game state"""
        custom_log(f"🤖 Computer player making decision with difficulty: {self.difficulty}")
        
        # Simple placeholder decision - just play the first card
        return {
            "action": "play_card",
            "card_index": 0,
            "reason": f"AI decision (difficulty: {self.difficulty})",
            "player_id": player_data.get("player_id", "unknown")
        }
