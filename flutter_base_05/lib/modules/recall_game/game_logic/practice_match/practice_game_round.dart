/// Practice Game Round Manager for Recall Game
///
/// This class handles the actual gameplay rounds, turn management, and game logic
/// for practice sessions, including turn rotation, card actions, and AI decision making.

import 'dart:async';
import 'package:recall/tools/logging/logger.dart';
import '../../../../core/managers/state_manager.dart';
import '../models/player.dart';
import 'practice_game.dart';

const bool LOGGING_SWITCH = true;

class PracticeGameRound {
  /// Manages practice game rounds and turn logic
  
  final StateManager _stateManager = StateManager();
  final PracticeGameCoordinator _gameCoordinator;
  
  // Turn management
  int _currentPlayerIndex = 0;
  List<Player> _players = [];
  String? _currentGameId;
  
  // Game state
  bool _isGameActive = false;
  bool _isHumanTurn = false;
  Timer? _turnTimer;
  int _turnDurationSeconds = 30; // User's choice from practice room
  
  PracticeGameRound(this._gameCoordinator);
  
  /// Initialize the game round with players
  void initializeRound(List<Player> players, String gameId, {int turnDurationSeconds = 30}) {
    try {
      _players = List.from(players);
      _currentGameId = gameId;
      _currentPlayerIndex = 0; // Human player always starts first
      _isGameActive = true;
      _turnDurationSeconds = turnDurationSeconds;
      
      Logger().info('Practice Round: Initialized with ${_players.length} players', isOn: LOGGING_SWITCH);
      Logger().info('Practice Round: Human player starts first (index: $_currentPlayerIndex)', isOn: LOGGING_SWITCH);
      Logger().info('Practice Round: Turn duration set to ${_turnDurationSeconds} seconds', isOn: LOGGING_SWITCH);
      
      // Start the first turn
      _startTurn();
      
    } catch (e) {
      Logger().error('Practice Round: Failed to initialize round: $e', isOn: LOGGING_SWITCH);
    }
  }
  
  /// Start a new turn
  void _startTurn() {
    try {
      if (!_isGameActive || _players.isEmpty) return;
      
      final currentPlayer = _players[_currentPlayerIndex];
      _isHumanTurn = currentPlayer.playerType == PlayerType.human;
      
      Logger().info('Practice Round: Starting turn for ${currentPlayer.name} (${currentPlayer.playerType.name})', isOn: LOGGING_SWITCH);
      
      // Update player status to drawing_card (matching backend behavior)
      currentPlayer.status = PlayerStatus.drawingCard;
      
      // Update UI state
      _updateTurnState();
      
      // Start turn timer for human players
      if (_isHumanTurn) {
        // Show contextual instructions for human player
        _gameCoordinator.showContextualInstructions();
        _startTurnTimer();
      } else {
        // AI player turn - handle automatically after a short delay
        _handleAITurn();
      }
      
    } catch (e) {
      Logger().error('Practice Round: Failed to start turn: $e', isOn: LOGGING_SWITCH);
    }
  }
  
  /// Start turn timer for human players
  void _startTurnTimer() {
    try {
      // Don't start timer if it's set to "Off" (0 seconds)
      if (_turnDurationSeconds == 0) {
        Logger().info('Practice Round: Turn timer is disabled (Off)', isOn: LOGGING_SWITCH);
        return;
      }
      
      _turnTimer?.cancel();
      _turnTimer = Timer(Duration(seconds: _turnDurationSeconds), () {
        Logger().info('Practice Round: Turn timer expired for human player', isOn: LOGGING_SWITCH);
        _endTurn();
      });
      
      Logger().info('Practice Round: Turn timer started (${_turnDurationSeconds}s)', isOn: LOGGING_SWITCH);
    } catch (e) {
      Logger().error('Practice Round: Failed to start turn timer: $e', isOn: LOGGING_SWITCH);
    }
  }
  
  /// Handle AI player turn
  void _handleAITurn() {
    try {
      final currentPlayer = _players[_currentPlayerIndex];
      Logger().info('Practice Round: AI player ${currentPlayer.name} is thinking...', isOn: LOGGING_SWITCH);
      
      // Simulate AI thinking time (1-3 seconds)
      final thinkingTime = Duration(milliseconds: 1000 + (DateTime.now().millisecondsSinceEpoch % 2000));
      
      Timer(thinkingTime, () {
        _simulateAIAction();
      });
      
    } catch (e) {
      Logger().error('Practice Round: Failed to handle AI turn: $e', isOn: LOGGING_SWITCH);
    }
  }
  
  /// Simulate AI player action
  void _simulateAIAction() {
    try {
      final currentPlayer = _players[_currentPlayerIndex];
      Logger().info('Practice Round: AI ${currentPlayer.name} performing action...', isOn: LOGGING_SWITCH);
      
      // For now, just end the turn (will implement actual AI logic later)
      _endTurn();
      
    } catch (e) {
      Logger().error('Practice Round: Failed to simulate AI action: $e', isOn: LOGGING_SWITCH);
    }
  }
  
  /// End current turn and move to next player
  void _endTurn() {
    try {
      if (!_isGameActive) return;
      
      final currentPlayer = _players[_currentPlayerIndex];
      Logger().info('Practice Round: Ending turn for ${currentPlayer.name}', isOn: LOGGING_SWITCH);
      
      // Cancel turn timer
      _turnTimer?.cancel();
      
      // Set current player back to waiting
      currentPlayer.status = PlayerStatus.waiting;
      
      // Move to next player
      _currentPlayerIndex = (_currentPlayerIndex + 1) % _players.length;
      
      Logger().info('Practice Round: Moving to next player (index: $_currentPlayerIndex)', isOn: LOGGING_SWITCH);
      
      // Start next turn
      _startTurn();
      
    } catch (e) {
      Logger().error('Practice Round: Failed to end turn: $e', isOn: LOGGING_SWITCH);
    }
  }
  
  /// Update UI state for current turn
  void _updateTurnState() {
    try {
      if (_currentGameId == null) return;
      
      final currentPlayer = _players[_currentPlayerIndex];
      
      // Get current state to preserve games map
      final currentState = _stateManager.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
      final currentGames = Map<String, dynamic>.from(currentState['games'] as Map<String, dynamic>? ?? {});
      
      // Update global state with preserved games map
      _stateManager.updateModuleState('recall_game', {
        'games': currentGames, // CRITICAL: Preserve the games map
        'currentGameId': _currentGameId,
        'currentPlayerId': currentPlayer.playerId,
        'isMyTurn': _isHumanTurn,
        'playerStatus': _isHumanTurn ? 'drawing_card' : 'waiting',
        'gamePhase': 'player_turn', // CRITICAL: Set game phase
        'isGameActive': true, // CRITICAL: Set game active
        'isInGame': true, // CRITICAL: Set in game
        'gameInfo': {
          'currentGameId': _currentGameId,
          'currentPlayer': currentPlayer.name,
          'isMyTurn': _isHumanTurn,
          'gamePhase': 'player_turn', // CRITICAL: Set game phase in gameInfo too
          'isInGame': true, // CRITICAL: Set in game in gameInfo too
        },
        'lastUpdated': DateTime.now().toIso8601String(),
      });
      
      Logger().info('Practice Round: Updated turn state - Current: ${currentPlayer.name}, IsHumanTurn: $_isHumanTurn', isOn: LOGGING_SWITCH);
      
    } catch (e) {
      Logger().error('Practice Round: Failed to update turn state: $e', isOn: LOGGING_SWITCH);
    }
  }
  
  /// Get current player
  Player? get currentPlayer {
    if (!_isGameActive || _players.isEmpty || _currentPlayerIndex >= _players.length) {
      return null;
    }
    return _players[_currentPlayerIndex];
  }
  
  /// Get all players
  List<Player> get players => List.from(_players);
  
  /// Check if it's human player's turn
  bool get isHumanTurn => _isHumanTurn;
  
  /// Check if game is active
  bool get isGameActive => _isGameActive;
  
  /// Get current player index
  int get currentPlayerIndex => _currentPlayerIndex;
  
  /// Get game coordinator reference
  PracticeGameCoordinator get gameCoordinator => _gameCoordinator;
  
  /// Dispose of round resources
  void dispose() {
    _turnTimer?.cancel();
    _turnTimer = null;
    _isGameActive = false;
    _players.clear();
    _currentGameId = null;
    
    Logger().info('Practice Round: Disposed', isOn: LOGGING_SWITCH);
  }
}
