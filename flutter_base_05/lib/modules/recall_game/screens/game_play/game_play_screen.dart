import 'package:flutter/material.dart';
import '../../../../core/managers/state_manager.dart';
import '../../models/card.dart' as cm;
import '../../models/turn_phase.dart';
import '../../models/player_action.dart';

import '../../utils/recall_game_helpers.dart';
import '../../../../../tools/logging/logger.dart';
// Provider removed – use StateManager only

import '../../../../core/00_base/screen_base.dart';
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
  
  // Widget state registration tracking
  static bool _widgetStatesRegistered = false;
  
  /// Show snackbar message to user
  void _showSnackBar(String message, {bool isError = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : Colors.green,
          duration: Duration(seconds: isError ? 4 : 2),
        ),
      );
    }
  }

  /// Ensure widget-specific states are registered under recall_game key
  void _ensureWidgetStatesRegistered() {
    if (!_widgetStatesRegistered) {
      _log.info('📊 Populating GamePlayScreen widget slices under recall_game...');
      
      // Get current recall_game state
      final currentState = _sm.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
      
      // Update with widget slices
      final updatedState = Map<String, dynamic>.from(currentState);
      
      // Populate actionBar slice
      updatedState['actionBar'] = {
        'showStartButton': false,
        'canPlayCard': false,
        'canCallRecall': false,
        'isGameStarted': false,
      };
      
      // Populate statusBar slice
      updatedState['statusBar'] = {
        'currentPhase': 'waiting',
        'turnInfo': '',
        'playerCount': 0,
        'gameStatus': 'inactive',
      };
      
      // Populate myHand slice
      updatedState['myHand'] = {
        'cards': <Map<String, dynamic>>[],
        'selectedIndex': null,
        'canSelectCards': false,
      };
      
      // Populate centerBoard slice
      updatedState['centerBoard'] = {
        'discardPile': <Map<String, dynamic>>[],
        'drawPileCount': 0,
        'lastPlayedCard': null,
      };
      
      // Populate opponentsPanel slice
      updatedState['opponentsPanel'] = {
        'players': <Map<String, dynamic>>[],
        'currentPlayerIndex': -1,
      };
      
      // Update the recall_game state with populated slices
      _sm.updateModuleState('recall_game', updatedState);
      
      _widgetStatesRegistered = true;
      _log.info('✅ GamePlayScreen widget slices populated under recall_game');
    }
  }

  @override
  void initState() {
    super.initState();
    _ensureWidgetStatesRegistered();
    _log.info('🎮 GamePlayScreen initialized');
      }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Update turn state whenever dependencies change (like StateManager updates)
  }

  Future<void> _onStartMatch() async {
    _log.info('🎮 Starting match');
    
    final recall = _sm.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    final currentGameId = recall['currentGameId'] as String?;
    final currentRoomId = recall['currentRoomId'] as String?;
    
    if (currentGameId != null || currentRoomId != null) {
      try {
        await RecallGameHelpers.startMatch(currentGameId ?? currentRoomId!);
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

    );
  }

}


