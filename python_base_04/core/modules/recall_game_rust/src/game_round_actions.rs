//! Player action handling methods for GameRound

use crate::models::{Card, Player, PlayerStatus};
use crate::game_state::GamePhase;
use crate::game_round::GameRound;
use serde_json;
use std::time::{SystemTime, UNIX_EPOCH};

impl GameRound {
    /// Handle player actions through the game round
    pub fn on_player_action(&mut self, session_id: &str, data: &serde_json::Value) -> bool {
        let action = data.get("action").or_else(|| data.get("action_type"))
            .and_then(|v| v.as_str())
            .unwrap_or("");
        
        if action.is_empty() {
            return false;
        }
        
        // Get player ID from session data or request data
        let user_id = self._extract_user_id(session_id, data);
        
        // Validate player exists before proceeding with any action
        if !self.game_state.players.contains_key(&user_id) {
            return false;
        }
        
        // Build action data for the round
        let action_data = self._build_action_data(data);
        
        // Route to appropriate action handler based on action type and wait for completion
        let action_result = self._route_action(action, &user_id, action_data);
        
        // Update game state timestamp after successful action
        if action_result {
            self.game_state.last_action_time = Some(
                SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .unwrap()
                    .as_secs()
            );
        }
        
        action_result
    }

    fn _get_player(&self, player_id: &str) -> Option<&Player> {
        self.game_state.players.get(player_id)
    }

    fn _get_player_mut(&mut self, player_id: &str) -> Option<&mut Player> {
        self.game_state.players.get_mut(player_id)
    }

    fn _build_action_data(&self, data: &serde_json::Value) -> serde_json::Value {
        serde_json::json!({
            "card_id": data.get("card_id").or_else(|| data.get("card").and_then(|c| c.get("card_id"))).or_else(|| data.get("card").and_then(|c| c.get("id"))),
            "replace_card_id": data.get("replace_card").and_then(|c| c.get("card_id")).or_else(|| data.get("replace_card_id")),
            "replace_index": data.get("replaceIndex"),
            "power_data": data.get("power_data"),
            "indices": data.get("indices").unwrap_or(&serde_json::json!([])),
            "source": data.get("source"),
            "first_card_id": data.get("first_card_id"),
            "first_player_id": data.get("first_player_id"),
            "second_card_id": data.get("second_card_id"),
            "second_player_id": data.get("second_player_id"),
            "queen_peek_card_id": data.get("card_id"),
            "queen_peek_player_id": data.get("player_id"),
            "ownerId": data.get("ownerId"),
        })
    }

    fn _extract_user_id(&self, session_id: &str, data: &serde_json::Value) -> String {
        // This would extract user ID from session data or request data
        // For now, use session_id as a placeholder
        session_id.to_string()
    }

    fn _route_action(&mut self, action: &str, user_id: &str, action_data: serde_json::Value) -> bool {
        match action {
            "draw_from_deck" => self._handle_draw_from_pile(user_id, &action_data),
            "play_card" => {
                let play_result = self._handle_play_card(user_id, &action_data);
                self._handle_same_rank_window(&action_data);
                play_result
            }
            "same_rank_play" => self._handle_same_rank_play(user_id, &action_data),
            "discard_card" => true, // Placeholder
            "take_from_discard" => true, // Placeholder
            "call_recall" => true, // Placeholder
            "jack_swap" => self._handle_jack_swap(user_id, &action_data),
            "queen_peek" => self._handle_queen_peek(user_id, &action_data),
            _ => false,
        }
    }

    fn _handle_same_rank_window(&mut self, action_data: &serde_json::Value) -> bool {
        // Set game state phase to SAME_RANK_WINDOW
        self.game_state.phase = GamePhase::SameRankWindow;
        
        // Update all players' status to SAME_RANK_WINDOW
        for player in self.game_state.players.values_mut() {
            if player.is_active() {
                player.set_status(PlayerStatus::SameRankWindow);
            }
        }
        
        // Set 5-second timer to automatically end same rank window
        self._start_same_rank_timer();
        
        true
    }

    fn _start_same_rank_timer(&mut self) {
        // This would start a 5-second timer
        // For now, just set a placeholder
        self.same_rank_timer = Some(
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_secs() + 5
        );
    }

    fn _end_same_rank_window(&mut self) {
        // Update all players' status to WAITING
        for player in self.game_state.players.values_mut() {
            if player.is_active() {
                player.set_status(PlayerStatus::Waiting);
            }
        }
        
        // Check if any player has no cards left (automatic win condition)
        for (player_id, player) in &self.game_state.players {
            if !player.is_active() {
                continue;
            }
            
            // Count actual cards (excluding None/blank slots)
            let actual_cards: Vec<&Card> = player.hand.iter().filter_map(|card| card.as_ref()).collect();
            let card_count = actual_cards.len();
            
            if card_count == 0 {
                self._handle_end_of_match();
                return; // Exit early since game is ending
            }
        }
        
        // Clear same_rank_data
        self.same_rank_data.clear();
        
        // Send game state update to all players
        self._send_game_state_update();
        
        // Check for special cards and handle them
        self._handle_special_cards_window();
    }

    fn _handle_special_cards_window(&mut self) {
        if self.special_card_data.is_empty() {
            // No special cards, go directly to ENDING_ROUND
            self.game_state.phase = GamePhase::EndingRound;
            self.continue_turn();
            return;
        }
        
        // We have special cards, transition to SPECIAL_PLAY_WINDOW
        self.game_state.phase = GamePhase::SpecialPlayWindow;
        
        // Create a working copy for processing
        self.special_card_players = self.special_card_data.clone();
        
        // Start processing the first player's special card
        self._process_next_special_card();
    }

    fn _process_next_special_card(&mut self) {
        if self.special_card_players.is_empty() {
            self._end_special_cards_window();
            return;
        }
        
        let special_data = self.special_card_players[0].clone();
        let player_id = special_data.get("player_id").and_then(|v| v.as_str()).unwrap_or("unknown");
        let special_power = special_data.get("special_power").and_then(|v| v.as_str()).unwrap_or("unknown");
        
        // Set player status based on special power
        if let Some(player) = self.game_state.players.get_mut(player_id) {
            match special_power {
                "jack_swap" => {
                    player.set_status(PlayerStatus::JackSwap);
                }
                "queen_peek" => {
                    player.set_status(PlayerStatus::QueenPeek);
                }
                _ => {
                    // Unknown special power, remove this card and move to next
                    self.special_card_players.remove(0);
                }
            }
        }
        
        // Start 10-second timer for this player's special card play
        self.special_card_timer = Some(
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_secs() + 10
        );
    }

    fn _on_special_card_timer_expired(&mut self) {
        // Reset current player's status to WAITING (if there are still cards to process)
        if !self.special_card_players.is_empty() {
            let special_data = self.special_card_players[0].clone();
            let player_id = special_data.get("player_id").and_then(|v| v.as_str()).unwrap_or("unknown");
            
            if let Some(player) = self.game_state.players.get_mut(player_id) {
                player.set_status(PlayerStatus::Waiting);
            }
            
            // Remove the processed card from the list
            self.special_card_players.remove(0);
        }
        
        // Process next special card or end window
        self._process_next_special_card();
    }

    fn _end_special_cards_window(&mut self) {
        // Cancel any running timer
        self.special_card_timer = None;
        
        // Clear special card data
        self.special_card_data.clear();
        
        // Reset special card processing variables
        self.special_card_players.clear();
        
        // Transition to ENDING_ROUND phase
        self.game_state.phase = GamePhase::TurnPendingEvents;
        
        // Continue with normal turn flow
        self.continue_turn();
    }

    fn _handle_draw_from_pile(&mut self, player_id: &str, action_data: &serde_json::Value) -> bool {
        // Get the source pile (deck or discard)
        let source = action_data.get("source").and_then(|v| v.as_str()).unwrap_or("");
        
        if source != "deck" && source != "discard" {
            return false;
        }
        
        // Draw card based on source first
        let drawn_card = if source == "deck" {
            self.game_state.draw_from_draw_pile()
        } else {
            self.game_state.draw_from_discard_pile()
        };
        
        let drawn_card = match drawn_card {
            Some(card) => card,
            None => return false,
        };
        
        // Get player and add card
        if let Some(player) = self._get_player_mut(player_id) {
            player.add_card_to_hand(drawn_card.clone());
            player.set_drawn_card(Some(drawn_card));
            player.set_status(PlayerStatus::PlayingCard);
        }
        
        true
    }

    fn _handle_play_card(&mut self, player_id: &str, action_data: &serde_json::Value) -> bool {
        let card_id = action_data.get("card_id").and_then(|v| v.as_str()).unwrap_or("");
        
        // Player validation already done in on_player_action
        let player = match self._get_player_mut(player_id) {
            Some(p) => p,
            None => return false,
        };
        
        // Find the card in the player's hand
        let mut card_to_play = None;
        let mut card_index = None;
        
        for (i, card) in player.hand.iter().enumerate() {
            if let Some(card) = card {
                if card.card_id == card_id {
                    card_to_play = Some(card.clone());
                    card_index = Some(i);
                    break;
                }
            }
        }
        
        let (card_to_play, card_index) = match (card_to_play, card_index) {
            (Some(card), Some(index)) => (card, index),
            _ => return false,
        };
        
        // Handle drawn card repositioning BEFORE removing the played card
        let drawn_card = player.get_drawn_card();
        let drawn_card_original_index = if let Some(drawn_card) = &drawn_card {
            if drawn_card.card_id != card_id {
                player.hand.iter().position(|card| {
                    card.as_ref().map(|c| c.card_id == drawn_card.card_id).unwrap_or(false)
                })
            } else {
                None
            }
        } else {
            None
        };
        
        // Remove card from hand
        let removed_card = match player.remove_card_from_hand(card_id) {
            Some(card) => card,
            None => return false,
        };
        
        // Drop the mutable reference to player before accessing game_state
        drop(player);
        
        // Add card to discard pile
        let add_success = self.game_state.add_to_discard_pile(removed_card.clone());
        if !add_success {
            // If we can't add to discard pile, put card back in hand
            if let Some(player) = self._get_player_mut(player_id) {
                player.add_card_to_hand(removed_card);
            }
            return false;
        }
        
        // Handle drawn card repositioning
        if let (Some(drawn_card), Some(original_index)) = (drawn_card, drawn_card_original_index) {
            if let Some(player) = self._get_player_mut(player_id) {
                if drawn_card.card_id != card_id {
                    // Remove the drawn card from its original position
                    player.hand.remove(original_index);
                    
                    // Place it in the blank slot left by the played card
                    if card_index < player.hand.len() {
                        player.hand.insert(card_index, Some(drawn_card));
                    } else {
                        player.hand.push(Some(drawn_card));
                    }
                    
                    // Clear the drawn card property since it's no longer "drawn"
                    player.clear_drawn_card();
                } else {
                    // Clear the drawn card property since it's now in the discard pile
                    player.clear_drawn_card();
                }
            }
        }
        
        // Check if the played card has special powers (Jack/Queen)
        self._check_special_card(player_id, serde_json::json!({
            "card_id": card_id,
            "rank": card_to_play.rank.to_string(),
            "suit": card_to_play.suit.to_string()
        }));
        
        true
    }

    fn _handle_same_rank_play(&mut self, user_id: &str, action_data: &serde_json::Value) -> bool {
        let card_id = action_data.get("card_id").and_then(|v| v.as_str()).unwrap_or("");
        
        // First, get the card info without mutable borrow
        let (played_card, card_rank, card_suit) = {
            let player = match self._get_player(user_id) {
                Some(p) => p,
                None => return false,
            };
            
            // Find the card in player's hand
            let played_card = player.hand.iter()
                .find_map(|card| card.as_ref().filter(|c| c.card_id == card_id));
            
            let played_card = match played_card {
                Some(card) => card.clone(),
                None => return false,
            };
            
            let card_rank = played_card.rank.to_string();
            let card_suit = played_card.suit.to_string();
            (played_card, card_rank, card_suit)
        };
        
        // Validate that this is actually a same rank play
        let is_valid_play = self._validate_same_rank_play(&card_rank);
        if !is_valid_play {
            // Apply penalty: draw a card from the draw pile
            self._apply_same_rank_penalty(user_id);
            return false;
        }
        
        // SUCCESSFUL SAME RANK PLAY - Remove card from hand and add to discard pile
        let removed_card = {
            let player = match self._get_player_mut(user_id) {
                Some(p) => p,
                None => return false,
            };
            
            match player.remove_card_from_hand(card_id) {
                Some(card) => card,
                None => return false,
            }
        };
        
        let add_success = self.game_state.add_to_discard_pile(removed_card.clone());
        if !add_success {
            return false;
        }
        
        // Check for special cards (Jack/Queen) and store data if applicable
        self._check_special_card(user_id, serde_json::json!({
            "card_id": card_id,
            "rank": card_rank,
            "suit": card_suit
        }));
        
        // Create play data structure
        let play_data = serde_json::json!({
            "player_id": user_id,
            "card_id": card_id,
            "rank": card_rank,
            "suit": card_suit,
            "timestamp": SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs(),
            "play_order": self.same_rank_data.len() + 1
        });
        
        // Store the play in same_rank_data
        self.same_rank_data.insert(user_id.to_string(), play_data);
        
        true
    }

    fn _validate_same_rank_play(&self, card_rank: &str) -> bool {
        // Check if there are any cards in the discard pile
        if self.game_state.discard_pile.is_empty() {
            return false;
        }
        
        // Get the last card from the discard pile
        let last_card = &self.game_state.discard_pile[self.game_state.discard_pile.len() - 1];
        let last_card_rank = last_card.rank.to_string();
        
        // Handle special case: first card of the game (no previous card to match)
        if self.game_state.discard_pile.len() == 1 {
            return true;
        }
        
        // Check if ranks match (case-insensitive for safety)
        card_rank.to_lowercase() == last_card_rank.to_lowercase()
    }

    fn _apply_same_rank_penalty(&mut self, player_id: &str) -> Option<Card> {
        // Check if draw pile has cards
        if self.game_state.draw_pile.is_empty() {
            return None;
        }
        
        // Draw penalty card from draw pile first
        let penalty_card = match self.game_state.draw_from_draw_pile() {
            Some(card) => card,
            None => return None,
        };
        
        // Get player object and add penalty card
        if let Some(player) = self._get_player_mut(player_id) {
            player.add_card_to_hand(penalty_card.clone());
            player.set_status(PlayerStatus::Waiting);
        }
        
        Some(penalty_card)
    }

    fn _check_special_card(&mut self, player_id: &str, action_data: serde_json::Value) {
        let card_id = action_data.get("card_id").and_then(|v| v.as_str()).unwrap_or("");
        let card_rank = action_data.get("rank").and_then(|v| v.as_str()).unwrap_or("");
        let card_suit = action_data.get("suit").and_then(|v| v.as_str()).unwrap_or("");
        
        match card_rank {
            "jack" => {
                let special_card_info = serde_json::json!({
                    "player_id": player_id,
                    "card_id": card_id,
                    "rank": card_rank,
                    "suit": card_suit,
                    "special_power": "jack_swap",
                    "timestamp": SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs(),
                    "description": "Can switch any two cards between players"
                });
                self.special_card_data.push(special_card_info);
            }
            "queen" => {
                let special_card_info = serde_json::json!({
                    "player_id": player_id,
                    "card_id": card_id,
                    "rank": card_rank,
                    "suit": card_suit,
                    "special_power": "queen_peek",
                    "timestamp": SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs(),
                    "description": "Can look at one card from any player's hand"
                });
                self.special_card_data.push(special_card_info);
            }
            _ => {}
        }
    }

    fn _handle_jack_swap(&mut self, user_id: &str, action_data: &serde_json::Value) -> bool {
        let first_card_id = action_data.get("first_card_id").and_then(|v| v.as_str()).unwrap_or("");
        let first_player_id = action_data.get("first_player_id").and_then(|v| v.as_str()).unwrap_or("");
        let second_card_id = action_data.get("second_card_id").and_then(|v| v.as_str()).unwrap_or("");
        let second_player_id = action_data.get("second_player_id").and_then(|v| v.as_str()).unwrap_or("");
        
        // Validate required data
        if first_card_id.is_empty() || first_player_id.is_empty() || second_card_id.is_empty() || second_player_id.is_empty() {
            return false;
        }
        
        // Validate both players exist
        if !self.game_state.players.contains_key(first_player_id) || !self.game_state.players.contains_key(second_player_id) {
            return false;
        }
        
        // Get player objects - we need to handle this carefully to avoid borrowing conflicts
        let first_player_hand = if let Some(player) = self.game_state.players.get_mut(first_player_id) {
            player.hand.clone()
        } else {
            return false;
        };
        
        let second_player_hand = if let Some(player) = self.game_state.players.get_mut(second_player_id) {
            player.hand.clone()
        } else {
            return false;
        };
        
        // Find the cards in each player's hand
        let mut first_card = None;
        let mut first_card_index = None;
        let mut second_card = None;
        let mut second_card_index = None;
        
        // Find first card
        for (i, card) in first_player_hand.iter().enumerate() {
            if let Some(card) = card {
                if card.card_id == first_card_id {
                    first_card = Some(card.clone());
                    first_card_index = Some(i);
                    break;
                }
            }
        }
        
        // Find second card
        for (i, card) in second_player_hand.iter().enumerate() {
            if let Some(card) = card {
                if card.card_id == second_card_id {
                    second_card = Some(card.clone());
                    second_card_index = Some(i);
                    break;
                }
            }
        }
        
        // Validate cards found
        let (first_card, first_card_index, second_card, second_card_index) = match (first_card, first_card_index, second_card, second_card_index) {
            (Some(fc), Some(fci), Some(sc), Some(sci)) => (fc, fci, sc, sci),
            _ => return false,
        };
        
        // Perform the swap by updating the actual player hands
        if let Some(first_player) = self.game_state.players.get_mut(first_player_id) {
            first_player.hand[first_card_index] = Some(second_card.clone());
        }
        
        if let Some(second_player) = self.game_state.players.get_mut(second_player_id) {
            second_player.hand[second_card_index] = Some(first_card.clone());
        }
        
        // Update card ownership
        // Note: We would need to update the card's owner_id field here
        // For now, this is a placeholder
        
        true
    }

    fn _handle_queen_peek(&mut self, user_id: &str, action_data: &serde_json::Value) -> bool {
        let card_id = action_data.get("card_id").and_then(|v| v.as_str()).unwrap_or("");
        let owner_id = action_data.get("ownerId").and_then(|v| v.as_str()).unwrap_or("");
        
        if card_id.is_empty() || owner_id.is_empty() {
            return false;
        }
        
        // Find the target player and card
        let target_player = match self._get_player_mut(owner_id) {
            Some(p) => p,
            None => return false,
        };
        
        // Find the card in the target player's hand
        let target_card = target_player.hand.iter()
            .find_map(|card| card.as_ref().filter(|c| c.card_id == card_id));
        
        let target_card = match target_card {
            Some(card) => card.clone(),
            None => return false,
        };
        
        // Get the current player (the one doing the peek)
        let current_player = match self._get_player_mut(user_id) {
            Some(p) => p,
            None => return false,
        };
        
        // Clear any existing cards from previous peeks
        current_player.clear_cards_to_peek();
        
        // Add the card to the current player's cards_to_peek list
        current_player.add_card_to_peek(target_card);
        
        // Set player status to PEEKING
        current_player.set_status(PlayerStatus::Peeking);
        
        true
    }
}
