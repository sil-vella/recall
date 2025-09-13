//! Game round management for the Recall card game

use crate::models::{Card, Player, PlayerStatus, CardRank, CardSuit};
use crate::game_state::{GameState, GamePhase};
use serde_json;
use std::collections::HashMap;
use std::time::{SystemTime, UNIX_EPOCH};

/// Manages a single round of gameplay in the Recall game
pub struct GameRound {
    pub game_state: GameState,
    pub round_number: u32,
    pub round_start_time: Option<u64>,
    pub round_end_time: Option<u64>,
    pub current_turn_start_time: Option<u64>,
    pub turn_timeout_seconds: u32,
    pub actions_performed: Vec<serde_json::Value>,
    
    // Same rank window data
    pub same_rank_data: HashMap<String, serde_json::Value>,
    pub special_card_data: Vec<serde_json::Value>,
    pub same_rank_timer: Option<u64>, // Timer ID for same rank window
    pub special_card_timer: Option<u64>, // Timer ID for special card window
    pub special_card_players: Vec<serde_json::Value>,
    
    // Pending events
    pub pending_events: Vec<serde_json::Value>,
    
    // Round status
    pub round_status: String, // waiting, active, paused, completed
    
    // Timed rounds configuration
    pub timed_rounds_enabled: bool,
    pub round_time_limit_seconds: u32,
    pub round_time_remaining: Option<u32>,
    
    // WebSocket manager reference for sending events
    pub websocket_manager: Option<String>, // Placeholder for WebSocket manager reference
}

impl GameRound {
    /// Create a new game round
    pub fn new(game_state: GameState) -> Self {
        Self {
            game_state,
            round_number: 1,
            round_start_time: None,
            round_end_time: None,
            current_turn_start_time: None,
            turn_timeout_seconds: 30, // 30 seconds per turn
            actions_performed: Vec::new(),
            
            same_rank_data: HashMap::new(),
            special_card_data: Vec::new(),
            same_rank_timer: None,
            special_card_timer: None,
            special_card_players: Vec::new(),
            
            pending_events: Vec::new(),
            round_status: "waiting".to_string(),
            
            timed_rounds_enabled: false,
            round_time_limit_seconds: 300, // 5 minutes default
            round_time_remaining: None,
            
            websocket_manager: None,
        }
    }

    /// Start a new round of gameplay
    pub fn start_turn(&mut self) -> serde_json::Value {
        match self._start_turn_internal() {
            Ok(result) => result,
            Err(error) => serde_json::json!({
                "error": format!("Failed to start round: {}", error)
            })
        }
    }

    fn _start_turn_internal(&mut self) -> Result<serde_json::Value, String> {
        // Clear same rank data
        self.same_rank_data.clear();
        
        // Only clear special card data if we're not in the middle of processing special cards
        if !self.special_card_data.is_empty() && self.game_state.phase != GamePhase::SpecialPlayWindow {
            self.special_card_data.clear();
        }
        
        // Initialize round state
        self.round_start_time = Some(
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_secs()
        );
        self.current_turn_start_time = self.round_start_time;
        self.round_status = "active".to_string();
        self.actions_performed.clear();

        self.game_state.phase = GamePhase::PlayerTurn;
        
        // Set current player status to drawing_card (they need to draw a card)
        if let Some(current_player_id) = &self.game_state.current_player_id {
            if let Some(player) = self.game_state.players.get_mut(current_player_id) {
                player.set_status(PlayerStatus::DrawingCard);
            }
        }
        
        // Initialize timed rounds if enabled
        if self.timed_rounds_enabled {
            self.round_time_remaining = Some(self.round_time_limit_seconds);
        }
        
        // Log round start
        self._log_action("round_started", serde_json::json!({
            "round_number": self.round_number,
            "current_player": self.game_state.current_player_id,
            "player_count": self.game_state.players.len()
        }));
        
        // Update turn start time
        self.current_turn_start_time = Some(
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_secs()
        );
        
        // Send game state update to all players
        self._send_game_state_update();
        
        // Send turn started event to current player
        self._send_turn_started_event();
        
        Ok(serde_json::json!({
            "success": true,
            "round_number": self.round_number,
            "round_start_time": self.round_start_time.map(|t| {
                chrono::NaiveDateTime::from_timestamp_opt(t as i64, 0)
                    .unwrap()
                    .to_string()
            }),
            "current_player": self.game_state.current_player_id,
            "game_phase": self.game_state.phase.to_string(),
            "player_count": self.game_state.players.len()
        }))
    }

    /// Complete the current round after a player action
    pub fn continue_turn(&mut self) -> bool {
        match self._continue_turn_internal() {
            Ok(result) => result,
            Err(_) => false,
        }
    }

    fn _continue_turn_internal(&mut self) -> Result<bool, String> {
        // Send game state update
        self._send_game_state_update();

        if self.game_state.phase == GamePhase::TurnPendingEvents {
            self._check_pending_events_before_ending_round();
        }
        
        if self.game_state.phase == GamePhase::EndingRound {
            self._move_to_next_player();
        }
        
        Ok(true)
    }

    fn _check_pending_events_before_ending_round(&mut self) {
        if self.pending_events.is_empty() {
            self.game_state.phase = GamePhase::EndingRound;
            return;
        }
        
        // Process each pending event
        let events = std::mem::take(&mut self.pending_events);
        for event in events {
            let event_type = event.get("type").and_then(|v| v.as_str()).unwrap_or("");
            let event_data = event.get("data").cloned().unwrap_or(serde_json::Value::Null);
            let player_id = event.get("player_id").and_then(|v| v.as_str()).unwrap_or("");
            
            // Handle different event types
            match event_type {
                "queen_peek_pause" => {
                    self._handle_queen_peek_pause(event_data, player_id);
                }
                _ => {
                    // Unknown event type
                }
            }
        }
        
        self.continue_turn();
    }

    fn _handle_queen_peek_pause(&mut self, _event_data: serde_json::Value, _player_id: &str) {
        // Handle queen peek pause - this would typically involve a timer
        // For now, just continue
    }

    fn _move_to_next_player(&mut self) {
        if self.game_state.players.is_empty() {
            return;
        }
        
        // Get list of active player IDs
        let active_player_ids: Vec<String> = self.game_state.players
            .iter()
            .filter(|(_, player)| player.is_active())
            .map(|(id, _)| id.clone())
            .collect();
        
        if active_player_ids.is_empty() {
            return;
        }
        
        // Set current player status to ready before moving to next player
        if let Some(current_player_id) = &self.game_state.current_player_id {
            if let Some(player) = self.game_state.players.get_mut(current_player_id) {
                player.set_status(PlayerStatus::Ready);
            }
        }
        
        // Find current player index
        let current_index = if let Some(current_player_id) = &self.game_state.current_player_id {
            active_player_ids.iter().position(|id| id == current_player_id).unwrap_or(0)
        } else {
            0
        };
        
        // Move to next player (or first if at end)
        let next_index = (current_index + 1) % active_player_ids.len();
        let next_player_id = active_player_ids[next_index].clone();
        
        // Update current player
        self.game_state.current_player_id = Some(next_player_id);
        
        // Check if recall has been called
        if let Some(recall_called_by) = &self.game_state.recall_called_by {
            if self.game_state.current_player_id.as_ref() == Some(recall_called_by) {
                self._handle_end_of_match();
                return;
            }
        }
        
        // Send turn started event to new player
        self.start_turn();
    }

    fn _log_action(&mut self, action_type: &str, action_data: serde_json::Value) {
        let log_entry = serde_json::json!({
            "timestamp": chrono::Utc::now().to_rfc3339(),
            "action_type": action_type,
            "round_number": self.round_number,
            "data": action_data
        });
        self.actions_performed.push(log_entry);
        
        // Keep only last 100 actions to prevent memory bloat
        if self.actions_performed.len() > 100 {
            self.actions_performed = self.actions_performed.clone().into_iter().rev().take(100).rev().collect();
        }
    }

    fn _send_turn_started_event(&self) {
        // This would send a WebSocket event to the current player
        // For now, this is a placeholder
    }

    pub fn _send_game_state_update(&self) {
        // This would send a game state update to all players
        // For now, this is a placeholder
    }

    pub fn _handle_end_of_match(&mut self) {
        // Collect all player data for scoring
        let mut player_results = HashMap::new();
        
        for (player_id, player) in &self.game_state.players {
            if !player.is_active() {
                continue;
            }
            
            // Get hand cards (filter out None values for consistency)
            let hand_cards: Vec<&Card> = player.hand.iter().filter_map(|card| card.as_ref()).collect();
            let card_count = hand_cards.len();
            
            // Calculate total points
            let total_points: u32 = hand_cards.iter().map(|card| card.get_point_value()).sum();
            
            // Store player data
            player_results.insert(player_id.clone(), serde_json::json!({
                "player_id": player_id,
                "player_name": player.name,
                "hand_cards": hand_cards.iter().map(|card| card.to_dict()).collect::<Vec<_>>(),
                "card_count": card_count,
                "total_points": total_points
            }));
        }
        
        // Determine winner based on Recall game rules
        let winner_data = self._determine_winner(&player_results);
        
        // Set game phase to GAME_ENDED
        self.game_state.phase = GamePhase::GameEnded;
        
        // Set winner status and log results
        if winner_data.get("is_tie").and_then(|v| v.as_bool()).unwrap_or(false) {
            if let Some(winners) = winner_data.get("winners").and_then(|v| v.as_array()) {
                for winner_name in winners {
                    if let Some(winner_name_str) = winner_name.as_str() {
                        for (player_id, player) in &mut self.game_state.players {
                            if player.name == winner_name_str {
                                player.set_status(PlayerStatus::Finished);
                            }
                        }
                    }
                }
            }
        } else {
            if let Some(winner_id) = winner_data.get("winner_id").and_then(|v| v.as_str()) {
                if let Some(player) = self.game_state.players.get_mut(winner_id) {
                    player.set_status(PlayerStatus::Winner);
                }
                
                // Set all other players to FINISHED status
                for (player_id, player) in &mut self.game_state.players {
                    if player_id != winner_id {
                        player.set_status(PlayerStatus::Finished);
                    }
                }
            }
        }
    }

    fn _determine_winner(&self, player_results: &HashMap<String, serde_json::Value>) -> serde_json::Value {
        // Rule 1: Check for player with 0 cards (automatic win)
        for (player_id, data) in player_results {
            if data.get("card_count").and_then(|v| v.as_u64()).unwrap_or(0) == 0 {
                return serde_json::json!({
                    "is_tie": false,
                    "winner_id": player_id,
                    "winner_name": data.get("player_name").and_then(|v| v.as_str()).unwrap_or(""),
                    "win_reason": "no_cards",
                    "winners": []
                });
            }
        }
        
        // Rule 2: Find player(s) with lowest points
        let min_points = player_results.values()
            .map(|data| data.get("total_points").and_then(|v| v.as_u64()).unwrap_or(0))
            .min()
            .unwrap_or(0);
        
        let lowest_point_players: Vec<_> = player_results.iter()
            .filter(|(_, data)| data.get("total_points").and_then(|v| v.as_u64()).unwrap_or(0) == min_points)
            .collect();
        
        // Rule 3: If only one player with lowest points, they win
        if lowest_point_players.len() == 1 {
            let (winner_id, winner_data) = lowest_point_players[0];
            return serde_json::json!({
                "is_tie": false,
                "winner_id": winner_id,
                "winner_name": winner_data.get("player_name").and_then(|v| v.as_str()).unwrap_or(""),
                "win_reason": "lowest_points",
                "winners": []
            });
        }
        
        // Rule 4: Multiple players with lowest points - check for recall caller
        if let Some(recall_caller_id) = &self.game_state.recall_called_by {
            for (player_id, data) in &lowest_point_players {
                if **player_id == *recall_caller_id {
                    return serde_json::json!({
                        "is_tie": false,
                        "winner_id": player_id,
                        "winner_name": data.get("player_name").and_then(|v| v.as_str()).unwrap_or(""),
                        "win_reason": "recall_caller_lowest_points",
                        "winners": []
                    });
                }
            }
        }
        
        // Rule 5: Multiple players with lowest points, none are recall callers - TIE
        let winner_names: Vec<String> = lowest_point_players.iter()
            .filter_map(|(_, data)| data.get("player_name").and_then(|v| v.as_str()).map(|s| s.to_string()))
            .collect();
        
        serde_json::json!({
            "is_tie": true,
            "winner_id": serde_json::Value::Null,
            "winner_name": serde_json::Value::Null,
            "win_reason": "tie_lowest_points",
            "winners": winner_names
        })
    }
}
