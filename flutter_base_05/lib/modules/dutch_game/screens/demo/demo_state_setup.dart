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
  /// CRITICAL: Hand should only contain 4 face-down ID-only cards (no drawn card)
  Future<Map<String, dynamic>> setupQueenPeekState(
    String gameId,
    Map<String, dynamic> gameState,
  ) async {
    _logger.info('🎮 DemoStateSetup: Setting up queen peek state', isOn: LOGGING_SWITCH);

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

      // Clear any drawnCard property (should not exist for queen peek demo)
      players[0].remove('drawnCard');
      
      // Find a Queen card from the original deck to add to discard pile
      Map<String, dynamic>? queenCard;
      try {
        queenCard = originalDeck.firstWhere(
          (card) => card is Map<String, dynamic> && card['rank']?.toString().toLowerCase() == 'queen',
        ) as Map<String, dynamic>?;
      } catch (e) {
        // Queen not found in deck, create a placeholder
        _logger.warning('⚠️ DemoStateSetup: Queen not found in deck, creating placeholder', isOn: LOGGING_SWITCH);
        queenCard = {
          'cardId': 'card_demo_queen_hearts_0',
          'rank': 'queen',
          'suit': 'hearts',
          'points': 10,
          'specialPower': 'peek_at_card',
        };
      }
      
      if (queenCard != null) {
        // Add Queen to discard pile (with full data for face-up display)
        discardPile.insert(0, Map<String, dynamic>.from(queenCard));
        _logger.info('✅ DemoStateSetup: Added Queen to discard pile: ${queenCard['rank']} of ${queenCard['suit']}', isOn: LOGGING_SWITCH);
      }

      players[0]['hand'] = hand;
      players[0]['status'] = 'queen_peek';
      players[0]['isCurrentPlayer'] = true;
      
      _logger.info('✅ DemoStateSetup: Queen peek state set up. Hand has ${hand.length} face-down ID-only cards (no drawn card).', isOn: LOGGING_SWITCH);
    }

    updatedState['players'] = players;
    updatedState['discardPile'] = discardPile;
    updatedState['phase'] = 'playing';
    updatedState['currentPlayer'] = players.isNotEmpty ? {
      'id': players[0]['id'],
      'name': players[0]['name'],
      'status': 'queen_peek',
    } : null;

    // Update game state store
    gameStateStore.setGameState(gameId, updatedState);

    return updatedState;
  }

  /// Set up state for Jack Swap action
  /// Game should be started, player played Jack, in jack_swap status
  /// CRITICAL: Hand should only contain 4 face-down ID-only cards (no drawn card)
  Future<Map<String, dynamic>> setupJackSwapState(
    String gameId,
    Map<String, dynamic> gameState,
  ) async {
    _logger.info('🎮 DemoStateSetup: Setting up jack swap state', isOn: LOGGING_SWITCH);

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

      // Clear any drawnCard property (should not exist for jack swap demo)
      players[0].remove('drawnCard');
      
      // Find a Jack card from the original deck to add to discard pile
      Map<String, dynamic>? jackCard;
      try {
        jackCard = originalDeck.firstWhere(
          (card) => card is Map<String, dynamic> && card['rank']?.toString().toLowerCase() == 'jack',
        ) as Map<String, dynamic>?;
      } catch (e) {
        // Jack not found in deck, create a placeholder
        _logger.warning('⚠️ DemoStateSetup: Jack not found in deck, creating placeholder', isOn: LOGGING_SWITCH);
        jackCard = {
          'cardId': 'card_demo_jack_hearts_0',
          'rank': 'jack',
          'suit': 'hearts',
          'points': 10,
          'specialPower': 'switch_cards',
        };
      }
      
      if (jackCard != null) {
        // Add Jack to discard pile (with full data for face-up display)
        discardPile.insert(0, Map<String, dynamic>.from(jackCard));
        _logger.info('✅ DemoStateSetup: Added Jack to discard pile: ${jackCard['rank']} of ${jackCard['suit']}', isOn: LOGGING_SWITCH);
      }

      players[0]['hand'] = hand;
      players[0]['status'] = 'jack_swap';
      players[0]['isCurrentPlayer'] = true;
      
      _logger.info('✅ DemoStateSetup: Jack swap state set up. Hand has ${hand.length} face-down ID-only cards (no drawn card).', isOn: LOGGING_SWITCH);
    }

    updatedState['players'] = players;
    updatedState['discardPile'] = discardPile;
    updatedState['phase'] = 'playing';
    updatedState['currentPlayer'] = players.isNotEmpty ? {
      'id': players[0]['id'],
      'name': players[0]['name'],
      'status': 'jack_swap',
    } : null;

    // Update game state store
    gameStateStore.setGameState(gameId, updatedState);

    return updatedState;
  }

  /// Set up state for Call Dutch action
  /// Game should be started, player in playing_card status, finalRoundActive: false
  /// CRITICAL: Hand should only contain 4 face-down ID-only cards (no drawn card)
  Future<Map<String, dynamic>> setupCallDutchState(
    String gameId,
    Map<String, dynamic> gameState,
  ) async {
    _logger.info('🎮 DemoStateSetup: Setting up call dutch state', isOn: LOGGING_SWITCH);

    // Start from initial game state (NOT playing state) to ensure only 4 face-down cards
    final gameStateStore = GameStateStore.instance;

    // Create updated state from initial game state
    final updatedState = Map<String, dynamic>.from(gameState);

    // Get players and ensure we start with initial state (4 cards, no drawn card)
    final players = List<Map<String, dynamic>>.from(gameState['players'] as List<dynamic>? ?? []);
    
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

      // Clear any drawnCard property (should not exist for call dutch demo)
      players[0].remove('drawnCard');
      
      players[0]['hand'] = hand;
      players[0]['hasCalledFinalRound'] = false;
      players[0]['status'] = 'playing_card';
      players[0]['isCurrentPlayer'] = true;
      
      _logger.info('✅ DemoStateSetup: Call dutch state set up. Hand has ${hand.length} face-down ID-only cards (no drawn card).', isOn: LOGGING_SWITCH);
    }

    // Ensure finalRoundActive is false and player hasn't called yet
    updatedState['finalRoundActive'] = false;
    updatedState['finalRoundCalledBy'] = null;

    updatedState['players'] = players;
    updatedState['phase'] = 'playing';
    updatedState['currentPlayer'] = players.isNotEmpty ? {
      'id': players[0]['id'],
      'name': players[0]['name'],
      'status': 'playing_card',
    } : null;

    // Update game state store
    gameStateStore.setGameState(gameId, updatedState);

    return updatedState;
  }

  /// Set up state for Collect Rank action
  /// Game should be in playing phase with discard pile having a card matching collection rank
  /// CRITICAL: Sets up collection mode with predefined collection rank and collection cards
  Future<Map<String, dynamic>> setupCollectRankState(
    String gameId,
    Map<String, dynamic> gameState,
  ) async {
    _logger.info('🎮 DemoStateSetup: Setting up collect rank state', isOn: LOGGING_SWITCH);

    // Get original deck to retrieve full card data
    final gameStateStore = GameStateStore.instance;
    final fullGameState = gameStateStore.getGameState(gameId);
    final originalDeck = fullGameState['originalDeck'] as List<dynamic>? ?? [];

    // Create updated state from initial game state
    final updatedState = Map<String, dynamic>.from(gameState);

    // CRITICAL: Set isClearAndCollect to true for collection mode
    updatedState['isClearAndCollect'] = true;

    // Get players and discard pile
    final players = List<Map<String, dynamic>>.from(gameState['players'] as List<dynamic>? ?? []);
    final discardPile = List<Map<String, dynamic>>.from(gameState['discardPile'] as List<dynamic>? ?? []);
    final drawPile = List<Map<String, dynamic>>.from(gameState['drawPile'] as List<dynamic>? ?? []);
    
    if (players.isNotEmpty && players[0]['hand'] != null) {
      // Get the initial 4 cards (ID-only, face-down)
      final initialHand = List<Map<String, dynamic>>.from(players[0]['hand'] as List<dynamic>? ?? []);
      final hand = <Map<String, dynamic>>[];
      
      // Only keep ID-only cards (face-down cards have suit: '?', rank: '?', points: 0)
      for (final card in initialHand) {
        final cardMap = card as Map<String, dynamic>?;
        if (cardMap != null) {
          final suit = cardMap['suit']?.toString();
          final rank = cardMap['rank']?.toString();
          if (suit == '?' && rank == '?') {
            hand.add(Map<String, dynamic>.from(cardMap));
          }
        }
      }
      
      // Ensure we have exactly 4 cards
      if (hand.length != 4) {
        _logger.warning('⚠️ DemoStateSetup: Expected 4 initial cards, found ${hand.length}. Using first 4.', isOn: LOGGING_SWITCH);
        hand.clear();
        for (int i = 0; i < 4 && i < initialHand.length; i++) {
          hand.add(Map<String, dynamic>.from(initialHand[i]));
        }
      }

      // Clear any drawnCard property
      players[0].remove('drawnCard');

      // Choose a collection rank (e.g., "ace" - low points, common)
      // First, find a suitable collection rank card from the player's hand or deck
      String collectionRank = 'ace';
      Map<String, dynamic>? collectionCard;
      
      // Try to find a card in hand that we can use as collection rank
      // Prefer ace, then 2, then 3, etc. (low points)
      final preferredRanks = ['ace', '2', '3', '4', '5'];
      
      for (final preferredRank in preferredRanks) {
        // Check if any card in hand matches this rank
        for (final handCard in hand) {
          final cardId = handCard['cardId']?.toString() ?? '';
          // Get full card data from original deck
          try {
            final fullCard = originalDeck.firstWhere(
              (card) => card is Map<String, dynamic> && card['cardId'] == cardId,
            ) as Map<String, dynamic>?;
            
            if (fullCard != null && fullCard['rank']?.toString().toLowerCase() == preferredRank) {
              collectionRank = preferredRank;
              collectionCard = Map<String, dynamic>.from(fullCard);
              _logger.info('✅ DemoStateSetup: Found collection rank card in hand: ${collectionCard['rank']} of ${collectionCard['suit']}', isOn: LOGGING_SWITCH);
              break;
            }
          } catch (e) {
            // Card not found, continue
          }
        }
        if (collectionCard != null) break;
      }
      
      // If no suitable card found in hand, use first ace from deck
      if (collectionCard == null) {
        try {
          collectionCard = originalDeck.firstWhere(
            (card) => card is Map<String, dynamic> && card['rank']?.toString().toLowerCase() == 'ace',
          ) as Map<String, dynamic>?;
          if (collectionCard != null) {
            collectionRank = 'ace';
            // Replace first card in hand with this collection card (as ID-only)
            if (hand.isNotEmpty) {
              hand[0] = {
                'cardId': collectionCard['cardId'],
                'suit': '?',
                'rank': '?',
                'points': 0,
              };
            }
            _logger.info('✅ DemoStateSetup: Added collection card to hand: ${collectionCard['rank']} of ${collectionCard['suit']}', isOn: LOGGING_SWITCH);
          }
        } catch (e) {
          _logger.warning('⚠️ DemoStateSetup: Could not find ace card in deck', isOn: LOGGING_SWITCH);
        }
      }

      // Ensure discard pile has a card with the same rank as collection rank
      Map<String, dynamic>? discardTopCard;
      
      if (discardPile.isNotEmpty) {
        discardTopCard = Map<String, dynamic>.from(discardPile.last);
        final discardRank = discardTopCard['rank']?.toString().toLowerCase();
        
        // If discard pile top card doesn't match collection rank, replace it
        if (discardRank != collectionRank.toLowerCase()) {
          // Find a card with collection rank from deck (not the collection card itself)
          Map<String, dynamic>? matchingCard;
          try {
            matchingCard = originalDeck.firstWhere(
              (card) => card is Map<String, dynamic> && 
                       card['rank']?.toString().toLowerCase() == collectionRank.toLowerCase() &&
                       card['cardId'] != collectionCard?['cardId'],
            ) as Map<String, dynamic>?;
          } catch (e) {
            // No matching card found, use collection card
            matchingCard = collectionCard;
          }
          
          if (matchingCard != null) {
            discardPile.clear();
            discardPile.add(Map<String, dynamic>.from(matchingCard));
            discardTopCard = matchingCard;
            _logger.info('✅ DemoStateSetup: Set discard pile top card to match collection rank: ${matchingCard['rank']} of ${matchingCard['suit']}', isOn: LOGGING_SWITCH);
          }
        } else {
          _logger.info('✅ DemoStateSetup: Discard pile top card already matches collection rank: $collectionRank', isOn: LOGGING_SWITCH);
        }
      } else {
        // No discard pile, create one with a card matching collection rank
        Map<String, dynamic>? matchingCard;
        try {
          matchingCard = originalDeck.firstWhere(
            (card) => card is Map<String, dynamic> && 
                     card['rank']?.toString().toLowerCase() == collectionRank.toLowerCase() &&
                     card['cardId'] != collectionCard?['cardId'],
          ) as Map<String, dynamic>?;
        } catch (e) {
          // No matching card found, use collection card
          matchingCard = collectionCard;
        }
        
        if (matchingCard != null) {
          discardPile.add(Map<String, dynamic>.from(matchingCard));
          discardTopCard = matchingCard;
          _logger.info('✅ DemoStateSetup: Created discard pile with card matching collection rank: ${matchingCard['rank']} of ${matchingCard['suit']}', isOn: LOGGING_SWITCH);
        }
      }

      // Set up collection rank cards for the player
      // Add the collection card to collection_rank_cards (the collection card that's face-up)
      final collectionRankCards = <Map<String, dynamic>>[];
      
      if (collectionCard != null) {
        collectionRankCards.add(Map<String, dynamic>.from(collectionCard));
        _logger.info('✅ DemoStateSetup: Added collection card to collection_rank_cards: ${collectionCard['rank']} of ${collectionCard['suit']}', isOn: LOGGING_SWITCH);
      }

      // Set player's collection rank and collection cards
      players[0]['collection_rank'] = collectionRank;
      players[0]['collection_rank_cards'] = collectionRankCards;
      players[0]['hand'] = hand;
      players[0]['status'] = 'waiting'; // Player can collect during waiting status
      players[0]['isCurrentPlayer'] = false;

      _logger.info('✅ DemoStateSetup: Collect rank state set up. Collection rank: $collectionRank, Collection cards: ${collectionRankCards.length}, Discard pile top: ${discardTopCard?['rank'] ?? "none"}', isOn: LOGGING_SWITCH);
    }

    updatedState['players'] = players;
    updatedState['discardPile'] = discardPile;
    updatedState['drawPile'] = drawPile;
    updatedState['phase'] = 'playing';
    updatedState['currentPlayer'] = null; // No current player during collection phase

    // Update game state store
    gameStateStore.setGameState(gameId, updatedState);

    return updatedState;
  }
}

