import 'package:flutter/material.dart';
import 'dart:async';
import '../../../../../core/managers/state_manager.dart';
import '../../../../../utils/consts/theme_consts.dart';

/// Unified Game Phase Chip Widget
/// 
/// This widget handles its own state subscription and provides a consistent
/// game phase chip display across the Dutch game.
/// 
/// Features:
/// - Self-contained state management using ListenableBuilder
/// - Consistent styling and behavior across all usage contexts
/// - Support for all game phases defined in the backend
/// - Reusable across different widgets (game_info, available_games, etc.)
/// 
/// Usage:
/// ```dart
/// GamePhaseChip(
///   gameId: 'game_123', // Required: ID of the game to show phase for
///   size: GamePhaseChipSize.medium, // Optional: small, medium, large
/// )
/// ```
class GamePhaseChip extends StatefulWidget {
  final String gameId;
  final GamePhaseChipSize size;
  final String? customPhase; // Optional: override phase from state

  const GamePhaseChip({
    Key? key,
    required this.gameId,
    this.size = GamePhaseChipSize.medium,
    this.customPhase,
  }) : super(key: key);

  @override
  State<GamePhaseChip> createState() => _GamePhaseChipState();
}

class _GamePhaseChipState extends State<GamePhaseChip> {
  Timer? _debounceTimer;
  String _displayedPhase = 'waiting';

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        // Get the game phase from state
        String currentPhase = widget.customPhase ?? _getGamePhaseFromState();
        
        // Debounce phase updates to prevent showing intermediate phases
        _debouncePhaseUpdate(currentPhase);
        
        return _buildPhaseChip(_displayedPhase);
      },
    );
  }

  /// Debounce phase updates to prevent showing intermediate phases during rapid updates
  void _debouncePhaseUpdate(String newPhase) {
    if (_displayedPhase != newPhase) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 100), () {
        if (mounted) {
          setState(() {
            _displayedPhase = newPhase;
          });
        }
      });
    }
  }

  /// Get game phase from the global state (SSOT first, fallback to legacy field)
  String _getGamePhaseFromState() {
    final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final games = dutchGameState['games'] as Map<String, dynamic>? ?? {};
    final gameInfo = dutchGameState['gameInfo'] as Map<String, dynamic>? ?? {};
    final currentGameId = gameInfo['currentGameId']?.toString() ?? '';
    
    // 1. Prefer the SSOT games map for any game (practice + multiplayer)
    final ssotPhase = _getPhaseFromGamesMap(games, widget.gameId);
    if (ssotPhase != null) {
      return ssotPhase;
    }
    
    // 2. Fallback to SSOT using current gameId (in case widget.gameId == 'current')
    if (widget.gameId == currentGameId) {
      final currentGamePhase = _getPhaseFromGamesMap(games, currentGameId);
      if (currentGamePhase != null) {
        return currentGamePhase;
      }
      
      // 3. Legacy fallback: main state gamePhase (kept for backward compatibility)
      final legacyPhase = dutchGameState['gamePhase']?.toString();
      return _normalizePhase(legacyPhase);
    }
    
    return 'waiting';
  }
  
  /// Extract phase for a given game from the SSOT games map
  String? _getPhaseFromGamesMap(Map<String, dynamic> games, String gameId) {
    if (gameId.isEmpty || !games.containsKey(gameId)) {
      return null;
    }
    
    final gameEntry = games[gameId] as Map<String, dynamic>? ?? {};
    final gameData = gameEntry['gameData'] as Map<String, dynamic>? ?? {};
    final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
    final rawPhase = gameState['phase']?.toString();
    
    if (rawPhase == null) {
      return null;
    }
    
    return _normalizePhase(rawPhase);
  }
  
  /// Normalize backend phases to UI values, falling back to defaults when needed
  String _normalizePhase(String? rawPhase, {String fallback = 'waiting'}) {
    if (rawPhase == null || rawPhase.isEmpty) {
      return fallback;
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

  /// Build the phase chip with appropriate styling
  Widget _buildPhaseChip(String phase) {
    final phaseData = _getPhaseData(phase);
    
    return Container(
      padding: _getPadding(),
      decoration: BoxDecoration(
        color: phaseData.color,
        borderRadius: BorderRadius.circular(_getBorderRadius()),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            phaseData.icon,
            size: _getIconSize(),
            color: AppColors.textOnAccent,
          ),
          SizedBox(width: _getSpacing()),
          Text(
            phaseData.text,
            style: AppTextStyles.bodySmall().copyWith(
              color: AppColors.textOnAccent,
              fontSize: _getFontSize(),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// Get phase data (color, text, icon) for a given phase
  _PhaseData _getPhaseData(String phase) {
    switch (phase) {
      // Backend phase values (direct from GamePhase enum)
      case 'waiting_for_players':
        return _PhaseData(
          color: Colors.orange,
          text: 'Waiting',
          icon: Icons.schedule,
        );
      case 'dealing_cards':
        return _PhaseData(
          color: Colors.blue,
          text: 'Setup',
          icon: Icons.settings,
        );
      case 'player_turn':
        return _PhaseData(
          color: Colors.green,
          text: 'Playing',
          icon: Icons.play_arrow,
        );
      case 'same_rank_window':
        return _PhaseData(
          color: Colors.purple,
          text: 'Same Rank',
          icon: Icons.flash_on,
        );
      case 'special_play_window':
        return _PhaseData(
          color: Colors.amber,
          text: 'Special Play',
          icon: Icons.star,
        );
      case 'queen_peek_window':
        return _PhaseData(
          color: Colors.pink,
          text: 'Queen Peek',
          icon: Icons.visibility,
        );
      case 'turn_pending_events':
        return _PhaseData(
          color: Colors.indigo,
          text: 'Pending Events',
          icon: Icons.pending_actions,
        );
      case 'ending_round':
        return _PhaseData(
          color: Colors.teal,
          text: 'Ending Round',
          icon: Icons.stop,
        );
      case 'ending_turn':
        return _PhaseData(
          color: Colors.cyan,
          text: 'Ending Turn',
          icon: Icons.stop_circle,
        );
      case 'dutch_called':
        return _PhaseData(
          color: Colors.red,
          text: 'Dutch Called',
          icon: Icons.warning,
        );
      case 'game_ended':
        return _PhaseData(
          color: Colors.grey,
          text: 'Game Ended',
          icon: Icons.check_circle,
        );
      
      // Legacy mapped values (for backward compatibility)
      case 'waiting':
        return _PhaseData(
          color: Colors.orange,
          text: 'Waiting',
          icon: Icons.schedule,
        );
      case 'setup':
        return _PhaseData(
          color: Colors.blue,
          text: 'Setup',
          icon: Icons.settings,
        );
      case 'playing':
        return _PhaseData(
          color: Colors.green,
          text: 'Playing',
          icon: Icons.play_arrow,
        );
      case 'out_of_turn':
        return _PhaseData(
          color: Colors.blue,
          text: 'Out of Turn',
          icon: Icons.flash_on,
        );
      case 'initial_peek':
        return _PhaseData(
          color: Colors.teal,
          text: 'Initial Peek',
          icon: Icons.visibility_outlined,
        );
      default:
        return _PhaseData(
          color: Colors.grey,
          text: 'Unknown',
          icon: Icons.help,
        );
    }
  }

  /// Get padding based on size
  EdgeInsets _getPadding() {
    switch (widget.size) {
      case GamePhaseChipSize.small:
        return const EdgeInsets.symmetric(horizontal: 6, vertical: 2);
      case GamePhaseChipSize.medium:
        return const EdgeInsets.symmetric(horizontal: 8, vertical: 4);
      case GamePhaseChipSize.large:
        return const EdgeInsets.symmetric(horizontal: 12, vertical: 6);
    }
  }

  /// Get border radius based on size
  double _getBorderRadius() {
    switch (widget.size) {
      case GamePhaseChipSize.small:
        return 10;
      case GamePhaseChipSize.medium:
        return 12;
      case GamePhaseChipSize.large:
        return 14;
    }
  }

  /// Get icon size based on size
  double _getIconSize() {
    switch (widget.size) {
      case GamePhaseChipSize.small:
        return 12;
      case GamePhaseChipSize.medium:
        return 14;
      case GamePhaseChipSize.large:
        return 16;
    }
  }

  /// Get spacing between icon and text based on size
  double _getSpacing() {
    switch (widget.size) {
      case GamePhaseChipSize.small:
        return 4;
      case GamePhaseChipSize.medium:
        return 6;
      case GamePhaseChipSize.large:
        return 8;
    }
  }

  /// Get font size based on size
  double _getFontSize() {
    switch (widget.size) {
      case GamePhaseChipSize.small:
        return 10;
      case GamePhaseChipSize.medium:
        return 12;
      case GamePhaseChipSize.large:
        return 14;
    }
  }
}

/// Size options for the GamePhaseChip
enum GamePhaseChipSize {
  small,
  medium,
  large,
}

/// Internal data class for phase information
class _PhaseData {
  final Color color;
  final String text;
  final IconData icon;

  _PhaseData({
    required this.color,
    required this.text,
    required this.icon,
  });
}
