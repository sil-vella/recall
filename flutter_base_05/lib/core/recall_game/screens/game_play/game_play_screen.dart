import 'package:flutter/material.dart';
import '../../../../managers/state_manager.dart';
import '../../../models/game_state.dart' as gm;
import '../../../models/player.dart';
import '../../../models/card.dart' as cm;
import '../../../managers/recall_game_manager.dart';
import '../../../managers/recall_state_manager.dart';
import '../../../../00_base/screen_base.dart';
import '../../lobby_room/widgets/message_board_widget.dart';
import '../../../../utils/consts/theme_consts.dart';
import 'widgets/status_bar.dart';
import 'widgets/opponents_panel.dart';
import 'widgets/center_board.dart';
import 'widgets/my_hand_panel.dart';
import 'widgets/action_bar.dart';

class GamePlayScreen extends BaseScreen {
  const GamePlayScreen({Key? key}) : super(key: key);

  @override
  String computeTitle(BuildContext context) => 'Recall Match';

  @override
  State<GamePlayScreen> createState() => _GamePlayScreenState();
}

class _GamePlayScreenState extends BaseScreenState<GamePlayScreen> {
  final StateManager _stateManager = StateManager();
  final RecallStateManager _recallState = RecallStateManager();
  final RecallGameManager _gameManager = RecallGameManager();

  // UI selections
  cm.Card? _selectedCard;
  int? _replaceIndex; // when replacing with drawn card

  @override
  void initState() {
    super.initState();
    // Ensure managers are initialized via RecallGameCore
  }

  void _onSelectCard(cm.Card card, int index) {
    setState(() {
      _selectedCard = card;
      _replaceIndex = index; // default replace index aligns with selected index
    });
  }

  Future<void> _onDrawFromDeck() async {
    await _gameManager.drawFromDeck();
  }

  Future<void> _onTakeFromDiscard() async {
    await _gameManager.takeFromDiscard();
  }

  Future<void> _onPlaySelected() async {
    final card = _selectedCard;
    if (card == null) return;
    await _gameManager.playCard(card);
    setState(() {
      _selectedCard = null;
    });
  }

  Future<void> _onReplaceWithDrawn() async {
    if (_replaceIndex == null) return;
    await _gameManager.placeDrawnCardReplace(_replaceIndex!);
    setState(() {
      _selectedCard = null;
      _replaceIndex = null;
    });
  }

  Future<void> _onPlaceDrawnAndPlay() async {
    await _gameManager.placeDrawnCardPlay();
  }

  Future<void> _onCallRecall() async {
    await _gameManager.callRecall();
  }

  @override
  Widget buildContent(BuildContext context) {
    final gameState = _recallState.currentGameState;
    final myHand = _recallState.getMyHand();
    final isMyTurn = _recallState.isMyTurn;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 900;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Match status header
              StatusBar(
                stateManager: _stateManager,
                gameState: gameState,
              ),
              const SizedBox(height: 12),

              // Opponents row
              if (gameState != null)
                OpponentsPanel(
                  opponents: gameState.players
                      .where((p) => p.isHuman || p.isComputer)
                      .where((p) => p.id != gameState.currentPlayer?.id)
                      .toList(),
                ),
              const SizedBox(height: 12),

              // Board + Messages side-by-side on wide screens
              if (isWide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: CenterBoard(
                        stateManager: _stateManager,
                        gameState: gameState,
                        onDrawFromDeck: _onDrawFromDeck,
                        onTakeFromDiscard: _onTakeFromDiscard,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: MessageBoardWidget(stateManager: _stateManager),
                    ),
                  ],
                )
              else ...[
                CenterBoard(
                  stateManager: _stateManager,
                  gameState: gameState,
                  onDrawFromDeck: _onDrawFromDeck,
                  onTakeFromDiscard: _onTakeFromDiscard,
                ),
                const SizedBox(height: 16),
                MessageBoardWidget(stateManager: _stateManager),
              ],

              const SizedBox(height: 16),

              // My Hand
              Card(
                child: Padding(
                  padding: AppPadding.cardPadding,
                  child: MyHandPanel(
                    hand: myHand,
                    selected: _selectedCard,
                    onSelect: _onSelectCard,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Actions
              ActionBar(
                isMyTurn: isMyTurn,
                hasSelection: _selectedCard != null,
                onPlay: _onPlaySelected,
                onReplaceWithDrawn: _onReplaceWithDrawn,
                onPlaceDrawnAndPlay: _onPlaceDrawnAndPlay,
                onCallRecall: _onCallRecall,
              ),
            ],
          ),
        );
      },
    );
  }
}


