import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../models/card_model.dart';
import '../../../models/card_display_config.dart';
import '../../../utils/card_dimensions.dart';
import '../../../widgets/card_widget.dart';
import 'player_status_chip_widget.dart';
import '../../../managers/player_action.dart';
import '../../../../../tools/logging/logger.dart';
import '../card_position_tracker.dart';
import '../../../managers/recall_event_handler_callbacks.dart';

// Logging switch
const bool LOGGING_SWITCH = true;

/// Widget to display the player's hand
/// 
/// This widget subscribes to the myHand state slice and displays:
/// - All cards in the player's hand
/// - Card selection functionality
/// - Visual representation of each card
/// - Dynamic add/remove cards based on state changes
/// - Initial peek functionality (2 card selection during initial_peek status)
/// 
/// Follows the established pattern of subscribing to state slices using ListenableBuilder
class MyHandWidget extends StatefulWidget {
  const MyHandWidget({Key? key}) : super(key: key);

  @override
  State<MyHandWidget> createState() => _MyHandWidgetState();
}

class _MyHandWidgetState extends State<MyHandWidget> {
  final Logger _logger = Logger();
  
  // Local state for initial peek card selections
  int _initialPeekSelectionCount = 0;
  List<String> _initialPeekSelectedCardIds = [];
  
  // Local flag to prevent rapid action execution (frontend-only, doesn't update backend state)
  bool _isProcessingAction = false;
  
  // GlobalKeys for each card to get positions
  final Map<String, GlobalKey> _cardKeys = {};

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
        
        // Get myHand state slice
        final myHand = recallGameState['myHand'] as Map<String, dynamic>? ?? {};
        final cards = myHand['cards'] as List<dynamic>? ?? [];
        final selectedIndex = myHand['selectedIndex'] ?? -1;
        final selectedCard = myHand['selectedCard'] as Map<String, dynamic>?;
        
        // Get cardsToPeek state slice
        final cardsToPeek = recallGameState['myCardsToPeek'] as List<dynamic>? ?? [];
        
        // Get additional game state for context
        final gamePhase = recallGameState['gamePhase']?.toString() ?? 'waiting';
        final isGameActive = recallGameState['isGameActive'] ?? false;
        final isMyTurn = recallGameState['isMyTurn'] ?? false;
        // Get playerStatus from myHand slice (computed from SSOT)
        final playerStatus = myHand['playerStatus']?.toString() ?? 'unknown';
        
        // Update card positions on rebuild (after cards are rendered)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateCardPositions(cards, playerStatus);
        });
        
        // Check for action errors and display snackbar
        final actionError = recallGameState['actionError'] as Map<String, dynamic>?;
        if (actionError != null) {
          final message = actionError['message']?.toString() ?? 'Action failed';
          
          // Show snackbar with error message
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 3),
              ),
            );
            
            // Clear the error after showing
            final currentState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
            StateManager().updateModuleState('recall_game', {
              ...currentState,
              'actionError': null,
            });
          });
        }
        
        // Debug logging
        _logger.info('🃏 MyHandWidget - playerStatus: $playerStatus', isOn: LOGGING_SWITCH);
        _logger.info('🃏 MyHandWidget - cards.length: ${cards.length}', isOn: LOGGING_SWITCH);
        _logger.info('🃏 MyHandWidget - cardsToPeek.length: ${cardsToPeek.length}', isOn: LOGGING_SWITCH);
        if (cardsToPeek.isNotEmpty) {
          _logger.info('🃏 MyHandWidget - cardsToPeek IDs: ${cardsToPeek.map((c) => c['cardId']).toList()}', isOn: LOGGING_SWITCH);
        }
        _logger.info('🃏 MyHandWidget - myHand keys: ${myHand.keys.toList()}', isOn: LOGGING_SWITCH);
        _logger.info('🃏 MyHandWidget - recallGameState keys: ${recallGameState.keys.toList()}', isOn: LOGGING_SWITCH);
        
        // Check what's in the games map
        final currentGameId = recallGameState['currentGameId']?.toString() ?? '';
        final games = recallGameState['games'] as Map<String, dynamic>? ?? {};
        final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
        final myHandCards = currentGame['myHandCards'] as List<dynamic>? ?? [];
        _logger.info('🃏 MyHandWidget - currentGameId: $currentGameId', isOn: LOGGING_SWITCH);
        _logger.info('🃏 MyHandWidget - myHandCards.length: ${myHandCards.length}', isOn: LOGGING_SWITCH);
        
        // Reset initial peek state when not in initial_peek status
        if (playerStatus != 'initial_peek' && _initialPeekSelectionCount > 0) {
          _initialPeekSelectionCount = 0;
          _initialPeekSelectedCardIds.clear();
        }
        
        return _buildMyHandCard(
          cards: cards,
          cardsToPeek: cardsToPeek,
          selectedIndex: selectedIndex,
          selectedCard: selectedCard,
          gamePhase: gamePhase,
          isGameActive: isGameActive,
          isMyTurn: isMyTurn,
          playerStatus: playerStatus,
        );
      },
    );
  }

  /// Build the my hand card widget
  Widget _buildMyHandCard({
    required List<dynamic> cards,
    required List<dynamic> cardsToPeek,
    required int selectedIndex,
    required Map<String, dynamic>? selectedCard,
    required String gamePhase,
    required bool isGameActive,
    required bool isMyTurn,
    required String playerStatus,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title and Status
            Row(
              children: [
                Icon(Icons.style, color: Colors.green),
                const SizedBox(width: 8),
                const Text(
                  'My Hand',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 12),
                // Player status indicator
                if (playerStatus != 'unknown') ...[
                  PlayerStatusChip(
                    playerId: _getCurrentUserId(),
                    size: PlayerStatusChipSize.small,
                  ),
                ],
                const Spacer(),
                Text(
                  '${cards.length} cards',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Cards display
            if (cards.isEmpty)
              _buildEmptyHand()
            else
              _buildCardsGrid(cards, cardsToPeek, selectedIndex),
            

          ],
        ),
      ),
    );
  }

  /// Build empty hand state
  Widget _buildEmptyHand() {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.style,
              size: 32,
              color: Colors.grey,
            ),
            SizedBox(height: 8),
            Text(
              'No cards in hand',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build the cards grid using the new CardWidget system
  Widget _buildCardsGrid(List<dynamic> cards, List<dynamic> cardsToPeek, int selectedIndex) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
        final drawnCard = recallGameState['myDrawnCard'] as Map<String, dynamic>?;
        final drawnCardId = drawnCard?['cardId']?.toString();
        
        // Get current player's collection rank cards from games map
        final currentGameId = recallGameState['currentGameId']?.toString() ?? '';
        final games = recallGameState['games'] as Map<String, dynamic>? ?? {};
        final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
        final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
        final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
        final players = gameState['players'] as List<dynamic>? ?? [];
        
        // Get current user ID - use helper that handles both practice and multiplayer modes
        final currentUserId = RecallEventHandlerCallbacks.getCurrentUserId();
        
        // Find current player's collection rank cards
        List<dynamic> myCollectionRankCards = [];
        for (var player in players) {
          if (player is Map<String, dynamic> && player['id']?.toString() == currentUserId) {
            myCollectionRankCards = player['collection_rank_cards'] as List<dynamic>? ?? [];
            break;
          }
        }
        
        // Build list of card IDs that are collection rank cards
        final collectionRankCardIds = myCollectionRankCards
            .where((c) => c is Map<String, dynamic>)
            .map((c) => (c as Map<String, dynamic>)['cardId']?.toString())
            .where((id) => id != null)
            .toSet();
        
        // Pre-build collection rank widgets map - ALL CARDS USE SAME BUILD PROCESS
        Map<String, Widget> collectionRankWidgets = {};
        
        // First pass: build all collection rank widgets with same build process as normal cards
        for (int i = 0; i < cards.length; i++) {
          final card = cards[i];
          if (card == null) continue;
          
          final cardMap = card as Map<String, dynamic>;
          final cardId = cardMap['cardId']?.toString();
          if (cardId == null) continue;
          
          // Get the same parameters as normal card building
          final isSelected = i == selectedIndex;
          final isDrawnCard = drawnCardId != null && cardId == drawnCardId;
          
          // Check if this card is in cardsToPeek (peeked cards have full data)
          Map<String, dynamic>? peekedCardData;
          if (cardsToPeek.isNotEmpty) {
            for (var peekedCard in cardsToPeek) {
              if (peekedCard is Map<String, dynamic> && peekedCard['cardId']?.toString() == cardId) {
                peekedCardData = peekedCard;
                break;
              }
            }
          }
          
          // Check if this card is a collection rank card
          Map<String, dynamic>? collectionRankCardData;
          if (myCollectionRankCards.isNotEmpty) {
            for (var collectionCard in myCollectionRankCards) {
              if (collectionCard is Map<String, dynamic> && collectionCard['cardId']?.toString() == cardId) {
                collectionRankCardData = collectionCard;
                break;
              }
            }
          }
          
          if (collectionRankCardData != null) {
            // Determine which data to use (same priority as normal cards)
            // collectionRankCardData is guaranteed non-null here, so no need for ?? cardMap fallback
            final cardDataToUse = isDrawnCard && drawnCard != null
                ? drawnCard 
                : (peekedCardData ?? collectionRankCardData);
            
            // Build the collection rank card widget with SAME BUILD PROCESS as normal cards
            final cardKey = _cardKeys.putIfAbsent(cardId, () => GlobalKey(debugLabel: 'card_$cardId'));
            final cardWidget = _buildCardWidget(cardDataToUse, isSelected, isDrawnCard, false, i, cardMap, cardKey);
            collectionRankWidgets[cardId] = cardWidget;
          }
        }
        
        // ListView needs height constraint when inside Column - use exact card height
        // This constrains the ListView container to match card height exactly
        final cardHeight = CardDimensions.getUnifiedHeight();
        final stackOffset = CardDimensions.getUnifiedStackOffset();
        
        return SizedBox(
          height: cardHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: cards.length,
            itemBuilder: (context, index) {
              final card = cards[index];
              
              // Handle null cards (blank slots from same-rank plays)
              if (card == null) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _buildBlankCardSlot(),
                );
              }
              
              final cardMap = card as Map<String, dynamic>;
              final cardId = cardMap['cardId']?.toString();
              final isSelected = index == selectedIndex;
              final isDrawnCard = drawnCardId != null && cardId == drawnCardId;
              
              // Check if this card is in cardsToPeek (peeked cards have full data)
              Map<String, dynamic>? peekedCardData;
              if (cardId != null && cardsToPeek.isNotEmpty) {
                for (var peekedCard in cardsToPeek) {
                  if (peekedCard is Map<String, dynamic> && peekedCard['cardId']?.toString() == cardId) {
                    peekedCardData = peekedCard;
                    break;
                  }
                }
              }
              
              // Check if this card is in player's collection_rank_cards
              Map<String, dynamic>? collectionRankCardData;
              bool isCollectionRankCard = false;
              if (cardId != null && myCollectionRankCards.isNotEmpty) {
                for (var collectionCard in myCollectionRankCards) {
                  if (collectionCard is Map<String, dynamic> && collectionCard['cardId']?.toString() == cardId) {
                    collectionRankCardData = collectionCard;
                    isCollectionRankCard = true;
                    break;
                  }
                }
              }
              
              // Determine which data to use (priority: drawn card > peeked card > collection rank card > ID-only hand card)
              final cardDataToUse = isDrawnCard && drawnCard != null 
                  ? drawnCard 
                  : (peekedCardData ?? collectionRankCardData ?? cardMap);
              
              // If this is a collection rank card, render the stack (only once, at the first collection card)
              if (isCollectionRankCard && collectionRankWidgets.containsKey(cardId)) {
                // Check if this is the first collection card in the hand
                bool isFirstCollectionCard = true;
                for (int i = 0; i < index; i++) {
                  final prevCard = cards[i];
                  if (prevCard != null && prevCard is Map<String, dynamic>) {
                    final prevCardId = prevCard['cardId']?.toString();
                    if (prevCardId != null && collectionRankCardIds.contains(prevCardId)) {
                      isFirstCollectionCard = false;
                      break;
                    }
                  }
                }
                
                if (isFirstCollectionCard) {
                  // This is the first collection card, render the entire stack
                  // Get all collection rank widgets in order
                  List<Widget> orderedCollectionWidgets = [];
                  for (var collectionCard in myCollectionRankCards) {
                    if (collectionCard is Map<String, dynamic>) {
                      final collectionCardId = collectionCard['cardId']?.toString();
                      if (collectionCardId != null && collectionRankWidgets.containsKey(collectionCardId)) {
                        orderedCollectionWidgets.add(collectionRankWidgets[collectionCardId]!);
                      }
                    }
                  }
                  
                  // Stack needs size constraint to render - constrain container, NOT individual cards
                  final cardDimensions = CardDimensions.getUnifiedDimensions();
                  final cardWidth = cardDimensions.width;
                  final cardHeight = cardDimensions.height;
                  final stackHeight = cardHeight + (orderedCollectionWidgets.length - 1) * stackOffset;
                  
                  final stackWidget = SizedBox(
                    width: cardWidth,
                    height: stackHeight,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: orderedCollectionWidgets.asMap().entries.map((entry) {
                        // Stack cards perfectly on top of each other with offset
                        return Positioned(
                          left: 0,
                          top: entry.key * stackOffset, // First card at top (0), subsequent cards offset downward
                          child: entry.value, // CardWidget already has exact dimensions
                        );
                      }).toList(),
                    ),
                  );
                  
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: stackWidget,
                  );
                } else {
                  // Not the first collection card, skip rendering (already handled in stack)
                  return const SizedBox.shrink();
                }
              }
              
              // Normal card rendering (non-collection rank)
              // CardWidget already uses exact dimensions from CardDimensions SSOT
              final cardKey = _cardKeys.putIfAbsent(cardId!, () => GlobalKey(debugLabel: 'card_$cardId'));
              final cardWidget = _buildCardWidget(cardDataToUse, isSelected, isDrawnCard, false, index, cardMap, cardKey);
              
              return Padding(
                padding: EdgeInsets.only(
                  right: 8,
                  left: isDrawnCard ? 16 : 0, // Extra left margin for drawn card
                ),
                child: cardWidget,
              );
            },
          ),
        );
      },
    );
  }





  /// Get current user ID from login state
  String _getCurrentUserId() {
    final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    return loginState['userId']?.toString() ?? '';
  }

  /// Detect state changes and create animation triggers
  /// Update card positions in animation manager
  void _updateCardPositions(List<dynamic> cards, String playerStatus) {
    // Verbose logging disabled to reduce log noise
    
    // Get turn_events from myHand slice to determine animation types
    final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    final myHandSlice = recallGameState['myHand'] as Map<String, dynamic>? ?? {};
    final turnEvents = myHandSlice['turn_events'] as List<dynamic>? ?? [];
    
    // Create a map of cardId -> actionType for quick lookup
    final Map<String, String> cardIdToActionType = {};
    for (final event in turnEvents) {
      if (event is Map<String, dynamic>) {
        final eventCardId = event['cardId']?.toString();
        final actionType = event['actionType']?.toString();
        if (eventCardId != null && actionType != null) {
          cardIdToActionType[eventCardId] = actionType;
        }
      }
    }
    
    final tracker = CardPositionTracker.instance();
    
    for (final card in cards) {
      if (card == null || card is! Map<String, dynamic>) {
        continue;
      }
      
      final cardId = card['cardId']?.toString();
      if (cardId == null) {
        continue;
      }
      
      // Get or create GlobalKey for this card
      final cardKey = _cardKeys.putIfAbsent(cardId, () => GlobalKey(debugLabel: 'card_$cardId'));
      
      // Get RenderBox from GlobalKey
      final renderObject = cardKey.currentContext?.findRenderObject();
      if (renderObject == null) {
        continue;
      }
      
      final RenderBox? renderBox = renderObject as RenderBox?;
      if (renderBox == null) {
        continue;
      }
      
      // Get screen position and size
      final position = renderBox.localToGlobal(Offset.zero);
      final size = renderBox.size;
      
      // Get animation type from turn_events if available
      final actionType = cardIdToActionType[cardId];
      AnimationType? suggestedAnimationType;
      if (actionType != null) {
        // Map actionType string to AnimationType enum
        switch (actionType) {
          case 'draw':
            suggestedAnimationType = AnimationType.draw;
            break;
          case 'play':
            suggestedAnimationType = AnimationType.play;
            break;
          case 'collect':
            suggestedAnimationType = AnimationType.collect;
            break;
          case 'reposition':
            suggestedAnimationType = AnimationType.reposition;
            break;
        }
      }
      
      // Update position in tracker with player status and suggested animation type
      tracker.updateCardPosition(
        cardId,
        position,
        size,
        'my_hand',
        playerStatus: playerStatus,
        suggestedAnimationType: suggestedAnimationType,
      );
    }
    
    // Verbose logging removed to reduce log noise
    // tracker.logAllPositions(); // Disabled - too verbose
  }


  /// Handle card selection with status validation
  void _handleCardSelection(BuildContext context, int index, Map<String, dynamic> card) async {
    // Check local processing flag first (prevents rapid clicking without touching backend state)
    if (_isProcessingAction) {
      _logger.info('🚫 MyHandWidget - Action already in progress, ignoring card selection', isOn: LOGGING_SWITCH);
      return;
    }
    
    // Get current player status from state
    final currentState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    final currentMyHand = currentState['myHand'] as Map<String, dynamic>? ?? {};
    // Get playerStatus from myHand slice (computed from SSOT)
    final currentPlayerStatus = currentMyHand['playerStatus']?.toString() ?? 'unknown';
      
    // Check if current player can interact with hand cards (playing_card, jack_swap, queen_peek, same_rank_window, or initial_peek status)
    if (currentPlayerStatus == 'playing_card' || 
        currentPlayerStatus == 'jack_swap' || 
        currentPlayerStatus == 'queen_peek' ||
        currentPlayerStatus == 'same_rank_window' ||
        currentPlayerStatus == 'initial_peek') {
      
      // Update the selected card in the state

      final updatedMyHand = {
        ...currentMyHand,
        'selectedIndex': index,
        'selectedCard': card,
      };
      
      StateManager().updateModuleState('recall_game', {
        ...currentState,
        'myHand': updatedMyHand,
      });
      
      // Get current game ID from state
      final currentGameId = currentState['currentGameId']?.toString() ?? '';
      if (currentGameId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error: No active game found'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }
      
      // Execute the appropriate action based on player status
      try {
        if (currentPlayerStatus == 'same_rank_window') {
          // Use same rank play action for same rank window
          final sameRankAction = PlayerAction.sameRankPlay(
            gameId: currentGameId,
            cardId: card['cardId']?.toString() ?? '',
          );
          await sameRankAction.execute();
          
          // Show success feedback for same rank play
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Same Rank Play: ${card['rank']} of ${card['suit']}'
              ),
              backgroundColor: Colors.blue,
              duration: Duration(seconds: 2),
            ),
          );
        } else if (currentPlayerStatus == 'jack_swap') {
          // Handle Jack swap card selection
          // Get current user ID (sessionId) - handles both practice and multiplayer modes
          final currentUserId = RecallEventHandlerCallbacks.getCurrentUserId();
          
          await PlayerAction.selectCardForJackSwap(
            cardId: card['cardId']?.toString() ?? '',
            playerId: currentUserId,
            gameId: currentGameId,
          );
          
          // Show feedback for Jack swap selection
          final selectionCount = PlayerAction.getJackSwapSelectionCount();
          if (selectionCount == 1) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'First card selected: ${card['rank']} of ${card['suit']}. Select another card to swap.'
                ),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 2),
              ),
            );
          } else if (selectionCount == 2) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Second card selected: ${card['rank']} of ${card['suit']}. Swapping cards...'
                ),
                backgroundColor: Colors.purple,
                duration: Duration(seconds: 2),
              ),
            );
          }
        } else if (currentPlayerStatus == 'queen_peek') {
          // Handle Queen peek card selection
          // Get current user ID (sessionId) - handles both practice and multiplayer modes
          final currentUserId = RecallEventHandlerCallbacks.getCurrentUserId();
          
          final queenPeekAction = PlayerAction.queenPeek(
            gameId: currentGameId,
            cardId: card['cardId']?.toString() ?? '',
            ownerId: currentUserId,
          );
          await queenPeekAction.execute();
          
          // Show feedback for Queen peek
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Peeking at: ${card['rank']} of ${card['suit']}'
              ),
              backgroundColor: Colors.pink,
              duration: Duration(seconds: 2),
            ),
          );
        } else if (currentPlayerStatus == 'initial_peek') {
          // Handle Initial peek card selection (limit to 2 cards)
          final cardId = card['cardId']?.toString() ?? '';
          
          if (cardId.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Invalid card data'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 2),
              ),
            );
            return;
          }
          
          // Check if card already selected
          if (_initialPeekSelectedCardIds.contains(cardId)) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Card already selected'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 2),
              ),
            );
            return;
          }
          
          if (_initialPeekSelectionCount < 2) {
            // Add card ID to selected list
            _initialPeekSelectedCardIds.add(cardId);
            _initialPeekSelectionCount++;
            
            // Show card selection feedback (without card details since we only have ID)
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Card ${_initialPeekSelectionCount}/2 selected'
                ),
                backgroundColor: Colors.teal,
                duration: Duration(seconds: 2),
              ),
            );
            
            // If this is the second card, trigger completed initial peek
            if (_initialPeekSelectionCount == 2) {
              // Small delay to show the second card snackbar
              await Future.delayed(Duration(milliseconds: 500));
              
              // Send completed_initial_peek with both card IDs
              final completedInitialPeekAction = PlayerAction.completedInitialPeek(
                gameId: currentGameId,
                cardIds: _initialPeekSelectedCardIds,
              );
              await completedInitialPeekAction.execute();
              
              // Show completion feedback
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Initial peek completed! You have looked at 2 cards.'
                  ),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 3),
                ),
              );
              
              // Reset state
              _initialPeekSelectionCount = 0;
              _initialPeekSelectedCardIds.clear();
            }
          } else {
            // Already selected 2 cards, show message
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'You have already peeked at 2 cards. Initial peek is complete.'
                ),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 2),
              ),
            );
          }
        } else {
          // Set local processing flag (prevents rapid clicking, frontend-only)
          setState(() {
            _isProcessingAction = true;
          });
          _logger.info('🔒 MyHandWidget - Set _isProcessingAction = true', isOn: LOGGING_SWITCH);
          
          // Use regular play card action for other states
          final playAction = PlayerAction.playerPlayCard(
            gameId: currentGameId,
            cardId: card['cardId']?.toString() ?? '',
          );
          await playAction.execute();
          
          // Reset processing flag after a short delay to allow backend response to arrive
          // Backend will set the correct status (waiting on success, playing_card on failure)
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              setState(() {
                _isProcessingAction = false;
              });
              _logger.info('🔓 MyHandWidget - Reset _isProcessingAction = false', isOn: LOGGING_SWITCH);
            }
          });
          
          // Note: Success feedback removed to avoid showing success when action actually failed
          // Failed actions will show error messages via actionError state
          // Successful plays will be visible via game state updates (card moves to discard pile)
        }
      } catch (e) {
        // Reset processing flag on error
        if (mounted) {
          setState(() {
            _isProcessingAction = false;
          });
          _logger.info('🔓 MyHandWidget - Reset _isProcessingAction = false (error case)', isOn: LOGGING_SWITCH);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to execute action: $e'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } else {
      // Show invalid action feedback
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Invalid action: Cannot interact with hand cards while status is "$currentPlayerStatus"'
          ),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  /// Build a blank card slot for same-rank play empty spaces
  Widget _buildBlankCardSlot() {
    // Use unified card dimensions to match regular cards
    final cardDimensions = CardDimensions.getUnifiedDimensions();
    
    return SizedBox(
      width: cardDimensions.width,
      height: cardDimensions.height,
      child: Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.grey.shade300,
          width: 2,
          style: BorderStyle.solid,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.space_bar,
              size: 24,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 4),
            Text(
              'Empty',
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }

  /// Build card widget with optional drawn card glow and collection rank border
  Widget _buildCardWidget(Map<String, dynamic> card, bool isSelected, bool isDrawnCard, bool isCollectionRankCard, int index, Map<String, dynamic> cardMap, GlobalKey cardKey) {
    // Convert to CardModel
    final cardModel = CardModel.fromMap(card);
    final updatedCardModel = cardModel.copyWith(isSelected: isSelected);
    
    // Size determined at widget level using CardDimensions
    final cardDimensions = CardDimensions.getUnifiedDimensions();
    
    Widget cardWidget = CardWidget(
      key: cardKey,
      card: updatedCardModel,
      dimensions: cardDimensions, // Pass dimensions directly
      config: CardDisplayConfig.forMyHand(),
      isSelected: isSelected,
      onTap: () => _handleCardSelection(context, index, cardMap),
    );
    
    // Note: Collection rank cards no longer get a border - they're visually distinct through stacking + full data
    
    // Wrap with drawn card glow if needed - explicit size constraints to prevent size changes
    if (isDrawnCard) {
      cardWidget = SizedBox(
        width: cardDimensions.width,
        height: cardDimensions.height,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFBC02D).withOpacity(0.6), // Gold glow using theme color
                blurRadius: 12,
                spreadRadius: 2,
                offset: const Offset(0, 0),
              ),
            ],
          ),
          child: cardWidget,
        ),
      );
    }
    
    return cardWidget;
  }

}
