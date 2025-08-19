import 'package:flutter/material.dart';
import '../../../managers/state_manager.dart';
import '../../models/card.dart' as cm;

import '../../services/recall_game_coordinator.dart';
import '../../utils/recall_game_helpers.dart';
import '../../utils/validated_event_emitter.dart';
import '../../../../../tools/logging/logger.dart';
// Provider removed – use StateManager only

import '../../../00_base/screen_base.dart';
import '../lobby_room/widgets/message_board_widget.dart';
import '../../../../../utils/consts/theme_consts.dart';
import 'widgets/status_bar.dart';

import 'widgets/center_board.dart';
import 'widgets/my_hand_panel.dart';
import 'widgets/action_bar.dart';
// Provider removed
import '../../recall_game_main.dart';

class GamePlayScreen extends BaseScreen {
  const GamePlayScreen({Key? key}) : super(key: key);

  @override
  String computeTitle(BuildContext context) => 'Recall Match';

  @override
  _GamePlayScreenState createState() => _GamePlayScreenState();
}

class _GamePlayScreenState extends BaseScreenState<GamePlayScreen> {
  static final Logger _log = Logger();
  // State management - screen itself doesn't subscribe to state changes
  final StateManager _sm = StateManager();
  final RecallGameCoordinator _gameCoordinator = RecallGameCoordinator();

  // UI selections are now managed in StateManager

  @override
  void initState() {
    super.initState();
    _log.info('🎮 GamePlayScreen initialized');
    
    // Ensure managers are initialized via RecallGameCore; if entering directly from lobby,
    // attempt to join the game with current room id.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 🔧 Ensure RecallGameManager is ready
      _log.info('🔧 [GAME_PLAY] Ensuring RecallGameManager is ready...');
      final recallGameCore = RecallGameCore();
      final managerReady = await recallGameCore.ensureGameManagerReady();
      
      if (managerReady) {
        _log.info('✅ [GAME_PLAY] RecallGameManager is ready');
        
        // Log detailed status for debugging
        final status = recallGameCore.getDetailedStatus();
        _log.info('📊 [GAME_PLAY] RecallGameManager status: $status');
        
        // 🔧 TEMPORARY DEBUG: Set room ownership to true to test start match
        _log.info('🔧 [GAME_PLAY] TEMPORARY DEBUG: Setting room ownership to true');
        recallGameCore.recallGameManager.setRoomOwnership(true);
      } else {
        _log.error('❌ [GAME_PLAY] RecallGameManager is not ready');
      }
      
      // 🎯 Use validated state access
      final recall = _sm.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
      final currentRoomId = recall['currentRoomId'] as String? ?? '';
      if (currentRoomId.isNotEmpty && _gameCoordinator.currentGameId != currentRoomId) {
        final userInfo = recall['userInfo'] as Map<String, dynamic>? ?? {};
        final playerName = userInfo['name'] as String? ?? 'Player';
        await _gameCoordinator.joinGameAndRoom(currentRoomId, playerName);
      }
    });
  }

  void _onSelectCard(cm.Card card, int index) {
    _log.info('🎮 Card selected: ${card.displayName} at index $index');
    // 🎯 Use validated helpers for UI state
    RecallGameHelpers.setSelectedCard(card.toJson(), index);
  }

  Future<void> _onDrawFromDeck() async {
    _log.info('🎮 Drawing from deck');
    final recall = _sm.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    final gameId = recall['currentGameId'] as String?;
    final playerId = recall['playerId'] as String?;
    
    if (gameId != null && playerId != null) {
      await RecallGameHelpers.drawCard(
        gameId: gameId,
        playerId: playerId,
        source: 'deck',
      );
    }
  }

  Future<void> _onTakeFromDiscard() async {
    _log.info('🎮 Taking from discard');
    final recall = _sm.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    final gameId = recall['currentGameId'] as String?;
    final playerId = recall['playerId'] as String?;
    
    if (gameId != null && playerId != null) {
      await RecallGameHelpers.drawCard(
        gameId: gameId,
        playerId: playerId,
        source: 'discard',
      );
    }
  }

  Future<void> _onPlaySelected() async {
    _log.info('🎮 Playing selected card');
    final recall = _sm.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    final selectedCardJson = recall['selectedCard'] as Map<String, dynamic>?;
    final gameId = recall['currentGameId'] as String?;
    final playerId = recall['playerId'] as String?;
    
    if (selectedCardJson != null && gameId != null && playerId != null) {
      await RecallGameHelpers.playCard(
        gameId: gameId,
        cardId: selectedCardJson['displayName'] as String,
        playerId: playerId,
      );
      RecallGameHelpers.clearSelectedCard();
    }
  }

  Future<void> _onReplaceWithDrawn() async {
    _log.info('🎮 Replacing with drawn card');
    final recall = _sm.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    final selectedCardIndex = recall['selectedCardIndex'] as int?;
    final gameId = recall['currentGameId'] as String?;
    final playerId = recall['playerId'] as String?;
    
    if (selectedCardIndex != null && gameId != null && playerId != null) {
      await RecallGameHelpers.replaceDrawnCard(
        gameId: gameId,
        playerId: playerId,
        cardIndex: selectedCardIndex,
      );
      RecallGameHelpers.clearSelectedCard();
    }
  }

  Future<void> _onPlaceDrawnAndPlay() async {
    _log.info('🎮 Placing drawn card and playing');
    final recall = _sm.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    final gameId = recall['currentGameId'] as String?;
    final playerId = recall['playerId'] as String?;
    
    if (gameId != null && playerId != null) {
      await RecallGameHelpers.placeDrawnCard(
        gameId: gameId,
        playerId: playerId,
      );
    }
  }

  Future<void> _onCallRecall() async {
    _log.info('🎮 Calling recall');
    final recall = _sm.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    final gameId = recall['currentGameId'] as String?;
    final playerId = recall['playerId'] as String?;
    
    if (gameId != null && playerId != null) {
      await RecallGameHelpers.callRecall(
        gameId: gameId,
        playerId: playerId,
      );
    }
  }

  Future<void> _onPlayOutOfTurn() async {
    _log.info('🎮 Playing out of turn');
    final recall = _sm.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    final selectedCardJson = recall['selectedCard'] as Map<String, dynamic>?;
    final gameId = recall['currentGameId'] as String?;
    final playerId = recall['playerId'] as String?;
    
    if (selectedCardJson != null && gameId != null && playerId != null) {
      await RecallGameHelpers.playOutOfTurn(
        gameId: gameId,
        cardId: selectedCardJson['displayName'] as String,
        playerId: playerId,
      );
      RecallGameHelpers.clearSelectedCard();
    }
  }

  Future<void> _onStartMatch() async {
    _log.info('🎮 Starting match');
    final recall = _sm.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    final gameId = recall['currentGameId'] as String? ?? recall['currentRoomId'] as String?;
    
    _log.info('🎮 [startMatch] recall state keys: ${recall.keys.join(', ')}');
    _log.info('🎮 [startMatch] currentGameId: ${recall['currentGameId']}');
    _log.info('🎮 [startMatch] currentRoomId: ${recall['currentRoomId']}');
    _log.info('🎮 [startMatch] final gameId: $gameId');
    _log.info('🎮 [startMatch] gameId type: ${gameId.runtimeType}');
    
    if (gameId != null) {
      _log.info('🎮 [startMatch] Calling RecallGameHelpers.startMatch with gameId: $gameId');
      try {
        await RecallGameHelpers.startMatch(gameId);
        _log.info('🎮 [startMatch] startMatch call completed successfully');
      } catch (e) {
        _log.error('❌ Error in _onStartMatch: $e');
        _log.error('❌ Error type: ${e.runtimeType}');
        if (e is Exception) {
          _log.error('❌ Error toString: ${e.toString()}');
        }
      }
    } else {
      _log.error('❌ [startMatch] Both currentGameId and currentRoomId are null!');
    }
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
                    onSelect: _onSelectCard,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Actions
              ActionBar(
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
}


