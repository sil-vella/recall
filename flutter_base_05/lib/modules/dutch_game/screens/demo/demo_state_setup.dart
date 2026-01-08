import '../../../../tools/logging/logger.dart';
import '../../backend_core/services/game_state_store.dart';

const bool LOGGING_SWITCH = true; // Enabled for demo debugging

/// Demo State Setup
/// 
/// Helper methods to set up game state for each demo action.
/// Each method modifies the game state to match the requirements of the specific action.
class DemoStateSetup {
  final Logger _logger = Logger();

  /// Set up game state for a specific action
  /// 
  /// Returns the modified game state ready for the action
  Future<Map<String, dynamic>> setupActionState({
    required String actionType,
    required String gameId,
    required Map<String, dynamic> gameState,
  }) async {
    _logger.info('🎮 DemoStateSetup: Setting up state for action: $actionType', isOn: LOGGING_SWITCH);

    switch (actionType) {
      case 'initial_peek':
        return await setupInitialPeekState(gameId, gameState);
      case 'drawing':
        return await setupDrawingState(gameId, gameState);
      case 'playing':
        return await setupPlayingState(gameId, gameState);
      case 'same_rank':
        return await setupSameRankState(gameId, gameState);
      case 'queen_peek':
        return await setupQueenPeekState(gameId, gameState);
      case 'jack_swap':
        return await setupJackSwapState(gameId, gameState);
      case 'call_dutch':
        return await setupCallDutchState(gameId, gameState);
      case 'collect_rank':
        return await setupCollectRankState(gameId, gameState);
      default:
        _logger.warning('⚠️ DemoStateSetup: Unknown action type: $actionType, returning original state', isOn: LOGGING_SWITCH);
        return gameState;
    }
  }

  /// Set up state for Initial Peek action
  /// Game should be in initial_peek phase with player in initial_peek status
  Future<Map<String, dynamic>> setupInitialPeekState(
    String gameId,
    Map<String, dynamic> gameState,
  ) async {
    _logger.info('🎮 DemoStateSetup: Setting up initial peek state', isOn: LOGGING_SWITCH);

    // Game should already be in initial_peek phase after startMatch
    // Just ensure player status is correct
    final players = List<Map<String, dynamic>>.from(gameState['players'] as List<dynamic>? ?? []);
    if (players.isNotEmpty) {
      players[0]['status'] = 'initial_peek';
      players[0]['isCurrentPlayer'] = true;
    }

    // Set current player
    final currentPlayer = players.isNotEmpty ? {
      'id': players[0]['id'],
      'name': players[0]['name'],
      'status': 'initial_peek',
    } : null;

    final updatedState = Map<String, dynamic>.from(gameState);
    updatedState['players'] = players;
    updatedState['phase'] = 'initial_peek';
    updatedState['currentPlayer'] = currentPlayer;

    // Update game state store
    final gameStateStore = GameStateStore.instance;
    gameStateStore.setGameState(gameId, updatedState);

    return updatedState;
  }

  /// Set up state for Drawing action
  /// Game should be started, player in drawing_card status
  Future<Map<String, dynamic>> setupDrawingState(
    String gameId,
    Map<String, dynamic> gameState,
  ) async {
    _logger.info('🎮 DemoStateSetup: Setting up drawing state', isOn: LOGGING_SWITCH);

    // Game should be started (phase: 'playing')
    // Player should be in drawing_card status
    final players = List<Map<String, dynamic>>.from(gameState['players'] as List<dynamic>? ?? []);
    if (players.isNotEmpty) {
      players[0]['status'] = 'drawing_card';
      players[0]['isCurrentPlayer'] = true;
    }

    // Set current player
    final currentPlayer = players.isNotEmpty ? {
      'id': players[0]['id'],
      'name': players[0]['name'],
      'status': 'drawing_card',
    } : null;

    final updatedState = Map<String, dynamic>.from(gameState);
    updatedState['players'] = players;
    updatedState['phase'] = 'playing';
    updatedState['currentPlayer'] = currentPlayer;

    // Update game state store
    final gameStateStore = GameStateStore.instance;
    gameStateStore.setGameState(gameId, updatedState);

    return updatedState;
  }

  /// Set up state for Playing action
  /// Game should be started, player in playing_card status with drawn card
  Future<Map<String, dynamic>> setupPlayingState(
    String gameId,
    Map<String, dynamic> gameState,
  ) async {
    _logger.info('🎮 DemoStateSetup: Setting up playing state', isOn: LOGGING_SWITCH);

    // First set up drawing state, then advance to playing
    var updatedState = await setupDrawingState(gameId, gameState);

    // Simulate drawing a card (get from draw pile)
    final drawPile = List<Map<String, dynamic>>.from(updatedState['drawPile'] as List<dynamic>? ?? []);
    if (drawPile.isNotEmpty) {
      final drawnCard = Map<String, dynamic>.from(drawPile[0]);
      drawPile.removeAt(0);

      final players = List<Map<String, dynamic>>.from(updatedState['players'] as List<dynamic>? ?? []);
      if (players.isNotEmpty) {
        players[0]['drawnCard'] = drawnCard;
        players[0]['status'] = 'playing_card';
        players[0]['isCurrentPlayer'] = true;
      }

      updatedState['drawPile'] = drawPile;
      updatedState['players'] = players;
      updatedState['currentPlayer'] = players.isNotEmpty ? {
        'id': players[0]['id'],
        'name': players[0]['name'],
        'status': 'playing_card',
      } : null;
    }

    // Update game state store
    final gameStateStore = GameStateStore.instance;
    gameStateStore.setGameState(gameId, updatedState);

    return updatedState;
  }

  /// Set up state for Same Rank action
  /// Game should be in same_rank_window phase with discard pile having a card
  Future<Map<String, dynamic>> setupSameRankState(
    String gameId,
    Map<String, dynamic> gameState,
  ) async {
    _logger.info('🎮 DemoStateSetup: Setting up same rank state', isOn: LOGGING_SWITCH);

    // First set up playing state, then simulate a card being played
    var updatedState = await setupPlayingState(gameId, gameState);

    // Simulate playing a card to discard pile
    final players = List<Map<String, dynamic>>.from(updatedState['players'] as List<dynamic>? ?? []);
    final discardPile = List<Map<String, dynamic>>.from(updatedState['discardPile'] as List<dynamic>? ?? []);
    
    if (players.isNotEmpty && players[0]['hand'] != null) {
      final hand = List<Map<String, dynamic>>.from(players[0]['hand'] as List<dynamic>? ?? []);
      if (hand.isNotEmpty) {
        // Play first card from hand
        final playedCard = Map<String, dynamic>.from(hand[0]);
        hand.removeAt(0);
        discardPile.insert(0, playedCard); // Add to top of discard pile

        players[0]['hand'] = hand;
        players[0]['status'] = 'same_rank_window';
        players[0]['isCurrentPlayer'] = false; // Not current player during same rank window
      }
    }

    // Set all players to same_rank_window status
    for (var player in players) {
      if (player['isHuman'] != true) {
        player['status'] = 'same_rank_window';
      }
    }

    updatedState['players'] = players;
    updatedState['discardPile'] = discardPile;
    updatedState['phase'] = 'same_rank_window';
    updatedState['currentPlayer'] = null; // No current player during same rank window

    // Update game state store
    final gameStateStore = GameStateStore.instance;
    gameStateStore.setGameState(gameId, updatedState);

    return updatedState;
  }

  /// Set up state for Queen Peek action
  /// Game should be started, player played Queen, in queen_peek status
  Future<Map<String, dynamic>> setupQueenPeekState(
    String gameId,
    Map<String, dynamic> gameState,
  ) async {
    _logger.info('🎮 DemoStateSetup: Setting up queen peek state', isOn: LOGGING_SWITCH);

    // First set up playing state, then simulate playing a Queen
    var updatedState = await setupPlayingState(gameId, gameState);

    // Find a Queen in the hand or create one
    final players = List<Map<String, dynamic>>.from(updatedState['players'] as List<dynamic>? ?? []);
    final discardPile = List<Map<String, dynamic>>.from(updatedState['discardPile'] as List<dynamic>? ?? []);
    
    if (players.isNotEmpty) {
      // Create a Queen card and add to discard pile
      final queenCard = {
        'cardId': 'card_demo_queen_hearts_0',
        'rank': 'queen',
        'suit': 'hearts',
        'points': 10,
        'specialPower': 'peek_at_card',
      };
      discardPile.insert(0, queenCard);

      players[0]['status'] = 'queen_peek';
      players[0]['isCurrentPlayer'] = true;
    }

    updatedState['players'] = players;
    updatedState['discardPile'] = discardPile;
    updatedState['currentPlayer'] = players.isNotEmpty ? {
      'id': players[0]['id'],
      'name': players[0]['name'],
      'status': 'queen_peek',
    } : null;

    // Update game state store
    final gameStateStore = GameStateStore.instance;
    gameStateStore.setGameState(gameId, updatedState);

    return updatedState;
  }

  /// Set up state for Jack Swap action
  /// Game should be started, player played Jack, in jack_swap status
  Future<Map<String, dynamic>> setupJackSwapState(
    String gameId,
    Map<String, dynamic> gameState,
  ) async {
    _logger.info('🎮 DemoStateSetup: Setting up jack swap state', isOn: LOGGING_SWITCH);

    // First set up playing state, then simulate playing a Jack
    var updatedState = await setupPlayingState(gameId, gameState);

    // Find a Jack in the hand or create one
    final players = List<Map<String, dynamic>>.from(updatedState['players'] as List<dynamic>? ?? []);
    final discardPile = List<Map<String, dynamic>>.from(updatedState['discardPile'] as List<dynamic>? ?? []);
    
    if (players.isNotEmpty) {
      // Create a Jack card and add to discard pile
      final jackCard = {
        'cardId': 'card_demo_jack_hearts_0',
        'rank': 'jack',
        'suit': 'hearts',
        'points': 10,
        'specialPower': 'switch_cards',
      };
      discardPile.insert(0, jackCard);

      players[0]['status'] = 'jack_swap';
      players[0]['isCurrentPlayer'] = true;
    }

    updatedState['players'] = players;
    updatedState['discardPile'] = discardPile;
    updatedState['currentPlayer'] = players.isNotEmpty ? {
      'id': players[0]['id'],
      'name': players[0]['name'],
      'status': 'jack_swap',
    } : null;

    // Update game state store
    final gameStateStore = GameStateStore.instance;
    gameStateStore.setGameState(gameId, updatedState);

    return updatedState;
  }

  /// Set up state for Call Dutch action
  /// Game should be started, player in playing_card status, finalRoundActive: false
  Future<Map<String, dynamic>> setupCallDutchState(
    String gameId,
    Map<String, dynamic> gameState,
  ) async {
    _logger.info('🎮 DemoStateSetup: Setting up call dutch state', isOn: LOGGING_SWITCH);

    // Set up playing state
    var updatedState = await setupPlayingState(gameId, gameState);

    // Ensure finalRoundActive is false and player hasn't called yet
    updatedState['finalRoundActive'] = false;
    updatedState['finalRoundCalledBy'] = null;

    final players = List<Map<String, dynamic>>.from(updatedState['players'] as List<dynamic>? ?? []);
    if (players.isNotEmpty) {
      players[0]['hasCalledFinalRound'] = false;
      players[0]['status'] = 'playing_card';
      players[0]['isCurrentPlayer'] = true;
    }

    updatedState['players'] = players;
    updatedState['currentPlayer'] = players.isNotEmpty ? {
      'id': players[0]['id'],
      'name': players[0]['name'],
      'status': 'playing_card',
    } : null;

    // Update game state store
    final gameStateStore = GameStateStore.instance;
    gameStateStore.setGameState(gameId, updatedState);

    return updatedState;
  }

  /// Set up state for Collect Rank action
  /// Game should be in initial_peek phase, collection mode enabled
  Future<Map<String, dynamic>> setupCollectRankState(
    String gameId,
    Map<String, dynamic> gameState,
  ) async {
    _logger.info('🎮 DemoStateSetup: Setting up collect rank state', isOn: LOGGING_SWITCH);

    // Set up initial peek state
    var updatedState = await setupInitialPeekState(gameId, gameState);

    // Ensure isClearAndCollect is true
    updatedState['isClearAndCollect'] = true;

    // Update game state store
    final gameStateStore = GameStateStore.instance;
    gameStateStore.setGameState(gameId, updatedState);

    return updatedState;
  }
}

