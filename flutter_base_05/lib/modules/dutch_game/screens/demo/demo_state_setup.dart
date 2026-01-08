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

    // Simulate drawing a card (get from draw pile - matches practice mode: removeLast from stack)
    final drawPile = List<Map<String, dynamic>>.from(updatedState['drawPile'] as List<dynamic>? ?? []);
    if (drawPile.isNotEmpty) {
      // Remove last card from draw pile (top of stack - matches practice mode)
      final idOnlyCard = drawPile.removeLast();
      final cardId = idOnlyCard['cardId']?.toString() ?? '';
      
      _logger.info('🎮 DemoStateSetup: Drawing card $cardId from draw pile', isOn: LOGGING_SWITCH);

      // Get full card data from originalDeck (draw pile has ID-only cards)
      Map<String, dynamic>? drawnCard;
      final originalDeck = updatedState['originalDeck'] as List<dynamic>? ?? [];
      
      // Search for card in originalDeck
      for (final card in originalDeck) {
        if (card is Map<String, dynamic>) {
          final cardIdInDeck = card['cardId']?.toString() ?? '';
          if (cardIdInDeck == cardId) {
            drawnCard = Map<String, dynamic>.from(card);
            _logger.info('✅ DemoStateSetup: Found full card data for $cardId', isOn: LOGGING_SWITCH);
            break;
          }
        }
      }

      // If not found in originalDeck, use the ID-only card (shouldn't happen with test deck)
      if (drawnCard == null) {
        _logger.warning('⚠️ DemoStateSetup: Card $cardId not found in originalDeck, using ID-only card', isOn: LOGGING_SWITCH);
        drawnCard = Map<String, dynamic>.from(idOnlyCard);
      }

      final players = List<Map<String, dynamic>>.from(updatedState['players'] as List<dynamic>? ?? []);
      if (players.isNotEmpty) {
        final player = players[0];
        final hand = List<dynamic>.from(player['hand'] as List<dynamic>? ?? []);
        
        // Add card to player's hand as ID-only (player hands always store ID-only cards)
        // IMPORTANT: Drawn cards ALWAYS go to the end of the hand (matches practice mode)
        final idOnlyCard = {
          'cardId': drawnCard['cardId'],
          'suit': '?',      // Face-down: hide suit
          'rank': '?',      // Face-down: hide rank
          'points': 0,      // Face-down: hide points
        };
        hand.add(idOnlyCard);
        
        // Set drawnCard with full data (matches practice mode)
        player['drawnCard'] = drawnCard;
        player['hand'] = hand;
        player['status'] = 'playing_card';
        player['isCurrentPlayer'] = true;
        
        _logger.info('✅ DemoStateSetup: Added drawn card to hand (now ${hand.length} cards)', isOn: LOGGING_SWITCH);
      }

      updatedState['drawPile'] = drawPile;
      updatedState['players'] = players;
      updatedState['currentPlayer'] = players.isNotEmpty ? {
        'id': players[0]['id'],
        'name': players[0]['name'],
        'status': 'playing_card',
      } : null;
      
      _logger.info('✅ DemoStateSetup: Playing state set up with drawn card: ${drawnCard['rank']} of ${drawnCard['suit']}', isOn: LOGGING_SWITCH);
    } else {
      _logger.warning('⚠️ DemoStateSetup: Draw pile is empty, cannot set up playing state with drawn card', isOn: LOGGING_SWITCH);
    }

    // Update game state store
    final gameStateStore = GameStateStore.instance;
    gameStateStore.setGameState(gameId, updatedState);

    return updatedState;
  }

  /// Set up state for Same Rank action
  /// Game should be in same_rank_window phase with discard pile having a card
  /// CRITICAL: Ensures player's hand has NO cards matching the discard pile top card's rank
  /// CRITICAL: Hand should only contain 4 face-down ID-only cards (no drawn card)
  Future<Map<String, dynamic>> setupSameRankState(
    String gameId,
    Map<String, dynamic> gameState,
  ) async {
    _logger.info('🎮 DemoStateSetup: Setting up same rank state', isOn: LOGGING_SWITCH);

    // Start from initial game state (NOT playing state) to ensure only 4 face-down cards
    // Get original deck to retrieve full card data
    final gameStateStore = GameStateStore.instance;
    final fullGameState = gameStateStore.getGameState(gameId);
    final originalDeck = fullGameState['originalDeck'] as List<dynamic>? ?? [];

    // Create updated state from initial game state
    final updatedState = Map<String, dynamic>.from(gameState);

    // Get players and ensure we start with initial state (4 cards, no drawn card)
    final players = List<Map<String, dynamic>>.from(gameState['players'] as List<dynamic>? ?? []);
    final discardPile = List<Map<String, dynamic>>.from(gameState['discardPile'] as List<dynamic>? ?? []);
    final drawPile = List<Map<String, dynamic>>.from(gameState['drawPile'] as List<dynamic>? ?? []);
    
    if (players.isNotEmpty && players[0]['hand'] != null) {
      // Get the initial 4 cards (ID-only, face-down)
      // Filter out any drawn card that might have been added
      final initialHand = List<Map<String, dynamic>>.from(players[0]['hand'] as List<dynamic>? ?? []);
      final hand = <Map<String, dynamic>>[];
      
      // Only keep ID-only cards (face-down cards have suit: '?', rank: '?', points: 0)
      // This ensures we only have the 4 initial cards, not any drawn card
      for (final card in initialHand) {
        final cardMap = card as Map<String, dynamic>?;
        if (cardMap != null) {
          final suit = cardMap['suit']?.toString();
          final rank = cardMap['rank']?.toString();
          // ID-only cards have '?' for suit and rank
          if (suit == '?' && rank == '?') {
            hand.add(Map<String, dynamic>.from(cardMap));
          }
        }
      }
      
      // Ensure we have exactly 4 cards (the initial deal)
      if (hand.length != 4) {
        _logger.warning('⚠️ DemoStateSetup: Expected 4 initial cards, found ${hand.length}. Using first 4.', isOn: LOGGING_SWITCH);
        hand.clear();
        for (int i = 0; i < 4 && i < initialHand.length; i++) {
          hand.add(Map<String, dynamic>.from(initialHand[i]));
        }
      }
      if (hand.isNotEmpty) {
        // Get full card data for all cards in hand
        final handFullData = <Map<String, dynamic>>[];
        for (final idOnlyCard in hand) {
          final cardId = idOnlyCard['cardId']?.toString() ?? '';
          Map<String, dynamic>? fullCard;
          try {
            fullCard = originalDeck.firstWhere(
              (card) => card is Map<String, dynamic> && card['cardId'] == cardId,
            ) as Map<String, dynamic>?;
          } catch (e) {
            // Card not found, skip
            fullCard = null;
          }
          if (fullCard != null) {
            handFullData.add(fullCard);
          }
        }

        // Find a card to play that has a unique rank (no other cards in hand have that rank)
        String? playedCardRank;
        int playedCardIndex = -1;
        
        for (int i = 0; i < handFullData.length; i++) {
          final candidateRank = handFullData[i]['rank']?.toString();
          if (candidateRank == null) continue;
          
          // Check if any other card in hand has the same rank
          bool hasMatchingRank = false;
          for (int j = 0; j < handFullData.length; j++) {
            if (i != j && handFullData[j]['rank']?.toString() == candidateRank) {
              hasMatchingRank = true;
              break;
            }
          }
          
          if (!hasMatchingRank) {
            // Found a card with unique rank - use this one
            playedCardRank = candidateRank;
            playedCardIndex = i;
            break;
          }
        }

        // If no unique rank card found, use first card and swap matching cards from hand
        if (playedCardIndex == -1) {
          playedCardIndex = 0;
          playedCardRank = handFullData[0]['rank']?.toString();
          _logger.warning('⚠️ DemoStateSetup: No unique rank card found, using first card (rank: $playedCardRank). Will swap matching cards.', isOn: LOGGING_SWITCH);
        }

        // Get the card to play (full data)
        final playedCardFullData = handFullData[playedCardIndex];
        
        // Remove played card from hand
        hand.removeAt(playedCardIndex);
        
        // Add to discard pile (with full data for face-up display)
        discardPile.insert(0, playedCardFullData);
        
        _logger.info('🎮 DemoStateSetup: Playing card with rank $playedCardRank to discard pile', isOn: LOGGING_SWITCH);

        // CRITICAL: Remove any cards from hand that match the played card's rank
        // Swap them with cards from draw pile that don't match
        final handToCheck = List<Map<String, dynamic>>.from(hand);
        final cardsToSwap = <int>[];
        
        for (int i = 0; i < handToCheck.length; i++) {
          final cardId = handToCheck[i]['cardId']?.toString() ?? '';
          Map<String, dynamic>? fullCard;
          try {
            fullCard = originalDeck.firstWhere(
              (card) => card is Map<String, dynamic> && card['cardId'] == cardId,
            ) as Map<String, dynamic>?;
          } catch (e) {
            // Card not found, skip
            fullCard = null;
          }
          
          if (fullCard != null) {
            final cardRank = fullCard['rank']?.toString();
            if (cardRank == playedCardRank) {
              cardsToSwap.add(i);
              _logger.info('⚠️ DemoStateSetup: Found matching rank card in hand (rank: $cardRank), will swap', isOn: LOGGING_SWITCH);
            }
          }
        }

        // Swap matching cards with cards from draw pile
        for (int swapIndex in cardsToSwap.reversed) {
          // Find a card from draw pile that doesn't match the played rank
          bool foundReplacement = false;
          for (int drawIndex = drawPile.length - 1; drawIndex >= 0; drawIndex--) {
            final drawCardId = drawPile[drawIndex]['cardId']?.toString() ?? '';
            Map<String, dynamic>? drawCardFull;
            try {
              drawCardFull = originalDeck.firstWhere(
                (card) => card is Map<String, dynamic> && card['cardId'] == drawCardId,
              ) as Map<String, dynamic>?;
            } catch (e) {
              // Card not found, skip
              drawCardFull = null;
            }
            
            if (drawCardFull != null) {
              final drawCardRank = drawCardFull['rank']?.toString();
              if (drawCardRank != playedCardRank) {
                // Found a replacement card - swap it
                final replacementCard = drawPile.removeAt(drawIndex);
                hand[swapIndex] = replacementCard; // Replace matching card
                foundReplacement = true;
                _logger.info('✅ DemoStateSetup: Swapped matching card (rank: $playedCardRank) with card from draw pile (rank: $drawCardRank)', isOn: LOGGING_SWITCH);
                break;
              }
            }
          }
          
          if (!foundReplacement) {
            // No replacement found - remove the matching card from hand
            hand.removeAt(swapIndex);
            _logger.warning('⚠️ DemoStateSetup: No replacement card found, removed matching card from hand', isOn: LOGGING_SWITCH);
          }
        }

        // Clear any drawnCard property (should not exist for same rank demo)
        players[0].remove('drawnCard');
        
        players[0]['hand'] = hand;
        players[0]['status'] = 'same_rank_window';
        players[0]['isCurrentPlayer'] = false; // Not current player during same rank window
        
        _logger.info('✅ DemoStateSetup: Same rank state set up. Hand has ${hand.length} face-down ID-only cards (no drawn card). Discard pile top: rank $playedCardRank.', isOn: LOGGING_SWITCH);
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
    updatedState['drawPile'] = drawPile; // Update draw pile if we removed cards
    updatedState['phase'] = 'same_rank_window';
    updatedState['currentPlayer'] = null; // No current player during same rank window

    // Update game state store
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

