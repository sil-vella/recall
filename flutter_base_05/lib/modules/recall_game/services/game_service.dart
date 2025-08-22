import 'dart:async';
import '../../../tools/logging/logger.dart';
import '../models/game_state.dart';
import '../models/player.dart';
import '../models/card.dart';
import '../utils/recall_game_helpers.dart';

/// Game-specific business logic only - no state management
/// Handles game operations, validation, and business rules
class GameService {
  static final Logger _log = Logger();
  static final GameService _instance = GameService._internal();
  factory GameService() => _instance;
  GameService._internal();

  // Game operations using validated systems
  Future<Map<String, dynamic>> startMatch(String gameId) async {
    try {
      _log.info('🎮 GameService: Starting match for game: $gameId');
      
      // Use validated event emitter for start match
      final result = await RecallGameHelpers.startMatch(gameId);
      
      _log.info('🎮 GameService: Start match result: $result');
      return result;
      
    } catch (e) {
      _log.error('❌ GameService: Error starting match: $e');
      return {'error': 'Failed to start match: $e'};
    }
  }

  Future<Map<String, dynamic>> joinGame(String gameId, String playerName, {int? maxPlayers}) async {
    try {
      _log.info('🎮 GameService: Joining game: $gameId as $playerName (max players: $maxPlayers)');
      
      // Use validated event emitter for join game
      final result = await RecallGameHelpers.joinGame(gameId, playerName, maxPlayers: maxPlayers);
      
      _log.info('🎮 GameService: Join game result: $result');
      return result;
      
    } catch (e) {
      _log.error('❌ GameService: Error joining game: $e');
      return {'error': 'Failed to join game: $e'};
    }
  }

  Future<Map<String, dynamic>> playCard(String gameId, String cardId, String playerId, {int? replaceIndex}) async {
    try {
      _log.info('🎮 GameService: Playing card: $cardId in game: $gameId');
      
      // Use validated event emitter for playing card
      final result = await RecallGameHelpers.playCard(
        gameId: gameId,
        cardId: cardId,
        playerId: playerId,
        replaceIndex: replaceIndex,
      );
      
      _log.info('🎮 GameService: Play card result: $result');
      return result;
      
    } catch (e) {
      _log.error('❌ GameService: Error playing card: $e');
      return {'error': 'Failed to play card: $e'};
    }
  }

  Future<Map<String, dynamic>> drawCard(String gameId, String playerId, String source) async {
    try {
      _log.info('🎮 GameService: Drawing card from $source in game: $gameId');
      
      // Use validated event emitter for drawing card
      final result = await RecallGameHelpers.drawCard(
        gameId: gameId,
        playerId: playerId,
        source: source,
      );
      
      _log.info('🎮 GameService: Draw card result: $result');
      return result;
      
    } catch (e) {
      _log.error('❌ GameService: Error drawing card: $e');
      return {'error': 'Failed to draw card: $e'};
    }
  }

  Future<Map<String, dynamic>> callRecall(String gameId, String playerId) async {
    try {
      _log.info('🎮 GameService: Calling recall in game: $gameId');
      
      // Use validated event emitter for calling recall
      final result = await RecallGameHelpers.callRecall(
        gameId: gameId,
        playerId: playerId,
      );
      
      _log.info('🎮 GameService: Call recall result: $result');
      return result;
      
    } catch (e) {
      _log.error('❌ GameService: Error calling recall: $e');
      return {'error': 'Failed to call recall: $e'};
    }
  }

  Future<Map<String, dynamic>> leaveGame(String gameId, String reason) async {
    try {
      _log.info('🎮 GameService: Leaving game: $gameId, reason: $reason');
      
      // Use validated event emitter for leaving game
      final result = await RecallGameHelpers.leaveGame(
        gameId: gameId,
        reason: reason,
      );
      
      _log.info('🎮 GameService: Leave game result: $result');
      return result;
      
    } catch (e) {
      _log.error('❌ GameService: Error leaving game: $e');
      return {'error': 'Failed to leave game: $e'};
    }
  }

  Future<Map<String, dynamic>> playOutOfTurn(String gameId, String cardId, String playerId) async {
    try {
      _log.info('🎮 GameService: Playing out of turn: $cardId in game: $gameId');
      
      // Use validated event emitter for out of turn play
      final result = await RecallGameHelpers.playOutOfTurn(
        gameId: gameId,
        cardId: cardId,
        playerId: playerId,
      );
      
      _log.info('🎮 GameService: Play out of turn result: $result');
      return result;
      
    } catch (e) {
      _log.error('❌ GameService: Error playing out of turn: $e');
      return {'error': 'Failed to play out of turn: $e'};
    }
  }

  Future<Map<String, dynamic>> replaceDrawnCard({
    required String gameId,
    required String playerId,
    required int cardIndex,
  }) async {
    try {
      _log.info('🎮 GameService: Replacing drawn card at index $cardIndex in game: $gameId');
      
      // Use validated event emitter for replace drawn card
      final result = await RecallGameHelpers.replaceDrawnCard(
        gameId: gameId,
        playerId: playerId,
        cardIndex: cardIndex,
      );
      
      _log.info('🎮 GameService: Replace drawn card result: $result');
      return result;
      
    } catch (e) {
      _log.error('❌ GameService: Error replacing drawn card: $e');
      return {'error': 'Failed to replace drawn card: $e'};
    }
  }

  Future<Map<String, dynamic>> placeDrawnCard({
    required String gameId,
    required String playerId,
  }) async {
    try {
      _log.info('🎮 GameService: Placing drawn card in game: $gameId');
      
      // Use validated event emitter for place drawn card
      final result = await RecallGameHelpers.placeDrawnCard(
        gameId: gameId,
        playerId: playerId,
      );
      
      _log.info('🎮 GameService: Place drawn card result: $result');
      return result;
      
    } catch (e) {
      _log.error('❌ GameService: Error placing drawn card: $e');
      return {'error': 'Failed to place drawn card: $e'};
    }
  }

  Future<Map<String, dynamic>> useSpecialPower({
    required String gameId,
    required String cardId,
    required String playerId,
    Map<String, dynamic>? powerData,
  }) async {
    try {
      _log.info('🎮 GameService: Using special power for card: $cardId in game: $gameId');
      
      // Use validated event emitter for special power
      final result = await RecallGameHelpers.useSpecialPower(
        gameId: gameId,
        cardId: cardId,
        playerId: playerId,
        powerData: powerData,
      );
      
      _log.info('🎮 GameService: Use special power result: $result');
      return result;
      
    } catch (e) {
      _log.error('❌ GameService: Error using special power: $e');
      return {'error': 'Failed to use special power: $e'};
    }
  }

  // Room management methods
  Future<Map<String, dynamic>> createRoom({
    required String roomName,
    required String permission,
    required int maxPlayers,
    required int minPlayers,
    String gameType = 'classic',
    int turnTimeLimit = 30,
    bool autoStart = false,
    String? password,
  }) async {
    try {
      _log.info('🎮 GameService: Creating room: $roomName');
      
      // Use validated event emitter for create room
      final result = await RecallGameHelpers.createRoom(
        roomName: roomName,
        permission: permission,
        maxPlayers: maxPlayers,
        minPlayers: minPlayers,
        gameType: gameType,
        turnTimeLimit: turnTimeLimit,
        autoStart: autoStart,
        password: password,
      );
      
      _log.info('🎮 GameService: Create room result: $result');
      return result;
      
    } catch (e) {
      _log.error('❌ GameService: Error creating room: $e');
      return {'error': 'Failed to create room: $e'};
    }
  }

  Future<Map<String, dynamic>> getPendingGames() async {
    try {
      _log.info('🎮 GameService: Getting pending games');
      
      // Use validated event emitter for get pending games
      final result = await RecallGameHelpers.getPendingGames();
      
      _log.info('🎮 GameService: Get pending games result: $result');
      return result;
      
    } catch (e) {
      _log.error('❌ GameService: Error getting pending games: $e');
      return {'error': 'Failed to get pending games: $e'};
    }
  }

  // Game state validation methods
  bool isValidGameState(GameState? gameState) {
    if (gameState == null) return false;
    
    // Basic validation
    if (gameState.gameId.isEmpty) return false;
    if (gameState.players.isEmpty) return false;
    if (gameState.players.length > 8) return false; // Max 8 players
    
    // Game phase validation
    final validPhases = ['waiting', 'playing', 'finished'];
    if (!validPhases.contains(gameState.phase.name)) return false;
    
    // Game status validation
    final validStatuses = ['inactive', 'active', 'paused', 'ended'];
    if (!validStatuses.contains(gameState.status.name)) return false;
    
    return true;
  }

  bool canPlayerPlayCard(String playerId, GameState gameState) {
    if (!isValidGameState(gameState)) return false;
    
    // Check if it's the player's turn
    if (gameState.currentPlayerId != playerId) return false;
    
    // Check if game is active
    if (gameState.status.name != 'active') return false;
    
    // Check if game phase allows playing cards
    if (gameState.phase.name != 'playing') return false;
    
    return true;
  }

  bool isGameReadyToStart(GameState gameState) {
    if (!isValidGameState(gameState)) return false;
    
    // Check if game is in waiting phase
    if (gameState.phase.name != 'waiting') return false;
    
    // Check if there are enough players
    if (gameState.players.length < 2) return false;
    
    // Check if there are not too many players
    if (gameState.players.length > 8) return false;
    
    // Check if game is inactive (ready to be started)
    if (gameState.status.name != 'inactive') return false;
    
    return true;
  }

  bool canPlayerCallRecall(String playerId, GameState gameState) {
    if (!isValidGameState(gameState)) return false;
    
    // Check if game is active
    if (gameState.status.name != 'active') return false;
    
    // Check if game phase allows calling recall
    if (gameState.phase.name != 'playing') return false;
    
    // Check if player is in the game
    final player = gameState.players.firstWhere(
      (p) => p.id == playerId,
      orElse: () => Player(
        id: '', 
        name: '', 
        type: PlayerType.human,
      ),
    );
    
    if (player.id.isEmpty) return false;
    
    return true;
  }

  // Game business logic methods
  List<Card> getValidCardsForPlayer(String playerId, GameState gameState) {
    if (!isValidGameState(gameState)) return [];
    
    final player = gameState.players.firstWhere(
      (p) => p.id == playerId,
      orElse: () => Player(
        id: '', 
        name: '', 
        type: PlayerType.human,
      ),
    );
    
    if (player.id.isEmpty) return [];
    
    // Return player's hand (this would need to be implemented based on your card model)
    // For now, return empty list as placeholder
    return [];
  }

  bool isGameEnded(GameState gameState) {
    if (!isValidGameState(gameState)) return false;
    
    return gameState.phase.name == 'finished' || gameState.status.name == 'ended';
  }

  Player? getWinner(GameState gameState) {
    if (!isGameEnded(gameState)) return null;
    
    // Find player with lowest score (winner in Recall game)
    if (gameState.players.isEmpty) return null;
    
    Player winner = gameState.players.first;
    for (final player in gameState.players) {
      if (player.totalScore < winner.totalScore) {
        winner = player;
      }
    }
    
    return winner;
  }

  // Game statistics methods
  Map<String, dynamic> getGameStatistics(GameState gameState) {
    if (!isValidGameState(gameState)) return {};
    
    final totalCards = gameState.players.fold<int>(0, (sum, player) => sum + player.handSize);
    final averageScore = gameState.players.isEmpty 
        ? 0 
        : gameState.players.fold<int>(0, (sum, player) => sum + player.totalScore) / gameState.players.length;
    
    return {
      'totalPlayers': gameState.players.length,
      'totalCards': totalCards,
      'averageScore': averageScore,
      'gamePhase': gameState.phase.name,
      'gameStatus': gameState.status.name,
      'turnNumber': gameState.turnNumber,
      'roundNumber': gameState.roundNumber,
    };
  }
}
