import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../managers/game_coordinator.dart';
import '../../../managers/validated_event_emitter.dart';
import '../../../../../tools/logging/logger.dart';
import '../../../../../utils/consts/theme_consts.dart';

/// Widget to display current game information
/// 
/// This widget subscribes to the dutch_game state slice and displays:
/// - Current game details (name, ID, players, phase, status)
/// - Game start timestamp
/// - Empty state when no game is active
/// 
/// Follows the established pattern of subscribing to state slices using ListenableBuilder
class GameInfoWidget extends StatefulWidget {
  const GameInfoWidget({Key? key}) : super(key: key);

  @override
  State<GameInfoWidget> createState() => _GameInfoWidgetState();
}

class _GameInfoWidgetState extends State<GameInfoWidget> {
  static const bool LOGGING_SWITCH = true; // Start / roster / effective size → server.log via Logger (enable-logging-switch.mdc)
  static final Logger _logger = Logger();
  bool _isStartingMatch = false;

  /// One-shot delayed rebuild when tournament [match_players] may arrive after first frame.
  bool _rosterRetryScheduled = false;
  bool _rosterRetryFired = false;
  String? _rosterRetryGameId;

  /// Mongo/session user ids already seated in [gameState.players] (excluded from roster comp bonus).
  Set<String> _seatedUserIds(Map<String, dynamic> gameState) {
    final players = gameState['players'];
    if (players is! List) return {};
    final out = <String>{};
    for (final p in players) {
      if (p is! Map) continue;
      final uid = p['userId']?.toString().trim() ?? '';
      if (uid.isNotEmpty) out.add(uid);
    }
    return out;
  }

  bool _isCompMatchPlayerEntry(Map<String, dynamic> e) {
    if (e['is_comp_player'] == true) return true;
    if (e['isHuman'] == false) return true;
    return false;
  }

  /// Comp roster slots from tournament [match_players] and/or [currentRoomInfo.accepted_players],
  /// deduped by [user_id] and excluding seated ids. Mirrors backend prefill intent.
  int _rosterCompBonus(
    Map<String, dynamic> gameState,
    Map<String, dynamic>? currentRoomInfo,
    String currentGameId,
  ) {
    if (currentGameId.isEmpty) return 0;
    final seated = _seatedUserIds(gameState);
    final bonusIds = <String>{};

    final td = gameState['tournament_data'];
    if (td is Map) {
      final mpr = td['match_players'];
      if (mpr is List) {
        for (final raw in mpr) {
          if (raw is! Map) continue;
          final e = Map<String, dynamic>.from(raw);
          if (!_isCompMatchPlayerEntry(e)) continue;
          final uid = (e['user_id'] ?? '').toString().trim();
          if (uid.isEmpty || seated.contains(uid)) continue;
          bonusIds.add(uid);
        }
      }
    }

    if (currentRoomInfo != null &&
        (currentRoomInfo['room_id']?.toString() ?? '') == currentGameId) {
      final ap = currentRoomInfo['accepted_players'];
      if (ap is List) {
        for (final raw in ap) {
          if (raw is! Map) continue;
          final e = Map<String, dynamic>.from(raw);
          if (e['is_comp_player'] != true) continue;
          final uid = (e['user_id'] ?? '').toString().trim();
          if (uid.isEmpty || seated.contains(uid)) continue;
          bonusIds.add(uid);
        }
      }
    }

    return bonusIds.length;
  }

  /// Tournament match is expected but [match_players] not loaded yet; one retry may help.
  bool _shouldScheduleTournamentRosterRetry(
    Map<String, dynamic> gameState,
    int rosterBonus,
    int baseSize,
    int minPlayers,
  ) {
    if (gameState['is_tournament'] != true) return false;
    if (baseSize >= minPlayers) return false;
    if (rosterBonus > 0) return false;
    final td = gameState['tournament_data'];
    if (td is! Map) return false;
    final mpr = td['match_players'];
    if (mpr is List && mpr.isNotEmpty) return false;
    return true;
  }

  void _syncRosterRetryGameId(String currentGameId) {
    if (_rosterRetryGameId != currentGameId) {
      _rosterRetryGameId = currentGameId;
      _rosterRetryScheduled = false;
      _rosterRetryFired = false;
    }
  }

  String? _getPhaseFromGamesMap(Map<String, dynamic> games, String gameId) {
    if (gameId.isEmpty || !games.containsKey(gameId)) {
      return null;
    }
    
    final gameEntry = games[gameId] as Map<String, dynamic>? ?? {};
    final gameData = gameEntry['gameData'] as Map<String, dynamic>? ?? {};
    final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
    final rawPhase = gameState['phase']?.toString();
    
    return _normalizePhase(rawPhase);
  }
  
  String? _normalizePhase(String? rawPhase) {
    if (rawPhase == null || rawPhase.isEmpty) {
      return null;
    }
    
    switch (rawPhase) {
      case 'waiting_for_players':
        return 'waiting';
      case 'dealing_cards':
        return 'setup';
      case 'player_turn':
      case 'same_rank_window':
      case 'special_play_window':
      case 'queen_peek_window':
      case 'turn_pending_events':
      case 'ending_round':
      case 'ending_turn':
      case 'dutch_called':
        return 'playing';
      default:
        return rawPhase;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        // Get gameInfo state slice
        final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        final wsState = StateManager().getModuleState<Map<String, dynamic>>('websocket') ?? {};
        final currentRoomInfo = wsState['currentRoomInfo'] as Map<String, dynamic>?;
        final gameInfo = dutchGameState['gameInfo'] as Map<String, dynamic>? ?? {};
        final games = dutchGameState['games'] as Map<String, dynamic>? ?? {};
        final currentGameId = gameInfo['currentGameId']?.toString() ?? '';
        _syncRosterRetryGameId(currentGameId);
        final roomName = 'Game $currentGameId';
        final rawSize = gameInfo['currentSize'];
        final baseSize = rawSize is num ? rawSize.toInt() : int.tryParse('$rawSize') ?? 0;
        
        // Derive phase from SSOT (games map) with fallback to gameInfo slice
        final ssotPhase = _getPhaseFromGamesMap(games, currentGameId);
        final gamePhase = ssotPhase ?? gameInfo['gamePhase']?.toString() ?? 'waiting';
        
        // Reset loading state if match has started
        if (_isStartingMatch && gamePhase != 'waiting' && gamePhase != 'setup') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _isStartingMatch = false;
              });
            }
          });
        }
        final gameStatus = gameInfo['gameStatus']?.toString() ?? 'inactive';
        final isRoomOwner = gameInfo['isRoomOwner'] ?? false;
        final isInGame = gameInfo['isInGame'] ?? false;
        final isPracticeGame = gameInfo['isPractice'] as bool? ?? currentGameId.startsWith('practice_room_');
        final multiplayerType = gameInfo['multiplayerType'] as Map<String, dynamic>?;
        final isRandomJoin = multiplayerType?['isRandom'] == true;

        // Game level and tournament info from current game's game_state (SSOT)
        final gameEntry = games[currentGameId] as Map<String, dynamic>? ?? {};
        final gameData = gameEntry['gameData'] as Map<String, dynamic>? ?? {};
        final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
        final gameLevel = gameState['gameLevel']; // int or null
        final minPlayers = (gameState['minPlayers'] as num?)?.toInt() ?? 2;
        final isTournament = gameState['is_tournament'] == true;
        final tournamentData = gameState['tournament_data'] as Map<String, dynamic>? ?? {};
        final tournamentId = tournamentData['tournament_id']?.toString();
        final matchId = tournamentData['match_id']?.toString() ?? tournamentData['match_index']?.toString();

        final rosterCompBonus = (gamePhase == 'waiting' && !isPracticeGame)
            ? _rosterCompBonus(gameState, currentRoomInfo, currentGameId)
            : 0;
        final effectiveSize = baseSize + rosterCompBonus;
        final displayJoinedSize =
            (gamePhase == 'waiting' && !isPracticeGame && rosterCompBonus > 0) ? effectiveSize : baseSize;

        if (gamePhase == 'waiting' &&
            !isPracticeGame &&
            !_rosterRetryFired &&
            !_rosterRetryScheduled &&
            _shouldScheduleTournamentRosterRetry(gameState, rosterCompBonus, baseSize, minPlayers)) {
          _rosterRetryScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Future<void>.delayed(const Duration(seconds: 3), () {
              if (!mounted) return;
              _rosterRetryFired = true;
              setState(() {});
            });
          });
        }

        // Waiting: practice always; multiplayer: owner, not random join, and effective seats >= minPlayers.
        final hasEnoughPlayersForStart =
            isPracticeGame ? baseSize >= minPlayers : effectiveSize >= minPlayers;
        final showStartButton = gamePhase == 'waiting' &&
            (isPracticeGame || (isRoomOwner && !isRandomJoin && hasEnoughPlayersForStart));
        
        if (LOGGING_SWITCH) {
          _logger.info(
            '🔍 GameInfoWidget DEBUG: currentGameId: $currentGameId, gamePhase: $gamePhase, baseSize: $baseSize, rosterCompBonus: $rosterCompBonus, effectiveSize: $effectiveSize, minPlayers: $minPlayers, isRoomOwner: $isRoomOwner, isInGame: $isInGame, isPracticeGame: $isPracticeGame, isRandomJoin: $isRandomJoin, multiplayerType: $multiplayerType, showStartButton: $showStartButton',
          );
        }
        
        // Get additional game state for context
        final isGameActive = dutchGameState['isGameActive'] ?? false;
        final isMyTurn = dutchGameState['isMyTurn'] ?? false;
        // Derive playerStatus from SSOT if needed (currently not used in GameInfoWidget)
        // For now, we'll derive it from myHand slice if needed
        final myHand = dutchGameState['myHand'] as Map<String, dynamic>? ?? {};
        final playerStatus = myHand['playerStatus']?.toString() ?? 'unknown';
        
        if (!isInGame || currentGameId.isEmpty) {
          return _buildEmptyState();
        }
        
        // Hide entire widget when match has started
        // Match has started when game phase is not 'waiting' or 'setup'
        final matchHasStarted = gamePhase != 'waiting' && gamePhase != 'setup';
        if (matchHasStarted) {
          return const SizedBox.shrink();
        }
        
        return _buildGameInfoCard(
          currentGameId: currentGameId,
          roomName: roomName,
          currentSize: displayJoinedSize,
          gamePhase: gamePhase,
          gameStatus: gameStatus,
          isRoomOwner: isRoomOwner,
          isGameActive: isGameActive,
          isMyTurn: isMyTurn,
          playerStatus: playerStatus,
          showStartButton: showStartButton,
          gameLevel: gameLevel,
          isTournament: isTournament,
          tournamentId: tournamentId,
          matchId: matchId,
        );
      },
    );
  }

  /// Build empty state when no game data is available: show spinning loader.
  Widget _buildEmptyState() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: AppPadding.smallPadding.left),
      decoration: BoxDecoration(
        color: AppColors.widgetContainerBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: AppPadding.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Game Information',
              style: AppTextStyles.headingSmall(),
            ),
            const SizedBox(height: 12),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.accentColor),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build game information card
  Widget _buildGameInfoCard({
    required String currentGameId,
    required String roomName,
    required int currentSize,
    required String gamePhase,
    required String gameStatus,
    required bool isRoomOwner,
    required bool isGameActive,
    required bool isMyTurn,
    required String playerStatus,
    required bool showStartButton,
    Object? gameLevel,
    bool isTournament = false,
    String? tournamentId,
    String? matchId,
  }) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: AppPadding.smallPadding.left),
      decoration: BoxDecoration(
        color: AppColors.widgetContainerBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: AppPadding.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              roomName,
              style: AppTextStyles.headingSmall(),
            ),
            
            const SizedBox(height: 12),
            
            // Game details - only show when not in active game (playing or out_of_turn phases)
            if (gamePhase != 'playing' && gamePhase != 'out_of_turn') ...[
              Row(
                children: [
                  Icon(Icons.tag, size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    'Game ID: $currentGameId',
                    style: AppTextStyles.bodySmall().copyWith(
                      color: AppColors.textSecondary,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),

              if (gameLevel != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.star, size: 16, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      'Level: $gameLevel',
                      style: AppTextStyles.bodySmall().copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],

              if (isTournament && (tournamentId != null || matchId != null)) ...[
                const SizedBox(height: 4),
                if (tournamentId != null)
                  Row(
                    children: [
                      Icon(Icons.emoji_events, size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        'Tournament: $tournamentId',
                        style: AppTextStyles.bodySmall().copyWith(
                          color: AppColors.textSecondary,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                if (matchId != null) ...[
                  if (tournamentId != null) const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.sports_esports, size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        'Match: $matchId',
                        style: AppTextStyles.bodySmall().copyWith(
                          color: AppColors.textSecondary,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ],
              ],
              
              const SizedBox(height: 4),
              
              Row(
                children: [
                  Icon(Icons.people, size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    'Joined: $currentSize',
                    style: AppTextStyles.bodySmall().copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
            
            const SizedBox(height: 12),
            
            
            const SizedBox(height: 16),
            
            // Start Match: practice in waiting; else room owner and not random join
            if (showStartButton)
              _buildStartMatchButton(isLoading: _isStartingMatch),
          ],
        ),
      ),
    );
  }
  
  /// Build start match button
  Widget _buildStartMatchButton({bool isLoading = false}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: isLoading ? null : _handleStartMatch,
        icon: isLoading 
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.textOnAccent),
              ),
            )
          : const Icon(Icons.play_arrow, size: 18),
        label: Text(
          isLoading ? 'Starting Match...' : 'Start Match',
          style: AppTextStyles.bodyMedium().copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: isLoading ? AppColors.disabledColor : AppColors.successColor,
          foregroundColor: AppColors.textOnAccent,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          disabledBackgroundColor: AppColors.disabledColor,
        ),
      ),
    );
  }
  
  /// Handle start match button press
  void _handleStartMatch() async {
    try {
      // Set loading state
      setState(() {
        _isStartingMatch = true;
      });
      
      if (LOGGING_SWITCH) {
        _logger.info('🎮 GameInfoWidget: ===== START MATCH BUTTON PRESSED =====');
      }
      if (LOGGING_SWITCH) {
        _logger.info('🎮 GameInfoWidget: Initiating start match flow');
      }
      
      // Get current game state to check if it's a dutch game
      final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final gameInfo = dutchGameState['gameInfo'] as Map<String, dynamic>? ?? {};
      final currentGameId = gameInfo['currentGameId']?.toString() ?? '';
      final currentGamePhase = gameInfo['gamePhase']?.toString() ?? 'unknown';
      
      if (LOGGING_SWITCH) {
        _logger.info('🎮 GameInfoWidget: Current game ID: $currentGameId');
      }
      if (LOGGING_SWITCH) {
        _logger.info('🎮 GameInfoWidget: Current game phase: $currentGamePhase');
      }
      
      // Check if this is a practice game (practice games start with 'practice_room_')
      final isPracticeGame = currentGameId.startsWith('practice_room_');
      if (LOGGING_SWITCH) {
        _logger.info('🎮 GameInfoWidget: Dutch game check - isPracticeGame: $isPracticeGame');
      }
      
      // CRITICAL: Ensure transport is practice before Start Match when we're in a practice game.
      // clearAllGameStateBeforeNewGame() resets transport to WebSocket; if something else
      // reset it (e.g. lobby init), start_match would go to backend and hang.
      if (isPracticeGame) {
        DutchGameEventEmitter.instance.setTransportMode(EventTransportMode.practice);
        if (LOGGING_SWITCH) {
          _logger.info('🎮 GameInfoWidget: Set transport to practice before start_match');
        }
      }
      
      // Use GameCoordinator for both practice and multiplayer games
      // The event emitter will route to practice bridge if transport mode is practice
      final gameCoordinator = GameCoordinator();
      
      if (isPracticeGame) {
        if (LOGGING_SWITCH) {
          _logger.info('🎮 GameInfoWidget: Practice game detected - routing to GameCoordinator (will use practice bridge)');
        }
      } else {
        if (LOGGING_SWITCH) {
          _logger.info('🎮 GameInfoWidget: Regular game detected - routing to GameCoordinator');
        }
      }
      
      if (LOGGING_SWITCH) {
        _logger.info('🎮 GameInfoWidget: Calling GameCoordinator.startMatch()');
      }
      // Timeout so we never hang indefinitely (e.g. after mode switch or backend not responding)
      const timeout = Duration(seconds: 12);
      final result = await gameCoordinator.startMatch().timeout(
        timeout,
        onTimeout: () {
          if (LOGGING_SWITCH) {
            _logger.warning('🎮 GameInfoWidget: startMatch timed out after ${timeout.inSeconds}s');
          }
          return false;
        },
      );
      if (LOGGING_SWITCH) {
        _logger.info('🎮 GameInfoWidget: GameCoordinator.startMatch() completed with result: $result');
      }
      
      if (LOGGING_SWITCH) {
        _logger.info('🎮 GameInfoWidget: ===== START MATCH FLOW COMPLETED =====');
      }
      
      // Reset loading immediately on failure; on success allow short delay for UI (gamePhase) to update
      if (!result) {
        if (mounted) {
          setState(() {
            _isStartingMatch = false;
          });
        }
      } else {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            setState(() {
              _isStartingMatch = false;
            });
          }
        });
      }
      
    } catch (e, stackTrace) {
      if (LOGGING_SWITCH) {
        _logger.error('🎮 GameInfoWidget: ❌ Error in _handleStartMatch: $e', error: e, stackTrace: stackTrace);
      }
      
      // Reset loading state on error
      if (mounted) {
        setState(() {
          _isStartingMatch = false;
        });
      }
    }
  }
  
  


}
