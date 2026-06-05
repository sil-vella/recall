import 'dart:async';
import '../../../../core/managers/state_manager.dart';
import '../../../../utils/analytics_service.dart';
import 'dutch_game_state_updater.dart';
import 'player_action.dart';
import '../utils/dutch_firebase_analytics.dart';
import '../utils/dutch_game_helpers.dart';


/// Game Coordinator for handling all player game actions
/// 
/// This class centralizes all player game actions and ensures they go through
/// a consistent flow before being sent to the backend.
class GameCoordinator {
  static final GameCoordinator _instance = GameCoordinator._internal();
  
  factory GameCoordinator() => _instance;
  GameCoordinator._internal();
  
  Timer? _leaveGameTimer; // Track active leave timer (survives widget disposal)
  String? _pendingLeaveGameId; // Track which game has pending leave
  /// One Firebase `start_match_*` per [gameId] (manual Start tap or server auto-start).
  final Set<String> _firebaseStartMatchLoggedGameIds = <String>{};
  
  /// Get the pending leave game ID (for checking if user returned to same game)
  String? get pendingLeaveGameId => _pendingLeaveGameId;
  
  /// Join a game
  Future<bool> joinGame({
    String? gameId,
    required String playerName,
    String playerType = 'human',
    int maxPlayers = 4,
  }) async {
    try {
      if (gameId == null || gameId.isEmpty) {
        return false;
      }
      
      final action = PlayerAction.joinGame(
        gameId: gameId,
        playerName: playerName,
        playerType: playerType,
        maxPlayers: maxPlayers,
      );
      await action.execute();
      return true;
    } catch (e) {
      return false;
    }
  }
  
  /// Leave a game
  Future<bool> leaveGame({
    required String gameId,
  }) async {
    
    try {
      
      final action = PlayerAction.leaveGame(gameId: gameId);
      await action.execute();
      
      return true;
    } catch (e) {
      
      return false;
    }
  }
  
  /// Start 30-second timer before leaving game
  /// Gives user chance to return to game within 30 seconds
  /// Timer is managed here (not in widget) so it survives widget disposal
  void startLeaveGameTimer(String gameId) {
    // Cancel any existing timer first
    if (_leaveGameTimer != null) {
      _leaveGameTimer?.cancel();
      
    }
    
    _pendingLeaveGameId = gameId;
    
    
    _leaveGameTimer = Timer(const Duration(seconds: 30), () {
      
      _executeLeaveGame(gameId);
    });
  }
  
  /// Cancel the leave game timer
  /// Called when user returns to the same game within 30 seconds
  void cancelLeaveGameTimer(String? gameId) {
    if (_leaveGameTimer != null && (gameId == null || _pendingLeaveGameId == gameId)) {
      
      _leaveGameTimer?.cancel();
      _leaveGameTimer = null;
      _pendingLeaveGameId = null;
    }
  }

  /// Reset coordinator to init state (no timer, no pending leave). Call when clearing all games.
  void resetToInit() {
    if (_leaveGameTimer != null) {
      _leaveGameTimer!.cancel();
      _leaveGameTimer = null;
    }
    _pendingLeaveGameId = null;
    _firebaseStartMatchLoggedGameIds.clear();
    DutchFirebaseAnalytics.resetSession();
  }

  /// Logs Firebase `start_match_*` when the server auto-starts (random join, auto_start rooms).
  ///
  /// Manual multiplayer starts still log via [startMatch]. Practice logs via [startMatch] only.
  void maybeLogFirebaseStartMatchOnServerPhaseTransition({
    required String gameId,
    required String previousUiPhase,
    required String rawPhase,
  }) {
    if (gameId.isEmpty || gameId.startsWith('practice_room_')) {
      return;
    }

    final wasWaiting = previousUiPhase == 'waiting' ||
        previousUiPhase == 'setup' ||
        previousUiPhase.isEmpty;
    if (!wasWaiting) {
      return;
    }

    if (rawPhase.isEmpty ||
        rawPhase == 'waiting_for_players' ||
        rawPhase == 'game_ended') {
      return;
    }

    if (_firebaseStartMatchLoggedGameIds.contains(gameId)) {
      return;
    }

    final dutchGameState =
        StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final isClearAndCollect = _resolveIsClearAndCollect(gameId, dutchGameState);

    unawaited(_logFirebaseStartMatch(
      currentGameId: gameId,
      isPractice: false,
      isClearAndCollect: isClearAndCollect,
    ));
  }

  bool _resolveIsClearAndCollect(
    String currentGameId,
    Map<String, dynamic> dutchGameState,
  ) {
    if (currentGameId.startsWith('practice_room_')) {
      final practiceSettings =
          dutchGameState['practiceSettings'] as Map<String, dynamic>?;
      return practiceSettings?['isClearAndCollect'] == true;
    }

    final rj = dutchGameState['randomJoinIsClearAndCollect'] as bool?;
    if (rj != null) {
      return rj;
    }

    final games = dutchGameState['games'] as Map<String, dynamic>? ?? {};
    final entry = games[currentGameId] as Map<String, dynamic>?;
    final gt = entry?['game_type']?.toString() ?? 'classic';
    return gt == 'clear_and_collect';
  }
  
  /// Execute leave game after timer expires
  /// Handles both multiplayer and practice mode
  void _executeLeaveGame(String gameId) {
    
    
    // Clear timer references
    _leaveGameTimer = null;
    _pendingLeaveGameId = null;
    
    // For multiplayer games (room_*), send leave_room event to backend
    // This removes the player from the game on the backend
    if (gameId.startsWith('room_')) {
      
      leaveGame(gameId: gameId).catchError((e) {
        
        return false;
      });
    }
    
    // For practice games (practice_room_*), just clear state (no backend event needed)
    // Practice mode bridge handles its own cleanup
    if (gameId.startsWith('practice_room_')) {
      
    }
    
    // Clear game state: remove player from games map and clear current game references
    // This triggers widget updates through StateManager
    DutchGameHelpers.removePlayerFromGame(gameId: gameId);
    
    
  }
  
  /// Create and execute a start match action
  Future<bool> startMatch() async {
    try {
      // Get current game state
      final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
      
      if (currentGameId.isEmpty) {
        
        return false;
      }
      
      // Get practice settings if this is a practice game (for showInstructions and isClearAndCollect)
      final bool? showInstructions;
      final bool? isClearAndCollect;
      if (currentGameId.startsWith('practice_room_')) {
        final practiceSettings = dutchGameState['practiceSettings'] as Map<String, dynamic>?;
        showInstructions = practiceSettings?['showInstructions'] as bool?;
        isClearAndCollect = practiceSettings?['isClearAndCollect'] as bool?;
      } else {
        showInstructions = null; // Multiplayer games don't use showInstructions
        isClearAndCollect = _resolveIsClearAndCollect(currentGameId, dutchGameState);
      }
      
      // Create and execute the player action
      final action = PlayerAction.startMatch(
        gameId: currentGameId,
        showInstructions: showInstructions,
        isClearAndCollect: isClearAndCollect,
      );
      
      await action.execute();
      await _logFirebaseStartMatch(
        currentGameId: currentGameId,
        isPractice: currentGameId.startsWith('practice_room_'),
        isClearAndCollect: isClearAndCollect == true,
      );
      return true;
    } catch (e) {
      
      rethrow;
    }
  }

  /// Firebase: separate events for random vs create vs join, classic vs clear/collect, practice.
  Future<void> _logFirebaseStartMatch({
    required String currentGameId,
    required bool isPractice,
    required bool isClearAndCollect,
  }) async {
    if (_firebaseStartMatchLoggedGameIds.contains(currentGameId)) {
      return;
    }
    _firebaseStartMatchLoggedGameIds.add(currentGameId);

    if (isPractice) {
      final name = isClearAndCollect
          ? 'start_match_practice_clear_collect'
          : 'start_match_practice_classic';
      await AnalyticsService.logEvent(
        name: name,
        parameters: {'game_id': currentGameId},
      );
      DutchGameStateUpdater.instance.updateStateSync({
        'pending_start_match_source': null,
      });
      return;
    }

    final dutchGameState =
        StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    var source = dutchGameState['pending_start_match_source']?.toString() ?? '';
    if (source.isEmpty) {
      final games = dutchGameState['games'] as Map<String, dynamic>? ?? {};
      final entry = games[currentGameId] as Map<String, dynamic>?;
      final isRandom = entry?['is_random_join'] == true;
      if (isRandom) {
        source = 'random_join';
      } else {
        final topOwner = dutchGameState['isRoomOwner'] == true;
        final entryOwner = entry?['isRoomOwner'] == true;
        source = (topOwner || entryOwner) ? 'create_room' : 'join_room';
      }
    }

    late final String eventName;
    switch (source) {
      case 'random_join':
        eventName = isClearAndCollect
            ? 'start_match_random_clear_collect'
            : 'start_match_random_classic';
        break;
      case 'create_room':
        eventName = isClearAndCollect
            ? 'start_match_create_clear_collect'
            : 'start_match_create_classic';
        break;
      case 'join_room':
        eventName = isClearAndCollect
            ? 'start_match_join_clear_collect'
            : 'start_match_join_classic';
        break;
      default:
        eventName = isClearAndCollect
            ? 'start_match_join_clear_collect'
            : 'start_match_join_classic';
        break;
    }

    await AnalyticsService.logEvent(
      name: eventName,
      parameters: {'game_id': currentGameId},
    );
    DutchGameStateUpdater.instance.updateStateSync({
      'pending_start_match_source': null,
    });
  }
}