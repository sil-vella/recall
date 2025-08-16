import 'package:flutter/material.dart';
import '../../../managers/state_manager.dart';
import '../../models/card.dart' as cm;

import '../../managers/recall_game_manager.dart';
import '../../utils/recall_game_helpers.dart';
// Provider removed – use StateManager only



import '../../../00_base/screen_base.dart';
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
  String computeTitle(BuildContext context) => 'Recall Match';

  @override
  _GamePlayScreenState createState() => _GamePlayScreenState();
}

class _GamePlayScreenState extends BaseScreenState<GamePlayScreen> {
  // State management - screen itself doesn't subscribe to state changes
  final StateManager _sm = StateManager();
  final RecallGameManager _gameManager = RecallGameManager();

  // UI selections are now managed in StateManager

  @override
  void initState() {
    super.initState();
    

    
    // Ensure managers are initialized via RecallGameCore; if entering directly from lobby,
    // attempt to join the game with current room id.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final wsState = _sm.getModuleState<Map<String, dynamic>>('websocket') ?? {};
      final currentRoomId = (wsState['currentRoomId'] ?? '') as String;
      if (currentRoomId.isNotEmpty && _gameManager.currentGameId != currentRoomId) {
        final userState = _sm.getModuleState<Map<String, dynamic>>('auth') ?? {};
        final loginState = _sm.getModuleState<Map<String, dynamic>>('login') ?? {};
        final playerName = (userState['user']?['name'] ?? loginState['username'] ?? loginState['email'] ?? 'Player').toString();
        await _gameManager.joinGame(currentRoomId, playerName);
      }
    });
  }

  void _onSelectCard(cm.Card card, int index) {
    // 🎯 Use validated helpers for UI state
    RecallGameHelpers.setSelectedCard(card.toJson(), index);
  }

  Future<void> _onDrawFromDeck() async {
    await _gameManager.drawFromDeck();
  }

  Future<void> _onTakeFromDiscard() async {
    await _gameManager.takeFromDiscard();
  }

  Future<void> _onPlaySelected() async {
    final recall = _sm.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    final selectedCardJson = recall['selectedCard'] as Map<String, dynamic>?;
    if (selectedCardJson != null) {
      final selectedCard = cm.Card.fromJson(selectedCardJson);
      await _gameManager.playCard(selectedCard);
      // 🎯 Clear selection using validated helpers
      RecallGameHelpers.clearSelectedCard();
    }
  }

  Future<void> _onReplaceWithDrawn() async {
    final recall = _sm.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    final selectedCardIndex = recall['selectedCardIndex'] as int?;
    if (selectedCardIndex != null) {
      await _gameManager.placeDrawnCardReplace(selectedCardIndex);
      // 🎯 Clear selection using validated helpers
      RecallGameHelpers.clearSelectedCard();
    }
  }

  Future<void> _onPlaceDrawnAndPlay() async {
    await _gameManager.placeDrawnCardPlay();
  }

  Future<void> _onCallRecall() async {
    await _gameManager.callRecall();
  }

  Future<void> _onPlayOutOfTurn() async {
    final recall = _sm.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    final selectedCardJson = recall['selectedCard'] as Map<String, dynamic>?;
    if (selectedCardJson != null) {
      final selectedCard = cm.Card.fromJson(selectedCardJson);
      await _gameManager.playOutOfTurn(selectedCard);
      // 🎯 Clear selection using validated helpers
      RecallGameHelpers.clearSelectedCard();
    }
  }

  Future<void> _onStartMatch() async {
    print('🚀 _onStartMatch called!');
    try {
      final result = await _gameManager.startMatch();
      print('🚀 startMatch result: $result');
    } catch (e) {
      print('❌ Error in _onStartMatch: $e');
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


