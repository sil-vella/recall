import 'dart:async';
import 'package:dutch/tools/logging/logger.dart';
import '../../../../core/managers/state_manager.dart';
import '../../managers/dutch_game_state_updater.dart';

const bool LOGGING_SWITCH = false; // Enabled for demo debugging

/// Demo Phase Instructions
/// 
/// Contains title and paragraph for each demo phase.
class DemoPhaseInstruction {
  final String phase;
  final String title;
  final String paragraph;
  final bool hasButton;

  DemoPhaseInstruction({
    required this.phase,
    required this.title,
    required this.paragraph,
    this.hasButton = false,
  });

  Map<String, dynamic> toMap() => {
    'phase': phase,
    'title': title,
    'paragraph': paragraph,
    'hasButton': hasButton,
  };
}

/// Demo Functionality
/// 
/// Handles all demo-specific game logic and state updates.
/// This intercepts player actions in demo mode and provides demo-specific behavior.
class DemoFunctionality {
  static DemoFunctionality? _instance;
  static DemoFunctionality get instance {
    _instance ??= DemoFunctionality._internal();
    return _instance!;
  }

  DemoFunctionality._internal();

  final Logger _logger = Logger();

  // Track selected card IDs for initial peek
  final Set<String> _initialPeekSelectedCardIds = {};
  
  // Timer for showing drawing instructions after both cards are selected
  Timer? _drawingInstructionsTimer;
  
  // Timer for showing same rank instructions after opponent plays
  Timer? _sameRankInstructionsTimer;
  
  // Timer for same rank window (5 seconds, like practice mode)
  Timer? _sameRankWindowTimer;

  // Timer for queen peek card display (3 seconds to show the peeked card before updating hand)
  Timer? _queenPeekTimer;

  /// List of demo phase instructions
  /// Each phase has a title and paragraph explaining what to do
  final List<DemoPhaseInstruction> _demoPhaseInstructions = [
    DemoPhaseInstruction(
      phase: 'initial',
      title: 'Welcome to the Demo',
      paragraph: 'Let\'s go through a quick demo. The goal is to end the game with no cards or least points possible.',
      hasButton: true,
    ),
    DemoPhaseInstruction(
      phase: 'initial_peek',
      title: 'Initial Peek Phase',
      paragraph: 'You have 4 cards face down. You can peek at any 2 of them to see what they are. Select 2 cards to peek at.',
    ),
    DemoPhaseInstruction(
      phase: 'drawing',
      title: 'Drawing Phase',
      paragraph: 'It\'s your turn! You can either draw a card from the draw pile (face down) or take the top card from the discard pile (face up). Choose where to get your card from.',
    ),
    DemoPhaseInstruction(
      phase: 'playing',
      title: 'Playing Phase',
      paragraph: 'After drawing, you can play a card from your hand. You can choose to play any card including the new draw card.',
    ),
    DemoPhaseInstruction(
      phase: 'same_rank',
      title: 'Same Rank Window',
      paragraph: 'An opponent has played a card of the same rank, and now they have 3 cards left. During same rank window any player can play a card of the same rank. If an incorrect rank is attempted, that player will be given an extra penalty card.',
    ),
    DemoPhaseInstruction(
      phase: 'wrong_same_rank_penalty',
      title: 'You played a wrong rank',
      paragraph: 'When playing a wrong rank in the same rank window you will be given an extra penalty card. Now you have 5 cards. Next we will wait for your opponents to play their turns.',
      hasButton: true, // Show "Let's go" button
    ),
    DemoPhaseInstruction(
      phase: 'special_plays',
      title: 'Special Plays',
      paragraph: 'When a queen or a jack is played, that player will have a special play.',
    ),
    DemoPhaseInstruction(
      phase: 'jack_swap',
      title: 'Jack Special Power',
      paragraph: 'You played a Jack! You can now swap any two cards between any players. Select the two cards you want to swap.',
    ),
    DemoPhaseInstruction(
      phase: 'queen_peek',
      title: 'Queen Peek:',
      paragraph: 'When a queen is played, that player can take a quick peek at any card from any player\'s hand, including their own.',
    ),
    DemoPhaseInstruction(
      phase: 'call_dutch',
      title: 'Call Dutch',
      paragraph: 'When it\'s your turn to play, you will be shown a \'Call Dutch\' button in your hand. Tapping it will start the final round of plays where each player will have one final turn. At the end, the winner is decided by these criteria, in order:\n\n1. Fewest points\n2. Fewest points with fewest cards\n3. Fewest points with fewest cards, and Dutch caller\n4. Draw if same number of cards and points, and no Dutch caller\n\nThe game can always end early when a player ends up with 0 cards, as they are automatically declared the winner(s). Tap \'Call Dutch\' then play a card to start the final round.',
    ),
  ];

  /// Handle a player action in demo mode
  /// Routes actions to demo-specific handlers instead of backend/WebSocket
  Future<Map<String, dynamic>> handleAction(
    String actionType,
    Map<String, dynamic> payload,
  ) async {
    try {
      _logger.info('🎮 DemoFunctionality: ========== HANDLING ACTION ==========', isOn: LOGGING_SWITCH);
      _logger.info('🎮 DemoFunctionality: Action type: "$actionType"', isOn: LOGGING_SWITCH);
      _logger.info('🎮 DemoFunctionality: Payload: $payload', isOn: LOGGING_SWITCH);
      _logger.info('🎮 DemoFunctionality: Action type check - play_card match: ${actionType == 'play_card'}', isOn: LOGGING_SWITCH);
      _logger.info('🎮 DemoFunctionality: Action type length: ${actionType.length}, play_card length: ${'play_card'.length}', isOn: LOGGING_SWITCH);

      // Route to specific action handlers
      switch (actionType) {
        case 'draw_card':
          return await _handleDrawCard(payload);
        case 'play_card':
          return await _handlePlayCard(payload);
        case 'replace_drawn_card':
          return await _handleReplaceDrawnCard(payload);
        case 'play_drawn_card':
          return await _handlePlayDrawnCard(payload);
        case 'initial_peek':
          return await _handleInitialPeek(payload);
        case 'completed_initial_peek':
          return await _handleCompletedInitialPeek(payload);
        case 'call_final_round':
          return await _handleCallFinalRound(payload);
        case 'collect_from_discard':
          return await _handleCollectFromDiscard(payload);
        case 'use_special_power':
          return await _handleUseSpecialPower(payload);
        case 'jack_swap':
          return await _handleJackSwap(payload);
        case 'queen_peek':
          return await _handleQueenPeek(payload);
        case 'play_out_of_turn':
          return await _handlePlayOutOfTurn(payload);
        case 'same_rank_play':
          return await _handleSameRankPlay(payload);
        default:
          _logger.warning('⚠️ DemoFunctionality: Unknown action type: $actionType', isOn: LOGGING_SWITCH);
          return {'success': false, 'error': 'Unknown action type'};
      }
    } catch (e, stackTrace) {
      _logger.error('❌ DemoFunctionality: Error handling action $actionType: $e', error: e, stackTrace: stackTrace, isOn: LOGGING_SWITCH);
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Handle draw card action in demo mode
  /// Intercepts PlayerAction.playerDraw() which sends event 'draw_card' with payload:
  /// - source: 'deck' (for draw_pile) or 'discard' (for discard_pile)
  /// - game_id: gameId
  /// - player_id: auto-added by event emitter
  Future<Map<String, dynamic>> _handleDrawCard(Map<String, dynamic> payload) async {
    _logger.info('🎮 DemoFunctionality: Draw card action intercepted', isOn: LOGGING_SWITCH);
    _logger.info('🎮 DemoFunctionality: Payload: $payload', isOn: LOGGING_SWITCH);
    
    // PlayerAction.playerDraw() sends 'source' as 'deck' or 'discard'
    // Also check for 'pile_type' or 'pileType' for backward compatibility
    final source = payload['source']?.toString() ?? '';
    final pileType = payload['pile_type']?.toString() ?? payload['pileType']?.toString() ?? '';
    
    // Map source to pileType (or use pileType if provided)
    String actualPileType;
    if (source == 'deck' || pileType == 'draw_pile' || pileType == 'deck') {
      actualPileType = 'draw_pile';
    } else if (source == 'discard' || pileType == 'discard_pile' || pileType == 'discard') {
      actualPileType = 'discard_pile';
    } else {
      actualPileType = 'draw_pile'; // Default to draw pile
    }
    
    _logger.info('🎮 DemoFunctionality: Drawing from pile: $actualPileType (source: $source, pileType: $pileType)', isOn: LOGGING_SWITCH);
    
    final stateManager = StateManager();
    final dutchGameState = stateManager.getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final games = dutchGameState['games'] as Map<String, dynamic>? ?? {};
    final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
    
    if (currentGameId.isEmpty) {
      _logger.error('❌ DemoFunctionality: No currentGameId found', isOn: LOGGING_SWITCH);
      return {'success': false, 'error': 'No active game'};
    }
    
    final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
    final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
    final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
    
    Map<String, dynamic>? drawnCard;
    
    if (actualPileType == 'draw_pile') {
      // Draw from draw pile
      final drawPile = gameState['drawPile'] as List<dynamic>? ?? [];
      if (drawPile.isEmpty) {
        _logger.error('❌ DemoFunctionality: Draw pile is empty', isOn: LOGGING_SWITCH);
        return {'success': false, 'error': 'Draw pile is empty'};
      }
      
      // Remove last card from draw pile (top of stack)
      final idOnlyCard = drawPile.removeLast() as Map<String, dynamic>;
      final cardId = idOnlyCard['cardId']?.toString() ?? '';
      
      _logger.info('🎮 DemoFunctionality: Drew ID-only card $cardId from draw pile', isOn: LOGGING_SWITCH);
      
      // Get full card data from originalDeck
      drawnCard = _getCardById(cardId);
      if (drawnCard == null) {
        _logger.error('❌ DemoFunctionality: Failed to get full card data for $cardId', isOn: LOGGING_SWITCH);
        return {'success': false, 'error': 'Failed to get card data'};
      }
      
      // Update draw pile in game state
      gameState['drawPile'] = drawPile;
      
    } else if (actualPileType == 'discard_pile') {
      // Take from discard pile
      final discardPile = gameState['discardPile'] as List<dynamic>? ?? [];
      if (discardPile.isEmpty) {
        _logger.error('❌ DemoFunctionality: Discard pile is empty', isOn: LOGGING_SWITCH);
        return {'success': false, 'error': 'Discard pile is empty'};
      }
      
      // Remove last card from discard pile (top of stack) - already has full data
      drawnCard = Map<String, dynamic>.from(discardPile.removeLast() as Map<String, dynamic>);
      final cardId = drawnCard['cardId']?.toString() ?? '';
      
      _logger.info('🎮 DemoFunctionality: Drew card $cardId from discard pile', isOn: LOGGING_SWITCH);
      
      // Update discard pile in game state
      gameState['discardPile'] = discardPile;
    } else {
      _logger.error('❌ DemoFunctionality: Invalid pile type: $actualPileType', isOn: LOGGING_SWITCH);
      return {'success': false, 'error': 'Invalid pile type'};
    }
    
    // At this point, drawnCard is guaranteed to be non-null:
    // - Draw pile branch: validated and returned early if null
    // - Discard pile branch: removeLast() always returns a Map
    
    // Find current player in game state and add card to hand
    final players = gameState['players'] as List<dynamic>? ?? [];
    
    // Find human player (demo mode always has one human player)
    int playerIndex = -1;
    Map<String, dynamic>? player;
    for (int i = 0; i < players.length; i++) {
      final p = players[i];
      if (p is Map<String, dynamic> && p['isHuman'] == true) {
        playerIndex = i;
        player = p;
        break;
      }
    }
    
    if (playerIndex == -1 || player == null) {
      _logger.error('❌ DemoFunctionality: Human player not found in players list', isOn: LOGGING_SWITCH);
      return {'success': false, 'error': 'Human player not found'};
    }
    final hand = player['hand'] as List<dynamic>? ?? [];
    
    // Convert drawn card to ID-only format (player hands always store ID-only cards)
    // Format matches practice mode: {'cardId': 'xxx', 'suit': '?', 'rank': '?', 'points': 0}
    final idOnlyCard = {
      'cardId': drawnCard['cardId'],
      'suit': '?',      // Face-down: hide suit
      'rank': '?',      // Face-down: hide rank
      'points': 0,      // Face-down: hide points
    };
    
    // IMPORTANT: Drawn cards ALWAYS go to the end of the hand (not in blank slots)
    // This matches practice mode logic
    hand.add(idOnlyCard);
    player['hand'] = hand;
    
    // Update player status to 'playing_card' (matches practice mode)
    player['status'] = 'playing_card';
    
    // Update myHandCards in games map (widgets read from this)
    final myHandCards = List<Map<String, dynamic>>.from(hand.map((c) {
      if (c is Map<String, dynamic>) {
        return Map<String, dynamic>.from(c);
      }
      return <String, dynamic>{};
    }));
    currentGame['myHandCards'] = myHandCards;
    
    // Update widget slices
    final centerBoard = dutchGameState['centerBoard'] as Map<String, dynamic>? ?? {};
    centerBoard['playerStatus'] = 'playing_card';
    
    final myHand = dutchGameState['myHand'] as Map<String, dynamic>? ?? {};
    myHand['playerStatus'] = 'playing_card';
    myHand['cards'] = myHandCards; // Update cards in myHand slice
    
    // Update state with all changes using official state updater
    // NOTE: Keep myDrawnCard in state - the unified widget uses it to show full data for the drawn card in hand
    // The card in hand is ID-only, but the widget will use myDrawnCard full data if IDs match
    final stateUpdater = DutchGameStateUpdater.instance;
    stateUpdater.updateStateSync({
      'myDrawnCard': drawnCard, // Keep drawn card with full data (widget uses it to show card face-up in hand)
      'playerStatus': 'playing_card', // Update main state
      'currentPlayerStatus': 'playing_card',
      'games': games, // Update games map with modified game state
      'lastUpdated': DateTime.now().toIso8601String(),
    });
    
    // Update widget slices and UI-only fields using state updater
    stateUpdater.updateStateSync({
      'demoInstructionsPhase': 'playing', // Transition to playing phase
      'centerBoard': centerBoard, // Update centerBoard slice
      'myHand': myHand, // Update myHand slice with new status and cards
    });
    
    _logger.info('✅ DemoFunctionality: Card drawn successfully: ${drawnCard['rank']} of ${drawnCard['suit']}', isOn: LOGGING_SWITCH);
    _logger.info('✅ DemoFunctionality: Added card to hand (now ${hand.length} cards)', isOn: LOGGING_SWITCH);
    _logger.info('✅ DemoFunctionality: Updated player status to playing_card', isOn: LOGGING_SWITCH);
    _logger.info('✅ DemoFunctionality: Transitioned to playing phase', isOn: LOGGING_SWITCH);
    
    return {'success': true, 'mode': 'demo', 'drawnCard': drawnCard};
  }

  /// Handle play card action in demo mode
  /// Intercepts PlayerAction.playerPlayCard() which sends event 'play_card' with payload:
  /// - card_id: Card ID to play
  /// - game_id: Current game ID
  /// - player_id: Auto-added by event emitter
  Future<Map<String, dynamic>> _handlePlayCard(Map<String, dynamic> payload) async {
    _logger.info('🎮 DemoFunctionality: ========== PLAY CARD ACTION INTERCEPTED ==========', isOn: LOGGING_SWITCH);
    _logger.info('🎮 DemoFunctionality: Play card action intercepted', isOn: LOGGING_SWITCH);
    _logger.info('🎮 DemoFunctionality: Payload: $payload', isOn: LOGGING_SWITCH);
    
    final cardId = payload['card_id']?.toString() ?? payload['cardId']?.toString() ?? '';
    _logger.info('🎮 DemoFunctionality: Extracted cardId: "$cardId"', isOn: LOGGING_SWITCH);
    if (cardId.isEmpty) {
      _logger.error('❌ DemoFunctionality: Invalid card_id in play card payload', isOn: LOGGING_SWITCH);
      return {'success': false, 'error': 'Invalid card_id'};
    }
    
    final stateManager = StateManager();
    final dutchGameState = stateManager.getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final games = dutchGameState['games'] as Map<String, dynamic>? ?? {};
    final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
    
    if (currentGameId.isEmpty) {
      _logger.error('❌ DemoFunctionality: No currentGameId found', isOn: LOGGING_SWITCH);
      return {'success': false, 'error': 'No active game'};
    }
    
    final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
    final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
    final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
    
    // Find human player
    final players = gameState['players'] as List<dynamic>? ?? [];
    int playerIndex = -1;
    Map<String, dynamic>? player;
    for (int i = 0; i < players.length; i++) {
      final p = players[i];
      if (p is Map<String, dynamic> && p['isHuman'] == true) {
        playerIndex = i;
        player = p;
        break;
      }
    }
    
    if (playerIndex == -1 || player == null) {
      _logger.error('❌ DemoFunctionality: Human player not found', isOn: LOGGING_SWITCH);
      return {'success': false, 'error': 'Human player not found'};
    }
    
    // Get hand and convert to mutable list (matches practice mode)
    final handRaw = player['hand'] as List<dynamic>? ?? [];
    final hand = List<dynamic>.from(handRaw); // Convert to mutable list to allow nulls
    
    // Get drawnCard from state (same as draw handler) - it's stored in myDrawnCard, not in player object
    final drawnCard = dutchGameState['myDrawnCard'] as Map<String, dynamic>?;
    
    // Find card index in hand (matches practice mode logic)
    _logger.info('🎮 DemoFunctionality: Searching for card $cardId in hand (hand length: ${hand.length})', isOn: LOGGING_SWITCH);
    int cardIndex = -1;
    for (int i = 0; i < hand.length; i++) {
      final card = hand[i];
      if (card != null && card is Map<String, dynamic>) {
        final cardIdInHand = card['cardId']?.toString() ?? '';
        _logger.info('🎮 DemoFunctionality: Hand[$i]: cardId=$cardIdInHand, searching for=$cardId, match=${cardIdInHand == cardId}', isOn: LOGGING_SWITCH);
        // Check for null first (blank slots), then check if it's a map, then compare cardId
        // Matches practice mode: if (card != null && card is Map<String, dynamic> && card['cardId'] == cardId)
        if (cardIdInHand == cardId) {
          cardIndex = i;
          _logger.info('✅ DemoFunctionality: Found card $cardId at index $cardIndex', isOn: LOGGING_SWITCH);
          break;
        }
      } else if (card == null) {
        _logger.info('🎮 DemoFunctionality: Hand[$i]: null (blank slot)', isOn: LOGGING_SWITCH);
      }
    }
    
    if (cardIndex == -1) {
      _logger.error('❌ DemoFunctionality: Card $cardId not found in hand', isOn: LOGGING_SWITCH);
      _logger.error('❌ DemoFunctionality: Hand contents: ${hand.map((c) => c is Map ? c['cardId'] : 'null').toList()}', isOn: LOGGING_SWITCH);
      return {'success': false, 'error': 'Card not found in hand'};
    }
    
    // Get full card data for discard pile
    final cardToPlayFullData = _getCardById(cardId);
    if (cardToPlayFullData == null) {
      _logger.error('❌ DemoFunctionality: Failed to get full card data for $cardId', isOn: LOGGING_SWITCH);
      return {'success': false, 'error': 'Failed to get card data'};
    }
    
    _logger.info('🎮 DemoFunctionality: Card data retrieved: ${cardToPlayFullData.toString()}', isOn: LOGGING_SWITCH);
    
    // Check if played card is a queen - if so, route to queen-specific logic
    final cardRank = cardToPlayFullData['rank']?.toString() ?? '';
    _logger.info('🎮 DemoFunctionality: Card rank: "$cardRank" (checking for "queen" or "jack")', isOn: LOGGING_SWITCH);
    if (cardRank == 'queen') {
      _logger.info('🎮 DemoFunctionality: Queen detected, routing to queen play logic', isOn: LOGGING_SWITCH);
      return await _handleQueenPlay(payload, cardToPlayFullData, player, hand, gameState, games, currentGameId, dutchGameState);
    } else if (cardRank == 'jack') {
      _logger.info('🎮 DemoFunctionality: Jack detected, routing to jack play logic', isOn: LOGGING_SWITCH);
      return await _handleJackPlay(payload, cardToPlayFullData, player, hand, gameState, games, currentGameId, dutchGameState);
    } else {
      _logger.info('🎮 DemoFunctionality: Not a queen or jack (rank: "$cardRank"), continuing with regular play logic', isOn: LOGGING_SWITCH);
    }
    
    // Check if played card is the drawn card
    final isDrawnCard = drawnCard != null && drawnCard['cardId']?.toString() == cardId;
    
    // Determine if we should create a blank slot or remove the card entirely
    // Matches practice mode logic: blank slots for indices 0-3, remove for index 4+ (if no cards after)
    bool shouldCreateBlankSlot = cardIndex <= 3;
    if (cardIndex > 3) {
      // For index 4+, only create blank slot if there are cards after this index
      for (int i = cardIndex + 1; i < hand.length; i++) {
        if (hand[i] != null) {
          shouldCreateBlankSlot = true;
          break;
        }
      }
    }
    
    // Remove card from hand (matches practice mode behavior)
    if (shouldCreateBlankSlot) {
      hand[cardIndex] = null; // Create blank slot to maintain structure
      _logger.info('✅ DemoFunctionality: Created blank slot at index $cardIndex', isOn: LOGGING_SWITCH);
    } else {
      hand.removeAt(cardIndex); // Remove entirely and shift remaining cards
      _logger.info('✅ DemoFunctionality: Removed card entirely from index $cardIndex', isOn: LOGGING_SWITCH);
    }
    
    // Handle drawn card repositioning if it wasn't played
    if (drawnCard != null && !isDrawnCard) {
      // Find drawn card in hand and remove it
      int? drawnCardOriginalIndex;
      for (int i = 0; i < hand.length; i++) {
        final card = hand[i];
        if (card is Map<String, dynamic> && card['cardId']?.toString() == drawnCard['cardId']?.toString()) {
          drawnCardOriginalIndex = i;
          break;
        }
      }
      
      if (drawnCardOriginalIndex != null) {
        // Apply smart blank slot logic to the original position (matches practice mode)
        bool shouldKeepOriginalSlot = drawnCardOriginalIndex <= 3;
        if (drawnCardOriginalIndex > 3) {
          for (int i = drawnCardOriginalIndex + 1; i < hand.length; i++) {
            if (hand[i] != null) {
              shouldKeepOriginalSlot = true;
              break;
            }
          }
        }
        
        if (shouldKeepOriginalSlot) {
          hand[drawnCardOriginalIndex] = null; // Create blank slot
          _logger.info('✅ DemoFunctionality: Created blank slot at original position $drawnCardOriginalIndex', isOn: LOGGING_SWITCH);
        } else {
          hand.removeAt(drawnCardOriginalIndex); // Remove entirely
          _logger.info('✅ DemoFunctionality: Removed drawn card entirely from original position $drawnCardOriginalIndex', isOn: LOGGING_SWITCH);
          // Adjust cardIndex if we removed a card before it
          if (drawnCardOriginalIndex < cardIndex) {
            cardIndex -= 1;
          }
        }
        
        // Place drawn card in blank slot left by played card (convert to ID-only)
        final drawnCardIdOnly = {
          'cardId': drawnCard['cardId'],
          'suit': '?',
          'rank': '?',
          'points': 0,
        };
        
        // Apply smart blank slot logic to the target position (matches practice mode)
        bool shouldPlaceInSlot = cardIndex <= 3;
        if (cardIndex > 3) {
          for (int i = cardIndex + 1; i < hand.length; i++) {
            if (hand[i] != null) {
              shouldPlaceInSlot = true;
              break;
            }
          }
        }
        
        if (shouldPlaceInSlot) {
          // Place in blank slot left by played card
          if (cardIndex < hand.length) {
            hand[cardIndex] = drawnCardIdOnly;
            _logger.info('✅ DemoFunctionality: Placed drawn card in blank slot at index $cardIndex', isOn: LOGGING_SWITCH);
          } else {
            hand.insert(cardIndex, drawnCardIdOnly);
            _logger.info('✅ DemoFunctionality: Inserted drawn card at index $cardIndex', isOn: LOGGING_SWITCH);
          }
        } else {
          // Append to end if slot shouldn't exist
          hand.add(drawnCardIdOnly);
          _logger.info('✅ DemoFunctionality: Appended drawn card to end of hand', isOn: LOGGING_SWITCH);
        }
      }
    }
    
    // Remove drawnCard property (card is now in hand or discarded)
    player.remove('drawnCard');
    
    // Update player's hand
    player['hand'] = hand;
    
    // Add card to discard pile
    final discardPile = gameState['discardPile'] as List<dynamic>? ?? [];
    discardPile.add(cardToPlayFullData);
    gameState['discardPile'] = discardPile;
    
    // Update all players' status to 'same_rank_window' (matches practice mode)
    for (var p in players) {
      if (p is Map<String, dynamic>) {
        p['status'] = 'same_rank_window';
      }
    }
    
    // Update myHandCards in games map
    final myHandCards = List<Map<String, dynamic>>.from(hand.map((c) {
      if (c is Map<String, dynamic>) {
        return Map<String, dynamic>.from(c);
      }
      return <String, dynamic>{};
    }));
    currentGame['myHandCards'] = myHandCards;
    
    // Update widget slices
    final centerBoard = dutchGameState['centerBoard'] as Map<String, dynamic>? ?? {};
    centerBoard['playerStatus'] = 'same_rank_window';
    
    final myHand = dutchGameState['myHand'] as Map<String, dynamic>? ?? {};
    myHand['playerStatus'] = 'same_rank_window';
    myHand['cards'] = myHandCards;
    
    // Update state with all changes using official state updater
    final stateUpdater = DutchGameStateUpdater.instance;
    stateUpdater.updateStateSync({
      'playerStatus': 'same_rank_window', // Update main state
      'currentPlayerStatus': 'same_rank_window',
      'games': games, // Update games map with modified game state
      'discardPile': discardPile, // Update discard pile
      'lastUpdated': DateTime.now().toIso8601String(),
    });
    
    // Cancel any pending same rank instructions timer (player is playing, not waiting for opponent)
    _sameRankInstructionsTimer?.cancel();
    
    // Don't show instructions immediately when player plays - wait for opponent to play
    // Instructions will be shown 2 seconds after an opponent plays (in _handleOpponentSameRankPlays)
    
    // Update widget slices and UI-only fields using state updater
    stateUpdater.updateStateSync({
      'myDrawnCard': null, // Clear drawn card (it's now repositioned in hand or discarded)
      'demoInstructionsPhase': '', // Don't show instructions yet - wait for opponent to play
      'centerBoard': centerBoard,
      'myHand': myHand,
      'gamePhase': 'same_rank_window', // Set game phase to same_rank_window
    });
    
    _logger.info('✅ DemoFunctionality: Card $cardId played successfully', isOn: LOGGING_SWITCH);
    _logger.info('✅ DemoFunctionality: Updated all players status to same_rank_window', isOn: LOGGING_SWITCH);
    _logger.info('✅ DemoFunctionality: Transitioned to same_rank phase', isOn: LOGGING_SWITCH);
    
    // Cancel any existing same rank window timer - user controls when to proceed
    // Timer will only be set when opponents play same rank cards
    _sameRankWindowTimer?.cancel();
    
    // After user plays, automatically play same rank cards from opponents (demo mode)
    // Read fresh gameState from games map to ensure we have the latest state
    final playedRank = cardToPlayFullData['rank']?.toString() ?? '';
    _logger.info('🎮 DemoFunctionality: About to check opponents for same rank plays (rank: $playedRank)', isOn: LOGGING_SWITCH);
    
    final freshGameId = dutchGameState['currentGameId']?.toString() ?? '';
    if (freshGameId.isNotEmpty) {
      final currentGame = games[freshGameId] as Map<String, dynamic>? ?? {};
      final currentGameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
      final freshGameState = currentGameData['game_state'] as Map<String, dynamic>? ?? gameState;
      _logger.info('🎮 DemoFunctionality: Calling _handleOpponentSameRankPlays with freshGameState', isOn: LOGGING_SWITCH);
      // Fire and forget - don't await to avoid blocking the response
      _handleOpponentSameRankPlays(freshGameState, playedRank).catchError((error, stackTrace) {
        _logger.error('❌ DemoFunctionality: Error in opponent same rank plays: $error', error: error, stackTrace: stackTrace, isOn: LOGGING_SWITCH);
      });
    } else {
      _logger.info('🎮 DemoFunctionality: Calling _handleOpponentSameRankPlays with original gameState (no freshGameId)', isOn: LOGGING_SWITCH);
      _handleOpponentSameRankPlays(gameState, playedRank).catchError((error, stackTrace) {
        _logger.error('❌ DemoFunctionality: Error in opponent same rank plays: $error', error: error, stackTrace: stackTrace, isOn: LOGGING_SWITCH);
      });
    }
    
    return {'success': true, 'mode': 'demo', 'cardId': cardId};
  }

  /// Handle queen play - plays queen to discard and shows queen peek instructions
  Future<Map<String, dynamic>> _handleQueenPlay(
    Map<String, dynamic> payload,
    Map<String, dynamic> cardToPlayFullData,
    Map<String, dynamic> player,
    List<dynamic> hand,
    Map<String, dynamic> gameState,
    Map<String, dynamic> games,
    String currentGameId,
    Map<String, dynamic> dutchGameState,
  ) async {
    _logger.info('🎮 DemoFunctionality: Queen play intercepted', isOn: LOGGING_SWITCH);
    
    final cardId = payload['card_id']?.toString() ?? payload['cardId']?.toString() ?? '';
    final drawnCard = dutchGameState['myDrawnCard'] as Map<String, dynamic>?;
    
    // Re-read latest state from SSOT to ensure we have the most up-to-date data
    final stateManager = StateManager();
    final latestDutchGameState = stateManager.getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final latestGames = latestDutchGameState['games'] as Map<String, dynamic>? ?? {};
    final latestCurrentGame = latestGames[currentGameId] as Map<String, dynamic>? ?? {};
    final latestGameData = latestCurrentGame['gameData'] as Map<String, dynamic>? ?? {};
    final latestGameState = latestGameData['game_state'] as Map<String, dynamic>? ?? gameState;
    final latestPlayers = latestGameState['players'] as List<dynamic>? ?? [];
    
    // Find user player from latest players (not the stale player parameter)
    Map<String, dynamic>? userPlayer;
    int userPlayerIndex = -1;
    for (int i = 0; i < latestPlayers.length; i++) {
      final p = latestPlayers[i];
      if (p is Map<String, dynamic> && p['isHuman'] == true) {
        userPlayer = Map<String, dynamic>.from(p);
        userPlayerIndex = i;
        break;
      }
    }
    
    if (userPlayer == null) {
      _logger.error('❌ DemoFunctionality: User player not found in latest players', isOn: LOGGING_SWITCH);
      return {'success': false, 'error': 'User player not found'};
    }
    
    // Use the fresh user player's hand
    final userHand = userPlayer['hand'] as List<dynamic>? ?? [];
    
    // Find card index in hand
    int cardIndex = -1;
    for (int i = 0; i < userHand.length; i++) {
      final card = userHand[i];
      if (card != null && card is Map<String, dynamic>) {
        final cardIdInHand = card['cardId']?.toString() ?? '';
        if (cardIdInHand == cardId) {
          cardIndex = i;
          break;
        }
      }
    }
    
    if (cardIndex == -1) {
      _logger.error('❌ DemoFunctionality: Queen card $cardId not found in hand', isOn: LOGGING_SWITCH);
      return {'success': false, 'error': 'Card not found in hand'};
    }
    
    // Check if played card is the drawn card
    final isDrawnCard = drawnCard != null && drawnCard['cardId']?.toString() == cardId;
    
    // Create mutable copy of hand
    final mutableHand = List<dynamic>.from(userHand);
    
    // Remove card from hand (create blank slot for indices 0-3, remove for index 4+)
    bool shouldCreateBlankSlot = cardIndex <= 3;
    if (cardIndex > 3) {
      for (int i = cardIndex + 1; i < mutableHand.length; i++) {
        if (mutableHand[i] != null) {
          shouldCreateBlankSlot = true;
          break;
        }
      }
    }
    
    if (shouldCreateBlankSlot) {
      mutableHand[cardIndex] = null;
      _logger.info('✅ DemoFunctionality: Created blank slot at index $cardIndex for queen', isOn: LOGGING_SWITCH);
    } else {
      mutableHand.removeAt(cardIndex);
      _logger.info('✅ DemoFunctionality: Removed queen entirely from index $cardIndex', isOn: LOGGING_SWITCH);
    }
    
    // Handle drawn card repositioning if it wasn't played (same logic as regular play)
    if (drawnCard != null && !isDrawnCard) {
      int? drawnCardOriginalIndex;
      for (int i = 0; i < mutableHand.length; i++) {
        final card = mutableHand[i];
        if (card is Map<String, dynamic> && card['cardId']?.toString() == drawnCard['cardId']?.toString()) {
          drawnCardOriginalIndex = i;
          break;
        }
      }
      
      if (drawnCardOriginalIndex != null) {
        bool shouldKeepOriginalSlot = drawnCardOriginalIndex <= 3;
        if (drawnCardOriginalIndex > 3) {
          for (int i = drawnCardOriginalIndex + 1; i < mutableHand.length; i++) {
            if (mutableHand[i] != null) {
              shouldKeepOriginalSlot = true;
              break;
            }
          }
        }
        
        if (shouldKeepOriginalSlot) {
          mutableHand[drawnCardOriginalIndex] = null;
        } else {
          mutableHand.removeAt(drawnCardOriginalIndex);
          if (drawnCardOriginalIndex < cardIndex) {
            cardIndex -= 1;
          }
        }
        
        final drawnCardIdOnly = {
          'cardId': drawnCard['cardId'],
          'suit': '?',
          'rank': '?',
          'points': 0,
        };
        
        bool shouldPlaceInSlot = cardIndex <= 3;
        if (cardIndex > 3) {
          for (int i = cardIndex + 1; i < mutableHand.length; i++) {
            if (mutableHand[i] != null) {
              shouldPlaceInSlot = true;
              break;
            }
          }
        }
        
        if (shouldPlaceInSlot) {
          if (cardIndex < mutableHand.length) {
            mutableHand[cardIndex] = drawnCardIdOnly;
          } else {
            mutableHand.insert(cardIndex, drawnCardIdOnly);
          }
        } else {
          mutableHand.add(drawnCardIdOnly);
        }
      }
    }
    
    // Find the played queen card from originalDeck using its actual cardId
    final originalDeck = latestGameState['originalDeck'] as List<dynamic>? ?? [];
    Map<String, dynamic>? originalQueenCard;
    
    // First, try to find the card by matching the cardId from the hand
    final playedCardId = cardToPlayFullData['cardId']?.toString() ?? '';
    for (final card in originalDeck) {
      if (card is Map<String, dynamic> && 
          card['cardId']?.toString() == playedCardId) {
        originalQueenCard = Map<String, dynamic>.from(card);
        break;
      }
    }
    
    // If not found by ID, try to find by rank and suit (fallback)
    if (originalQueenCard == null) {
      final playedRank = cardToPlayFullData['rank']?.toString() ?? '';
      final playedSuit = cardToPlayFullData['suit']?.toString() ?? '';
      for (final card in originalDeck) {
        if (card is Map<String, dynamic> && 
            card['rank']?.toString() == playedRank && 
            card['suit']?.toString() == playedSuit) {
          originalQueenCard = Map<String, dynamic>.from(card);
          break;
        }
      }
    }
    
    // If still not found, create one with the played card's suit
    if (originalQueenCard == null) {
      final playedSuit = cardToPlayFullData['suit']?.toString() ?? 'hearts';
      originalQueenCard = {
        'cardId': 'card_demo_queen_${playedSuit}_0',
        'rank': 'queen',
        'suit': playedSuit,
        'points': 10,
        'specialPower': 'peek_at_card',
      };
      _logger.warning('⚠️ DemoFunctionality: Queen not found in originalDeck, created fallback queen of $playedSuit', isOn: LOGGING_SWITCH);
    } else {
      _logger.info('🎮 DemoFunctionality: Using original queen card ID: ${originalQueenCard['cardId']}, suit: ${originalQueenCard['suit']}', isOn: LOGGING_SWITCH);
    }
    
    // Restore original hand and update piles
    final drawPile = latestGameState['drawPile'] as List<dynamic>? ?? [];
    final discardPile = latestGameState['discardPile'] as List<dynamic>? ?? [];
    final restored = _restoreOriginalHand(originalDeck, drawPile, discardPile, originalQueenCard);
    
    // Update user player's hand and status
    userPlayer['hand'] = restored['hand'];
    userPlayer['status'] = 'queen_peek';
    
    // Update myHandCards in games map with restored hand
    final myHandCards = List<Map<String, dynamic>>.from((restored['hand'] as List<dynamic>).map((c) {
      if (c is Map<String, dynamic>) {
        return Map<String, dynamic>.from(c);
      }
      return <String, dynamic>{};
    }));
    
    // Update players list with updated user player
    final updatedPlayers = List<dynamic>.from(latestPlayers);
    updatedPlayers[userPlayerIndex] = userPlayer;
    
    // Update SSOT with player status change, restored hand, and updated piles
    final updatedGameState = Map<String, dynamic>.from(latestGameState);
    updatedGameState['players'] = updatedPlayers;
    updatedGameState['currentPlayer'] = userPlayer; // Set currentPlayer so _getCurrentUserStatus can find it
    updatedGameState['discardPile'] = restored['discardPile'];
    updatedGameState['drawPile'] = restored['drawPile'];
    final updatedGameData = Map<String, dynamic>.from(latestGameData);
    updatedGameData['game_state'] = updatedGameState;
    final updatedCurrentGame = Map<String, dynamic>.from(latestCurrentGame);
    updatedCurrentGame['gameData'] = updatedGameData;
    updatedCurrentGame['myHandCards'] = myHandCards; // Update myHandCards so _computeMyHandSlice picks it up
    final updatedGames = Map<String, dynamic>.from(latestGames);
    updatedGames[currentGameId] = updatedCurrentGame;
    
    // Get current dutch game state for widget slice updates (same pattern as _handleDrawCard)
    final stateManagerForSlices = StateManager();
    final currentDutchGameState = stateManagerForSlices.getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    
    // Update widget slices manually (same pattern as _handleDrawCard)
    final centerBoard = currentDutchGameState['centerBoard'] as Map<String, dynamic>? ?? {};
    centerBoard['playerStatus'] = 'queen_peek';
    
    final myHand = currentDutchGameState['myHand'] as Map<String, dynamic>? ?? {};
    myHand['playerStatus'] = 'queen_peek';
    myHand['cards'] = myHandCards; // Update cards in myHand slice
    
    // Update state using official state updater (same pattern as regular play)
    final stateUpdater = DutchGameStateUpdater.instance;
    stateUpdater.updateStateSync({
      'playerStatus': 'queen_peek', // Update main state
      'currentPlayerStatus': 'queen_peek',
      'games': updatedGames, // SSOT with player status = 'queen_peek' and restored hand
      'discardPile': restored['discardPile'], // Update discard pile
      'drawPileCount': (restored['drawPile'] as List<dynamic>).length,
      'myDrawnCard': null, // Clear drawn card
      'currentPlayer': userPlayer, // Set currentPlayer so _getCurrentUserStatus can find it
      'lastUpdated': DateTime.now().toIso8601String(),
    });
    
    // Update widget slices and UI-only fields using state updater (same pattern as regular play)
    stateUpdater.updateStateSync({
      'centerBoard': centerBoard, // Update centerBoard slice
      'myHand': myHand, // Update myHand slice with new status and cards
    });
    
    // Update instructions phase separately using updateState (triggers widget rebuild)
    // Same pattern as special_plays - use updateState to ensure ListenableBuilder rebuilds
    // NOTE: Do NOT set gamePhase - it's validated and 'queen_peek' is not allowed
    // Only set demoInstructionsPhase which controls the instructions widget
    stateUpdater.updateState({
      'demoInstructionsPhase': 'queen_peek', // Show queen peek instructions
      'lastUpdated': DateTime.now().toIso8601String(),
    });
    
    _logger.info('✅ DemoFunctionality: Updated user status to queen_peek in SSOT', isOn: LOGGING_SWITCH);
    _logger.info('✅ DemoFunctionality: Updated state - widget slices will be recomputed with playerStatus=queen_peek', isOn: LOGGING_SWITCH);
    _logger.info('✅ DemoFunctionality: Queen played successfully, showing queen peek instructions', isOn: LOGGING_SWITCH);
    
    return {'success': true, 'mode': 'demo', 'cardId': cardId};
  }

  /// Handle jack play - plays jack to discard and shows jack swap instructions
  Future<Map<String, dynamic>> _handleJackPlay(
    Map<String, dynamic> payload,
    Map<String, dynamic> cardToPlayFullData,
    Map<String, dynamic> player,
    List<dynamic> hand,
    Map<String, dynamic> gameState,
    Map<String, dynamic> games,
    String currentGameId,
    Map<String, dynamic> dutchGameState,
  ) async {
    _logger.info('🎮 DemoFunctionality: Jack play intercepted', isOn: LOGGING_SWITCH);
    
    final cardId = payload['card_id']?.toString() ?? payload['cardId']?.toString() ?? '';
    final drawnCard = dutchGameState['myDrawnCard'] as Map<String, dynamic>?;
    
    // Re-read latest state from SSOT to ensure we have the most up-to-date data
    final stateManager = StateManager();
    final latestDutchGameState = stateManager.getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final latestGames = latestDutchGameState['games'] as Map<String, dynamic>? ?? {};
    final latestCurrentGame = latestGames[currentGameId] as Map<String, dynamic>? ?? {};
    final latestGameData = latestCurrentGame['gameData'] as Map<String, dynamic>? ?? {};
    final latestGameState = latestGameData['game_state'] as Map<String, dynamic>? ?? gameState;
    final latestPlayers = latestGameState['players'] as List<dynamic>? ?? [];
    
    // Find user player from latest players (not the stale player parameter)
    Map<String, dynamic>? userPlayer;
    int userPlayerIndex = -1;
    for (int i = 0; i < latestPlayers.length; i++) {
      final p = latestPlayers[i];
      if (p is Map<String, dynamic> && p['isHuman'] == true) {
        userPlayer = Map<String, dynamic>.from(p);
        userPlayerIndex = i;
        break;
      }
    }
    
    if (userPlayer == null) {
      _logger.error('❌ DemoFunctionality: User player not found in latest players', isOn: LOGGING_SWITCH);
      return {'success': false, 'error': 'User player not found'};
    }
    
    // Use the fresh user player's hand
    final userHand = userPlayer['hand'] as List<dynamic>? ?? [];
    
    // Find card index in hand
    int cardIndex = -1;
    for (int i = 0; i < userHand.length; i++) {
      final card = userHand[i];
      if (card != null && card is Map<String, dynamic>) {
        final cardIdInHand = card['cardId']?.toString() ?? '';
        if (cardIdInHand == cardId) {
          cardIndex = i;
          break;
        }
      }
    }
    
    if (cardIndex == -1) {
      _logger.error('❌ DemoFunctionality: Jack card $cardId not found in hand', isOn: LOGGING_SWITCH);
      return {'success': false, 'error': 'Card not found in hand'};
    }
    
    // Check if played card is the drawn card
    final isDrawnCard = drawnCard != null && drawnCard['cardId']?.toString() == cardId;
    
    // Create mutable copy of hand
    final mutableHand = List<dynamic>.from(userHand);
    
    // Remove card from hand (create blank slot for indices 0-3, remove for index 4+)
    bool shouldCreateBlankSlot = cardIndex <= 3;
    if (cardIndex > 3) {
      for (int i = cardIndex + 1; i < mutableHand.length; i++) {
        if (mutableHand[i] != null) {
          shouldCreateBlankSlot = true;
          break;
        }
      }
    }
    
    if (shouldCreateBlankSlot) {
      mutableHand[cardIndex] = null;
      _logger.info('✅ DemoFunctionality: Created blank slot at index $cardIndex for jack', isOn: LOGGING_SWITCH);
    } else {
      mutableHand.removeAt(cardIndex);
      _logger.info('✅ DemoFunctionality: Removed jack entirely from index $cardIndex', isOn: LOGGING_SWITCH);
    }
    
    // Handle drawn card repositioning if it wasn't played (same logic as regular play)
    if (drawnCard != null && !isDrawnCard) {
      int? drawnCardOriginalIndex;
      for (int i = 0; i < mutableHand.length; i++) {
        final card = mutableHand[i];
        if (card is Map<String, dynamic> && card['cardId']?.toString() == drawnCard['cardId']?.toString()) {
          drawnCardOriginalIndex = i;
          break;
        }
      }
      
      if (drawnCardOriginalIndex != null) {
        bool shouldKeepOriginalSlot = drawnCardOriginalIndex <= 3;
        if (drawnCardOriginalIndex > 3) {
          for (int i = drawnCardOriginalIndex + 1; i < mutableHand.length; i++) {
            if (mutableHand[i] != null) {
              shouldKeepOriginalSlot = true;
              break;
            }
          }
        }
        
        if (shouldKeepOriginalSlot) {
          mutableHand[drawnCardOriginalIndex] = null;
        } else {
          mutableHand.removeAt(drawnCardOriginalIndex);
          if (drawnCardOriginalIndex < cardIndex) {
            cardIndex -= 1;
          }
        }
        
        final drawnCardIdOnly = {
          'cardId': drawnCard['cardId'],
          'suit': '?',
          'rank': '?',
          'points': 0,
        };
        
        bool shouldPlaceInSlot = cardIndex <= 3;
        if (cardIndex > 3) {
          for (int i = cardIndex + 1; i < mutableHand.length; i++) {
            if (mutableHand[i] != null) {
              shouldPlaceInSlot = true;
              break;
            }
          }
        }
        
        if (shouldPlaceInSlot) {
          if (cardIndex < mutableHand.length) {
            mutableHand[cardIndex] = drawnCardIdOnly;
          } else {
            mutableHand.insert(cardIndex, drawnCardIdOnly);
          }
        } else {
          mutableHand.add(drawnCardIdOnly);
        }
      }
    }
    
    // Find the played jack card from originalDeck using its actual cardId
    final originalDeck = latestGameState['originalDeck'] as List<dynamic>? ?? [];
    Map<String, dynamic>? originalJackCard;
    
    // First, try to find the card by matching the cardId from the hand
    final playedCardId = cardToPlayFullData['cardId']?.toString() ?? '';
    for (final card in originalDeck) {
      if (card is Map<String, dynamic> && 
          card['cardId']?.toString() == playedCardId) {
        originalJackCard = Map<String, dynamic>.from(card);
        break;
      }
    }
    
    // If not found by ID, try to find by rank and suit (fallback)
    if (originalJackCard == null) {
      final playedRank = cardToPlayFullData['rank']?.toString() ?? '';
      final playedSuit = cardToPlayFullData['suit']?.toString() ?? '';
      for (final card in originalDeck) {
        if (card is Map<String, dynamic> && 
            card['rank']?.toString() == playedRank && 
            card['suit']?.toString() == playedSuit) {
          originalJackCard = Map<String, dynamic>.from(card);
          break;
        }
      }
    }
    
    // If still not found, create one with the played card's suit
    if (originalJackCard == null) {
      final playedSuit = cardToPlayFullData['suit']?.toString() ?? 'hearts';
      originalJackCard = {
        'cardId': 'card_demo_jack_${playedSuit}_0',
        'rank': 'jack',
        'suit': playedSuit,
        'points': 10,
        'specialPower': 'swap_cards',
      };
      _logger.warning('⚠️ DemoFunctionality: Jack not found in originalDeck, created fallback jack of $playedSuit', isOn: LOGGING_SWITCH);
    } else {
      _logger.info('🎮 DemoFunctionality: Using original jack card ID: ${originalJackCard['cardId']}, suit: ${originalJackCard['suit']}', isOn: LOGGING_SWITCH);
    }
    
    // Restore original hand and update piles
    final drawPile = latestGameState['drawPile'] as List<dynamic>? ?? [];
    final discardPile = latestGameState['discardPile'] as List<dynamic>? ?? [];
    final restored = _restoreOriginalHand(originalDeck, drawPile, discardPile, originalJackCard);
    
    // Update user player's hand and status
    userPlayer['hand'] = restored['hand'];
    userPlayer['status'] = 'jack_swap';
    
    // Update myHandCards in games map with restored hand
    final myHandCards = List<Map<String, dynamic>>.from((restored['hand'] as List<dynamic>).map((c) {
      if (c is Map<String, dynamic>) {
        return Map<String, dynamic>.from(c);
      }
      return <String, dynamic>{};
    }));
    
    // Update players list with updated user player
    final updatedPlayers = List<dynamic>.from(latestPlayers);
    updatedPlayers[userPlayerIndex] = userPlayer;
    
    // Update SSOT with player status change, restored hand, and updated piles
    // NOTE: Do NOT set gamePhase to 'same_rank_window' - we skip same rank window for jack play
    final updatedGameState = Map<String, dynamic>.from(latestGameState);
    updatedGameState['players'] = updatedPlayers;
    updatedGameState['currentPlayer'] = userPlayer; // Set currentPlayer so _getCurrentUserStatus can find it
    updatedGameState['discardPile'] = restored['discardPile'];
    updatedGameState['drawPile'] = restored['drawPile'];
    final updatedGameData = Map<String, dynamic>.from(latestGameData);
    updatedGameData['game_state'] = updatedGameState;
    final updatedCurrentGame = Map<String, dynamic>.from(latestCurrentGame);
    updatedCurrentGame['gameData'] = updatedGameData;
    updatedCurrentGame['myHandCards'] = myHandCards; // Update myHandCards so _computeMyHandSlice picks it up
    final updatedGames = Map<String, dynamic>.from(latestGames);
    updatedGames[currentGameId] = updatedCurrentGame;
    
    // Get current dutch game state for widget slice updates (same pattern as _handleQueenPlay)
    final stateManagerForSlices = StateManager();
    final currentDutchGameState = stateManagerForSlices.getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    
    // Update widget slices manually (same pattern as _handleQueenPlay)
    final centerBoard = currentDutchGameState['centerBoard'] as Map<String, dynamic>? ?? {};
    centerBoard['playerStatus'] = 'jack_swap';
    
    final myHand = currentDutchGameState['myHand'] as Map<String, dynamic>? ?? {};
    myHand['playerStatus'] = 'jack_swap';
    myHand['cards'] = myHandCards; // Update cards in myHand slice
    
    // Update state using official state updater (same pattern as regular play)
    final stateUpdater = DutchGameStateUpdater.instance;
    stateUpdater.updateStateSync({
      'playerStatus': 'jack_swap', // Update main state
      'currentPlayerStatus': 'jack_swap',
      'games': updatedGames, // SSOT with player status = 'jack_swap' and restored hand
      'discardPile': restored['discardPile'], // Update discard pile
      'drawPileCount': (restored['drawPile'] as List<dynamic>).length,
      'myDrawnCard': null, // Clear drawn card
      'currentPlayer': userPlayer, // Set currentPlayer so _getCurrentUserStatus can find it
      'lastUpdated': DateTime.now().toIso8601String(),
    });
    
    // Update widget slices and UI-only fields using state updater (same pattern as regular play)
    stateUpdater.updateStateSync({
      'centerBoard': centerBoard, // Update centerBoard slice
      'myHand': myHand, // Update myHand slice with new status and cards
    });
    
    // Update instructions phase separately using updateState (triggers widget rebuild)
    // Same pattern as queen_peek - use updateState to ensure ListenableBuilder rebuilds
    // NOTE: Do NOT set gamePhase - it's validated and 'jack_swap' is not allowed
    // Only set demoInstructionsPhase which controls the instructions widget
    stateUpdater.updateState({
      'demoInstructionsPhase': 'jack_swap', // Show jack swap instructions
      'lastUpdated': DateTime.now().toIso8601String(),
    });
    
    _logger.info('✅ DemoFunctionality: Updated user status to jack_swap in SSOT', isOn: LOGGING_SWITCH);
    _logger.info('✅ DemoFunctionality: Updated state - widget slices will be recomputed with playerStatus=jack_swap', isOn: LOGGING_SWITCH);
    _logger.info('✅ DemoFunctionality: Jack played successfully, showing jack swap instructions (skipped same rank window)', isOn: LOGGING_SWITCH);
    
    return {'success': true, 'mode': 'demo', 'cardId': cardId};
  }
  
  /// Handle same rank play action in demo mode
  /// Intercepts PlayerAction.sameRankPlay() which sends event 'same_rank_play' with payload:
  /// - card_id: ID of the card to play
  /// - game_id: gameId
  /// - player_id: auto-added by event emitter
  Future<Map<String, dynamic>> _handleSameRankPlay(Map<String, dynamic> payload) async {
    _logger.info('🎮 DemoFunctionality: Same rank play action intercepted', isOn: LOGGING_SWITCH);
    _logger.info('🎮 DemoFunctionality: Payload: $payload', isOn: LOGGING_SWITCH);
    
    // Cancel any pending same rank instructions timer (player is playing, not waiting)
    _sameRankInstructionsTimer?.cancel();
    
    // Cancel same rank window timer - timer only applies to opponent simulation, not user plays
    _sameRankWindowTimer?.cancel();
    
    final cardId = payload['card_id']?.toString() ?? '';
    if (cardId.isEmpty) {
      _logger.error('❌ DemoFunctionality: No card_id provided for same rank play', isOn: LOGGING_SWITCH);
      return {'success': false, 'error': 'No card_id provided'};
    }
    
    final stateManager = StateManager();
    final dutchGameState = stateManager.getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final games = dutchGameState['games'] as Map<String, dynamic>? ?? {};
    final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
    
    if (currentGameId.isEmpty) {
      _logger.error('❌ DemoFunctionality: No currentGameId found', isOn: LOGGING_SWITCH);
      return {'success': false, 'error': 'No active game'};
    }
    
    final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
    final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
    final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
    
    // Get current player ID from state
    final currentPlayerId = dutchGameState['currentPlayer']?['id']?.toString() ?? 
                           dutchGameState['playerId']?.toString() ?? '';
    
    if (currentPlayerId.isEmpty) {
      _logger.error('❌ DemoFunctionality: No current player ID found', isOn: LOGGING_SWITCH);
      return {'success': false, 'error': 'No current player'};
    }
    
    // Find the player
    final players = gameState['players'] as List<dynamic>? ?? [];
    Map<String, dynamic>? player;
    for (var p in players) {
      if (p is Map<String, dynamic> && p['id']?.toString() == currentPlayerId) {
        player = p;
        break;
      }
    }
    
    if (player == null) {
      _logger.error('❌ DemoFunctionality: Player $currentPlayerId not found', isOn: LOGGING_SWITCH);
      return {'success': false, 'error': 'Player not found'};
    }
    
    // Find the card in player's hand
    final handRaw = player['hand'] as List<dynamic>? ?? [];
    final hand = List<dynamic>.from(handRaw); // Convert to mutable list to allow nulls
    Map<String, dynamic>? playedCard;
    int cardIndex = -1;
    
    for (int i = 0; i < hand.length; i++) {
      final card = hand[i];
      if (card != null && card is Map<String, dynamic> && card['cardId']?.toString() == cardId) {
        playedCard = card;
        cardIndex = i;
        break;
      }
    }
    
    if (playedCard == null) {
      _logger.warning('⚠️ DemoFunctionality: Card $cardId not found in player $currentPlayerId hand', isOn: LOGGING_SWITCH);
      return {'success': false, 'error': 'Card not found in hand'};
    }
    
    _logger.info('🎮 DemoFunctionality: Found card $cardId at index $cardIndex', isOn: LOGGING_SWITCH);
    
    // Get full card data
    final playedCardFullData = _getCardById(cardId);
    if (playedCardFullData == null) {
      _logger.error('❌ DemoFunctionality: Failed to get full card data for $cardId', isOn: LOGGING_SWITCH);
      return {'success': false, 'error': 'Failed to get card data'};
    }
    
    final cardRank = playedCardFullData['rank']?.toString() ?? '';
    final cardSuit = playedCardFullData['suit']?.toString() ?? '';
    
    _logger.info('🎮 DemoFunctionality: Playing card $cardId (rank: $cardRank, suit: $cardSuit)', isOn: LOGGING_SWITCH);
    
    // Validate same rank play (check if rank matches discard pile top card)
    final discardPile = gameState['discardPile'] as List<dynamic>? ?? [];
    bool isValidSameRank = false;
    
    if (discardPile.isNotEmpty) {
      final lastCard = discardPile.last as Map<String, dynamic>?;
      if (lastCard != null) {
        final lastCardRank = lastCard['rank']?.toString() ?? '';
        isValidSameRank = cardRank.toLowerCase() == lastCardRank.toLowerCase();
        _logger.info('🎮 DemoFunctionality: Same rank validation - played: $cardRank, required: $lastCardRank, valid: $isValidSameRank', isOn: LOGGING_SWITCH);
      }
    }
    
    if (!isValidSameRank) {
      // Apply penalty: draw a card from the draw pile and add to player's hand
      _logger.info('🎮 DemoFunctionality: Same rank validation failed - applying penalty card', isOn: LOGGING_SWITCH);
      
      final drawPile = gameState['drawPile'] as List<dynamic>? ?? [];
      
      // Check if draw pile is empty and reshuffle if needed
      if (drawPile.isEmpty) {
        if (discardPile.length <= 1) {
          _logger.error('❌ DemoFunctionality: Cannot apply penalty - draw pile is empty and discard pile has ${discardPile.length} card(s)', isOn: LOGGING_SWITCH);
          return {'success': false, 'error': 'Cannot apply penalty - no cards available'};
        }
        
        // Keep the top card in discard pile, reshuffle the rest
        final topCard = discardPile.last as Map<String, dynamic>;
        final cardsToReshuffle = discardPile.sublist(0, discardPile.length - 1);
        
        _logger.info('🎮 DemoFunctionality: Draw pile empty during penalty - reshuffling ${cardsToReshuffle.length} cards from discard pile', isOn: LOGGING_SWITCH);
        
        // Convert full card data to ID-only for reshuffled cards
        final idOnlyCards = cardsToReshuffle.map((card) {
          if (card is Map<String, dynamic>) {
            return <String, dynamic>{
              'cardId': card['cardId'],
              'suit': '?',
              'rank': '?',
              'points': 0,
            };
          }
          return card;
        }).toList();
        
        // Shuffle the cards
        idOnlyCards.shuffle();
        
        // Add shuffled cards to draw pile
        drawPile.addAll(idOnlyCards);
        
        // Keep only the top card in discard pile
        gameState['discardPile'] = [topCard];
        gameState['drawPile'] = drawPile;
        
        _logger.info('🎮 DemoFunctionality: Reshuffled ${idOnlyCards.length} cards into draw pile for penalty', isOn: LOGGING_SWITCH);
      }
      
      // Re-fetch drawPile in case it was reshuffled
      final currentDrawPile = gameState['drawPile'] as List<dynamic>? ?? [];
      if (currentDrawPile.isEmpty) {
        _logger.error('❌ DemoFunctionality: Draw pile is empty after reshuffle check - cannot apply penalty', isOn: LOGGING_SWITCH);
        return {'success': false, 'error': 'Draw pile is empty'};
      }
      
      // Draw a card from the draw pile (remove last card)
      final penaltyCardRaw = currentDrawPile.removeLast();
      Map<String, dynamic> penaltyCard;
      if (penaltyCardRaw is Map<String, dynamic>) {
        penaltyCard = penaltyCardRaw;
      } else {
        _logger.error('❌ DemoFunctionality: Penalty card is not a Map', isOn: LOGGING_SWITCH);
        return {'success': false, 'error': 'Invalid penalty card format'};
      }
      
      _logger.info('🎮 DemoFunctionality: Drew penalty card ${penaltyCard['cardId']} from draw pile', isOn: LOGGING_SWITCH);
      
      // Add penalty card to player's hand as ID-only (same format as regular hand cards)
      final penaltyCardIdOnly = {
        'cardId': penaltyCard['cardId'],
        'suit': '?',      // Face-down: hide suit
        'rank': '?',      // Face-down: hide rank
        'points': 0,      // Face-down: hide points
      };
      
      hand.add(penaltyCardIdOnly);
      _logger.info('🎮 DemoFunctionality: Added penalty card ${penaltyCard['cardId']} to player $currentPlayerId hand', isOn: LOGGING_SWITCH);
      
      // Update player's hand and draw pile in game state
      player['hand'] = hand;
      gameState['drawPile'] = currentDrawPile;
      gameState['players'] = players;
      
      // Update game data
      gameData['game_state'] = gameState;
      currentGame['gameData'] = gameData;
      games[currentGameId] = currentGame;
      
      // Update player status to 'waiting' (penalty applied, same rank window continues)
      player['status'] = 'waiting';
      
      // Update widget slices
      final centerBoard = dutchGameState['centerBoard'] as Map<String, dynamic>? ?? {};
      final myHand = dutchGameState['myHand'] as Map<String, dynamic>? ?? {};
      
      // Update myHand slice with new hand
      final myHandCards = List<dynamic>.from(hand);
      myHand['cards'] = myHandCards;
      myHand['playerStatus'] = 'waiting';
      
      // Update centerBoard slice with draw pile count
      centerBoard['drawPileCount'] = currentDrawPile.length;
      
      // Use official state updater for main game state
      final stateUpdater = DutchGameStateUpdater.instance;
      stateUpdater.updateStateSync({
        'games': games,
        'lastUpdated': DateTime.now().toIso8601String(),
      });
      
      // Cancel same rank window timer - user will control when to proceed via "Let's go" button
      _sameRankWindowTimer?.cancel();
      
      // Update widget slices and UI-only fields using state updater
      stateUpdater.updateStateSync({
        'centerBoard': centerBoard,
        'myHand': myHand,
        'playerStatus': 'waiting',
        'currentPlayerStatus': 'waiting',
        'demoInstructionsPhase': 'wrong_same_rank_penalty', // Show wrong rank penalty instructions
      });
      
      final handCount = hand.where((c) => c != null).length;
      
      _logger.info('✅ DemoFunctionality: Penalty applied successfully - player $currentPlayerId now has $handCount cards', isOn: LOGGING_SWITCH);
      
      return {'success': true, 'mode': 'demo', 'penalty': true, 'cardId': cardId};
    }
    
    // SUCCESSFUL SAME RANK PLAY - Remove card from hand and add to discard pile
    _logger.info('✅ DemoFunctionality: Same rank validation passed - removing card from hand', isOn: LOGGING_SWITCH);
    
    // Check if we should create a blank slot or remove the card entirely
    bool shouldCreateBlankSlot = cardIndex <= 3;
    if (cardIndex > 3) {
      // For index 4+, only create blank slot if there are cards after this index
      for (int i = cardIndex + 1; i < hand.length; i++) {
        if (hand[i] != null) {
          shouldCreateBlankSlot = true;
          break;
        }
      }
    }
    
    // Remove card from hand
    if (shouldCreateBlankSlot) {
      hand[cardIndex] = null; // Create blank slot to maintain structure
      _logger.info('✅ DemoFunctionality: Created blank slot at index $cardIndex for same rank play', isOn: LOGGING_SWITCH);
    } else {
      hand.removeAt(cardIndex); // Remove entirely and shift remaining cards
      _logger.info('✅ DemoFunctionality: Removed same rank card entirely from index $cardIndex', isOn: LOGGING_SWITCH);
    }
    
    // Update player's hand
    player['hand'] = hand;
    
    // Add card to discard pile with full data
    final updatedDiscardPile = List<Map<String, dynamic>>.from(
      (gameState['discardPile'] as List<dynamic>? ?? []).map((c) {
        if (c is Map<String, dynamic>) {
          return Map<String, dynamic>.from(c);
        }
        return <String, dynamic>{};
      })
    );
    updatedDiscardPile.add(Map<String, dynamic>.from(playedCardFullData));
    gameState['discardPile'] = updatedDiscardPile;
    
    // Update game state
    gameState['players'] = players;
    gameData['game_state'] = gameState;
    currentGame['gameData'] = gameData;
    games[currentGameId] = currentGame;
    
    // Update player status to 'waiting' (same rank window continues)
    player['status'] = 'waiting';
    
    // Update widget slices
    final centerBoard = dutchGameState['centerBoard'] as Map<String, dynamic>? ?? {};
    final myHand = dutchGameState['myHand'] as Map<String, dynamic>? ?? {};
    
    // Update myHand slice with new hand
    final myHandCards = List<dynamic>.from(hand);
    myHand['cards'] = myHandCards;
    myHand['playerStatus'] = 'waiting';
    
    // Update centerBoard slice with discard pile
    centerBoard['discardPile'] = updatedDiscardPile;
    
    // Create turn event for the same rank play
    final currentTurnEvents = dutchGameState['turn_events'] as List<dynamic>? ?? [];
    final turnEvents = List<Map<String, dynamic>>.from(currentTurnEvents)
      ..add({
        'cardId': cardId,
        'actionType': 'same_rank_play',
        'playerId': currentPlayerId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    
    // Use official state updater for main game state
    final stateUpdater = DutchGameStateUpdater.instance;
    stateUpdater.updateStateSync({
      'games': games,
      'discardPile': updatedDiscardPile,
      'turn_events': turnEvents,
      'lastUpdated': DateTime.now().toIso8601String(),
    });
    
    // Update widget slices and UI-only fields using state updater
    stateUpdater.updateStateSync({
      'centerBoard': centerBoard,
      'myHand': myHand,
      'playerStatus': 'waiting',
      'currentPlayerStatus': 'waiting',
      'turn_events': turnEvents,
      'demoInstructionsPhase': '', // Clear instructions when player plays
      'gamePhase': 'same_rank_window', // Keep same rank window active
    });
    
    // Cancel any existing same rank window timer - user controls when to proceed
    // Timer will only be set when opponents play same rank cards
    _sameRankWindowTimer?.cancel();
    
    _logger.info('✅ DemoFunctionality: Same rank play successful - card $cardId (rank: $cardRank) added to discard pile', isOn: LOGGING_SWITCH);
    
    return {'success': true, 'mode': 'demo', 'cardId': cardId};
  }
  
  /// Handle automatic same rank plays from opponents (demo mode)
  /// Simulates computer opponents playing same rank cards after user plays
  Future<void> _handleOpponentSameRankPlays(Map<String, dynamic> gameState, String playedRank) async {
    _logger.info('🎮 DemoFunctionality: _handleOpponentSameRankPlays ENTRY - rank: $playedRank', isOn: LOGGING_SWITCH);
    
    if (playedRank.isEmpty) {
      _logger.warning('⚠️ DemoFunctionality: No rank provided for opponent same rank plays', isOn: LOGGING_SWITCH);
      return;
    }
    
    _logger.info('🎮 DemoFunctionality: Checking opponents for same rank cards (rank: $playedRank)', isOn: LOGGING_SWITCH);
    
    final players = gameState['players'] as List<dynamic>? ?? [];
    _logger.info('🎮 DemoFunctionality: Found ${players.length} players to check', isOn: LOGGING_SWITCH);
    
    final stateManager = StateManager();
    final dutchGameState = stateManager.getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
    
    if (currentGameId.isEmpty) {
      _logger.error('❌ DemoFunctionality: No currentGameId found for opponent same rank plays', isOn: LOGGING_SWITCH);
      return;
    }
    
    // Check each opponent for same rank cards (with delay between plays)
    int opponentCount = 0;
    for (var playerData in players) {
      if (playerData is! Map<String, dynamic>) continue;
      
      final playerId = playerData['id']?.toString() ?? '';
      final isHuman = playerData['isHuman'] == true;
      
      // Skip human player
      if (isHuman) {
        _logger.info('🎮 DemoFunctionality: Skipping human player $playerId', isOn: LOGGING_SWITCH);
        continue;
      }
      
      opponentCount++;
      _logger.info('🎮 DemoFunctionality: Checking opponent $opponentCount: $playerId', isOn: LOGGING_SWITCH);
      
      // Add delay before each opponent plays (3 seconds for demo)
      const delayMs = 3000;
      _logger.info('🎮 DemoFunctionality: Waiting ${delayMs}ms before checking opponent $playerId', isOn: LOGGING_SWITCH);
      await Future.delayed(const Duration(milliseconds: delayMs));
      
      // Re-read gameState after delay to avoid stale references
      final stateManager = StateManager();
      final dutchGameStateAfterDelay = stateManager.getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final gamesAfterDelay = dutchGameStateAfterDelay['games'] as Map<String, dynamic>? ?? {};
      final currentGameIdAfterDelay = dutchGameStateAfterDelay['currentGameId']?.toString() ?? '';
      
      if (currentGameIdAfterDelay.isEmpty) {
        _logger.warning('⚠️ DemoFunctionality: No currentGameId after delay, skipping opponent $playerId', isOn: LOGGING_SWITCH);
        continue;
      }
      
      final currentGameAfterDelay = gamesAfterDelay[currentGameIdAfterDelay] as Map<String, dynamic>? ?? {};
      final gameDataAfterDelay = currentGameAfterDelay['gameData'] as Map<String, dynamic>? ?? {};
      final gameStateAfterDelay = gameDataAfterDelay['game_state'] as Map<String, dynamic>? ?? {};
      
      if (gameStateAfterDelay.isEmpty) {
        _logger.warning('⚠️ DemoFunctionality: No gameState after delay, skipping opponent $playerId', isOn: LOGGING_SWITCH);
        continue;
      }
      
      // Re-find the player in the fresh gameState
      final playersAfterDelay = gameStateAfterDelay['players'] as List<dynamic>? ?? [];
      Map<String, dynamic>? playerDataAfterDelay;
      for (var p in playersAfterDelay) {
        if (p is Map<String, dynamic> && p['id']?.toString() == playerId) {
          playerDataAfterDelay = p;
          break;
        }
      }
      
      if (playerDataAfterDelay == null) {
        _logger.warning('⚠️ DemoFunctionality: Player $playerId not found after delay, skipping', isOn: LOGGING_SWITCH);
        continue;
      }
      
      final handRaw = playerDataAfterDelay['hand'] as List<dynamic>? ?? [];
      // Create a mutable list that allows null values (dynamic is nullable)
      final hand = List<dynamic>.from(handRaw);
      _logger.info('🎮 DemoFunctionality: Opponent $playerId has ${hand.length} cards in hand', isOn: LOGGING_SWITCH);
      
      // Find cards with matching rank in opponent's hand
      List<Map<String, dynamic>> sameRankCards = [];
      for (int i = 0; i < hand.length; i++) {
        final card = hand[i];
        if (card != null && card is Map<String, dynamic>) {
          final cardId = card['cardId']?.toString() ?? '';
          _logger.info('🎮 DemoFunctionality: Checking card $cardId at index $i', isOn: LOGGING_SWITCH);
          
          // Get full card data to check rank
          final fullCardData = _getCardById(cardId);
          if (fullCardData == null) {
            _logger.warning('⚠️ DemoFunctionality: Could not get full card data for $cardId', isOn: LOGGING_SWITCH);
            continue;
          }
          
          final cardRank = fullCardData['rank']?.toString() ?? '';
          _logger.info('🎮 DemoFunctionality: Card $cardId has rank: $cardRank (target: $playedRank)', isOn: LOGGING_SWITCH);
          
          if (cardRank == playedRank) {
            _logger.info('✅ DemoFunctionality: Found matching rank card! $cardId (rank: $cardRank)', isOn: LOGGING_SWITCH);
            sameRankCards.add({
              'card': card,
              'cardId': cardId,
              'index': i,
              'fullData': fullCardData,
            });
          }
        }
      }
      
      _logger.info('🎮 DemoFunctionality: Opponent $playerId has ${sameRankCards.length} matching rank card(s)', isOn: LOGGING_SWITCH);
      
      if (sameRankCards.isNotEmpty) {
        _logger.info('🎮 DemoFunctionality: Opponent $playerId has ${sameRankCards.length} same rank card(s) (rank: $playedRank)', isOn: LOGGING_SWITCH);
        
        // Play the first matching card (simplified for demo)
        final cardToPlay = sameRankCards[0];
        final opponentCardId = cardToPlay['cardId']?.toString() ?? '';
        final cardIndex = cardToPlay['index'] as int;
        final opponentCardFullDataRaw = cardToPlay['fullData'] as Map<String, dynamic>?;
        
        if (opponentCardFullDataRaw == null) {
          _logger.error('❌ DemoFunctionality: opponentCardFullData is null for card $opponentCardId', isOn: LOGGING_SWITCH);
          continue; // Skip this opponent if we can't get full card data
        }
        
        // At this point, opponentCardFullDataRaw is guaranteed to be non-null
        final opponentCardFullData = opponentCardFullDataRaw;
        
        _logger.info('🎮 DemoFunctionality: Auto-playing card $opponentCardId from opponent $playerId', isOn: LOGGING_SWITCH);
        _logger.info('🎮 DemoFunctionality: playerDataAfterDelay type: ${playerDataAfterDelay.runtimeType}', isOn: LOGGING_SWITCH);
        _logger.info('🎮 DemoFunctionality: hand type: ${hand.runtimeType}, length: ${hand.length}', isOn: LOGGING_SWITCH);
        _logger.info('🎮 DemoFunctionality: cardIndex: $cardIndex', isOn: LOGGING_SWITCH);
        _logger.info('🎮 DemoFunctionality: gameStateAfterDelay type: ${gameStateAfterDelay.runtimeType}', isOn: LOGGING_SWITCH);
        
        List<dynamic> discardPile;
        try {
          // Remove card from opponent's hand (create blank slot or remove)
          _logger.info('🎮 DemoFunctionality: Starting hand manipulation', isOn: LOGGING_SWITCH);
          _logger.info('🎮 DemoFunctionality: Checking hand[cardIndex] before manipulation', isOn: LOGGING_SWITCH);
          _logger.info('🎮 DemoFunctionality: hand[cardIndex] type: ${hand[cardIndex]?.runtimeType}, is null: ${hand[cardIndex] == null}', isOn: LOGGING_SWITCH);
          
          bool shouldCreateBlankSlot = cardIndex <= 3;
          _logger.info('🎮 DemoFunctionality: shouldCreateBlankSlot (initial): $shouldCreateBlankSlot', isOn: LOGGING_SWITCH);
          
          if (cardIndex > 3) {
            _logger.info('🎮 DemoFunctionality: Checking for cards after index $cardIndex', isOn: LOGGING_SWITCH);
            for (int i = cardIndex + 1; i < hand.length; i++) {
              _logger.info('🎮 DemoFunctionality: Checking hand[$i], type: ${hand[i]?.runtimeType}, is null: ${hand[i] == null}', isOn: LOGGING_SWITCH);
              if (hand[i] != null) {
                shouldCreateBlankSlot = true;
                break;
              }
            }
          }
          
          _logger.info('🎮 DemoFunctionality: shouldCreateBlankSlot (final): $shouldCreateBlankSlot', isOn: LOGGING_SWITCH);
          
          if (shouldCreateBlankSlot) {
            _logger.info('🎮 DemoFunctionality: Creating blank slot at index $cardIndex', isOn: LOGGING_SWITCH);
            hand[cardIndex] = null; // Create blank slot
          } else {
            _logger.info('🎮 DemoFunctionality: Removing card entirely at index $cardIndex', isOn: LOGGING_SWITCH);
            hand.removeAt(cardIndex); // Remove entirely
          }
          
          _logger.info('🎮 DemoFunctionality: Updating playerDataAfterDelay hand', isOn: LOGGING_SWITCH);
          playerDataAfterDelay['hand'] = hand;
          _logger.info('🎮 DemoFunctionality: Updated playerDataAfterDelay hand successfully', isOn: LOGGING_SWITCH);
          
          // Add card to discard pile
          _logger.info('🎮 DemoFunctionality: Getting discardPile from gameStateAfterDelay', isOn: LOGGING_SWITCH);
          _logger.info('🎮 DemoFunctionality: gameStateAfterDelay type: ${gameStateAfterDelay.runtimeType}', isOn: LOGGING_SWITCH);
          final discardPileRaw = gameStateAfterDelay['discardPile'];
          _logger.info('🎮 DemoFunctionality: discardPileRaw type: ${discardPileRaw?.runtimeType}, is null: ${discardPileRaw == null}', isOn: LOGGING_SWITCH);
          discardPile = (discardPileRaw as List<dynamic>?) ?? [];
          _logger.info('🎮 DemoFunctionality: Adding card to discardPile', isOn: LOGGING_SWITCH);
          discardPile.add(Map<String, dynamic>.from(opponentCardFullData));
          gameStateAfterDelay['discardPile'] = discardPile;
        } catch (e, stackTrace) {
          _logger.error('❌ DemoFunctionality: Error in auto-play section: $e', error: e, stackTrace: stackTrace, isOn: LOGGING_SWITCH);
          rethrow;
        }
        
        // Update state immediately after each opponent plays (for visual feedback)
        // Align with other demo state updates - use DutchGameStateUpdater
        if (currentGameIdAfterDelay.isNotEmpty) {
          _logger.info('🎮 DemoFunctionality: Getting currentGame from gamesAfterDelay', isOn: LOGGING_SWITCH);
          final currentGame = gamesAfterDelay[currentGameIdAfterDelay] as Map<String, dynamic>? ?? {};
          _logger.info('🎮 DemoFunctionality: currentGame is not null: ${currentGame.isNotEmpty}', isOn: LOGGING_SWITCH);
          _logger.info('🎮 DemoFunctionality: Getting currentGameData', isOn: LOGGING_SWITCH);
          final currentGameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
          _logger.info('🎮 DemoFunctionality: currentGameData is not null: ${currentGameData.isNotEmpty}', isOn: LOGGING_SWITCH);
          currentGameData['game_state'] = gameStateAfterDelay;
          currentGame['gameData'] = currentGameData;
          gamesAfterDelay[currentGameIdAfterDelay] = currentGame;
          
          // Update widget slices (aligns with _handlePlayCard pattern)
          final centerBoard = dutchGameStateAfterDelay['centerBoard'] as Map<String, dynamic>? ?? {};
          centerBoard['discardPile'] = discardPile;
          
          // Update opponents panel slice
          final opponentsPanel = dutchGameStateAfterDelay['opponentsPanel'] as Map<String, dynamic>? ?? {};
          final opponentsList = opponentsPanel['opponents'] as List<dynamic>? ?? [];
          
          // Update opponent in opponents list
          for (int j = 0; j < opponentsList.length; j++) {
            final opp = opponentsList[j];
            if (opp is Map<String, dynamic> && opp['id']?.toString() == playerId) {
              final handCount = hand.where((c) => c != null).length;
              opponentsList[j] = {
                ...opp,
                'handCount': handCount,
                'hand': hand,
              };
              break;
            }
          }
          
          opponentsPanel['opponents'] = opponentsList;
          
          // Create turn event for the same rank play (matches practice mode)
          final currentTurnEvents = dutchGameStateAfterDelay['turn_events'] as List<dynamic>? ?? [];
          final turnEvents = List<Map<String, dynamic>>.from(currentTurnEvents)
            ..add({
              'cardId': opponentCardId,
              'actionType': 'play',
              'playerId': playerId,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            });
          
          // Update state using official state updater
          final stateUpdater = DutchGameStateUpdater.instance;
          stateUpdater.updateStateSync({
            'games': gamesAfterDelay, // Updated games map with modified game state
            'discardPile': discardPile, // Updated discard pile
            'turn_events': turnEvents, // Add turn event for animation
            'lastUpdated': DateTime.now().toIso8601String(),
          });
          
          // Update widget slices using state updater
          final stateUpdaterForOpponent = DutchGameStateUpdater.instance;
          stateUpdaterForOpponent.updateStateSync({
            'centerBoard': centerBoard, // Updated center board slice
            'opponentsPanel': opponentsPanel, // Updated opponents panel slice
          });
          
          _logger.info('✅ DemoFunctionality: State updated for opponent $playerId play', isOn: LOGGING_SWITCH);
          
          // Cancel any existing same rank instructions timer
          _sameRankInstructionsTimer?.cancel();
          
          // Set timer to show same rank instructions 3 seconds after opponent plays
          _sameRankInstructionsTimer = Timer(const Duration(seconds: 3), () {
            _logger.info('🎮 DemoFunctionality: Showing same rank instructions after 3 seconds', isOn: LOGGING_SWITCH);
            
            final stateUpdaterForTimer = DutchGameStateUpdater.instance;
            stateUpdaterForTimer.updateStateSync({
              'demoInstructionsPhase': 'same_rank',
            });
            
            _logger.info('✅ DemoFunctionality: Same rank instructions shown', isOn: LOGGING_SWITCH);
          });
        }
        
        _logger.info('✅ DemoFunctionality: Opponent $playerId played ${opponentCardFullData['rank']} of ${opponentCardFullData['suit']}', isOn: LOGGING_SWITCH);
      }
    }
    
    _logger.info('✅ DemoFunctionality: Completed opponent same rank plays', isOn: LOGGING_SWITCH);
  }

  /// Handle replace drawn card action in demo mode
  Future<Map<String, dynamic>> _handleReplaceDrawnCard(Map<String, dynamic> payload) async {
    _logger.info('🎮 DemoFunctionality: Replace drawn card action (demo mode - no-op)', isOn: LOGGING_SWITCH);
    // TODO: Implement demo replace drawn card logic
    return {'success': true, 'mode': 'demo'};
  }

  /// Handle play drawn card action in demo mode
  Future<Map<String, dynamic>> _handlePlayDrawnCard(Map<String, dynamic> payload) async {
    _logger.info('🎮 DemoFunctionality: Play drawn card action (demo mode - no-op)', isOn: LOGGING_SWITCH);
    // TODO: Implement demo play drawn card logic
    return {'success': true, 'mode': 'demo'};
  }

  /// Handle initial peek action in demo mode
  /// This is called when a card is selected during initial peek phase
  Future<Map<String, dynamic>> _handleInitialPeek(Map<String, dynamic> payload) async {
    _logger.info('🎮 DemoFunctionality: Initial peek action', isOn: LOGGING_SWITCH);
    
    final cardId = payload['cardId']?.toString() ?? '';
    if (cardId.isEmpty) {
      _logger.warning('⚠️ DemoFunctionality: Invalid cardId in initial peek payload', isOn: LOGGING_SWITCH);
      return {'success': false, 'error': 'Invalid cardId'};
    }

    // Add card to initial peek selection
    final selectedCount = await addCardToInitialPeek(cardId);
    
    return {
      'success': true,
      'mode': 'demo',
      'selectedCount': selectedCount,
    };
  }

  /// Handle completed initial peek action in demo mode
  /// This is called when 2 cards have been selected
  /// Note: Drawing instructions are shown via timer in addCardToInitialPeek, not here
  Future<Map<String, dynamic>> _handleCompletedInitialPeek(Map<String, dynamic> payload) async {
    _logger.info('🎮 DemoFunctionality: Completed initial peek action', isOn: LOGGING_SWITCH);
    
    final cardIds = (payload['card_ids'] as List<dynamic>?)?.cast<String>() ?? [];
    if (cardIds.length != 2) {
      _logger.warning('⚠️ DemoFunctionality: Invalid card_ids count: ${cardIds.length}', isOn: LOGGING_SWITCH);
      return {'success': false, 'error': 'Expected exactly 2 card IDs'};
    }

    // Clear only the tracking set (not myCardsToPeek - cards should remain visible)
    _initialPeekSelectedCardIds.clear();
    _logger.info('🎮 DemoFunctionality: Cleared initial peek tracking (cards remain visible in myCardsToPeek)', isOn: LOGGING_SWITCH);
    
    // Note: Drawing instructions will be shown via the 5-second timer started in addCardToInitialPeek
    // Don't transition here - let the timer handle it
    
    _logger.info('✅ DemoFunctionality: Initial peek completed (drawing instructions will show after 5 seconds)', isOn: LOGGING_SWITCH);
    
    return {'success': true, 'mode': 'demo'};
  }

  /// Handle call final round action in demo mode
  /// Handle call final round action in demo mode
  /// Sets finalRoundActive flag and marks player as having called final round
  /// Player can still play cards after calling Dutch
  Future<Map<String, dynamic>> _handleCallFinalRound(Map<String, dynamic> payload) async {
    _logger.info('🎮 DemoFunctionality: Call final round action intercepted', isOn: LOGGING_SWITCH);
    _logger.info('🎮 DemoFunctionality: Payload: $payload', isOn: LOGGING_SWITCH);
    
    // Re-read latest state from SSOT to ensure we have the most up-to-date data
    final stateManager = StateManager();
    final latestDutchGameState = stateManager.getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final latestGames = latestDutchGameState['games'] as Map<String, dynamic>? ?? {};
    final currentGameId = latestDutchGameState['currentGameId']?.toString() ?? '';
    
    if (currentGameId.isEmpty) {
      _logger.error('❌ DemoFunctionality: No currentGameId found', isOn: LOGGING_SWITCH);
      return {'success': false, 'error': 'No active game'};
    }
    
    final latestCurrentGame = latestGames[currentGameId] as Map<String, dynamic>? ?? {};
    final latestGameData = latestCurrentGame['gameData'] as Map<String, dynamic>? ?? {};
    final latestGameState = latestGameData['game_state'] as Map<String, dynamic>? ?? {};
    final latestPlayers = latestGameState['players'] as List<dynamic>? ?? [];
    
    // Find the user player (isHuman == true)
    Map<String, dynamic>? userPlayer;
    int userPlayerIndex = -1;
    
    for (int i = 0; i < latestPlayers.length; i++) {
      final p = latestPlayers[i];
      if (p is Map<String, dynamic> && p['isHuman'] == true) {
        userPlayer = Map<String, dynamic>.from(p);
        userPlayerIndex = i;
        break;
      }
    }
    
    if (userPlayer == null) {
      _logger.error('❌ DemoFunctionality: User player not found', isOn: LOGGING_SWITCH);
      return {'success': false, 'error': 'User player not found'};
    }
    
    final userId = userPlayer['id']?.toString() ?? '';
    if (userId.isEmpty) {
      _logger.error('❌ DemoFunctionality: User player ID is empty', isOn: LOGGING_SWITCH);
      return {'success': false, 'error': 'User player ID is empty'};
    }
    
    _logger.info('✅ DemoFunctionality: Found user player: ${userPlayer['name']} ($userId)', isOn: LOGGING_SWITCH);
    
    // Update game state to indicate final round is active
    final updatedGameState = Map<String, dynamic>.from(latestGameState);
    updatedGameState['finalRoundCalledBy'] = userId;
    updatedGameState['finalRoundActive'] = true;
    
    // Update player's hasCalledFinalRound flag
    userPlayer['hasCalledFinalRound'] = true;
    // Keep player status as 'playing_card' so they can still play their card
    userPlayer['status'] = 'playing_card';
    
    // Update players list
    final updatedPlayers = List<dynamic>.from(latestPlayers);
    updatedPlayers[userPlayerIndex] = userPlayer;
    updatedGameState['players'] = updatedPlayers;
    
    // Set currentPlayer to user player
    updatedGameState['currentPlayer'] = userPlayer;
    
    // Update SSOT
    final updatedGameData = Map<String, dynamic>.from(latestGameData);
    updatedGameData['game_state'] = updatedGameState;
    final updatedCurrentGame = Map<String, dynamic>.from(latestCurrentGame);
    updatedCurrentGame['gameData'] = updatedGameData;
    
    final updatedGames = Map<String, dynamic>.from(latestGames);
    updatedGames[currentGameId] = updatedCurrentGame;
    
    // Get current dutch game state for widget slice updates
    final currentDutchGameState = stateManager.getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    
    // Update widget slices manually
    final centerBoard = currentDutchGameState['centerBoard'] as Map<String, dynamic>? ?? {};
    centerBoard['playerStatus'] = 'playing_card';
    
    final myHand = currentDutchGameState['myHand'] as Map<String, dynamic>? ?? {};
    myHand['playerStatus'] = 'playing_card';
    
    // Update state using official state updater
    final stateUpdater = DutchGameStateUpdater.instance;
    
    // Combine all state updates into a single atomic update
    stateUpdater.updateStateSync({
      'currentGameId': currentGameId,
      'games': updatedGames, // SSOT with final round info
      'currentPlayer': userPlayer,
      'currentPlayerStatus': 'playing_card',
      'playerStatus': 'playing_card',
      'isGameActive': true,
      'isMyTurn': true,
      'centerBoard': centerBoard,
      'myHand': myHand,
      'demoInstructionsPhase': 'playing', // Show playing phase after calling Dutch
      'lastUpdated': DateTime.now().toIso8601String(),
    });
    
    _logger.info('✅ DemoFunctionality: Final round called successfully - player can still play cards', isOn: LOGGING_SWITCH);
    
    return {'success': true, 'mode': 'demo', 'finalRoundActive': true, 'finalRoundCalledBy': userId};
  }

  /// Handle collect from discard action in demo mode
  Future<Map<String, dynamic>> _handleCollectFromDiscard(Map<String, dynamic> payload) async {
    _logger.info('🎮 DemoFunctionality: Collect from discard action (demo mode - no-op)', isOn: LOGGING_SWITCH);
    // TODO: Implement demo collect from discard logic
    return {'success': true, 'mode': 'demo'};
  }

  /// Handle use special power action in demo mode
  Future<Map<String, dynamic>> _handleUseSpecialPower(Map<String, dynamic> payload) async {
    _logger.info('🎮 DemoFunctionality: Use special power action (demo mode - no-op)', isOn: LOGGING_SWITCH);
    // TODO: Implement demo use special power logic
    return {'success': true, 'mode': 'demo'};
  }

  /// Handle jack swap action in demo mode
  /// Intercepts PlayerAction.jackSwap() which sends event 'jack_swap' with payload:
  /// - first_card_id: ID of the first card to swap
  /// - first_player_id: ID of the player who owns the first card
  /// - second_card_id: ID of the second card to swap
  /// - second_player_id: ID of the player who owns the second card
  /// - game_id: Current game ID
  Future<Map<String, dynamic>> _handleJackSwap(Map<String, dynamic> payload) async {
    _logger.info('🎮 DemoFunctionality: Jack swap action intercepted', isOn: LOGGING_SWITCH);
    _logger.info('🎮 DemoFunctionality: Payload: $payload', isOn: LOGGING_SWITCH);
    
    final firstCardId = payload['first_card_id']?.toString() ?? '';
    final firstPlayerId = payload['first_player_id']?.toString() ?? '';
    final secondCardId = payload['second_card_id']?.toString() ?? '';
    final secondPlayerId = payload['second_player_id']?.toString() ?? '';
    
    if (firstCardId.isEmpty || firstPlayerId.isEmpty || secondCardId.isEmpty || secondPlayerId.isEmpty) {
      _logger.error('❌ DemoFunctionality: Missing required fields for jack swap', isOn: LOGGING_SWITCH);
      return {'success': false, 'error': 'Missing required fields'};
    }
    
    _logger.info('🎮 DemoFunctionality: Swapping cards - First: $firstCardId (player: $firstPlayerId), Second: $secondCardId (player: $secondPlayerId)', isOn: LOGGING_SWITCH);
    
    // Re-read latest state from SSOT to ensure we have the most up-to-date data
    final stateManager = StateManager();
    final latestDutchGameState = stateManager.getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final latestGames = latestDutchGameState['games'] as Map<String, dynamic>? ?? {};
    final currentGameId = latestDutchGameState['currentGameId']?.toString() ?? '';
    
    if (currentGameId.isEmpty) {
      _logger.error('❌ DemoFunctionality: No currentGameId found', isOn: LOGGING_SWITCH);
      return {'success': false, 'error': 'No active game'};
    }
    
    final latestCurrentGame = latestGames[currentGameId] as Map<String, dynamic>? ?? {};
    final latestGameData = latestCurrentGame['gameData'] as Map<String, dynamic>? ?? {};
    final latestGameState = latestGameData['game_state'] as Map<String, dynamic>? ?? {};
    final latestPlayers = latestGameState['players'] as List<dynamic>? ?? [];
    
    // Find both players
    Map<String, dynamic>? firstPlayer;
    int firstPlayerIndex = -1;
    Map<String, dynamic>? secondPlayer;
    int secondPlayerIndex = -1;
    
    for (int i = 0; i < latestPlayers.length; i++) {
      final p = latestPlayers[i];
      if (p is Map<String, dynamic>) {
        final pId = p['id']?.toString() ?? '';
        if (pId == firstPlayerId) {
          firstPlayer = Map<String, dynamic>.from(p);
          firstPlayerIndex = i;
        }
        if (pId == secondPlayerId) {
          secondPlayer = Map<String, dynamic>.from(p);
          secondPlayerIndex = i;
        }
      }
    }
    
    if (firstPlayer == null || secondPlayer == null) {
      _logger.error('❌ DemoFunctionality: One or both players not found. firstPlayerId: $firstPlayerId (found: ${firstPlayer != null}), secondPlayerId: $secondPlayerId (found: ${secondPlayer != null})', isOn: LOGGING_SWITCH);
      return {'success': false, 'error': 'Player not found'};
    }
    
    _logger.info('✅ DemoFunctionality: Both players found - firstPlayer: ${firstPlayer['name']} (${firstPlayer['id']}), secondPlayer: ${secondPlayer['name']} (${secondPlayer['id']})', isOn: LOGGING_SWITCH);
    
    // Get player hands (convert to mutable lists)
    final firstPlayerHand = List<dynamic>.from(firstPlayer['hand'] as List<dynamic>? ?? []);
    final secondPlayerHand = List<dynamic>.from(secondPlayer['hand'] as List<dynamic>? ?? []);
    
    // Find the cards in each player's hand
    Map<String, dynamic>? firstCard;
    int? firstCardIndex;
    Map<String, dynamic>? secondCard;
    int? secondCardIndex;
    
    // Find first card
    for (int i = 0; i < firstPlayerHand.length; i++) {
      final card = firstPlayerHand[i];
      if (card != null && card is Map<String, dynamic>) {
        final cardIdInHand = card['cardId']?.toString() ?? '';
        if (cardIdInHand == firstCardId) {
          firstCard = Map<String, dynamic>.from(card);
          firstCardIndex = i;
          break;
        }
      }
    }
    
    // Find second card
    for (int i = 0; i < secondPlayerHand.length; i++) {
      final card = secondPlayerHand[i];
      if (card != null && card is Map<String, dynamic>) {
        final cardIdInHand = card['cardId']?.toString() ?? '';
        if (cardIdInHand == secondCardId) {
          secondCard = Map<String, dynamic>.from(card);
          secondCardIndex = i;
          break;
        }
      }
    }
    
    // Validate cards found
    if (firstCard == null || secondCard == null || firstCardIndex == null || secondCardIndex == null) {
      _logger.error('❌ DemoFunctionality: One or both cards not found in players\' hands', isOn: LOGGING_SWITCH);
      return {'success': false, 'error': 'Card not found in hand'};
    }
    
    _logger.info('✅ DemoFunctionality: Found cards - First card at index $firstCardIndex in player $firstPlayerId hand, Second card at index $secondCardIndex in player $secondPlayerId hand', isOn: LOGGING_SWITCH);
    
    // Get full card data for both cards to ensure we have the correct cardId
    final firstCardFullData = _getCardById(firstCardId);
    final secondCardFullData = _getCardById(secondCardId);
    
    if (firstCardFullData == null || secondCardFullData == null) {
      _logger.error('❌ DemoFunctionality: Failed to get full card data for swap - firstCard: ${firstCardFullData != null}, secondCard: ${secondCardFullData != null}', isOn: LOGGING_SWITCH);
      return {'success': false, 'error': 'Failed to get card data'};
    }
    
    // Convert swapped cards to ID-only format (player hands always store ID-only cards)
    // Format matches dutch game: {'cardId': 'xxx', 'suit': '?', 'rank': '?', 'points': 0}
    final firstCardIdOnly = {
      'cardId': firstCardFullData['cardId'],
      'suit': '?',      // Face-down: hide suit
      'rank': '?',      // Face-down: hide rank
      'points': 0,      // Face-down: hide points
    };
    
    final secondCardIdOnly = {
      'cardId': secondCardFullData['cardId'],
      'suit': '?',      // Face-down: hide suit
      'rank': '?',      // Face-down: hide rank
      'points': 0,      // Face-down: hide points
    };
    
    // Perform the swap with ID-only format
    firstPlayerHand[firstCardIndex] = secondCardIdOnly;
    secondPlayerHand[secondCardIndex] = firstCardIdOnly;
    
    _logger.info('✅ DemoFunctionality: Successfully swapped cards: $firstCardId <-> $secondCardId', isOn: LOGGING_SWITCH);
    _logger.info('✅ DemoFunctionality: Player $firstPlayerId now has card $secondCardId at index $firstCardIndex', isOn: LOGGING_SWITCH);
    _logger.info('✅ DemoFunctionality: Player $secondPlayerId now has card $firstCardId at index $secondCardIndex', isOn: LOGGING_SWITCH);
    
    // Update player hands in player objects
    firstPlayer['hand'] = firstPlayerHand;
    secondPlayer['hand'] = secondPlayerHand;
    
    // Update user player status to 'playing_card' after swap completes
    // Check if user is one of the players involved
    bool userInvolved = false;
    if (firstPlayer['isHuman'] == true) {
      firstPlayer['status'] = 'playing_card';
      userInvolved = true;
    }
    if (secondPlayer['isHuman'] == true) {
      secondPlayer['status'] = 'playing_card';
      userInvolved = true;
    }
    
    // Update players list
    final updatedPlayers = List<dynamic>.from(latestPlayers);
    updatedPlayers[firstPlayerIndex] = firstPlayer;
    updatedPlayers[secondPlayerIndex] = secondPlayer;
    
    // Update SSOT
    final updatedGameState = Map<String, dynamic>.from(latestGameState);
    updatedGameState['players'] = updatedPlayers;
    
    // Ensure finalRoundActive is false (needed for Call Final Round button visibility)
    updatedGameState['finalRoundActive'] = false;
    updatedGameState['finalRoundCalledBy'] = null;
    
    // If user is involved, set currentPlayer to user player
    if (userInvolved) {
      Map<String, dynamic>? userPlayer;
      for (final p in updatedPlayers) {
        if (p is Map<String, dynamic> && p['isHuman'] == true) {
          userPlayer = p;
          break;
        }
      }
      if (userPlayer != null) {
        updatedGameState['currentPlayer'] = userPlayer;
        // Ensure user player doesn't have hasCalledFinalRound set (needed for button visibility)
        userPlayer['hasCalledFinalRound'] = false;
        // Update the player in the list
        for (int i = 0; i < updatedPlayers.length; i++) {
          if (updatedPlayers[i] is Map<String, dynamic> && 
              updatedPlayers[i]['id']?.toString() == userPlayer['id']?.toString()) {
            updatedPlayers[i] = userPlayer;
            break;
          }
        }
        updatedGameState['players'] = updatedPlayers;
      }
    }
    
    final updatedGameData = Map<String, dynamic>.from(latestGameData);
    updatedGameData['game_state'] = updatedGameState;
    final updatedCurrentGame = Map<String, dynamic>.from(latestCurrentGame);
    updatedCurrentGame['gameData'] = updatedGameData;
    
    // Update myHandCards if user is involved
    if (userInvolved) {
      Map<String, dynamic>? userPlayer;
      for (final p in updatedPlayers) {
        if (p is Map<String, dynamic> && p['isHuman'] == true) {
          userPlayer = p;
          break;
        }
      }
      if (userPlayer != null) {
        final userHand = userPlayer['hand'] as List<dynamic>? ?? [];
        final myHandCards = List<Map<String, dynamic>>.from(userHand.map((c) {
          if (c is Map<String, dynamic>) {
            return Map<String, dynamic>.from(c);
          }
          return <String, dynamic>{};
        }));
        updatedCurrentGame['myHandCards'] = myHandCards;
      }
    }
    
    final updatedGames = Map<String, dynamic>.from(latestGames);
    updatedGames[currentGameId] = updatedCurrentGame;
    
    // Get current dutch game state for widget slice updates
    final stateManagerForSlices = StateManager();
    final currentDutchGameState = stateManagerForSlices.getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    
    // Update widget slices manually
    final centerBoard = currentDutchGameState['centerBoard'] as Map<String, dynamic>? ?? {};
    if (userInvolved) {
      centerBoard['playerStatus'] = 'playing_card';
    }
    
    final myHand = currentDutchGameState['myHand'] as Map<String, dynamic>? ?? {};
    if (userInvolved) {
      myHand['playerStatus'] = 'playing_card';
      if (updatedCurrentGame['myHandCards'] != null) {
        myHand['cards'] = updatedCurrentGame['myHandCards'];
      }
    }
    
    final opponentsPanel = currentDutchGameState['opponentsPanel'] as Map<String, dynamic>? ?? {};
    final opponents = opponentsPanel['opponents'] as List<dynamic>? ?? [];
    // Update opponent hands in opponentsPanel if they were involved
    for (int i = 0; i < opponents.length; i++) {
      final opponent = opponents[i];
      if (opponent is Map<String, dynamic>) {
        final opponentId = opponent['id']?.toString() ?? '';
        if (opponentId == firstPlayerId && firstPlayer['isHuman'] != true) {
          opponents[i] = {
            ...opponent,
            'hand': firstPlayerHand,
          };
        } else if (opponentId == secondPlayerId && secondPlayer['isHuman'] != true) {
          opponents[i] = {
            ...opponent,
            'hand': secondPlayerHand,
          };
        }
      }
    }
    opponentsPanel['opponents'] = opponents;
    
    // Update state using official state updater
    final stateUpdater = DutchGameStateUpdater.instance;
    
    // Step 1: Update SSOT and main state fields using updateStateSync
    // Also ensure isGameActive and isMyTurn are set for Call Final Round button visibility
    // Note: isMyTurn must be set at top level of dutchGameState, not just in game data
    if (userInvolved) {
      // Update isMyTurn in the game data first
      final updatedGameForMyTurn = updatedGames[currentGameId] as Map<String, dynamic>? ?? {};
      updatedGameForMyTurn['isMyTurn'] = true;
      updatedGames[currentGameId] = updatedGameForMyTurn;
    }
    
    // Combine all state updates into a single atomic update for immediate widget rebuild
    final stateUpdates = <String, dynamic>{
      'currentGameId': currentGameId,
      'games': updatedGames, // SSOT with swapped cards (includes isMyTurn in game data)
      'centerBoard': centerBoard,
      'myHand': myHand,
      'opponentsPanel': opponentsPanel,
      'lastUpdated': DateTime.now().toIso8601String(),
    };
    
    if (userInvolved) {
      stateUpdates.addAll({
        'currentPlayer': updatedGameState['currentPlayer'],
        'currentPlayerStatus': 'playing_card',
        'playerStatus': 'playing_card',
        'isGameActive': true, // Required for Call Final Round button
        'isMyTurn': true, // Required for Call Final Round button (top level)
        'demoInstructionsPhase': 'call_dutch', // Show call dutch instructions after swap
      });
    }
    
    // Single atomic update to ensure all state changes happen together and widget rebuilds
    stateUpdater.updateStateSync(stateUpdates);
    
    _logger.info('✅ DemoFunctionality: Jack swap completed - cards swapped successfully', isOn: LOGGING_SWITCH);
    
    return {'success': true, 'mode': 'demo', 'firstCardId': firstCardId, 'secondCardId': secondCardId};
  }

  /// Handle queen peek action in demo mode
  /// Intercepts PlayerAction.queenPeek() which sends event 'queen_peek' with payload:
  /// - card_id: ID of the card to peek at
  /// - ownerId: ID of the player who owns the card
  /// - game_id: Current game ID
  /// - player_id: Auto-added by event emitter
  Future<Map<String, dynamic>> _handleQueenPeek(Map<String, dynamic> payload) async {
    _logger.info('🎮 DemoFunctionality: Queen peek action intercepted', isOn: LOGGING_SWITCH);
    _logger.info('🎮 DemoFunctionality: Payload: $payload', isOn: LOGGING_SWITCH);
    
    final cardId = payload['card_id']?.toString() ?? payload['cardId']?.toString() ?? '';
    if (cardId.isEmpty) {
      _logger.error('❌ DemoFunctionality: No card_id provided for queen peek', isOn: LOGGING_SWITCH);
      return {'success': false, 'error': 'No card_id provided'};
    }
    
    // Get full card data from originalDeck (similar to initial peek)
    final fullCardData = _getCardById(cardId);
    if (fullCardData == null) {
      _logger.error('❌ DemoFunctionality: Failed to get full card data for $cardId', isOn: LOGGING_SWITCH);
      return {'success': false, 'error': 'Failed to get card data'};
    }
    
    _logger.info('🎮 DemoFunctionality: Peeking at card: ${fullCardData['rank']} of ${fullCardData['suit']}', isOn: LOGGING_SWITCH);
    
    // Re-read latest state from SSOT to ensure we have the most up-to-date data
    final stateManager = StateManager();
    final latestDutchGameState = stateManager.getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final latestGames = latestDutchGameState['games'] as Map<String, dynamic>? ?? {};
    final currentGameId = latestDutchGameState['currentGameId']?.toString() ?? '';
    
    if (currentGameId.isEmpty) {
      _logger.error('❌ DemoFunctionality: No currentGameId found', isOn: LOGGING_SWITCH);
      return {'success': false, 'error': 'No active game'};
    }
    
    final latestCurrentGame = latestGames[currentGameId] as Map<String, dynamic>? ?? {};
    final latestGameData = latestCurrentGame['gameData'] as Map<String, dynamic>? ?? {};
    final latestGameState = latestGameData['game_state'] as Map<String, dynamic>? ?? {};
    final latestPlayers = latestGameState['players'] as List<dynamic>? ?? [];
    
    // Find user player from latest players
    Map<String, dynamic>? userPlayer;
    int userPlayerIndex = -1;
    for (int i = 0; i < latestPlayers.length; i++) {
      final p = latestPlayers[i];
      if (p is Map<String, dynamic> && p['isHuman'] == true) {
        userPlayer = Map<String, dynamic>.from(p);
        userPlayerIndex = i;
        break;
      }
    }
    
    if (userPlayer == null) {
      _logger.error('❌ DemoFunctionality: User player not found in latest players', isOn: LOGGING_SWITCH);
      return {'success': false, 'error': 'User player not found'};
    }
    
    // Immediately set player status to 'waiting' (queen peek in progress)
    userPlayer['status'] = 'waiting';
    
    // Update players list with updated user player
    final updatedPlayers = List<dynamic>.from(latestPlayers);
    updatedPlayers[userPlayerIndex] = userPlayer;
    
    // Update SSOT with player status change (waiting during peek)
    final updatedGameState = Map<String, dynamic>.from(latestGameState);
    updatedGameState['players'] = updatedPlayers;
    updatedGameState['currentPlayer'] = userPlayer; // Set currentPlayer so _getCurrentUserStatus can find it
    final updatedGameData = Map<String, dynamic>.from(latestGameData);
    updatedGameData['game_state'] = updatedGameState;
    final updatedCurrentGame = Map<String, dynamic>.from(latestCurrentGame);
    updatedCurrentGame['gameData'] = updatedGameData;
    final updatedGames = Map<String, dynamic>.from(latestGames);
    updatedGames[currentGameId] = updatedCurrentGame;
    
    // Get current dutch game state for widget slice updates
    final stateManagerForSlices = StateManager();
    final currentDutchGameState = stateManagerForSlices.getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    
    // Update widget slices manually
    final centerBoard = currentDutchGameState['centerBoard'] as Map<String, dynamic>? ?? {};
    centerBoard['playerStatus'] = 'waiting';
    
    final myHand = currentDutchGameState['myHand'] as Map<String, dynamic>? ?? {};
    myHand['playerStatus'] = 'waiting';
    
    // Update state using official state updater
    final stateUpdater = DutchGameStateUpdater.instance;
    
    // Step 1: Update SSOT and main state fields using updateStateSync (immediate - show card and set to waiting)
    stateUpdater.updateStateSync({
      'currentGameId': currentGameId,
      'games': updatedGames, // SSOT with player status = 'waiting'
      'myCardsToPeek': [fullCardData], // Show the peeked card with full data (similar to initial peek)
      'currentPlayer': userPlayer, // Set currentPlayer so _getCurrentUserStatus can find it
      'currentPlayerStatus': 'waiting',
      'playerStatus': 'waiting',
      'lastUpdated': DateTime.now().toIso8601String(),
    });
    
    // Step 2: Update widget slices using updateStateSync
    stateUpdater.updateStateSync({
      'centerBoard': centerBoard, // Update centerBoard slice
      'myHand': myHand, // Update myHand slice with waiting status
    });
    
    // Step 3: Clear queen peek instructions (user is waiting during peek)
    stateUpdater.updateState({
      'demoInstructionsPhase': '', // Clear instructions during peek
      'lastUpdated': DateTime.now().toIso8601String(),
    });
    
    _logger.info('✅ DemoFunctionality: Queen peek card selected, showing card and setting status to waiting', isOn: LOGGING_SWITCH);
    _logger.info('✅ DemoFunctionality: Card data added to myCardsToPeek: ${fullCardData['rank']} of ${fullCardData['suit']}', isOn: LOGGING_SWITCH);
    
    // Cancel any existing queen peek timer
    _queenPeekTimer?.cancel();
    
    // Start 3-second timer before updating hand to jacks and changing to playing_card
    _queenPeekTimer = Timer(Duration(seconds: 3), () {
      _logger.info('🎮 DemoFunctionality: Queen peek timer expired, updating hand to 4 jacks and setting status to playing_card', isOn: LOGGING_SWITCH);
      
      // Re-read latest state from SSOT
      final timerStateManager = StateManager();
      final timerDutchGameState = timerStateManager.getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final timerGames = timerDutchGameState['games'] as Map<String, dynamic>? ?? {};
      final timerCurrentGameId = timerDutchGameState['currentGameId']?.toString() ?? '';
      
      if (timerCurrentGameId.isEmpty) {
        _logger.error('❌ DemoFunctionality: No currentGameId found in timer callback', isOn: LOGGING_SWITCH);
        return;
      }
      
      final timerCurrentGame = timerGames[timerCurrentGameId] as Map<String, dynamic>? ?? {};
      final timerGameData = timerCurrentGame['gameData'] as Map<String, dynamic>? ?? {};
      final timerGameState = timerGameData['game_state'] as Map<String, dynamic>? ?? {};
      final timerPlayers = timerGameState['players'] as List<dynamic>? ?? [];
      
      // Find user player
      Map<String, dynamic>? timerUserPlayer;
      int timerUserPlayerIndex = -1;
      for (int i = 0; i < timerPlayers.length; i++) {
        final p = timerPlayers[i];
        if (p is Map<String, dynamic> && p['isHuman'] == true) {
          timerUserPlayer = Map<String, dynamic>.from(p);
          timerUserPlayerIndex = i;
          break;
        }
      }
      
      if (timerUserPlayer == null) {
        _logger.error('❌ DemoFunctionality: User player not found in timer callback', isOn: LOGGING_SWITCH);
        return;
      }
      
      // Update user's hand from 4 queens to 4 jacks (for jack swap demo)
      final originalDeck = timerGameState['originalDeck'] as List<dynamic>? ?? [];
      final suits = ['hearts', 'diamonds', 'clubs', 'spades'];
      final jacksHand = <Map<String, dynamic>>[];
      
      // Find each jack by suit from originalDeck
      for (final suit in suits) {
        Map<String, dynamic>? jackCard;
        for (final card in originalDeck) {
          if (card is Map<String, dynamic> && 
              card['rank']?.toString() == 'jack' && 
              card['suit']?.toString() == suit) {
            jackCard = Map<String, dynamic>.from(card);
            break;
          }
        }
        
        // If jack not found in originalDeck, create one with standard ID
        if (jackCard == null) {
          jackCard = {
            'cardId': 'card_demo_jack_${suit}_0',
            'rank': 'jack',
            'suit': suit,
            'points': 10,
            'specialPower': 'swap_cards',
          };
          _logger.warning('⚠️ DemoFunctionality: Jack of $suit not found in originalDeck, created fallback', isOn: LOGGING_SWITCH);
        }
        
        // Convert to ID-only format (as stored in hands) using the actual card ID
        final idOnlyCard = {
          'cardId': jackCard['cardId'], // Use actual card ID from originalDeck
          'suit': '?',      // Face-down: hide suit
          'rank': '?',      // Face-down: hide rank
          'points': 0,      // Face-down: hide points
        };
        jacksHand.add(idOnlyCard);
        _logger.info('✅ DemoFunctionality: Added jack of $suit to hand with ID: ${jackCard['cardId']}', isOn: LOGGING_SWITCH);
      }
      
      // Update user's hand to 4 jacks and status to playing_card
      timerUserPlayer['hand'] = jacksHand;
      timerUserPlayer['status'] = 'playing_card';
      
      // Update players list
      final timerUpdatedPlayers = List<dynamic>.from(timerPlayers);
      timerUpdatedPlayers[timerUserPlayerIndex] = timerUserPlayer;
      
      // Update SSOT with new hand and playing_card status
      final timerUpdatedGameState = Map<String, dynamic>.from(timerGameState);
      timerUpdatedGameState['players'] = timerUpdatedPlayers;
      timerUpdatedGameState['currentPlayer'] = timerUserPlayer;
      final timerUpdatedGameData = Map<String, dynamic>.from(timerGameData);
      timerUpdatedGameData['game_state'] = timerUpdatedGameState;
      final timerUpdatedCurrentGame = Map<String, dynamic>.from(timerCurrentGame);
      timerUpdatedCurrentGame['gameData'] = timerUpdatedGameData;
      // Update myHandCards with the new jacks hand
      final timerMyHandCards = List<Map<String, dynamic>>.from(jacksHand.map((c) => Map<String, dynamic>.from(c)));
      timerUpdatedCurrentGame['myHandCards'] = timerMyHandCards;
      final timerUpdatedGames = Map<String, dynamic>.from(timerGames);
      timerUpdatedGames[timerCurrentGameId] = timerUpdatedCurrentGame;
      
      // Get current dutch game state for widget slice updates
      final timerStateManagerForSlices = StateManager();
      final timerCurrentDutchGameState = timerStateManagerForSlices.getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      
      // Update widget slices manually
      final timerCenterBoard = timerCurrentDutchGameState['centerBoard'] as Map<String, dynamic>? ?? {};
      timerCenterBoard['playerStatus'] = 'playing_card';
      
      final timerMyHand = timerCurrentDutchGameState['myHand'] as Map<String, dynamic>? ?? {};
      timerMyHand['playerStatus'] = 'playing_card';
      timerMyHand['cards'] = timerMyHandCards; // Update cards in myHand slice with new jacks
      
      // Update state using official state updater
      final timerStateUpdater = DutchGameStateUpdater.instance;
      
      // Step 1: Update SSOT and main state fields using updateStateSync
      timerStateUpdater.updateStateSync({
        'currentGameId': timerCurrentGameId,
        'games': timerUpdatedGames, // SSOT with player status = 'playing_card' and new jacks hand
        'myCardsToPeek': [], // Clear peeked card (convert back to ID-only after timer)
        'currentPlayer': timerUserPlayer,
        'currentPlayerStatus': 'playing_card',
        'playerStatus': 'playing_card',
        'lastUpdated': DateTime.now().toIso8601String(),
      });
      
      // Step 2: Update widget slices using updateStateSync
      timerStateUpdater.updateStateSync({
        'centerBoard': timerCenterBoard, // Update centerBoard slice
        'myHand': timerMyHand, // Update myHand slice with new status and cards
      });
      
      // Step 3: Show special plays instructions (for jack swap demo)
      timerStateUpdater.updateState({
        'demoInstructionsPhase': 'special_plays', // Show special plays instructions
        'lastUpdated': DateTime.now().toIso8601String(),
      });
      
      _logger.info('✅ DemoFunctionality: Queen peek timer expired - updated hand to 4 jacks and status to playing_card', isOn: LOGGING_SWITCH);
      _logger.info('✅ DemoFunctionality: Showing special plays instructions', isOn: LOGGING_SWITCH);
      _queenPeekTimer = null;
    });
    
    return {'success': true, 'mode': 'demo', 'cardId': cardId, 'cardData': fullCardData};
  }

  /// Handle play out of turn action in demo mode
  Future<Map<String, dynamic>> _handlePlayOutOfTurn(Map<String, dynamic> payload) async {
    _logger.info('🎮 DemoFunctionality: Play out of turn action (demo mode - no-op)', isOn: LOGGING_SWITCH);
    // TODO: Implement demo play out of turn logic
    return {'success': true, 'mode': 'demo'};
  }

  /// Get instructions for a specific phase
  /// Returns a map with 'isVisible', 'title', and 'paragraph'
  Map<String, dynamic> getInstructionsForPhase(String phase) {
    // Find matching instruction for the exact phase name
    final instruction = _demoPhaseInstructions.firstWhere(
      (inst) => inst.phase == phase,
      orElse: () => DemoPhaseInstruction(
        phase: phase,
        title: '',
        paragraph: '',
      ),
    );

    // Determine if instructions should be visible
    // Instructions are visible if phase matches one of our demo phases exactly
    final isVisible = _demoPhaseInstructions.any((inst) => inst.phase == phase);

    return {
      'isVisible': isVisible,
      'title': instruction.title,
      'paragraph': instruction.paragraph,
      'hasButton': instruction.hasButton,
    };
  }

  /// Get all demo phase instructions (for reference/debugging)
  List<Map<String, dynamic>> getAllPhaseInstructions() {
    return _demoPhaseInstructions.map((inst) => inst.toMap()).toList();
  }

  /// Transition from initial phase to initial_peek phase
  /// Updates the demoInstructionsPhase in StateManager (separate from game phase)
  void transitionToInitialPeek() {
    _logger.info('🎮 DemoFunctionality: Transitioning demo instructions from initial to initial_peek', isOn: LOGGING_SWITCH);
    
    // Clear any previous selection (including myCardsToPeek since we're starting fresh)
    clearInitialPeekSelection();
    
    // Update demoInstructionsPhase using state updater
    final stateUpdater = DutchGameStateUpdater.instance;
    stateUpdater.updateStateSync({
      'demoInstructionsPhase': 'initial_peek',
    });
    
    _logger.info('✅ DemoFunctionality: Demo instructions phase transitioned to initial_peek', isOn: LOGGING_SWITCH);
  }

  /// Restore original hand (Ace hearts, 5 diamonds, 8 clubs, 4 hearts) and update piles
  /// Returns the restored hand as ID-only cards and updated draw/discard piles
  Map<String, dynamic> _restoreOriginalHand(
    List<dynamic> originalDeck,
    List<dynamic> currentDrawPile,
    List<dynamic> currentDiscardPile,
    Map<String, dynamic> playedCard,
  ) {
    _logger.info('🎮 DemoFunctionality: Restoring original hand (Ace hearts, 5 diamonds, 8 clubs, 4 hearts)', isOn: LOGGING_SWITCH);
    
    // Helper to find card by rank and suit
    Map<String, dynamic>? _findCard(String rank, String suit) {
      for (final card in originalDeck) {
        if (card is Map<String, dynamic> && 
            card['rank']?.toString() == rank && 
            card['suit']?.toString() == suit) {
          return Map<String, dynamic>.from(card);
        }
      }
      return null;
    }
    
    // Find the 4 original cards
    final aceHearts = _findCard('ace', 'hearts');
    final fiveDiamonds = _findCard('5', 'diamonds');
    final eightClubs = _findCard('8', 'clubs');
    final fourHearts = _findCard('4', 'hearts');
    
    if (aceHearts == null || fiveDiamonds == null || eightClubs == null || fourHearts == null) {
      _logger.error('❌ DemoFunctionality: Could not find all original cards in deck', isOn: LOGGING_SWITCH);
      return {
        'hand': <Map<String, dynamic>>[],
        'drawPile': currentDrawPile,
        'discardPile': currentDiscardPile,
      };
    }
    
    // Convert to ID-only format
    Map<String, dynamic> _cardToIdOnly(Map<String, dynamic> card) => {
      'cardId': card['cardId'],
      'suit': '?',
      'rank': '?',
      'points': 0,
    };
    
    final restoredHand = [
      _cardToIdOnly(aceHearts),
      _cardToIdOnly(fiveDiamonds),
      _cardToIdOnly(eightClubs),
      _cardToIdOnly(fourHearts),
    ];
    
    _logger.info('✅ DemoFunctionality: Restored original hand with ${restoredHand.length} cards', isOn: LOGGING_SWITCH);
    
    // Create mutable copies of piles
    final updatedDrawPile = List<dynamic>.from(currentDrawPile);
    final updatedDiscardPile = List<dynamic>.from(currentDiscardPile);
    
    // Remove original cards from draw pile if present
    final originalCardIds = [
      aceHearts['cardId'],
      fiveDiamonds['cardId'],
      eightClubs['cardId'],
      fourHearts['cardId'],
    ];
    
    updatedDrawPile.removeWhere((card) {
      if (card is Map<String, dynamic>) {
        final cardId = card['cardId']?.toString() ?? '';
        return originalCardIds.contains(cardId);
      }
      return false;
    });
    
    // Remove original cards from discard pile if present (except the played card)
    final playedCardId = playedCard['cardId']?.toString() ?? '';
    updatedDiscardPile.removeWhere((card) {
      if (card is Map<String, dynamic>) {
        final cardId = card['cardId']?.toString() ?? '';
        // Keep the played card, remove others
        if (cardId == playedCardId) {
          return false; // Keep played card
        }
        return originalCardIds.contains(cardId);
      }
      return false;
    });
    
    // Remove played card from discard pile if it exists (we'll add it at the top)
    updatedDiscardPile.removeWhere((card) {
      if (card is Map<String, dynamic>) {
        return card['cardId']?.toString() == playedCardId;
      }
      return false;
    });
    
    // Add played card to the TOP of discard pile (last item = top of stack)
    updatedDiscardPile.add(playedCard);
    _logger.info('✅ DemoFunctionality: Added played card to TOP of discard pile', isOn: LOGGING_SWITCH);
    
    _logger.info('✅ DemoFunctionality: Updated draw pile (${updatedDrawPile.length} cards), discard pile (${updatedDiscardPile.length} cards)', isOn: LOGGING_SWITCH);
    
    return {
      'hand': restoredHand,
      'drawPile': updatedDrawPile,
      'discardPile': updatedDiscardPile,
    };
  }

  /// Get full card data from game state by cardId
  /// Looks up card in originalDeck stored in StateManager
  Map<String, dynamic>? _getCardById(String cardId) {
    try {
      final stateManager = StateManager();
      final dutchGameState = stateManager.getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      
      // Get current game
      final games = dutchGameState['games'] as Map<String, dynamic>? ?? {};
      final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
      if (currentGameId.isEmpty) {
        _logger.warning('⚠️ DemoFunctionality: No currentGameId found', isOn: LOGGING_SWITCH);
        return null;
      }
      
      final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
      final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
      final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
      
      // Get originalDeck from game state
      final originalDeck = gameState['originalDeck'] as List<dynamic>? ?? [];
      
      // Search for card in originalDeck
      for (final card in originalDeck) {
        if (card is Map<String, dynamic>) {
          final cardIdInDeck = card['cardId']?.toString() ?? '';
          if (cardIdInDeck == cardId) {
            _logger.info('✅ DemoFunctionality: Found card $cardId in originalDeck', isOn: LOGGING_SWITCH);
            return Map<String, dynamic>.from(card);
          }
        }
      }
      
      // Check if this is a queen card - try to find it by ID first, then by suit
      _logger.info('🎮 DemoFunctionality: Checking if cardId contains queen pattern: $cardId', isOn: LOGGING_SWITCH);
      final hasQueen = cardId.toLowerCase().contains('queen');
      _logger.info('🎮 DemoFunctionality: hasQueen=$hasQueen', isOn: LOGGING_SWITCH);
      
      if (hasQueen) {
        _logger.info('🎮 DemoFunctionality: ✅ Detected queen card: $cardId', isOn: LOGGING_SWITCH);
        
        // First, try to find the queen by exact cardId match in originalDeck
        for (final card in originalDeck) {
          if (card is Map<String, dynamic> && 
              card['cardId']?.toString() == cardId) {
            final queenCard = Map<String, dynamic>.from(card);
            _logger.info('✅ DemoFunctionality: Found queen by ID in originalDeck: ${queenCard['cardId']}, suit: ${queenCard['suit']}', isOn: LOGGING_SWITCH);
            return queenCard;
          }
        }
        
        // If not found by ID, try to extract suit from cardId and find matching queen
        // Extract suit from cardId (e.g., card_demo_queen_hearts_0 -> hearts)
        final parts = cardId.split('_');
        String? suit;
        for (int i = 0; i < parts.length; i++) {
          if (parts[i] == 'queen' && i + 1 < parts.length) {
            suit = parts[i + 1];
            break;
          }
        }
        
        if (suit != null) {
          for (final card in originalDeck) {
            if (card is Map<String, dynamic> && 
                card['rank']?.toString() == 'queen' && 
                card['suit']?.toString() == suit) {
              final queenCard = Map<String, dynamic>.from(card);
              _logger.info('✅ DemoFunctionality: Found queen by suit in originalDeck: ${queenCard['cardId']}, suit: ${queenCard['suit']}', isOn: LOGGING_SWITCH);
              return queenCard;
            }
          }
        }
        
        // Fallback: create queen card manually with extracted suit
        final fallbackSuit = suit ?? 'hearts';
        final fallbackQueenCard = {
          'cardId': cardId,
          'rank': 'queen',
          'suit': fallbackSuit,
          'points': 10,
          'specialPower': 'peek_at_card',
        };
        _logger.warning('⚠️ DemoFunctionality: Queen not found in originalDeck, created fallback queen of $fallbackSuit', isOn: LOGGING_SWITCH);
        return fallbackQueenCard;
      }
      
      _logger.warning('⚠️ DemoFunctionality: Card $cardId not found in originalDeck', isOn: LOGGING_SWITCH);
      return null;
    } catch (e, stackTrace) {
      _logger.error('❌ DemoFunctionality: Error getting card by ID: $e', error: e, stackTrace: stackTrace, isOn: LOGGING_SWITCH);
      return null;
    }
  }

  /// Add a card to initial peek selection
  /// Gets full card data and updates myCardsToPeek in StateManager
  /// Returns the number of cards currently selected
  /// Note: State is only updated when both cards are selected (batched update)
  Future<int> addCardToInitialPeek(String cardId) async {
    _logger.info('🎮 DemoFunctionality: Adding card $cardId to initial peek', isOn: LOGGING_SWITCH);
    
    // Check if already selected
    if (_initialPeekSelectedCardIds.contains(cardId)) {
      _logger.info('⚠️ DemoFunctionality: Card $cardId already selected', isOn: LOGGING_SWITCH);
      return _initialPeekSelectedCardIds.length;
    }
    
    // Get full card data from game state
    final fullCardData = _getCardById(cardId);
    if (fullCardData == null) {
      _logger.error('❌ DemoFunctionality: Failed to get full card data for $cardId', isOn: LOGGING_SWITCH);
      return _initialPeekSelectedCardIds.length;
    }
    
    // Add to selection
    _initialPeekSelectedCardIds.add(cardId);
    final selectedCount = _initialPeekSelectedCardIds.length;
    
    final updates = <String, dynamic>{};
    
    if (selectedCount == 1) {
      // First card selected - hide instructions but don't update myCardsToPeek yet
      updates['demoInstructionsPhase'] = '';
      _logger.info('🎮 DemoFunctionality: Hiding initial peek instructions (first card selected, waiting for second card)', isOn: LOGGING_SWITCH);
      
      // Update state to hide instructions only using state updater
      final stateUpdater = DutchGameStateUpdater.instance;
      stateUpdater.updateStateSync(updates);
      
    } else if (selectedCount == 2) {
      // Both cards selected - now update state with both cards at once
      _logger.info('🎮 DemoFunctionality: Both cards selected, updating state with both cards', isOn: LOGGING_SWITCH);
      
      // Get full card data for both cards
      final cardsToPeek = <Map<String, dynamic>>[];
      for (final selectedCardId in _initialPeekSelectedCardIds) {
        final cardData = _getCardById(selectedCardId);
        if (cardData != null) {
          cardsToPeek.add(cardData);
        }
      }
      
      // Update state with both cards at once
      updates['myCardsToPeek'] = cardsToPeek;
      
      // Start 5-second timer before showing drawing instructions
      _logger.info('🎮 DemoFunctionality: Starting 5-second timer for drawing instructions', isOn: LOGGING_SWITCH);
      
      // Cancel any existing timer
      _drawingInstructionsTimer?.cancel();
      
      // Start 5-second timer
      _drawingInstructionsTimer = Timer(Duration(seconds: 5), () {
        _logger.info('🎮 DemoFunctionality: 5-second timer expired, showing drawing instructions and converting cards to ID-only', isOn: LOGGING_SWITCH);
        final stateManager = StateManager();
        final dutchGameState = stateManager.getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        final currentCardsToPeek = dutchGameState['myCardsToPeek'] as List<dynamic>? ?? [];
        final games = dutchGameState['games'] as Map<String, dynamic>? ?? {};
        final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
        
        // Convert full card data back to ID-only format (face-down)
        final idOnlyCards = currentCardsToPeek.map((card) {
          if (card is Map<String, dynamic>) {
            final cardId = card['cardId']?.toString() ?? '';
            return {
              'cardId': cardId,
              'suit': '?',
              'rank': '?',
              'points': 0,
            };
          }
          return card;
        }).toList();
        
        // Update player status to 'drawing_card' so draw pile is clickable
        if (currentGameId.isNotEmpty && games.containsKey(currentGameId)) {
          final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
          final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
          final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
          final players = gameState['players'] as List<dynamic>? ?? [];
          
          // Find current player and update status
          for (var player in players) {
            if (player is Map<String, dynamic> && player['isHuman'] == true) {
              player['status'] = 'drawing_card';
              break;
            }
          }
        }
        
        // Update centerBoard slice with playerStatus
        final centerBoard = dutchGameState['centerBoard'] as Map<String, dynamic>? ?? {};
        centerBoard['playerStatus'] = 'drawing_card';
        
        // Update myHand slice with playerStatus (widgets read from this slice)
        final myHand = dutchGameState['myHand'] as Map<String, dynamic>? ?? {};
        myHand['playerStatus'] = 'drawing_card';
        
        // Update state with ID-only cards, drawing phase, and player status using official state updater
        final stateUpdater = DutchGameStateUpdater.instance;
        stateUpdater.updateStateSync({
          'playerStatus': 'drawing_card', // Set player status for draw pile click
          'currentPlayerStatus': 'drawing_card',
          'games': games, // Update games map with modified player status
          'lastUpdated': DateTime.now().toIso8601String(),
        });
        
        // Update widget slices and demo-specific UI fields using state updater
        stateUpdater.updateStateSync({
          'myCardsToPeek': idOnlyCards,
          'demoInstructionsPhase': 'drawing',
          'centerBoard': centerBoard, // Update centerBoard slice
          'myHand': myHand, // Update myHand slice so widget shows correct status chip
        });
        
        _logger.info('✅ DemoFunctionality: Converted ${idOnlyCards.length} cards to ID-only format and set player status to drawing_card', isOn: LOGGING_SWITCH);
        _logger.info('✅ DemoFunctionality: Updated myHand slice with playerStatus=drawing_card for status chip display', isOn: LOGGING_SWITCH);
      });
      
      // Update state with both cards using state updater
      final stateUpdater = DutchGameStateUpdater.instance;
      stateUpdater.updateStateSync(updates);
    }
    
    _logger.info('✅ DemoFunctionality: Added card $cardId to initial peek. Selected: $selectedCount/2', isOn: LOGGING_SWITCH);
    
    return selectedCount;
  }

  /// Get list of selected card IDs for initial peek
  List<String> getInitialPeekSelectedCardIds() {
    return List<String>.from(_initialPeekSelectedCardIds);
  }

  /// Clear initial peek selection
  /// This clears both the tracking set and myCardsToPeek from state
  /// Use this when you want to completely reset the initial peek (e.g., when transitioning phases)
  void clearInitialPeekSelection() {
    _logger.info('🎮 DemoFunctionality: Clearing initial peek selection', isOn: LOGGING_SWITCH);
    _initialPeekSelectedCardIds.clear();
    
    // Cancel any pending timer
    _drawingInstructionsTimer?.cancel();
    _drawingInstructionsTimer = null;
    
    // Also clear myCardsToPeek from state using state updater
    final stateUpdater = DutchGameStateUpdater.instance;
    stateUpdater.updateStateSync({
      'myCardsToPeek': <Map<String, dynamic>>[],
    });
  }

  /// Clear only the tracking set (keeps cards visible in myCardsToPeek)
  /// Use this when completing initial peek - cards should remain visible
  void clearInitialPeekTracking() {
    _logger.info('🎮 DemoFunctionality: Clearing initial peek tracking (keeping cards visible)', isOn: LOGGING_SWITCH);
    _initialPeekSelectedCardIds.clear();
  }
  
  /// End same rank window and simulate opponent turns
  /// Matches practice mode behavior: reset players to waiting, then simulate each opponent drawing and playing
  /// Can be called from instructions widget "Let's go" button or from timer
  Future<void> endSameRankWindowAndSimulateOpponents() async {
    try {
      _logger.info('🎮 DemoFunctionality: Ending same rank window and simulating opponents', isOn: LOGGING_SWITCH);
      
      final stateManager = StateManager();
      final dutchGameState = stateManager.getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final games = dutchGameState['games'] as Map<String, dynamic>? ?? {};
      final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
      
      if (currentGameId.isEmpty) {
        _logger.error('❌ DemoFunctionality: No currentGameId found', isOn: LOGGING_SWITCH);
        return;
      }
      
      final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
      final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
      final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
      
      // Cancel any existing same rank window timer before starting simulation
      _sameRankWindowTimer?.cancel();
      _sameRankWindowTimer = null;
      
      // CRITICAL: Read from SSOT (games[currentGameId]['gameData']['game_state']['players'])
      // Create a deep copy of the entire games map structure to avoid mutating references
      final gamesCopy = Map<String, dynamic>.from(games);
      final currentGameCopy = Map<String, dynamic>.from(currentGame);
      final gameDataCopy = Map<String, dynamic>.from(gameData);
      final gameStateCopy = Map<String, dynamic>.from(gameState);
      
      // Create new players list with all players set to 'waiting'
      // Also find the user player to set as currentPlayer
      Map<String, dynamic>? userPlayerForCurrent;
      final playersCopy = (gameStateCopy['players'] as List<dynamic>? ?? []).map((p) {
        if (p is Map<String, dynamic>) {
          final playerCopy = Map<String, dynamic>.from(p);
          playerCopy['status'] = 'waiting';
          // Find user player (isHuman == true)
          if (playerCopy['isHuman'] == true) {
            userPlayerForCurrent = playerCopy;
          }
          return playerCopy;
        }
        return p;
      }).toList();
      
      // Update SSOT structure with new players list
      gameStateCopy['players'] = playersCopy;
      gameDataCopy['game_state'] = gameStateCopy;
      currentGameCopy['gameData'] = gameDataCopy;
      gamesCopy[currentGameId] = currentGameCopy;
      
      // Log all player statuses before update
      _logger.info('🎮 DemoFunctionality: Resetting all players to waiting:', isOn: LOGGING_SWITCH);
      for (var p in playersCopy) {
        if (p is Map<String, dynamic>) {
          final playerId = p['id']?.toString() ?? '';
          final playerName = p['name']?.toString() ?? 'Unknown';
          final status = p['status']?.toString() ?? 'unknown';
          _logger.info('  - Player $playerName ($playerId): $status', isOn: LOGGING_SWITCH);
        }
      }
      
      // Update state using state updater - use updateState to trigger widget slice recomputation
      final stateUpdater = DutchGameStateUpdater.instance;
      stateUpdater.updateState({
        'currentGameId': currentGameId,
        'games': gamesCopy, // SSOT: Updated games map with all players set to waiting
        'gamePhase': 'player_turn', // Set phase to player_turn
        'currentPlayer': userPlayerForCurrent, // Set user as current player
        'currentPlayerStatus': 'waiting', // Update widget slice
        'playerStatus': 'waiting', // Update widget slice
        'lastUpdated': DateTime.now().toIso8601String(),
      });
      
      _logger.info('✅ DemoFunctionality: Same rank window ended, reset all players to waiting in SSOT', isOn: LOGGING_SWITCH);
      
      // CRITICAL: Re-read from SSOT after update to verify all players are waiting
      await Future.delayed(const Duration(milliseconds: 100)); // Allow state to propagate
      final freshDutchGameState = stateManager.getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final freshGames = freshDutchGameState['games'] as Map<String, dynamic>? ?? {};
      final freshCurrentGame = freshGames[currentGameId] as Map<String, dynamic>? ?? {};
      final freshGameData = freshCurrentGame['gameData'] as Map<String, dynamic>? ?? {};
      final freshGameState = freshGameData['game_state'] as Map<String, dynamic>? ?? {};
      final freshPlayers = freshGameState['players'] as List<dynamic>? ?? [];
      
      // Verify all players are waiting (defensive check)
      bool needsUpdate = false;
      final freshPlayersCopy = freshPlayers.map((p) {
        if (p is Map<String, dynamic>) {
          final playerId = p['id']?.toString() ?? '';
          final playerName = p['name']?.toString() ?? 'Unknown';
          final status = p['status']?.toString() ?? 'unknown';
          _logger.info('🎮 DemoFunctionality: Verified Player $playerName ($playerId) status: $status', isOn: LOGGING_SWITCH);
          
          if (status != 'waiting') {
            _logger.warning('⚠️ DemoFunctionality: Player $playerName ($playerId) still has status $status, fixing...', isOn: LOGGING_SWITCH);
            needsUpdate = true;
            final playerCopy = Map<String, dynamic>.from(p);
            playerCopy['status'] = 'waiting';
            return playerCopy;
          }
        }
        return p;
      }).toList();
      
      // If any players needed fixing, update SSOT again with deep copy
      if (needsUpdate) {
        final fixedGamesCopy = Map<String, dynamic>.from(freshGames);
        final fixedCurrentGameCopy = Map<String, dynamic>.from(freshCurrentGame);
        final fixedGameDataCopy = Map<String, dynamic>.from(freshGameData);
        final fixedGameStateCopy = Map<String, dynamic>.from(freshGameState);
        
        fixedGameStateCopy['players'] = freshPlayersCopy;
        fixedGameDataCopy['game_state'] = fixedGameStateCopy;
        fixedCurrentGameCopy['gameData'] = fixedGameDataCopy;
        fixedGamesCopy[currentGameId] = fixedCurrentGameCopy;
        
        stateUpdater.updateStateSync({
          'currentGameId': currentGameId,
          'games': fixedGamesCopy, // SSOT: Updated games map with all players confirmed as waiting
          'lastUpdated': DateTime.now().toIso8601String(),
        });
        
        _logger.info('✅ DemoFunctionality: Re-updated SSOT with all players confirmed as waiting', isOn: LOGGING_SWITCH);
      }
      
      // Simulate each opponent's turn (draw and play)
      // Get opponents (non-human players) from fresh state
      final opponents = freshPlayers.where((p) {
        if (p is Map<String, dynamic>) {
          return p['isHuman'] != true && p['isActive'] == true;
        }
        return false;
      }).toList();
      
      _logger.info('🎮 DemoFunctionality: Simulating ${opponents.length} opponents', isOn: LOGGING_SWITCH);
      
      // Predefined play indices: Opponent 1 -> index 3, Opponent 2 -> index 2, Opponent 3 -> index 4 (drawn card)
      final playIndices = [3, 2, 4];
      
      // Process each opponent sequentially
      for (int opponentIndex = 0; opponentIndex < opponents.length; opponentIndex++) {
        final opponent = opponents[opponentIndex];
        if (opponent is! Map<String, dynamic>) continue;
        
        final opponentId = opponent['id']?.toString() ?? '';
        final opponentName = opponent['name']?.toString() ?? 'Opponent';
        final playIndex = playIndices[opponentIndex % playIndices.length];
        
        _logger.info('🎮 DemoFunctionality: Simulating turn for $opponentName ($opponentId) - will play index $playIndex', isOn: LOGGING_SWITCH);
        
        // 2 second delay before drawing
        await Future.delayed(const Duration(seconds: 2));
        
        // Re-read state to avoid stale references
        final freshDutchGameState = stateManager.getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        final freshGames = freshDutchGameState['games'] as Map<String, dynamic>? ?? {};
        final freshCurrentGame = freshGames[currentGameId] as Map<String, dynamic>? ?? {};
        final freshGameData = freshCurrentGame['gameData'] as Map<String, dynamic>? ?? {};
        final freshGameState = freshGameData['game_state'] as Map<String, dynamic>? ?? {};
        
        // Find opponent in fresh state
        final freshPlayers = freshGameState['players'] as List<dynamic>? ?? [];
        Map<String, dynamic>? freshOpponent;
        for (var p in freshPlayers) {
          if (p is Map<String, dynamic> && p['id']?.toString() == opponentId) {
            freshOpponent = p;
            break;
          }
        }
        
        if (freshOpponent == null) {
          _logger.warning('⚠️ DemoFunctionality: Opponent $opponentId not found in fresh state', isOn: LOGGING_SWITCH);
          continue;
        }
        
        // Update opponent status to 'drawing_card'
        freshOpponent['status'] = 'drawing_card';
        freshGameState['players'] = freshPlayers;
        freshGameData['game_state'] = freshGameState;
        freshCurrentGame['gameData'] = freshGameData;
        freshGames[currentGameId] = freshCurrentGame;
        
        // Use updateState (not updateStateSync) to trigger widget slice recomputation
        stateUpdater.updateState({
          'currentGameId': currentGameId,
          'games': freshGames,
          'currentPlayer': freshOpponent,
          'currentPlayerStatus': 'drawing_card',
          'lastUpdated': DateTime.now().toIso8601String(),
        });
        
        // 1. Draw a card from draw pile
        final drawPile = freshGameState['drawPile'] as List<dynamic>? ?? [];
        if (drawPile.isEmpty) {
          _logger.warning('⚠️ DemoFunctionality: Draw pile is empty, cannot draw for $opponentName', isOn: LOGGING_SWITCH);
          continue;
        }
        
        // Remove last card from draw pile (top of stack)
        final drawnCardRaw = drawPile.removeLast();
        Map<String, dynamic> drawnCard;
        if (drawnCardRaw is Map<String, dynamic>) {
          drawnCard = drawnCardRaw;
        } else {
          // If it's ID-only, get full data
          final cardId = drawnCardRaw['cardId']?.toString() ?? '';
          final fullCard = _getCardById(cardId);
          if (fullCard == null) {
            _logger.warning('⚠️ DemoFunctionality: Could not get full card data for $cardId', isOn: LOGGING_SWITCH);
            continue;
          }
          drawnCard = fullCard;
        }
        
        _logger.info('🎮 DemoFunctionality: $opponentName drew ${drawnCard['rank']} of ${drawnCard['suit']}', isOn: LOGGING_SWITCH);
        
        // Add drawn card to opponent's hand as ID-only (temporarily at the end)
        final opponentHandRaw = freshOpponent['hand'] as List<dynamic>? ?? [];
        final opponentHand = List<dynamic>.from(opponentHandRaw);
        final drawnCardIdOnly = {
          'cardId': drawnCard['cardId'],
          'suit': '?',
          'rank': '?',
          'points': 0,
        };
        opponentHand.add(drawnCardIdOnly);
        freshOpponent['hand'] = opponentHand;
        
        // Update draw pile
        freshGameState['drawPile'] = drawPile;
        freshGameState['players'] = freshPlayers;
        freshGameData['game_state'] = freshGameState;
        freshCurrentGame['gameData'] = freshGameData;
        freshGames[currentGameId] = freshCurrentGame;
        
        // Update state after drawing (match practice mode pattern)
        // Update games map with new draw pile and player status
        freshCurrentGame['gameData'] = freshGameData;
        freshGames[currentGameId] = freshCurrentGame;
        
        // Update main state like practice mode does (use updateState to trigger widget recomputation)
        stateUpdater.updateState({
          'currentGameId': currentGameId,
          'games': freshGames,
          'currentPlayer': freshOpponent,
          'currentPlayerStatus': 'drawing_card',
          'drawPileCount': drawPile.length,
          'lastUpdated': DateTime.now().toIso8601String(),
        });
        
        // Wait 2 seconds after drawing before playing
        await Future.delayed(const Duration(seconds: 2));
        
        // 2. Play card from predefined index
        // For index 4, play the drawn card (last card in hand)
        // For other indices, play the card at that index
        Map<String, dynamic>? cardToPlay;
        int actualCardIndex = -1;
        
        if (playIndex == 4) {
          // Play the drawn card (last card in hand, which is the one we just added)
          if (opponentHand.isEmpty) {
            _logger.warning('⚠️ DemoFunctionality: $opponentName cannot play index 4 (drawn card) - hand is empty', isOn: LOGGING_SWITCH);
            continue;
          }
          actualCardIndex = opponentHand.length - 1; // Last card is the drawn one
          final cardAtIndex = opponentHand[actualCardIndex];
          if (cardAtIndex == null || cardAtIndex is! Map<String, dynamic>) {
            _logger.warning('⚠️ DemoFunctionality: $opponentName has no valid drawn card at index $actualCardIndex', isOn: LOGGING_SWITCH);
            continue;
          }
          cardToPlay = cardAtIndex;
        } else {
          // Play card at predefined index (use actual array index)
          if (opponentHand.isEmpty || playIndex >= opponentHand.length) {
            _logger.warning('⚠️ DemoFunctionality: $opponentName cannot play index $playIndex (hand size: ${opponentHand.length})', isOn: LOGGING_SWITCH);
            continue;
          }
          final cardAtIndex = opponentHand[playIndex];
          if (cardAtIndex == null || cardAtIndex is! Map<String, dynamic>) {
            _logger.warning('⚠️ DemoFunctionality: $opponentName has no valid card at index $playIndex', isOn: LOGGING_SWITCH);
            continue;
          }
          cardToPlay = cardAtIndex;
          actualCardIndex = playIndex;
        }
        
        final cardId = cardToPlay['cardId']?.toString() ?? '';
        final fullCardData = _getCardById(cardId);
        if (fullCardData == null) {
          _logger.warning('⚠️ DemoFunctionality: Could not get full card data for $cardId', isOn: LOGGING_SWITCH);
          continue;
        }
        
        _logger.info('🎮 DemoFunctionality: $opponentName playing ${fullCardData['rank']} of ${fullCardData['suit']} from index $actualCardIndex', isOn: LOGGING_SWITCH);
        
        // Update opponent status to 'playing_card' (match practice mode)
        freshOpponent['status'] = 'playing_card';
        freshGameState['players'] = freshPlayers;
        freshGameData['game_state'] = freshGameState;
        freshCurrentGame['gameData'] = freshGameData;
        freshGames[currentGameId] = freshCurrentGame;
        
        // Update main state like practice mode does (use updateState to trigger widget recomputation)
        stateUpdater.updateState({
          'currentGameId': currentGameId,
          'games': freshGames,
          'currentPlayer': freshOpponent,
          'currentPlayerStatus': 'playing_card',
          'lastUpdated': DateTime.now().toIso8601String(),
        });
        
        // Remove card from hand (create blank slot)
        opponentHand[actualCardIndex] = null;
        freshOpponent['hand'] = opponentHand;
        
        // Add card to discard pile
        final discardPile = freshGameState['discardPile'] as List<dynamic>? ?? [];
        discardPile.add(Map<String, dynamic>.from(fullCardData));
        freshGameState['discardPile'] = discardPile;
        
        // Update all players to same_rank_window (except human player - they stay at 'waiting')
        for (var p in freshPlayers) {
          if (p is Map<String, dynamic> && p['isHuman'] != true) {
            p['status'] = 'same_rank_window';
          }
        }
        
        freshGameState['players'] = freshPlayers;
        freshGameData['game_state'] = freshGameState;
        freshCurrentGame['gameData'] = freshGameData;
        freshGames[currentGameId] = freshCurrentGame;
        
        // Wait 1 second after playing, then move drawn card to played index (if not playing the drawn card itself)
        await Future.delayed(const Duration(seconds: 1));
        
        // Move drawn card to the played index (only if we didn't play the drawn card)
        // The drawn card is at the last index (opponentHand.length - 1) after we set the played card to null
        final drawnCardIndex = opponentHand.length - 1; // Last card is the drawn one
        if (actualCardIndex != drawnCardIndex && drawnCardIndex >= 0 && drawnCardIndex < opponentHand.length) {
          // The played card was not the drawn card, so move the drawn card to the played index
          final drawnCardToMove = opponentHand[drawnCardIndex];
          if (drawnCardToMove != null && drawnCardToMove is Map<String, dynamic>) {
            // Remove the drawn card from the end (removeAt to avoid empty slot)
            opponentHand.removeAt(drawnCardIndex);
            // Place at played index (which is already null from when we played the card)
            opponentHand[actualCardIndex] = drawnCardToMove;
            freshOpponent['hand'] = opponentHand;
            freshGameState['players'] = freshPlayers;
            freshGameData['game_state'] = freshGameState;
            freshCurrentGame['gameData'] = freshGameData;
            freshGames[currentGameId] = freshCurrentGame;
            _logger.info('🎮 DemoFunctionality: Moved drawn card from index $drawnCardIndex to index $actualCardIndex for $opponentName (removed empty slot)', isOn: LOGGING_SWITCH);
          }
        } else {
          // The played card was the drawn card itself, no reposition needed
          // But we still need to remove the null slot at actualCardIndex
          if (actualCardIndex >= 0 && actualCardIndex < opponentHand.length && opponentHand[actualCardIndex] == null) {
            opponentHand.removeAt(actualCardIndex);
            freshOpponent['hand'] = opponentHand;
            freshGameState['players'] = freshPlayers;
            freshGameData['game_state'] = freshGameState;
            freshCurrentGame['gameData'] = freshGameData;
            freshGames[currentGameId] = freshCurrentGame;
            _logger.info('🎮 DemoFunctionality: $opponentName played the drawn card at index $actualCardIndex, removed empty slot', isOn: LOGGING_SWITCH);
          } else {
            _logger.info('🎮 DemoFunctionality: $opponentName played the drawn card at index $actualCardIndex, no reposition needed', isOn: LOGGING_SWITCH);
          }
        }
        
        // Update games map with final state (after card reposition)
        freshCurrentGame['gameData'] = freshGameData;
        freshGames[currentGameId] = freshCurrentGame;
        
        // Re-read state to get latest turn_events before adding new event
        final latestDutchGameState = stateManager.getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        final currentTurnEvents = latestDutchGameState['turn_events'] as List<dynamic>? ?? [];
        
        // Create turn event (match practice mode format)
        final turnEvents = List<Map<String, dynamic>>.from(currentTurnEvents)
          ..add({
            'cardId': cardId,
            'actionType': 'play',
            'playerId': opponentId,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });
        
        // Update main state like practice mode does (comprehensive update - use updateState to trigger widget recomputation)
        stateUpdater.updateState({
          'currentGameId': currentGameId,
          'games': freshGames, // Full games map with updated game state
          'gamePhase': 'same_rank_window', // Normalized UI phase
          'currentPlayer': freshOpponent,
          'currentPlayerStatus': 'same_rank_window',
          'playerStatus': 'same_rank_window', // All players status
          'discardPile': discardPile, // For centerBoard slice
          'drawPileCount': drawPile.length,
          'turn_events': turnEvents, // For animations
          'lastUpdated': DateTime.now().toIso8601String(),
        });
        
        _logger.info('✅ DemoFunctionality: $opponentName played card, same rank window started', isOn: LOGGING_SWITCH);
        
        // Don't start timer during simulation - only start after all opponents have played
        // Cancel any existing timer to prevent multiple triggers
        _sameRankWindowTimer?.cancel();
        _sameRankWindowTimer = null;
        
        // Continue to next opponent (don't break)
      }
      
      _logger.info('✅ DemoFunctionality: Completed opponent simulation', isOn: LOGGING_SWITCH);
      
      // Re-read state to get fresh references before updating user's hand
      final latestDutchGameState = stateManager.getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final latestGames = latestDutchGameState['games'] as Map<String, dynamic>? ?? {};
      final latestCurrentGame = latestGames[currentGameId] as Map<String, dynamic>? ?? {};
      final latestGameData = latestCurrentGame['gameData'] as Map<String, dynamic>? ?? {};
      final latestGameState = latestGameData['game_state'] as Map<String, dynamic>? ?? {};
      final latestPlayers = latestGameState['players'] as List<dynamic>? ?? [];
      
      // Set all opponents' status to 'waiting' (same pattern as during simulation)
      final playersWithWaitingOpponents = List<dynamic>.from(latestPlayers);
      for (var p in playersWithWaitingOpponents) {
        if (p is Map<String, dynamic> && p['isHuman'] != true) {
          p['status'] = 'waiting';
          _logger.info('✅ DemoFunctionality: Set opponent ${p['id']} status to waiting', isOn: LOGGING_SWITCH);
        }
      }
      
      // Update SSOT with opponents set to waiting
      final gameStateWithWaitingOpponents = Map<String, dynamic>.from(latestGameState);
      gameStateWithWaitingOpponents['players'] = playersWithWaitingOpponents;
      final gameDataWithWaitingOpponents = Map<String, dynamic>.from(latestGameData);
      gameDataWithWaitingOpponents['game_state'] = gameStateWithWaitingOpponents;
      final currentGameWithWaitingOpponents = Map<String, dynamic>.from(latestCurrentGame);
      currentGameWithWaitingOpponents['gameData'] = gameDataWithWaitingOpponents;
      final gamesWithWaitingOpponents = Map<String, dynamic>.from(latestGames);
      gamesWithWaitingOpponents[currentGameId] = currentGameWithWaitingOpponents;
      
      // Update state with opponents set to waiting (before updating user's hand)
      stateUpdater.updateState({
        'currentGameId': currentGameId,
        'games': gamesWithWaitingOpponents, // SSOT with opponents status = 'waiting'
        'lastUpdated': DateTime.now().toIso8601String(),
      });
      
      _logger.info('✅ DemoFunctionality: Set all opponents to waiting status', isOn: LOGGING_SWITCH);
      
      // Re-read state again after setting opponents to waiting (to get fresh references for user hand update)
      final finalDutchGameState = stateManager.getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final finalGames = finalDutchGameState['games'] as Map<String, dynamic>? ?? {};
      final finalCurrentGame = finalGames[currentGameId] as Map<String, dynamic>? ?? {};
      final finalGameData = finalCurrentGame['gameData'] as Map<String, dynamic>? ?? {};
      final finalGameState = finalGameData['game_state'] as Map<String, dynamic>? ?? {};
      final finalPlayers = finalGameState['players'] as List<dynamic>? ?? [];
      
      // Find user player (isHuman == true)
      Map<String, dynamic>? userPlayer;
      int userPlayerIndex = -1;
      for (int i = 0; i < finalPlayers.length; i++) {
        final p = finalPlayers[i];
        if (p is Map<String, dynamic> && p['isHuman'] == true) {
          userPlayer = Map<String, dynamic>.from(p);
          userPlayerIndex = i;
          break;
        }
      }
      
      if (userPlayer != null) {
        // Get originalDeck to find all 4 queens (one of each suit)
        final originalDeck = finalGameState['originalDeck'] as List<dynamic>? ?? [];
        final suits = ['hearts', 'diamonds', 'clubs', 'spades'];
        final queensHand = <Map<String, dynamic>>[];
        
        // Find each queen by suit from originalDeck
        for (final suit in suits) {
          Map<String, dynamic>? queenCard;
          for (final card in originalDeck) {
            if (card is Map<String, dynamic> && 
                card['rank']?.toString() == 'queen' && 
                card['suit']?.toString() == suit) {
              queenCard = Map<String, dynamic>.from(card);
              break;
            }
          }
          
          // If queen not found in originalDeck, create one with standard ID
          if (queenCard == null) {
            queenCard = {
              'cardId': 'card_demo_queen_${suit}_0',
              'rank': 'queen',
              'suit': suit,
              'points': 10,
              'specialPower': 'peek_at_card',
            };
            _logger.warning('⚠️ DemoFunctionality: Queen of $suit not found in originalDeck, created fallback', isOn: LOGGING_SWITCH);
          }
          
          // Convert to ID-only format (as stored in hands) using the actual card ID
          final idOnlyCard = {
            'cardId': queenCard['cardId'], // Use actual card ID from originalDeck
            'suit': '?',      // Face-down: hide suit
            'rank': '?',      // Face-down: hide rank
            'points': 0,      // Face-down: hide points
          };
          queensHand.add(idOnlyCard);
          _logger.info('✅ DemoFunctionality: Added queen of $suit to hand with ID: ${queenCard['cardId']}', isOn: LOGGING_SWITCH);
        }
        
        // Update user's hand and status
        userPlayer['hand'] = queensHand;
        userPlayer['status'] = 'playing_card';
        final updatedPlayers = List<dynamic>.from(finalPlayers);
        updatedPlayers[userPlayerIndex] = userPlayer;
        
        // Update SSOT with deep copies
        final updatedGameState = Map<String, dynamic>.from(finalGameState);
        updatedGameState['players'] = updatedPlayers;
        // Also set currentPlayer in gameState so _getCurrentUserStatus can find it
        updatedGameState['currentPlayer'] = userPlayer;
        final updatedGameData = Map<String, dynamic>.from(finalGameData);
        updatedGameData['game_state'] = updatedGameState;
        final updatedCurrentGame = Map<String, dynamic>.from(finalCurrentGame);
        updatedCurrentGame['gameData'] = updatedGameData;
        // Also update myHandCards in currentGame so _computeMyHandSlice picks it up
        final myHandCards = List<Map<String, dynamic>>.from(queensHand.map((c) => Map<String, dynamic>.from(c)));
        updatedCurrentGame['myHandCards'] = myHandCards;
        final updatedGames = Map<String, dynamic>.from(finalGames);
        updatedGames[currentGameId] = updatedCurrentGame;
        
        _logger.info('✅ DemoFunctionality: Updated user hand to 4 queens (one of each suit), status set to playing_card in SSOT', isOn: LOGGING_SWITCH);
        _logger.info('✅ DemoFunctionality: User player status in SSOT: ${userPlayer['status']}', isOn: LOGGING_SWITCH);
        
        // After all opponents have played, show special plays instruction
        // The widget slices will be recomputed automatically by _updateWidgetSlices
        stateUpdater.updateState({
          'currentGameId': currentGameId,
          'games': updatedGames, // SSOT with player status = 'playing_card'
          'demoInstructionsPhase': 'special_plays',
          'currentPlayer': userPlayer, // Set currentPlayer so _getCurrentUserStatus can find it
          'currentPlayerStatus': 'playing_card',
          'playerStatus': 'playing_card',
          'lastUpdated': DateTime.now().toIso8601String(),
        });
        
        _logger.info('✅ DemoFunctionality: Updated state - widget slices will be recomputed with playerStatus=playing_card', isOn: LOGGING_SWITCH);
        _logger.info('✅ DemoFunctionality: Showing special plays instruction', isOn: LOGGING_SWITCH);
      } else {
        _logger.warning('⚠️ DemoFunctionality: User player not found when updating hand', isOn: LOGGING_SWITCH);
        
        // Still show instruction even if user not found
        stateUpdater.updateState({
          'demoInstructionsPhase': 'special_plays',
          'lastUpdated': DateTime.now().toIso8601String(),
        });
        _logger.info('✅ DemoFunctionality: Showing special plays instruction (user not found)', isOn: LOGGING_SWITCH);
      }
      
      // CRITICAL: Cancel ALL timers after opponent simulation completes
      // The simulation should stop here, no more automatic actions
      _sameRankWindowTimer?.cancel();
      _sameRankWindowTimer = null;
      _sameRankInstructionsTimer?.cancel();
      _sameRankInstructionsTimer = null;
      _drawingInstructionsTimer?.cancel();
      _drawingInstructionsTimer = null;
      _queenPeekTimer?.cancel();
      _queenPeekTimer = null;
      _logger.info('✅ DemoFunctionality: Cancelled all timers after opponent simulation completed', isOn: LOGGING_SWITCH);
      
    } catch (e, stackTrace) {
      _logger.error('❌ DemoFunctionality: Error in _endSameRankWindowAndSimulateOpponents: $e', error: e, stackTrace: stackTrace, isOn: LOGGING_SWITCH);
    }
  }
}

