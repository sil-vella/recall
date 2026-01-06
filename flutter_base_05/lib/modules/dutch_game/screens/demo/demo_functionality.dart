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
      paragraph: 'After drawing, you can play a card from your hand. Select a card to play, or you can choose to keep the drawn card and discard one from your hand.',
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
  Future<Map<String, dynamic>> _handleDrawCard(Map<String, dynamic> payload) async {
    _logger.info('🎮 DemoFunctionality: Draw card action (demo mode - no-op)', isOn: LOGGING_SWITCH);
    // TODO: Implement demo draw card logic
    return {'success': true, 'mode': 'demo'};
  }

  /// Handle play card action in demo mode
  Future<Map<String, dynamic>> _handlePlayCard(Map<String, dynamic> payload) async {
    _logger.info('🎮 DemoFunctionality: Play card action (demo mode - no-op)', isOn: LOGGING_SWITCH);
    // TODO: Implement demo play card logic
    return {'success': true, 'mode': 'demo'};
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
        
        // Update state with ID-only cards and drawing phase
        stateManager.updateModuleState('dutch_game', {
          'myCardsToPeek': idOnlyCards,
          'demoInstructionsPhase': 'drawing',
        });
        
        _logger.info('✅ DemoFunctionality: Converted ${idOnlyCards.length} cards to ID-only format', isOn: LOGGING_SWITCH);
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

