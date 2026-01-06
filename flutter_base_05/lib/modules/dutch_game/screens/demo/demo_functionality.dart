import 'dart:async';
import 'package:dutch/tools/logging/logger.dart';
import '../../../../core/managers/state_manager.dart';

const bool LOGGING_SWITCH = true; // Enabled for demo debugging

/// Demo Phase Instructions
/// 
/// Contains title and paragraph for each demo phase.
class DemoPhaseInstruction {
  final String phase;
  final String title;
  final String paragraph;

  DemoPhaseInstruction({
    required this.phase,
    required this.title,
    required this.paragraph,
  });

  Map<String, dynamic> toMap() => {
    'phase': phase,
    'title': title,
    'paragraph': paragraph,
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

  /// List of demo phase instructions
  /// Each phase has a title and paragraph explaining what to do
  final List<DemoPhaseInstruction> _demoPhaseInstructions = [
    DemoPhaseInstruction(
      phase: 'initial',
      title: 'Welcome to the Demo',
      paragraph: 'Let\'s go through a quick demo. The goal is to end the game with no cards or least points possible.',
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
      paragraph: 'A card with the same rank was just played! You can play a matching rank card out of turn if you act quickly. This is your chance to get rid of a card!',
    ),
    DemoPhaseInstruction(
      phase: 'jack_swap',
      title: 'Jack Special Power',
      paragraph: 'You played a Jack! You can now swap any two cards between any players. Select the two cards you want to swap.',
    ),
    DemoPhaseInstruction(
      phase: 'queen_peek',
      title: 'Queen Special Power',
      paragraph: 'You played a Queen! You can now peek at any one card from any player\'s hand. Select which player and which card you want to see.',
    ),
  ];

  /// Handle a player action in demo mode
  /// Routes actions to demo-specific handlers instead of backend/WebSocket
  Future<Map<String, dynamic>> handleAction(
    String actionType,
    Map<String, dynamic> payload,
  ) async {
    try {
      _logger.info('🎮 DemoFunctionality: Handling action $actionType', isOn: LOGGING_SWITCH);
      _logger.info('🎮 DemoFunctionality: Payload: $payload', isOn: LOGGING_SWITCH);
      _logger.info('🎮 DemoFunctionality: Action type check - play_card match: ${actionType == 'play_card'}', isOn: LOGGING_SWITCH);

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
    
    // Update state with all changes
    // NOTE: Keep myDrawnCard in state - the unified widget uses it to show full data for the drawn card in hand
    // The card in hand is ID-only, but the widget will use myDrawnCard full data if IDs match
    stateManager.updateModuleState('dutch_game', {
      'myDrawnCard': drawnCard, // Keep drawn card with full data (widget uses it to show card face-up in hand)
      'demoInstructionsPhase': 'playing', // Transition to playing phase
      'playerStatus': 'playing_card', // Update main state
      'currentPlayerStatus': 'playing_card',
      'centerBoard': centerBoard, // Update centerBoard slice
      'myHand': myHand, // Update myHand slice with new status and cards
      'games': games, // Update games map with modified game state
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
    _logger.info('🎮 DemoFunctionality: Play card action intercepted', isOn: LOGGING_SWITCH);
    _logger.info('🎮 DemoFunctionality: Payload: $payload', isOn: LOGGING_SWITCH);
    
    final cardId = payload['card_id']?.toString() ?? '';
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
    
    // Update state with all changes
    stateManager.updateModuleState('dutch_game', {
      'myDrawnCard': null, // Clear drawn card (it's now repositioned in hand or discarded)
      'demoInstructionsPhase': 'same_rank', // Transition to same rank phase
      'playerStatus': 'same_rank_window', // Update main state
      'currentPlayerStatus': 'same_rank_window',
      'centerBoard': centerBoard,
      'myHand': myHand,
      'games': games, // Update games map with modified game state
    });
    
    _logger.info('✅ DemoFunctionality: Card $cardId played successfully', isOn: LOGGING_SWITCH);
    _logger.info('✅ DemoFunctionality: Updated all players status to same_rank_window', isOn: LOGGING_SWITCH);
    _logger.info('✅ DemoFunctionality: Transitioned to same_rank phase', isOn: LOGGING_SWITCH);
    
    return {'success': true, 'mode': 'demo', 'cardId': cardId};
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
  Future<Map<String, dynamic>> _handleCallFinalRound(Map<String, dynamic> payload) async {
    _logger.info('🎮 DemoFunctionality: Call final round action (demo mode - no-op)', isOn: LOGGING_SWITCH);
    // TODO: Implement demo call final round logic
    return {'success': true, 'mode': 'demo'};
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
  Future<Map<String, dynamic>> _handleJackSwap(Map<String, dynamic> payload) async {
    _logger.info('🎮 DemoFunctionality: Jack swap action (demo mode - no-op)', isOn: LOGGING_SWITCH);
    // TODO: Implement demo jack swap logic
    return {'success': true, 'mode': 'demo'};
  }

  /// Handle queen peek action in demo mode
  Future<Map<String, dynamic>> _handleQueenPeek(Map<String, dynamic> payload) async {
    _logger.info('🎮 DemoFunctionality: Queen peek action (demo mode - no-op)', isOn: LOGGING_SWITCH);
    // TODO: Implement demo queen peek logic
    return {'success': true, 'mode': 'demo'};
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
    
    // Update demoInstructionsPhase directly in StateManager (bypasses validation - it's just for UI)
    final stateManager = StateManager();
    stateManager.updateModuleState('dutch_game', {
      'demoInstructionsPhase': 'initial_peek',
    });
    
    _logger.info('✅ DemoFunctionality: Demo instructions phase transitioned to initial_peek', isOn: LOGGING_SWITCH);
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
    
    final stateManager = StateManager();
    final updates = <String, dynamic>{};
    
    if (selectedCount == 1) {
      // First card selected - hide instructions but don't update myCardsToPeek yet
      updates['demoInstructionsPhase'] = '';
      _logger.info('🎮 DemoFunctionality: Hiding initial peek instructions (first card selected, waiting for second card)', isOn: LOGGING_SWITCH);
      
      // Update state to hide instructions only
      stateManager.updateModuleState('dutch_game', updates);
      
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
        
        // Update state with ID-only cards, drawing phase, and player status
        stateManager.updateModuleState('dutch_game', {
          'myCardsToPeek': idOnlyCards,
          'demoInstructionsPhase': 'drawing',
          'playerStatus': 'drawing_card', // Set player status for draw pile click
          'currentPlayerStatus': 'drawing_card',
          'centerBoard': centerBoard, // Update centerBoard slice
          'myHand': myHand, // Update myHand slice so widget shows correct status chip
          'games': games, // Update games map with modified player status
        });
        
        _logger.info('✅ DemoFunctionality: Converted ${idOnlyCards.length} cards to ID-only format and set player status to drawing_card', isOn: LOGGING_SWITCH);
        _logger.info('✅ DemoFunctionality: Updated myHand slice with playerStatus=drawing_card for status chip display', isOn: LOGGING_SWITCH);
      });
      
      // Update state with both cards
      stateManager.updateModuleState('dutch_game', updates);
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
    
    // Also clear myCardsToPeek from state
    final stateManager = StateManager();
    stateManager.updateModuleState('dutch_game', {
      'myCardsToPeek': <Map<String, dynamic>>[],
    });
  }

  /// Clear only the tracking set (keeps cards visible in myCardsToPeek)
  /// Use this when completing initial peek - cards should remain visible
  void clearInitialPeekTracking() {
    _logger.info('🎮 DemoFunctionality: Clearing initial peek tracking (keeping cards visible)', isOn: LOGGING_SWITCH);
    _initialPeekSelectedCardIds.clear();
  }
}

