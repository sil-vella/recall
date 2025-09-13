//! Game state management for the Recall card game

use crate::models::{Card, Player, PlayerStatus, PlayerType, CardRank, CardSuit};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::time::{SystemTime, UNIX_EPOCH};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum GamePhase {
    WaitingForPlayers,
    DealingCards,
    PlayerTurn,
    SameRankWindow,
    SpecialPlayWindow,
    QueenPeekWindow,
    TurnPendingEvents,
    EndingRound,
    EndingTurn,
    RecallCalled,
    GameEnded,
}

impl GamePhase {
    pub fn to_string(&self) -> String {
        match self {
            GamePhase::WaitingForPlayers => "waiting_for_players".to_string(),
            GamePhase::DealingCards => "dealing_cards".to_string(),
            GamePhase::PlayerTurn => "player_turn".to_string(),
            GamePhase::SameRankWindow => "same_rank_window".to_string(),
            GamePhase::SpecialPlayWindow => "special_play_window".to_string(),
            GamePhase::QueenPeekWindow => "queen_peek_window".to_string(),
            GamePhase::TurnPendingEvents => "turn_pending_events".to_string(),
            GamePhase::EndingRound => "ending_round".to_string(),
            GamePhase::EndingTurn => "ending_turn".to_string(),
            GamePhase::RecallCalled => "recall_called".to_string(),
            GamePhase::GameEnded => "game_ended".to_string(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameState {
    pub game_id: String,
    pub max_players: u32,
    pub min_players: u32,
    pub permission: String,
    pub players: HashMap<String, Player>,
    pub current_player_id: Option<String>,
    pub phase: GamePhase,
    pub discard_pile: Vec<Card>,
    pub draw_pile: Vec<Card>,
    pub pending_draws: HashMap<String, Card>,
    pub out_of_turn_deadline: Option<u64>,
    pub out_of_turn_timeout_seconds: u32,
    pub last_played_card: Option<Card>,
    pub recall_called_by: Option<String>,
    pub game_start_time: Option<u64>,
    pub last_action_time: Option<u64>,
    pub game_ended: bool,
    pub winner: Option<String>,
    pub game_history: Vec<serde_json::Value>,
    
    // Session tracking for individual player messaging
    pub player_sessions: HashMap<String, String>, // player_id -> session_id
    pub session_players: HashMap<String, String>, // session_id -> player_id
    
    // Auto-change detection for state updates
    pub change_tracking_enabled: bool,
    pub pending_changes: std::collections::HashSet<String>,
    pub initialized: bool,
    pub previous_phase: Option<GamePhase>,
}

impl GameState {
    pub fn new(game_id: String, max_players: u32, min_players: u32, permission: String) -> Self {
        Self {
            game_id,
            max_players,
            min_players,
            permission,
            players: HashMap::new(),
            current_player_id: None,
            phase: GamePhase::WaitingForPlayers,
            discard_pile: Vec::new(),
            draw_pile: Vec::new(),
            pending_draws: HashMap::new(),
            out_of_turn_deadline: None,
            out_of_turn_timeout_seconds: 5,
            last_played_card: None,
            recall_called_by: None,
            game_start_time: None,
            last_action_time: None,
            game_ended: false,
            winner: None,
            game_history: Vec::new(),
            player_sessions: HashMap::new(),
            session_players: HashMap::new(),
            change_tracking_enabled: true,
            pending_changes: std::collections::HashSet::new(),
            initialized: true,
            previous_phase: None,
        }
    }

    pub fn add_player(&mut self, player: Player, session_id: Option<String>) -> bool {
        if self.players.len() >= self.max_players as usize {
            return false;
        }
        
        self.players.insert(player.player_id.clone(), player);
        
        // Track session mapping if session_id provided
        if let Some(session_id) = session_id {
            self.player_sessions.insert(self.players.keys().last().unwrap().clone(), session_id.clone());
            self.session_players.insert(session_id, self.players.keys().last().unwrap().clone());
        }
        
        true
    }

    pub fn remove_player(&mut self, player_id: &str) -> bool {
        if let Some(_) = self.players.remove(player_id) {
            // Remove session mapping
            if let Some(session_id) = self.player_sessions.remove(player_id) {
                self.session_players.remove(&session_id);
            }
            true
        } else {
            false
        }
    }

    pub fn get_player_session(&self, player_id: &str) -> Option<&String> {
        self.player_sessions.get(player_id)
    }

    pub fn get_session_player(&self, session_id: &str) -> Option<&String> {
        self.session_players.get(session_id)
    }

    pub fn update_player_session(&mut self, player_id: &str, session_id: &str) -> bool {
        if !self.players.contains_key(player_id) {
            return false;
        }
        
        // Remove old mapping if exists
        if let Some(old_session_id) = self.player_sessions.remove(player_id) {
            self.session_players.remove(&old_session_id);
        }
        
        // Add new mapping
        self.player_sessions.insert(player_id.to_string(), session_id.to_string());
        self.session_players.insert(session_id.to_string(), player_id.to_string());
        true
    }

    pub fn remove_session(&mut self, session_id: &str) -> Option<String> {
        if let Some(player_id) = self.session_players.remove(session_id) {
            self.player_sessions.remove(&player_id);
            Some(player_id)
        } else {
            None
        }
    }

    // ========= DISCARD PILE MANAGEMENT METHODS =========
    
    pub fn add_to_discard_pile(&mut self, card: Card) -> bool {
        self.discard_pile.push(card);
        self._track_change("discard_pile".to_string());
        self._send_changes_if_needed();
        true
    }

    pub fn remove_from_discard_pile(&mut self, card_id: &str) -> Option<Card> {
        for (i, card) in self.discard_pile.iter().enumerate() {
            if card.card_id == card_id {
                let removed_card = self.discard_pile.remove(i);
                self._track_change("discard_pile".to_string());
                self._send_changes_if_needed();
                return Some(removed_card);
            }
        }
        None
    }

    pub fn get_top_discard_card(&self) -> Option<&Card> {
        self.discard_pile.last()
    }

    pub fn clear_discard_pile(&mut self) -> Vec<Card> {
        let cleared_cards = self.discard_pile.clone();
        self.discard_pile.clear();
        self._track_change("discard_pile".to_string());
        self._send_changes_if_needed();
        cleared_cards
    }

    // ========= DRAW PILE MANAGEMENT METHODS =========
    
    pub fn draw_from_draw_pile(&mut self) -> Option<Card> {
        if self.draw_pile.is_empty() {
            return None;
        }
        
        let drawn_card = self.draw_pile.pop().unwrap();
        self._track_change("draw_pile".to_string());
        self._send_changes_if_needed();
        Some(drawn_card)
    }

    pub fn draw_from_discard_pile(&mut self) -> Option<Card> {
        if self.discard_pile.is_empty() {
            return None;
        }
        
        let drawn_card = self.discard_pile.pop().unwrap();
        self._track_change("discard_pile".to_string());
        self._send_changes_if_needed();
        Some(drawn_card)
    }

    pub fn add_to_draw_pile(&mut self, card: Card) -> bool {
        self.draw_pile.push(card);
        self._track_change("draw_pile".to_string());
        self._send_changes_if_needed();
        true
    }

    pub fn get_draw_pile_count(&self) -> usize {
        self.draw_pile.len()
    }

    pub fn get_discard_pile_count(&self) -> usize {
        self.discard_pile.len()
    }

    pub fn is_draw_pile_empty(&self) -> bool {
        self.draw_pile.is_empty()
    }

    pub fn is_discard_pile_empty(&self) -> bool {
        self.discard_pile.is_empty()
    }

    // ========= PLAYER STATUS MANAGEMENT METHODS =========
    
    pub fn update_all_players_status(&mut self, status: PlayerStatus, filter_active: bool) -> u32 {
        let mut updated_count = 0;
        
        for player in self.players.values_mut() {
            if !filter_active || player.is_active() {
                player.set_status(status.clone());
                updated_count += 1;
            }
        }
        
        updated_count
    }

    pub fn update_players_status_by_ids(&mut self, player_ids: &[String], status: PlayerStatus) -> u32 {
        let mut updated_count = 0;
        
        for player_id in player_ids {
            if let Some(player) = self.players.get_mut(player_id) {
                player.set_status(status.clone());
                updated_count += 1;
            }
        }
        
        updated_count
    }

    pub fn clear_same_rank_data(&mut self) {
        // This would clear same_rank_data if it existed
        // For now, just track the change
        self._track_change("same_rank_data".to_string());
        self._send_changes_if_needed();
    }

    pub fn get_current_player(&self) -> Option<&Player> {
        if let Some(current_player_id) = &self.current_player_id {
            self.players.get(current_player_id)
        } else {
            None
        }
    }

    pub fn get_card_by_id(&self, card_id: &str) -> Option<&Card> {
        // Search in all player hands
        for player in self.players.values() {
            for card in &player.hand {
                if let Some(card) = card {
                    if card.card_id == card_id {
                        return Some(card);
                    }
                }
            }
        }
        
        // Search in draw pile
        for card in &self.draw_pile {
            if card.card_id == card_id {
                return Some(card);
            }
        }
        
        // Search in discard pile
        for card in &self.discard_pile {
            if card.card_id == card_id {
                return Some(card);
            }
        }
        
        // Search in pending draws
        for card in self.pending_draws.values() {
            if card.card_id == card_id {
                return Some(card);
            }
        }
        
        None
    }

    pub fn find_card_location(&self, card_id: &str) -> Option<serde_json::Value> {
        // Search in all player hands
        for (player_id, player) in &self.players {
            for (index, card) in player.hand.iter().enumerate() {
                if let Some(card) = card {
                    if card.card_id == card_id {
                        return Some(serde_json::json!({
                            "card": card.to_dict(),
                            "location_type": "player_hand",
                            "player_id": player_id,
                            "index": index
                        }));
                    }
                }
            }
        }
        
        // Search in draw pile
        for (index, card) in self.draw_pile.iter().enumerate() {
            if card.card_id == card_id {
                return Some(serde_json::json!({
                    "card": card.to_dict(),
                    "location_type": "draw_pile",
                    "player_id": serde_json::Value::Null,
                    "index": index
                }));
            }
        }
        
        // Search in discard pile
        for (index, card) in self.discard_pile.iter().enumerate() {
            if card.card_id == card_id {
                return Some(serde_json::json!({
                    "card": card.to_dict(),
                    "location_type": "discard_pile",
                    "player_id": serde_json::Value::Null,
                    "index": index
                }));
            }
        }
        
        // Search in pending draws
        for (player_id, card) in &self.pending_draws {
            if card.card_id == card_id {
                return Some(serde_json::json!({
                    "card": card.to_dict(),
                    "location_type": "pending_draw",
                    "player_id": player_id,
                    "index": serde_json::Value::Null
                }));
            }
        }
        
        None
    }

    // ========= AUTO-CHANGE DETECTION METHODS =========
    
    fn _track_change(&mut self, property_name: String) {
        if self.change_tracking_enabled {
            self.pending_changes.insert(property_name.clone());
            
            // Detect specific phase transitions
            if property_name == "phase" {
                self._detect_phase_transitions();
            }
        }
    }

    fn _detect_phase_transitions(&self) {
        // Check for SPECIAL_PLAY_WINDOW to ENDING_ROUND transition
        if (self.phase == GamePhase::EndingRound && 
            self.previous_phase == Some(GamePhase::SpecialPlayWindow)) {
            // Log phase transition
        }
    }

    fn _send_changes_if_needed(&mut self) {
        if !self.change_tracking_enabled || self.pending_changes.is_empty() {
            return;
        }
        
        // This would send changes to the coordinator
        // For now, just clear pending changes
        self.pending_changes.clear();
    }

    pub fn enable_change_tracking(&mut self) {
        self.change_tracking_enabled = true;
    }

    pub fn disable_change_tracking(&mut self) {
        self.change_tracking_enabled = false;
    }

    pub fn to_dict(&self) -> serde_json::Value {
        serde_json::json!({
            "game_id": self.game_id,
            "max_players": self.max_players,
            "players": self.players.iter().map(|(pid, player)| (pid, player.to_dict())).collect::<HashMap<_, _>>(),
            "current_player_id": self.current_player_id,
            "phase": self.phase.to_string(),
            "discard_pile": self.discard_pile.iter().map(|card| card.to_dict()).collect::<Vec<_>>(),
            "draw_pile_count": self.draw_pile.len(),
            "last_played_card": self.last_played_card.as_ref().map(|card| card.to_dict()),
            "recall_called_by": self.recall_called_by,
            "game_start_time": self.game_start_time,
            "last_action_time": self.last_action_time,
            "game_ended": self.game_ended,
            "winner": self.winner,
            "player_sessions": self.player_sessions,
            "session_players": self.session_players
        })
    }

    pub fn from_dict(data: serde_json::Value) -> Self {
        let mut game_state = Self::new(
            data["game_id"].as_str().unwrap_or("").to_string(),
            data["max_players"].as_u64().unwrap_or(4) as u32,
            data["min_players"].as_u64().unwrap_or(2) as u32,
            data["permission"].as_str().unwrap_or("public").to_string(),
        );
        
        // Restore players
        if let Some(players_data) = data["players"].as_object() {
            for (player_id, player_data) in players_data {
                let player = Player::from_dict(player_data.clone());
                game_state.players.insert(player_id.clone(), player);
            }
        }
        
        game_state.current_player_id = data["current_player_id"].as_str().map(|s| s.to_string());
        game_state.phase = match data["phase"].as_str().unwrap_or("waiting_for_players") {
            "waiting_for_players" => GamePhase::WaitingForPlayers,
            "dealing_cards" => GamePhase::DealingCards,
            "player_turn" => GamePhase::PlayerTurn,
            "same_rank_window" => GamePhase::SameRankWindow,
            "special_play_window" => GamePhase::SpecialPlayWindow,
            "queen_peek_window" => GamePhase::QueenPeekWindow,
            "turn_pending_events" => GamePhase::TurnPendingEvents,
            "ending_round" => GamePhase::EndingRound,
            "ending_turn" => GamePhase::EndingTurn,
            "recall_called" => GamePhase::RecallCalled,
            "game_ended" => GamePhase::GameEnded,
            _ => GamePhase::WaitingForPlayers,
        };
        game_state.recall_called_by = data["recall_called_by"].as_str().map(|s| s.to_string());
        game_state.game_start_time = data["game_start_time"].as_u64();
        game_state.last_action_time = data["last_action_time"].as_u64();
        game_state.game_ended = data["game_ended"].as_bool().unwrap_or(false);
        game_state.winner = data["winner"].as_str().map(|s| s.to_string());
        
        // Restore session tracking data
        if let Some(sessions) = data["player_sessions"].as_object() {
            for (k, v) in sessions {
                game_state.player_sessions.insert(k.clone(), v.as_str().unwrap_or("").to_string());
            }
        }
        if let Some(sessions) = data["session_players"].as_object() {
            for (k, v) in sessions {
                game_state.session_players.insert(k.clone(), v.as_str().unwrap_or("").to_string());
            }
        }
        
        // Restore cards
        if let Some(cards_data) = data["discard_pile"].as_array() {
            for card_data in cards_data {
                let card = Card::from_dict(card_data.clone());
                game_state.discard_pile.push(card);
            }
        }
        
        if let Some(card_data) = data["last_played_card"].as_object() {
            game_state.last_played_card = Some(Card::from_dict(serde_json::Value::Object(card_data.clone())));
        }
        
        game_state
    }
}

// ========= GAME STATE MANAGER =========

#[derive(Debug)]
pub struct GameStateManager {
    pub active_games: HashMap<String, GameState>,
    pub initialized: bool,
}

impl GameStateManager {
    pub fn new() -> Self {
        Self {
            active_games: HashMap::new(),
            initialized: false,
        }
    }

    pub fn initialize(&mut self) -> bool {
        self.initialized = true;
        true
    }

    pub fn create_game(&mut self, max_players: u32, min_players: u32, permission: String) -> String {
        let game_id = Uuid::new_v4().to_string();
        let game_state = GameState::new(game_id.clone(), max_players, min_players, permission);
        self.active_games.insert(game_id.clone(), game_state);
        game_id
    }

    pub fn create_game_with_id(&mut self, game_id: String, max_players: u32, min_players: u32, permission: String) -> String {
        if self.active_games.contains_key(&game_id) {
            return game_id;
        }
        let game_state = GameState::new(game_id.clone(), max_players, min_players, permission);
        self.active_games.insert(game_id.clone(), game_state);
        game_id
    }

    pub fn get_game(&self, game_id: &str) -> Option<&GameState> {
        self.active_games.get(game_id)
    }

    pub fn get_game_mut(&mut self, game_id: &str) -> Option<&mut GameState> {
        self.active_games.get_mut(game_id)
    }

    pub fn remove_game(&mut self, game_id: &str) -> bool {
        self.active_games.remove(game_id).is_some()
    }

    pub fn get_all_games(&self) -> &HashMap<String, GameState> {
        &self.active_games
    }

    pub fn get_available_games(&self) -> Vec<serde_json::Value> {
        let mut available_games = Vec::new();
        
        for (game_id, game) in &self.active_games {
            if game.phase == GamePhase::WaitingForPlayers && game.permission == "public" {
                available_games.push(self._to_flutter_game_data(game));
            }
        }
        
        available_games
    }

    fn _to_flutter_game_data(&self, game: &GameState) -> serde_json::Value {
        let current_player = if let Some(current_player_id) = &game.current_player_id {
            if let Some(player) = game.players.get(current_player_id) {
                Some(self._to_flutter_player_data(player, true))
            } else {
                None
            }
        } else {
            None
        };

        serde_json::json!({
            "gameId": game.game_id,
            "gameName": format!("Recall Game {}", game.game_id),
            "players": game.players.iter().map(|(pid, player)| 
                self._to_flutter_player_data(player, Some(pid) == game.current_player_id.as_ref())
            ).collect::<Vec<_>>(),
            "currentPlayer": current_player,
            "playerCount": game.players.len(),
            "maxPlayers": game.max_players,
            "minPlayers": game.min_players,
            "activePlayerCount": game.players.values().filter(|p| p.is_active()).count(),
            "phase": game.phase.to_string(),
            "status": if matches!(game.phase, GamePhase::PlayerTurn | GamePhase::SameRankWindow | GamePhase::EndingRound | GamePhase::EndingTurn | GamePhase::RecallCalled) {
                "active"
            } else {
                "inactive"
            },
            "drawPile": game.draw_pile.iter().map(|card| self._to_flutter_card(card)).collect::<Vec<_>>(),
            "discardPile": game.discard_pile.iter().map(|card| self._to_flutter_card(card)).collect::<Vec<_>>(),
            "gameStartTime": game.game_start_time.map(|t| 
                SystemTime::from(UNIX_EPOCH + std::time::Duration::from_secs(t))
                    .duration_since(UNIX_EPOCH)
                    .unwrap()
                    .as_secs()
            ),
            "lastActivityTime": game.last_action_time.map(|t| 
                SystemTime::from(UNIX_EPOCH + std::time::Duration::from_secs(t))
                    .duration_since(UNIX_EPOCH)
                    .unwrap()
                    .as_secs()
            ),
            "winner": game.winner,
            "gameEnded": game.game_ended,
            "permission": game.permission,
            "recallCalledBy": game.recall_called_by,
            "lastPlayedCard": game.last_played_card.as_ref().map(|card| self._to_flutter_card(card)),
            "outOfTurnDeadline": game.out_of_turn_deadline,
            "outOfTurnTimeoutSeconds": game.out_of_turn_timeout_seconds,
        })
    }

    fn _to_flutter_card(&self, card: &Card) -> serde_json::Value {
        let rank_mapping: std::collections::HashMap<&str, &str> = [
            ("2", "two"), ("3", "three"), ("4", "four"), ("5", "five"),
            ("6", "six"), ("7", "seven"), ("8", "eight"), ("9", "nine"), ("10", "ten")
        ].iter().cloned().collect();
        
        serde_json::json!({
            "cardId": card.card_id,
            "suit": card.suit.to_string(),
            "rank": rank_mapping.get(card.rank.to_string().as_str()).unwrap_or(&card.rank.to_string()),
            "points": card.points,
            "displayName": format!("{} of {}", card.rank.to_string(), card.suit.to_string()),
            "color": if matches!(card.suit, CardSuit::Hearts | CardSuit::Diamonds) { "red" } else { "black" },
        })
    }

    fn _to_flutter_player_data(&self, player: &Player, is_current: bool) -> serde_json::Value {
        serde_json::json!({
            "id": player.player_id,
            "name": player.name,
            "type": player.player_type.to_string(),
            "hand": player.hand.iter().map(|card| 
                card.as_ref().map(|c| self._to_flutter_card(c)).unwrap_or(serde_json::Value::Null)
            ).collect::<Vec<_>>(),
            "visibleCards": player.visible_cards.iter().map(|card| self._to_flutter_card(card)).collect::<Vec<_>>(),
            "cardsToPeek": player.cards_to_peek.iter().map(|card| self._to_flutter_card(card)).collect::<Vec<_>>(),
            "score": player.calculate_points(),
            "status": player.status.to_string(),
            "isCurrentPlayer": is_current,
            "hasCalledRecall": player.has_called_recall,
            "drawnCard": player.drawn_card.as_ref().map(|card| self._to_flutter_card(card)),
        })
    }
}
