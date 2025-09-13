//! Game state management for the Recall card game

use crate::models::{Card, Player, PlayerStatus};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

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

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameState {
    pub game_id: String,
    pub players: HashMap<String, Player>,
    pub draw_pile: Vec<Card>,
    pub discard_pile: Vec<Card>,
    pub current_player_id: Option<String>,
    pub phase: GamePhase,
    pub max_players: u32,
    pub min_players: u32,
    pub permission: String,
    pub game_started: bool,
    pub game_ended: bool,
    pub winner: Option<String>,
    pub recall_called_by: Option<String>,
    pub last_action_time: Option<u64>,
    pub game_start_time: Option<u64>,
}

impl GameState {
    pub fn new(game_id: String, max_players: u32, min_players: u32, permission: String) -> Self {
        Self {
            game_id,
            players: HashMap::new(),
            draw_pile: Vec::new(),
            discard_pile: Vec::new(),
            current_player_id: None,
            phase: GamePhase::WaitingForPlayers,
            max_players,
            min_players,
            permission,
            game_started: false,
            game_ended: false,
            winner: None,
            recall_called_by: None,
            last_action_time: None,
            game_start_time: None,
        }
    }

    pub fn add_player(&mut self, player: Player) -> bool {
        if self.players.len() >= self.max_players as usize {
            return false;
        }
        
        self.players.insert(player.player_id.clone(), player);
        true
    }

    pub fn remove_player(&mut self, player_id: &str) -> bool {
        self.players.remove(player_id).is_some()
    }

    pub fn is_full(&self) -> bool {
        self.players.len() >= self.max_players as usize
    }

    pub fn is_started(&self) -> bool {
        self.game_started
    }

    pub fn can_start(&self) -> bool {
        self.players.len() >= self.min_players as usize && !self.game_started
    }

    pub fn start_game(&mut self) -> bool {
        if !self.can_start() {
            return false;
        }
        
        self.game_started = true;
        self.phase = GamePhase::DealingCards;
        self.game_start_time = Some(std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs());
        
        // Deal cards to players
        self.deal_cards();
        
        // Set first player
        if let Some(first_player_id) = self.players.keys().next() {
            self.current_player_id = Some(first_player_id.clone());
        }
        
        true
    }

    fn deal_cards(&mut self) {
        // Create a standard deck
        self.create_deck();
        
        // Deal 4 cards to each player
        for _ in 0..4 {
            for player in self.players.values_mut() {
                if let Some(card) = self.draw_from_draw_pile() {
                    player.add_card_to_hand(card);
                }
            }
        }
    }

    fn create_deck(&mut self) {
        use crate::models::{CardRank, CardSuit};
        
        let mut deck = Vec::new();
        
        // Create standard 52-card deck
        for suit in [CardSuit::Hearts, CardSuit::Diamonds, CardSuit::Clubs, CardSuit::Spades] {
            for rank in [
                CardRank::Ace, CardRank::Two, CardRank::Three, CardRank::Four,
                CardRank::Five, CardRank::Six, CardRank::Seven, CardRank::Eight,
                CardRank::Nine, CardRank::Ten, CardRank::Jack, CardRank::Queen, CardRank::King
            ] {
                let points = match rank {
                    CardRank::Joker => 0,
                    CardRank::Ace => 1,
                    CardRank::Two => 2,
                    CardRank::Three => 3,
                    CardRank::Four => 4,
                    CardRank::Five => 5,
                    CardRank::Six => 6,
                    CardRank::Seven => 7,
                    CardRank::Eight => 8,
                    CardRank::Nine => 9,
                    CardRank::Ten => 10,
                    CardRank::Jack => 10,
                    CardRank::Queen => 10,
                    CardRank::King => 10,
                };
                
                let special_power = match rank {
                    CardRank::Jack => Some("switch_cards".to_string()),
                    CardRank::Queen => Some("peek_at_card".to_string()),
                    _ => None,
                };
                
                deck.push(Card::new(rank, suit, points, special_power));
            }
        }
        
        // Add jokers
        deck.push(Card::new(CardRank::Joker, CardSuit::Hearts, 0, None));
        deck.push(Card::new(CardRank::Joker, CardSuit::Spades, 0, None));
        
        // Shuffle the deck
        use rand::seq::SliceRandom;
        use rand::thread_rng;
        deck.shuffle(&mut thread_rng());
        
        self.draw_pile = deck;
    }

    pub fn draw_from_draw_pile(&mut self) -> Option<Card> {
        self.draw_pile.pop()
    }

    pub fn add_to_discard_pile(&mut self, card: Card) {
        self.discard_pile.push(card);
    }

    pub fn process_action(&mut self, action: crate::PlayerAction) -> crate::GameResult {
        // This would contain the actual game logic
        // For now, just return a placeholder
        crate::GameResult {
            success: true,
            error: None,
            data: Some(serde_json::json!({
                "message": "Action processed",
                "game_id": self.game_id
            })),
        }
    }
}
