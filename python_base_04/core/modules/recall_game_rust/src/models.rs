//! Game models for the Recall card game

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum CardSuit {
    Hearts,
    Diamonds,
    Clubs,
    Spades,
}

impl CardSuit {
    pub fn to_string(&self) -> String {
        match self {
            CardSuit::Hearts => "hearts".to_string(),
            CardSuit::Diamonds => "diamonds".to_string(),
            CardSuit::Clubs => "clubs".to_string(),
            CardSuit::Spades => "spades".to_string(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum CardRank {
    Joker,
    Ace,
    Two,
    Three,
    Four,
    Five,
    Six,
    Seven,
    Eight,
    Nine,
    Ten,
    Jack,
    Queen,
    King,
}

impl CardRank {
    pub fn to_string(&self) -> String {
        match self {
            CardRank::Joker => "joker".to_string(),
            CardRank::Ace => "ace".to_string(),
            CardRank::Two => "2".to_string(),
            CardRank::Three => "3".to_string(),
            CardRank::Four => "4".to_string(),
            CardRank::Five => "5".to_string(),
            CardRank::Six => "6".to_string(),
            CardRank::Seven => "7".to_string(),
            CardRank::Eight => "8".to_string(),
            CardRank::Nine => "9".to_string(),
            CardRank::Ten => "10".to_string(),
            CardRank::Jack => "jack".to_string(),
            CardRank::Queen => "queen".to_string(),
            CardRank::King => "king".to_string(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum PlayerType {
    Human,
    Computer,
}

impl PlayerType {
    pub fn to_string(&self) -> String {
        match self {
            PlayerType::Human => "human".to_string(),
            PlayerType::Computer => "computer".to_string(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum PlayerStatus {
    Waiting,
    Ready,
    Playing,
    SameRankWindow,
    PlayingCard,
    DrawingCard,
    QueenPeek,
    JackSwap,
    Peeking,
    InitialPeek,
    Finished,
    Disconnected,
    Winner,
}

impl PlayerStatus {
    pub fn to_string(&self) -> String {
        match self {
            PlayerStatus::Waiting => "waiting".to_string(),
            PlayerStatus::Ready => "ready".to_string(),
            PlayerStatus::Playing => "playing".to_string(),
            PlayerStatus::SameRankWindow => "same_rank_window".to_string(),
            PlayerStatus::PlayingCard => "playing_card".to_string(),
            PlayerStatus::DrawingCard => "drawing_card".to_string(),
            PlayerStatus::QueenPeek => "queen_peek".to_string(),
            PlayerStatus::JackSwap => "jack_swap".to_string(),
            PlayerStatus::Peeking => "peeking".to_string(),
            PlayerStatus::InitialPeek => "initial_peek".to_string(),
            PlayerStatus::Finished => "finished".to_string(),
            PlayerStatus::Disconnected => "disconnected".to_string(),
            PlayerStatus::Winner => "winner".to_string(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Card {
    pub card_id: String,
    pub rank: CardRank,
    pub suit: CardSuit,
    pub points: u32,
    pub special_power: Option<String>,
    pub is_visible: bool,
    pub owner_id: Option<String>,
}

impl Card {
    pub fn new(rank: CardRank, suit: CardSuit, points: u32, special_power: Option<String>) -> Self {
        Self {
            card_id: uuid::Uuid::new_v4().to_string(),
            rank,
            suit,
            points,
            special_power,
            is_visible: false,
            owner_id: None,
        }
    }

    pub fn get_point_value(&self) -> u32 {
        self.points
    }

    pub fn has_special_power(&self) -> bool {
        self.special_power.is_some()
    }

    pub fn to_dict(&self) -> serde_json::Value {
        serde_json::json!({
            "card_id": self.card_id,
            "rank": self.rank.to_string(),
            "suit": self.suit.to_string(),
            "points": self.points,
            "special_power": self.special_power,
            "is_visible": self.is_visible,
            "owner_id": self.owner_id
        })
    }

    pub fn from_dict(data: serde_json::Value) -> Self {
        Self {
            card_id: data["card_id"].as_str().unwrap_or("").to_string(),
            rank: match data["rank"].as_str().unwrap_or("") {
                "joker" => CardRank::Joker,
                "ace" => CardRank::Ace,
                "2" => CardRank::Two,
                "3" => CardRank::Three,
                "4" => CardRank::Four,
                "5" => CardRank::Five,
                "6" => CardRank::Six,
                "7" => CardRank::Seven,
                "8" => CardRank::Eight,
                "9" => CardRank::Nine,
                "10" => CardRank::Ten,
                "jack" => CardRank::Jack,
                "queen" => CardRank::Queen,
                "king" => CardRank::King,
                _ => CardRank::Ace,
            },
            suit: match data["suit"].as_str().unwrap_or("") {
                "hearts" => CardSuit::Hearts,
                "diamonds" => CardSuit::Diamonds,
                "clubs" => CardSuit::Clubs,
                "spades" => CardSuit::Spades,
                _ => CardSuit::Hearts,
            },
            points: data["points"].as_u64().unwrap_or(0) as u32,
            special_power: data["special_power"].as_str().map(|s| s.to_string()),
            is_visible: data["is_visible"].as_bool().unwrap_or(false),
            owner_id: data["owner_id"].as_str().map(|s| s.to_string()),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Player {
    pub player_id: String,
    pub name: String,
    pub player_type: PlayerType,
    pub hand: Vec<Option<Card>>,
    pub visible_cards: Vec<Card>,
    pub status: PlayerStatus,
    pub has_called_recall: bool,
    pub drawn_card: Option<Card>,
    pub cards_to_peek: Vec<Card>,
    pub is_active: bool,
}

impl Player {
    pub fn new(player_id: String, name: String, player_type: PlayerType) -> Self {
        Self {
            player_id,
            name,
            player_type,
            hand: vec![None; 4], // 4 card slots
            visible_cards: Vec::new(),
            status: PlayerStatus::Waiting,
            has_called_recall: false,
            drawn_card: None,
            cards_to_peek: Vec::new(),
            is_active: true,
        }
    }

    pub fn add_card_to_hand(&mut self, card: Card) {
        // Find first empty slot
        for slot in &mut self.hand {
            if slot.is_none() {
                *slot = Some(card);
                return;
            }
        }
        // If no empty slots, add to end
        self.hand.push(Some(card));
    }

    pub fn remove_card_from_hand(&mut self, card_id: &str) -> Option<Card> {
        for slot in &mut self.hand {
            if let Some(card) = slot {
                if card.card_id == card_id {
                    let removed_card = slot.take();
                    return removed_card;
                }
            }
        }
        None
    }

    pub fn calculate_points(&self) -> u32 {
        self.hand
            .iter()
            .filter_map(|card| card.as_ref())
            .map(|card| card.get_point_value())
            .sum()
    }

    pub fn set_status(&mut self, status: PlayerStatus) {
        self.status = status;
    }

    pub fn is_active(&self) -> bool {
        self.is_active && !matches!(self.status, PlayerStatus::Finished | PlayerStatus::Disconnected)
    }

    pub fn set_drawn_card(&mut self, card: Option<Card>) {
        self.drawn_card = card;
    }

    pub fn get_drawn_card(&self) -> Option<Card> {
        self.drawn_card.clone()
    }

    pub fn clear_drawn_card(&mut self) {
        self.drawn_card = None;
    }

    pub fn clear_cards_to_peek(&mut self) {
        self.cards_to_peek.clear();
    }

    pub fn add_card_to_peek(&mut self, card: Card) {
        self.cards_to_peek.push(card);
    }

    pub fn to_dict(&self) -> serde_json::Value {
        serde_json::json!({
            "player_id": self.player_id,
            "name": self.name,
            "player_type": self.player_type.to_string(),
            "hand": self.hand.iter().map(|card| 
                card.as_ref().map(|c| c.to_dict()).unwrap_or(serde_json::Value::Null)
            ).collect::<Vec<_>>(),
            "visible_cards": self.visible_cards.iter().map(|card| card.to_dict()).collect::<Vec<_>>(),
            "status": self.status.to_string(),
            "has_called_recall": self.has_called_recall,
            "drawn_card": self.drawn_card.as_ref().map(|card| card.to_dict()),
            "cards_to_peek": self.cards_to_peek.iter().map(|card| card.to_dict()).collect::<Vec<_>>(),
            "is_active": self.is_active
        })
    }

    pub fn from_dict(data: serde_json::Value) -> Self {
        let hand: Vec<Option<Card>> = data["hand"]
            .as_array()
            .unwrap_or(&vec![])
            .iter()
            .map(|card_data| {
                if card_data.is_null() {
                    None
                } else {
                    Some(Card::from_dict(card_data.clone()))
                }
            })
            .collect();

        let visible_cards: Vec<Card> = data["visible_cards"]
            .as_array()
            .unwrap_or(&vec![])
            .iter()
            .map(|card_data| Card::from_dict(card_data.clone()))
            .collect();

        let cards_to_peek: Vec<Card> = data["cards_to_peek"]
            .as_array()
            .unwrap_or(&vec![])
            .iter()
            .map(|card_data| Card::from_dict(card_data.clone()))
            .collect();

        Self {
            player_id: data["player_id"].as_str().unwrap_or("").to_string(),
            name: data["name"].as_str().unwrap_or("").to_string(),
            player_type: match data["player_type"].as_str().unwrap_or("") {
                "human" => PlayerType::Human,
                "computer" => PlayerType::Computer,
                _ => PlayerType::Human,
            },
            hand,
            visible_cards,
            status: match data["status"].as_str().unwrap_or("") {
                "waiting" => PlayerStatus::Waiting,
                "ready" => PlayerStatus::Ready,
                "playing" => PlayerStatus::Playing,
                "same_rank_window" => PlayerStatus::SameRankWindow,
                "playing_card" => PlayerStatus::PlayingCard,
                "drawing_card" => PlayerStatus::DrawingCard,
                "queen_peek" => PlayerStatus::QueenPeek,
                "jack_swap" => PlayerStatus::JackSwap,
                "peeking" => PlayerStatus::Peeking,
                "initial_peek" => PlayerStatus::InitialPeek,
                "finished" => PlayerStatus::Finished,
                "disconnected" => PlayerStatus::Disconnected,
                "winner" => PlayerStatus::Winner,
                _ => PlayerStatus::Waiting,
            },
            has_called_recall: data["has_called_recall"].as_bool().unwrap_or(false),
            drawn_card: data["drawn_card"].as_object().map(|_| Card::from_dict(data["drawn_card"].clone())),
            cards_to_peek,
            is_active: data["is_active"].as_bool().unwrap_or(true),
        }
    }
}
