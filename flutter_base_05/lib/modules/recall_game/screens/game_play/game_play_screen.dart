import 'package:flutter/material.dart';
import '../../../../core/managers/state_manager.dart';
import '../../models/card.dart' as cm;
import '../../models/turn_phase.dart';

import '../../services/recall_game_coordinator.dart';
import '../../utils/recall_game_helpers.dart';
import '../../../../../tools/logging/logger.dart';
// Provider removed – use StateManager only

import '../../../../core/00_base/screen_base.dart';
import '../lobby_room/widgets/message_board_widget.dart';
import '../../../../../utils/consts/theme_consts.dart';
import 'widgets/status_bar.dart';

import 'widgets/center_board.dart';
import 'widgets/my_hand_panel.dart';
import 'widgets/action_bar.dart';
// Provider removed

class GamePlayScreen extends BaseScreen {
  const GamePlayScreen({Key? key}) : super(key: key);

  @override
  String computeTitle(BuildContext context) => 'Recall Game';

  @override
  _GamePlayScreenState createState() => _GamePlayScreenState();
}

class _GamePlayScreenState extends BaseScreenState<GamePlayScreen> {
  static final Logger _log = Logger();
  // State management - screen itself doesn't subscribe to state changes
  final StateManager _sm = StateManager();
  
  // Use singleton instance from RecallGameMain module
  RecallGameCoordinator get _gameCoordinator => RecallGameCoordinator();

  // 🎯 INNER SCREEN TURN STATE MANAGEMENT
  PlayerTurnPhase _currentTurnPhase = PlayerTurnPhase.waiting;
  Map<String, dynamic>? _pendingDrawnCard;  // Card drawn but not placed
  bool _hasDrawnThisTurn = false;
  cm.Card? _selectedCard;
  int? _selectedCardIndex;

  // UI selections are now managed in StateManager

  @override
  void initState() {
    super.initState();
    _log.info('🎮 GamePlayScreen initialized');
    
    // Ensure managers are initialized via RecallGameCore; if entering directly from lobby,
    // attempt to join the game with current room id.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 🎯 Use validated state access
      final recall = _sm.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
      final currentRoomId = recall['currentRoomId'] as String? ?? '';
      if (currentRoomId.isNotEmpty && _gameCoordinator.currentGameId != currentRoomId) {
        final userInfo = recall['userInfo'] as Map<String, dynamic>? ?? {};
        final playerName = userInfo['name'] as String? ?? 'Player';
        await _gameCoordinator.joinGameAndRoom(currentRoomId, playerName);
      }
      
      // Initialize turn state based on current game state
      _updateTurnStateFromGameState();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Update turn state whenever dependencies change (like StateManager updates)
    _updateTurnStateFromGameState();
  }

  /// 🎯 Update turn state based on current game state
  void _updateTurnStateFromGameState() {
    final recall = _sm.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    final isMyTurn = recall['isMyTurn'] as bool? ?? false;
    final gamePhase = recall['gamePhase'] as String? ?? 'waiting';
    final canCallRecall = recall['canCallRecall'] as bool? ?? false;
    
    _log.info('🎯 Updating turn state: isMyTurn=$isMyTurn, gamePhase=$gamePhase, canCallRecall=$canCallRecall');
    _log.info('🎯 Current local state: hasDrawnThisTurn=$_hasDrawnThisTurn, pendingDrawnCard=${_pendingDrawnCard != null}');
    
    PlayerTurnPhase newPhase;
    
    if (!isMyTurn) {
      newPhase = PlayerTurnPhase.waiting;
      _log.info('🎯 Setting phase to waiting (not my turn)');
    } else if (_pendingDrawnCard != null) {
      // Check if we have a pending drawn card
      newPhase = PlayerTurnPhase.hasDrawnCard;
      _log.info('🎯 Setting phase to hasDrawnCard (pending drawn card)');
    } else if (!_hasDrawnThisTurn && gamePhase == 'playing') {
      // Check if we need to draw first
      newPhase = PlayerTurnPhase.mustDraw;
      _log.info('🎯 Setting phase to mustDraw (need to draw first)');
    } else if (canCallRecall) {
      // Normal play phase
      newPhase = PlayerTurnPhase.recallOpportunity;
      _log.info('🎯 Setting phase to recallOpportunity (can call recall)');
    } else {
      newPhase = PlayerTurnPhase.canPlay;
      _log.info('🎯 Setting phase to canPlay (normal play phase)');
    }
    
    _setTurnPhase(newPhase);
  }

  /// 🎯 Set turn phase and log the transition
  void _setTurnPhase(PlayerTurnPhase newPhase) {
    if (_currentTurnPhase != newPhase) {
      _log.info('🎯 Turn phase transition: ${_currentTurnPhase.name} → ${newPhase.name}');
      _currentTurnPhase = newPhase;
      _notifyTurnStateChanged();
    }
  }

  /// 🎯 Get current turn phase for UI components
  PlayerTurnPhase get currentTurnPhase => _currentTurnPhase;

  /// 🎯 Force rebuild when turn state changes
  void _notifyTurnStateChanged() {
    setState(() {
      // This will trigger a rebuild of the widgets
    });
  }

  /// 🎯 Check if an action is available in current turn phase
  bool _isActionAvailable(String action) {
    switch (_currentTurnPhase) {
      case PlayerTurnPhase.waiting:
        // Allow start_match in waiting phase
        return action == 'start_match';
      case PlayerTurnPhase.mustDraw:
        return action == 'draw_from_deck' || action == 'take_from_discard';
      case PlayerTurnPhase.hasDrawnCard:
        return action == 'play_drawn' || action == 'replace_with_drawn';
      case PlayerTurnPhase.canPlay:
        return action == 'play_card' || action == 'call_recall';
      case PlayerTurnPhase.outOfTurn:
        return action == 'play_out_of_turn';
      case PlayerTurnPhase.recallOpportunity:
        return action == 'call_recall';
    }
  }

  void _onSelectCard(cm.Card card, int index) {
    _log.info('🎮 Card selected: ${card.displayName} at index $index');
    
    // Only allow selection in appropriate phases
    if (!_isActionAvailable('play_card') && !_isActionAvailable('replace_with_drawn')) {
      _log.info('🎮 Card selection not allowed in current phase: ${_currentTurnPhase.name}');
      return;
    }
    
    _selectedCard = card;
    _selectedCardIndex = index;
    
    // 🎯 Use validated helpers for UI state
    RecallGameHelpers.setSelectedCard(card.toJson(), index);
    
    // Notify tutorial system of card selection
    handlePlayerAction(PlayerAction.selectCard, actionData: {
      'cardId': card.cardId,
      'cardIndex': index,
      'cardName': card.displayName,
    });
  }

  // ========= Centralized Player Action Handler =========
  
  /// 🎯 Catchall method for handling all player actions
  /// This centralizes common logic and enables tutorial integration
  Future<void> handlePlayerAction(PlayerAction action, {Map<String, dynamic>? actionData}) async {
    _log.info('🎮 [handlePlayerAction] Starting action: ${action.name}');
    
    try {
      // Common validation
      final recall = _sm.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
      _log.info('🎮 [handlePlayerAction] Debug - State keys: ${recall.keys.toList()}');
      _log.info('🎮 [handlePlayerAction] Debug - currentGameId: ${recall['currentGameId']}');
      
      final gameId = recall['currentGameId'] as String?;
      
      // Extract playerId from gameState.players array
      String? playerId;
      final gameState = recall['gameState'] as Map<String, dynamic>?;
      if (gameState != null) {
        final players = gameState['players'] as List<dynamic>? ?? [];
        if (players.isNotEmpty) {
          // Get the first player (assuming single player for now)
          final player = players.first as Map<String, dynamic>?;
          playerId = player?['id'] as String?;
          _log.info('🎮 [handlePlayerAction] Debug - Extracted playerId from gameState: $playerId');
        }
      }
      
      // Fallback: try to get playerId from top level
      if (playerId == null) {
        playerId = recall['playerId'] as String?;
        _log.info('🎮 [handlePlayerAction] Debug - Fallback playerId: $playerId');
      }
      
      if (gameId == null || playerId == null) {
        _log.error('❌ [handlePlayerAction] Missing gameId or playerId for action: ${action.name}');
        _log.error('❌ [handlePlayerAction] gameId: $gameId, playerId: $playerId');
        return;
      }
      
      // Check if action is allowed in current turn phase
      final actionName = _getActionName(action);
      if (!_isActionAvailable(actionName)) {
        _log.info('🎮 [handlePlayerAction] Action ${action.name} not allowed in current phase: ${_currentTurnPhase.name}');
        return;
      }
      
      // Execute the specific action
      final result = await _executePlayerAction(action, gameId, playerId, actionData);
      
      if (result['success'] == true) {
        _log.info('🎯 [handlePlayerAction] Action ${action.name} completed successfully');
        
        // Common cleanup after successful action
        _handleSuccessfulAction(action);
        
        // TODO: Tutorial integration - notify tutorial system of completed action
        // _notifyTutorialActionCompleted(action);
        
      } else {
        _log.error('❌ [handlePlayerAction] Action ${action.name} failed: ${result['error']}');
        // Don't clear selections on error - let user try again
      }
      
    } catch (e) {
      _log.error('❌ [handlePlayerAction] Error in action ${action.name}: $e');
      // Don't clear selections on error - let user try again
    }
  }
  
  /// Get the action name string for validation
  String _getActionName(PlayerAction action) {
    switch (action) {
      case PlayerAction.drawFromDeck:
        return 'draw_from_deck';
      case PlayerAction.takeFromDiscard:
        return 'take_from_discard';
      case PlayerAction.playCard:
        return 'play_card';
      case PlayerAction.replaceWithDrawn:
        return 'replace_with_drawn';
      case PlayerAction.placeDrawnAndPlay:
        return 'play_drawn';
      case PlayerAction.callRecall:
        return 'call_recall';
      case PlayerAction.playOutOfTurn:
        return 'play_out_of_turn';
      case PlayerAction.selectCard:
        return 'select_card';
      case PlayerAction.startMatch:
        return 'start_match';
    }
  }
  
  /// Execute the specific player action
  /// 🛡️ PRESERVED: Uses RecallGameHelpers for validation and event emission
  /// 🎯 ALIGNED: RecallGameHelpers now delegates business logic to GameService
  Future<Map<String, dynamic>> _executePlayerAction(
    PlayerAction action, 
    String gameId, 
    String playerId, 
    Map<String, dynamic>? actionData
  ) async {
    _log.info('🎯 [executePlayerAction] Executing ${action.name}');
    
    switch (action) {
      case PlayerAction.drawFromDeck:
        return await RecallGameHelpers.drawCard(
          gameId: gameId,
          playerId: playerId,
          source: 'deck',
        );
        
      case PlayerAction.takeFromDiscard:
        return await RecallGameHelpers.drawCard(
          gameId: gameId,
          playerId: playerId,
          source: 'discard',
        );
        
      case PlayerAction.playCard:
        if (_selectedCard == null) {
          return {'success': false, 'error': 'No card selected'};
        }
        return await RecallGameHelpers.playCard(
          gameId: gameId,
          cardId: _selectedCard!.cardId,
          playerId: playerId,
          replaceIndex: _selectedCardIndex,
        );
        
      case PlayerAction.replaceWithDrawn:
        if (_selectedCardIndex == null || _pendingDrawnCard == null) {
          return {'success': false, 'error': 'No card selected or no drawn card'};
        }
        return await RecallGameHelpers.replaceDrawnCard(
          gameId: gameId,
          playerId: playerId,
          cardIndex: _selectedCardIndex!,
        );
        
      case PlayerAction.placeDrawnAndPlay:
        if (_pendingDrawnCard == null) {
          return {'success': false, 'error': 'No drawn card to play'};
        }
        return await RecallGameHelpers.placeDrawnCard(
          gameId: gameId,
          playerId: playerId,
        );
        
      case PlayerAction.callRecall:
        return await RecallGameHelpers.callRecall(
          gameId: gameId,
          playerId: playerId,
        );
        
      case PlayerAction.playOutOfTurn:
        if (_selectedCard == null) {
          return {'success': false, 'error': 'No card selected'};
        }
        return await RecallGameHelpers.playOutOfTurn(
          gameId: gameId,
          cardId: _selectedCard!.cardId,
          playerId: playerId,
        );
        
      case PlayerAction.selectCard:
        // This is a frontend-only action for tutorial tracking
        return {'success': true, 'message': 'Card selected'};
        
      case PlayerAction.startMatch:
        return await RecallGameHelpers.startMatch(gameId);
    }
  }
  
  /// Handle successful action completion
  void _handleSuccessfulAction(PlayerAction action) {
    switch (action) {
      case PlayerAction.drawFromDeck:
      case PlayerAction.takeFromDiscard:
        // These actions don't clear selections - backend will update state
        break;
        
      case PlayerAction.playCard:
      case PlayerAction.playOutOfTurn:
        // Clear card selection after playing
        _selectedCard = null;
        _selectedCardIndex = null;
        RecallGameHelpers.clearSelectedCard();
        break;
        
      case PlayerAction.replaceWithDrawn:
        // Clear drawn card and selection
        _pendingDrawnCard = null;
        _selectedCard = null;
        _selectedCardIndex = null;
        RecallGameHelpers.clearSelectedCard();
        break;
        
      case PlayerAction.placeDrawnAndPlay:
        // Clear drawn card
        _pendingDrawnCard = null;
        _hasDrawnThisTurn = false;
        break;
        
      case PlayerAction.callRecall:
        // No specific cleanup needed
        break;
        
      case PlayerAction.selectCard:
        // No cleanup needed for selection
        break;
        
      case PlayerAction.startMatch:
        // No cleanup needed
        break;
    }
  }
  
  // ========= Individual Action Methods (now delegate to catchall) =========
  
  Future<void> _onDrawFromDeck() async {
    // Delegate to centralized action handler
    await handlePlayerAction(PlayerAction.drawFromDeck);
  }

  Future<void> _onTakeFromDiscard() async {
    // Delegate to centralized action handler
    await handlePlayerAction(PlayerAction.takeFromDiscard);
  }

  Future<void> _onPlaySelected() async {
    // Delegate to centralized action handler
    await handlePlayerAction(PlayerAction.playCard);
  }

  Future<void> _onReplaceWithDrawn() async {
    // Delegate to centralized action handler
    await handlePlayerAction(PlayerAction.replaceWithDrawn);
  }

  Future<void> _onPlaceDrawnAndPlay() async {
    // Delegate to centralized action handler
    await handlePlayerAction(PlayerAction.placeDrawnAndPlay);
  }

  Future<void> _onCallRecall() async {
    // Delegate to centralized action handler
    await handlePlayerAction(PlayerAction.callRecall);
  }

  Future<void> _onPlayOutOfTurn() async {
    // Delegate to centralized action handler
    await handlePlayerAction(PlayerAction.playOutOfTurn);
  }

  Future<void> _onStartMatch() async {
    // Delegate to centralized action handler
    await handlePlayerAction(PlayerAction.startMatch);
  }

  @override
  Widget buildContent(BuildContext context) {
    // Screen doesn't read state directly - widgets handle their own subscriptions
    return _buildGameContent(context);
  }

  Widget _buildGameContent(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 900;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🎯 Turn Phase Indicator
              _buildTurnPhaseIndicator(),
              const SizedBox(height: 8),
              
              // 🎯 DEBUG: Turn Phase Controls (remove in production)
              _buildDebugControls(),
              const SizedBox(height: 12),
              
              // 🎯 DEBUG: Current State Info
              _buildCurrentStateInfo(),
              const SizedBox(height: 12),
              
              // Match status header
              StatusBar(),
              const SizedBox(height: 12),

              // Opponents row - TODO: Create reactive OpponentsPanel
              const SizedBox(height: 12),

              // Board + Messages side-by-side on wide screens
              if (isWide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: CenterBoard(
                        currentTurnPhase: currentTurnPhase,
                        onDrawFromDeck: _onDrawFromDeck,
                        onTakeFromDiscard: _onTakeFromDiscard,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: MessageBoardWidget(),
                    ),
                  ],
                )
              else ...[
                CenterBoard(
                  currentTurnPhase: currentTurnPhase,
                  onDrawFromDeck: _onDrawFromDeck,
                  onTakeFromDiscard: _onTakeFromDiscard,
                ),
                const SizedBox(height: 16),
                MessageBoardWidget(),
              ],

              const SizedBox(height: 16),

              // My Hand
              Card(
                child: Padding(
                  padding: AppPadding.cardPadding,
                  child: MyHandPanel(
                    currentTurnPhase: currentTurnPhase,
                    onSelect: _onSelectCard,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Actions
              ActionBar(
                currentTurnPhase: currentTurnPhase,
                pendingDrawnCard: _pendingDrawnCard,
                onPlay: _onPlaySelected,
                onReplaceWithDrawn: _onReplaceWithDrawn,
                onPlaceDrawnAndPlay: _onPlaceDrawnAndPlay,
                onCallRecall: _onCallRecall,
                onPlayOutOfTurn: _onPlayOutOfTurn,
                onStartMatch: _onStartMatch,
              ),
            ],
          ),
        );
      },
    );
  }

  /// 🎯 Build turn phase indicator widget
  Widget _buildTurnPhaseIndicator() {
    final phaseColors = {
      PlayerTurnPhase.waiting: Colors.grey,
      PlayerTurnPhase.mustDraw: Colors.blue,
      PlayerTurnPhase.hasDrawnCard: Colors.orange,
      PlayerTurnPhase.canPlay: Colors.green,
      PlayerTurnPhase.outOfTurn: Colors.purple,
      PlayerTurnPhase.recallOpportunity: Colors.red,
    };

    final phaseMessages = {
      PlayerTurnPhase.waiting: 'Waiting for turn...',
      PlayerTurnPhase.mustDraw: 'Your turn! Draw a card first',
      PlayerTurnPhase.hasDrawnCard: 'Place your drawn card',
      PlayerTurnPhase.canPlay: 'Play a card or call Recall',
      PlayerTurnPhase.outOfTurn: 'Play matching card out of turn',
      PlayerTurnPhase.recallOpportunity: 'Call Recall or end turn',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: phaseColors[_currentTurnPhase]?.withOpacity(0.1),
        border: Border.all(color: phaseColors[_currentTurnPhase] ?? Colors.grey),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            color: phaseColors[_currentTurnPhase],
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              phaseMessages[_currentTurnPhase] ?? 'Unknown phase',
              style: AppTextStyles.bodyMedium.copyWith(
                color: phaseColors[_currentTurnPhase],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 🎯 Build debug controls for testing turn phases
  Widget _buildDebugControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.1),
        border: Border.all(color: Colors.amber),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '🎯 DEBUG: Turn Phase Controls (Current: ${_currentTurnPhase.name})',
            style: AppTextStyles.bodyMedium.copyWith(
              color: Colors.amber,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _buildDebugButton('Waiting', PlayerTurnPhase.waiting),
              _buildDebugButton('Must Draw', PlayerTurnPhase.mustDraw),
              _buildDebugButton('Has Drawn', PlayerTurnPhase.hasDrawnCard),
              _buildDebugButton('Can Play', PlayerTurnPhase.canPlay),
              _buildDebugButton('Out of Turn', PlayerTurnPhase.outOfTurn),
              _buildDebugButton('Recall Opp', PlayerTurnPhase.recallOpportunity),
            ],
          ),
        ],
      ),
    );
  }

  /// 🎯 Build individual debug button
  Widget _buildDebugButton(String label, PlayerTurnPhase phase) {
    final isCurrentPhase = _currentTurnPhase == phase;
    return ElevatedButton(
      onPressed: () {
        _log.info('🎯 DEBUG: Setting turn phase to ${phase.name}');
        _setTurnPhase(phase);
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: isCurrentPhase ? Colors.amber : Colors.grey,
        foregroundColor: isCurrentPhase ? Colors.black : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: const Size(0, 32),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  /// 🎯 Build current state info for debugging
  Widget _buildCurrentStateInfo() {
    final recall = _sm.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    final isMyTurn = recall['isMyTurn'] as bool? ?? false;
    final gamePhase = recall['gamePhase'] as String? ?? 'waiting';
    final canCallRecall = recall['canCallRecall'] as bool? ?? false;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        border: Border.all(color: Colors.blue),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '🎯 DEBUG: Current State Info',
            style: AppTextStyles.bodyMedium.copyWith(
              color: Colors.blue,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text('Turn Phase: ${_currentTurnPhase.name}', style: AppTextStyles.bodyMedium),
          Text('Is My Turn: $isMyTurn', style: AppTextStyles.bodyMedium),
          Text('Game Phase: $gamePhase', style: AppTextStyles.bodyMedium),
          Text('Can Call Recall: $canCallRecall', style: AppTextStyles.bodyMedium),
          Text('Has Drawn This Turn: $_hasDrawnThisTurn', style: AppTextStyles.bodyMedium),
          Text('Pending Drawn Card: ${_pendingDrawnCard != null}', style: AppTextStyles.bodyMedium),
        ],
      ),
    );
  }
}


