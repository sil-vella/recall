//! Recall Game Rust Library
//! 
//! This library provides the core game logic for the Recall card game,
//! designed to be used by both Python backend and Flutter frontend.

use std::collections::HashMap;
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int};
use serde::{Deserialize, Serialize};

mod game_state;
mod game_round;
mod game_round_actions;
mod models;
mod websocket_handlers;

use game_state::{GameState, GamePhase, GameStateManager};
use models::{Card, Player, PlayerType, PlayerStatus};

/// Main game engine that manages all game instances
pub struct RecallGameEngine {
    game_state_manager: GameStateManager,
}

impl RecallGameEngine {
    pub fn new() -> Self {
        Self {
            game_state_manager: GameStateManager::new(),
        }
    }

    pub fn create_game(&mut self, config: GameConfig) -> String {
        self.game_state_manager.create_game(config.max_players, config.min_players, config.permission)
    }

    pub fn get_game(&self, game_id: &str) -> Option<&GameState> {
        self.game_state_manager.get_game(game_id)
    }

    pub fn get_available_games(&self) -> Vec<GameInfo> {
        self.game_state_manager.get_available_games()
            .iter()
            .map(|game_data| GameInfo {
                game_id: game_data["gameId"].as_str().unwrap_or("").to_string(),
                player_count: game_data["playerCount"].as_u64().unwrap_or(0) as usize,
                max_players: game_data["maxPlayers"].as_u64().unwrap_or(4) as u32,
                permission: game_data["permission"].as_str().unwrap_or("public").to_string(),
            })
            .collect()
    }

    pub fn process_action(&mut self, game_id: &str, action: PlayerAction) -> GameResult {
        if let Some(game) = self.game_state_manager.get_game_mut(game_id) {
            // Process the action through the game round
            // For now, just return success
            GameResult {
                success: true,
                error: None,
                data: Some(serde_json::json!({
                    "message": "Action processed",
                    "game_id": game_id
                })),
            }
        } else {
            GameResult {
                success: false,
                error: Some("Game not found".to_string()),
                data: None,
            }
        }
    }

    pub fn to_flutter_game_data(&self, game_id: &str) -> Option<serde_json::Value> {
        self.game_state_manager.get_game(game_id)
            .map(|game| self.game_state_manager._to_flutter_game_data(game))
    }

    pub fn to_flutter_player_data(&self, game_id: &str, player_id: &str, is_current: bool) -> Option<serde_json::Value> {
        self.game_state_manager.get_game(game_id)
            .and_then(|game| game.players.get(player_id))
            .map(|player| self.game_state_manager._to_flutter_player_data(player, is_current))
    }
}

// Data structures for FFI
#[derive(Serialize, Deserialize)]
pub struct GameConfig {
    pub max_players: u32,
    pub min_players: u32,
    pub permission: String,
}

#[derive(Serialize, Deserialize)]
pub struct GameInfo {
    pub game_id: String,
    pub player_count: usize,
    pub max_players: u32,
    pub permission: String,
}

#[derive(Serialize, Deserialize)]
pub struct PlayerAction {
    pub action_type: String,
    pub player_id: String,
    pub card_id: Option<String>,
    pub game_id: String,
    pub data: Option<serde_json::Value>,
}

#[derive(Serialize, Deserialize)]
pub struct GameResult {
    pub success: bool,
    pub error: Option<String>,
    pub data: Option<serde_json::Value>,
}

// FFI Functions
#[no_mangle]
pub extern "C" fn create_engine() -> *mut RecallGameEngine {
    Box::into_raw(Box::new(RecallGameEngine::new()))
}

#[no_mangle]
pub extern "C" fn destroy_engine(engine: *mut RecallGameEngine) {
    if !engine.is_null() {
        unsafe {
            let _ = Box::from_raw(engine);
        }
    }
}

#[no_mangle]
pub extern "C" fn create_game(
    engine: *mut RecallGameEngine,
    config_json: *const c_char,
) -> *mut c_char {
    let engine = unsafe { &mut *engine };
    let config_str = unsafe { CStr::from_ptr(config_json).to_string_lossy() };
    
    let config: GameConfig = match serde_json::from_str(&config_str) {
        Ok(config) => config,
        Err(_) => return CString::new("").unwrap().into_raw(),
    };
    
    let game_id = engine.create_game(config);
    CString::new(game_id).unwrap().into_raw()
}

#[no_mangle]
pub extern "C" fn get_game(
    engine: *mut RecallGameEngine,
    game_id: *const c_char,
) -> *mut c_char {
    let engine = unsafe { &*engine };
    let game_id_str = unsafe { CStr::from_ptr(game_id).to_string_lossy() };
    
    if let Some(game) = engine.get_game(&game_id_str) {
        let game_json = serde_json::to_string(game).unwrap_or("{}".to_string());
        CString::new(game_json).unwrap().into_raw()
    } else {
        CString::new("").unwrap().into_raw()
    }
}

#[no_mangle]
pub extern "C" fn get_available_games(
    engine: *mut RecallGameEngine,
) -> *mut c_char {
    let engine = unsafe { &*engine };
    let games = engine.get_available_games();
    let games_json = serde_json::to_string(&games).unwrap_or("[]".to_string());
    CString::new(games_json).unwrap().into_raw()
}

#[no_mangle]
pub extern "C" fn process_action(
    engine: *mut RecallGameEngine,
    game_id: *const c_char,
    action_json: *const c_char,
) -> *mut c_char {
    let engine = unsafe { &mut *engine };
    let game_id_str = unsafe { CStr::from_ptr(game_id).to_string_lossy() };
    let action_str = unsafe { CStr::from_ptr(action_json).to_string_lossy() };
    
    let action: PlayerAction = match serde_json::from_str(&action_str) {
        Ok(action) => action,
        Err(_) => return CString::new(r#"{"success": false, "error": "Invalid action JSON"}"#).unwrap().into_raw(),
    };
    
    let result = engine.process_action(&game_id_str, action);
    let result_json = serde_json::to_string(&result).unwrap_or(r#"{"success": false, "error": "Serialization failed"}"#.to_string());
    CString::new(result_json).unwrap().into_raw()
}

#[no_mangle]
pub extern "C" fn to_flutter_game_data(
    engine: *mut RecallGameEngine,
    game_json: *const c_char,
) -> *mut c_char {
    let engine = unsafe { &*engine };
    let game_str = unsafe { CStr::from_ptr(game_json).to_string_lossy() };
    
    // Parse the game JSON to extract game_id
    let game_data: serde_json::Value = match serde_json::from_str(&game_str) {
        Ok(data) => data,
        Err(_) => return CString::new("{}").unwrap().into_raw(),
    };
    
    let game_id = game_data.get("game_id")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    
    if let Some(flutter_data) = engine.to_flutter_game_data(game_id) {
        let flutter_json = serde_json::to_string(&flutter_data).unwrap_or("{}".to_string());
        CString::new(flutter_json).unwrap().into_raw()
    } else {
        CString::new("{}").unwrap().into_raw()
    }
}

#[no_mangle]
pub extern "C" fn to_flutter_player_data(
    engine: *mut RecallGameEngine,
    player_json: *const c_char,
    game_id: *const c_char,
    is_current: c_int,
) -> *mut c_char {
    let engine = unsafe { &*engine };
    let player_str = unsafe { CStr::from_ptr(player_json).to_string_lossy() };
    let game_id_str = unsafe { CStr::from_ptr(game_id).to_string_lossy() };
    
    // Parse the player JSON to extract player_id
    let player_data: serde_json::Value = match serde_json::from_str(&player_str) {
        Ok(data) => data,
        Err(_) => return CString::new("{}").unwrap().into_raw(),
    };
    
    let player_id = player_data.get("player_id")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    
    if let Some(flutter_data) = engine.to_flutter_player_data(&game_id_str, player_id, is_current != 0) {
        let flutter_json = serde_json::to_string(&flutter_data).unwrap_or("{}".to_string());
        CString::new(flutter_json).unwrap().into_raw()
    } else {
        CString::new("{}").unwrap().into_raw()
    }
}

#[no_mangle]
pub extern "C" fn handle_game_event(
    engine: *mut RecallGameEngine,
    session_id: *const c_char,
    event_name: *const c_char,
    event_data: *const c_char,
) -> c_int {
    // This would handle WebSocket events
    // For now, just return success
    1
}

#[no_mangle]
pub extern "C" fn register_game_event_listeners(
    engine: *mut RecallGameEngine,
) -> c_int {
    // This would register WebSocket event listeners
    // For now, just return success
    1
}
