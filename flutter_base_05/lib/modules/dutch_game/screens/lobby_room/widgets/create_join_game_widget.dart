import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../../../core/managers/navigation_manager.dart';
import '../../../../../core/managers/hooks_manager.dart';
import '../../../../../core/managers/websockets/websocket_manager.dart';
import '../../../../dutch_game/utils/dutch_game_helpers.dart';
import '../../../../../utils/consts/theme_consts.dart';
import '../../../backend_core/utils/level_matcher.dart';

/// Unified widget for creating and joining games
class CreateJoinGameWidget extends StatefulWidget {
  /// Returns the same map as [DutchGameHelpers.createRoom] (e.g. `{ success: true }` on emit ok).
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> roomSettings) onCreateRoom;
  final VoidCallback? onJoinRoom;

  const CreateJoinGameWidget({
    Key? key,
    required this.onCreateRoom,
    this.onJoinRoom,
  }) : super(key: key);

  @override
  State<CreateJoinGameWidget> createState() => _CreateJoinGameWidgetState();
}

class _CreateJoinGameWidgetState extends State<CreateJoinGameWidget> {
  // Mode: 'create' or 'join'
  String _mode = 'create';

  // Join form state
  final _joinFormKey = GlobalKey<FormState>();
  final _roomIdController = TextEditingController();
  bool _isLoading = false;
  bool _isFinding = false;
  bool _isPrivateRoom = false;

  /// Callback for room_creation hook (Join tab commented out – creator navigates to play screen)
  void _onRoomCreation(Map<String, dynamic> data) {
    if (!mounted) return;
    // Join tab commented out: no longer switch to Join; creator goes to game-play via dutch_event_manager
    // final status = data['status']?.toString();
    // final isRandomJoin = data['is_random_join'] == true;
    // if (status == 'success' && !isRandomJoin) {
    //   setState(() => _mode = 'join');
    // }
  }

  /// Game type: 'classic' | 'clear_and_collect' (matches random join: classic = no collection, clear_and_collect = collection)
  String _selectedGameType = 'classic';

  @override
  void initState() {
    super.initState();
    _setupWebSocketListeners();
    HooksManager().registerHookWithData('room_creation', _onRoomCreation);
  }

  void _setupWebSocketListeners() {
    final wsManager = WebSocketManager.instance;
    wsManager.socket?.on('join_room_error', (data) {
      if (mounted) {
        final error = data['message'] ?? data['error'] ?? 'Unknown error';
        final errStr = error.toString().toLowerCase();
        final skipSnack = errStr.contains('insufficient coins');
        if (!skipSnack) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Join game failed: $error'),
              backgroundColor: AppColors.errorColor,
            ),
          );
        }
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    HooksManager().deregisterCallbackWithData('room_creation', _onRoomCreation);
    _roomIdController.dispose();
    final wsManager = WebSocketManager.instance;
    wsManager.socket?.off('join_room_error');
    super.dispose();
  }

  void _onRoomIdChanged(String value) {
    setState(() {
      _isPrivateRoom = false;
    });

    final dutchState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final availableGames = dutchState['availableGames'] as List<dynamic>? ?? [];

    final matchingGame = availableGames.firstWhere(
      (game) => game['roomId'] == value,
      orElse: () => null,
    );

    if (matchingGame != null) {
      setState(() {
        _isPrivateRoom = matchingGame['permission'] == 'private';
      });
    }
  }

  Future<void> _findRoom() async {
    final roomId = _roomIdController.text.trim();
    if (roomId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter a game ID to find'),
          backgroundColor: AppColors.warningColor,
        ),
      );
      return;
    }

    setState(() {
      _isFinding = true;
    });

    try {
      final result = await DutchGameHelpers.findRoom(roomId);

      if (result['success'] == true) {
        final game = result['game'];
        final message = result['message'] ?? 'Game found successfully';

        setState(() {
          _isPrivateRoom = game['permission'] == 'private';
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$message\nPhase: ${game['phase']}, Permission: ${game['permission']}'),
              backgroundColor: AppColors.successColor,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } else {
        final errorMessage = result['error'] ?? 'Failed to find game';
        // Show error message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to find game: $errorMessage'),
              backgroundColor: AppColors.errorColor,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to find game: $e'),
            backgroundColor: AppColors.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isFinding = false;
        });
      }
    }
  }

  Future<void> _joinRoom() async {
    if (!_joinFormKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Frontend coin check bypassed to test backend coin check
      // final hasEnoughCoins = await DutchGameHelpers.checkCoinsRequirement(fetchFromAPI: true);
      // if (!hasEnoughCoins) {
      //   if (mounted) {
      //     ScaffoldMessenger.of(context).showSnackBar(
      //       SnackBar(
      //         content: Text('Insufficient coins to join a game. Required: ${LevelMatcher.levelToCoinFee(null, defaultFee: 25)}'),
      //         backgroundColor: AppColors.errorColor,
      //       ),
      //     );
      //   }
      //   setState(() {
      //     _isLoading = false;
      //   });
      //   return;
      // }

      final roomId = _roomIdController.text.trim();

      // Ensure WebSocket is ready before attempting to join
      final isReady = await DutchGameHelpers.ensureWebSocketReady();
      if (!isReady) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // If already in this room (e.g. creator auto-joined), use same nav as current_games_widget / random join
      if (DutchGameHelpers.isGameStillInState(roomId)) {
        final dutchState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        final games = Map<String, dynamic>.from(dutchState['games'] as Map<String, dynamic>? ?? {});
        if (games.containsKey(roomId)) {
          DutchGameHelpers.setCurrentGameSync(roomId, games);
          NavigationManager().navigateTo('/dutch/game-play');
          _roomIdController.clear();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Opening game...'),
                backgroundColor: AppColors.successColor,
              ),
            );
          }
          return;
        }
      }

      // Not in room: join then navigate when state is ready (same pattern as random join room_creation)
      final result = await DutchGameHelpers.joinRoom(roomId: roomId);

      if (result['success'] != true) {
        final errorMessage = result['error'] ?? 'Failed to join game';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to join game: $errorMessage'),
              backgroundColor: AppColors.errorColor,
            ),
          );
        }
        return;
      }

      _roomIdController.clear();
      widget.onJoinRoom?.call();

      // Wait for game_state_updated to populate state (like room_creation delay for random join)
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      final dutchState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final games = Map<String, dynamic>.from(dutchState['games'] as Map<String, dynamic>? ?? {});
      if (games.containsKey(roomId)) {
        DutchGameHelpers.setCurrentGameSync(roomId, games);
        NavigationManager().navigateTo('/dutch/game-play');
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (mounted) {
          final retryState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
          final retryGames = Map<String, dynamic>.from(retryState['games'] as Map<String, dynamic>? ?? {});
          if (retryGames.containsKey(roomId)) {
            DutchGameHelpers.setCurrentGameSync(roomId, retryGames);
            NavigationManager().navigateTo('/dutch/game-play');
          }
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Joined. Opening game...'),
            backgroundColor: AppColors.successColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to join game: $e'),
            backgroundColor: AppColors.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showCreateRoomModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppBorderRadius.large)),
      ),
      builder: (context) => _CreateRoomModal(
        selectedGameType: _selectedGameType,
        onGameTypeChanged: (value) => setState(() => _selectedGameType = value),
        onCreateRoom: widget.onCreateRoom,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: AppPadding.smallPadding.left),
      decoration: BoxDecoration(
        color: AppColors.widgetContainerBackground,
        borderRadius: BorderRadius.circular(AppBorderRadius.large),
      ),
      child: Padding(
        padding: AppPadding.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildCreateContent(),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildModeButton(String mode, IconData icon, String label) {
    final isSelected = _mode == mode;
    return GestureDetector(
      onTap: () => setState(() => _mode = mode),
      child: Container(
        padding: AppPadding.cardPadding,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accentColor2.withValues(alpha: 0.35) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppBorderRadius.small),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: AppSizes.iconSmall,
              color: AppColors.textOnAccent,
            ),
            SizedBox(width: AppPadding.smallPadding.left),
            Text(
              label,
              style: AppTextStyles.label().copyWith(
                color: AppColors.textOnAccent,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreateContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Create New Game',
          style: AppTextStyles.headingSmall().copyWith(color: AppColors.white),
        ),
        SizedBox(height: AppPadding.mediumPadding.top),
        Text(
          'Create a match by inviting friends.',
          style: AppTextStyles.bodySmall().copyWith(color: AppColors.textSecondary),
        ),
        SizedBox(height: AppPadding.defaultPadding.top),
        Semantics(
          label: 'create_room_open_modal',
          identifier: 'create_room_open_modal',
          button: true,
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _showCreateRoomModal,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentColor,
                foregroundColor: AppColors.textOnAccent,
                padding: EdgeInsets.symmetric(vertical: AppPadding.defaultPadding.top),
              ),
              icon: Icon(Icons.add, size: AppSizes.iconSmall),
              label: Text(
                'Create',
                style: AppTextStyles.bodyMedium().copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.textOnAccent,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Kept for when Join tab is re-enabled (currently commented out)
  // ignore: unused_element
  Widget _buildJoinContent() {
    return Form(
      key: _joinFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Join Game',
            style: AppTextStyles.headingSmall().copyWith(color: AppColors.white),
          ),
          SizedBox(height: AppPadding.defaultPadding.top),

          // User's own created games (from state when Join tab is active)
          ListenableBuilder(
            listenable: StateManager(),
            builder: (context, _) {
              final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
              final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
              final currentUserId = loginState['userId']?.toString() ?? '';
              final joinedGamesSlice = dutchGameState['joinedGamesSlice'] as Map<String, dynamic>? ?? {};
              final joinedGames = joinedGamesSlice['games'] as List<dynamic>? ?? [];
              final ownCreatedGames = joinedGames
                  .cast<Map<String, dynamic>>()
                  .where((g) {
                    final ownerId = g['owner_id']?.toString() ?? '';
                    return currentUserId.isNotEmpty && ownerId.isNotEmpty && currentUserId == ownerId;
                  })
                  .toList();
              if (ownCreatedGames.isEmpty) {
                return const SizedBox.shrink();
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Your created games',
                    style: AppTextStyles.label().copyWith(
                      color: AppColors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: AppPadding.smallPadding.top),
                  ...ownCreatedGames.map((gameData) {
                    final gameId = gameData['game_id']?.toString() ?? '';
                    final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
                    final phase = gameState['phase']?.toString() ?? 'waiting';
                    final permission = gameState['permission']?.toString() ?? 'public';
                    final currentSize = gameState['playerCount'] ?? 0;
                    final maxSize = gameState['maxPlayers'] ?? 4;
                    return Padding(
                      padding: EdgeInsets.only(bottom: AppPadding.smallPadding.top),
                      child: Material(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(AppBorderRadius.small),
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _roomIdController.text = gameId;
                              _isPrivateRoom = permission == 'private';
                            });
                          },
                          borderRadius: BorderRadius.circular(AppBorderRadius.small),
                          child: Padding(
                            padding: AppPadding.cardPadding,
                            child: Row(
                              children: [
                                Icon(Icons.room, size: 20, color: AppColors.accentColor),
                                SizedBox(width: AppPadding.smallPadding.left),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        gameId,
                                        style: AppTextStyles.bodyMedium().copyWith(
                                          color: AppColors.textOnSurface,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      SizedBox(height: 2),
                                      Text(
                                        '$phase · $currentSize/$maxSize players',
                                        style: AppTextStyles.bodySmall().copyWith(
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.textSecondary),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                  SizedBox(height: AppPadding.defaultPadding.top),
                ],
              );
            },
          ),

          // Room ID Field
          Text(
            'Game ID',
            style: AppTextStyles.label().copyWith(color: AppColors.white),
          ),
          SizedBox(height: AppPadding.smallPadding.top),
          TextFormField(
            controller: _roomIdController,
            style: AppTextStyles.bodyMedium().copyWith(color: AppColors.textOnPrimary),
            decoration: InputDecoration(
              hintText: 'Enter game ID to join',
              prefixIcon: const Icon(Icons.room),
              contentPadding: EdgeInsets.symmetric(
                horizontal: AppPadding.defaultPadding.left,
                vertical: AppPadding.mediumPadding.top,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppBorderRadius.small),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppBorderRadius.small),
                borderSide: BorderSide(color: AppColors.white.withValues(alpha: 0.4)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppBorderRadius.small),
                borderSide: BorderSide(color: AppColors.borderFocused),
              ),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Game ID is required';
              }
              return null;
            },
            onChanged: _onRoomIdChanged,
            textInputAction: TextInputAction.next,
          ),
          SizedBox(height: AppPadding.defaultPadding.top),

          // Find and Join Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isFinding ? null : _findRoom,
                  icon: _isFinding
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.textOnAccent,
                          ),
                        )
                      : const Icon(Icons.search),
                  label: Text(_isFinding ? 'Finding...' : 'Find Games'),
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: AppPadding.defaultPadding.top),
                    backgroundColor: AppColors.warningColor,
                    foregroundColor: AppColors.textOnAccent,
                  ),
                ),
              ),
              SizedBox(width: AppPadding.defaultPadding.left),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _joinRoom,
                  icon: _isLoading
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.textOnAccent,
                          ),
                        )
                      : const Icon(Icons.login),
                  label: Text(_isLoading ? 'Joining...' : 'Join Game'),
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: AppPadding.defaultPadding.top),
                  ),
                ),
              ),
            ],
          ),

          // Help Text
          if (_roomIdController.text.isNotEmpty) ...[
            SizedBox(height: AppPadding.smallPadding.top),
            Text(
              _isPrivateRoom
                  ? 'This is a private game. Join with the room ID (invite link).'
                  : 'This is a public game.',
              style: AppTextStyles.bodySmall().copyWith(
                color: _isPrivateRoom ? AppColors.warningColor : AppColors.successColor,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Game type options: classic (no collection), clear_and_collect (collection mode).
const List<String> _kGameTypeValues = ['classic', 'clear_and_collect'];
const Map<String, String> _kGameTypeLabels = {
  'classic': 'Classic',
  'clear_and_collect': 'Clear and Collect',
};

class _CreateRoomModal extends StatefulWidget {
  final String selectedGameType;
  final Function(String) onGameTypeChanged;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> roomSettings) onCreateRoom;

  const _CreateRoomModal({
    required this.selectedGameType,
    required this.onGameTypeChanged,
    required this.onCreateRoom,
  });

  @override
  State<_CreateRoomModal> createState() => _CreateRoomModalState();
}

class _CreateRoomModalState extends State<_CreateRoomModal> {
  late String _selectedGameType;
  /// Room table tier (1–4) for `game_level` on create_room.
  late int _selectedTableLevel;

  bool _isSubmitting = false;
  /// After successful create: room id + echo of settings for display.
  Map<String, dynamic>? _createdSummary;

  int _currentUserLevel() {
    final stats = DutchGameHelpers.getUserDutchGameStats();
    final raw = stats?['level'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? 1;
  }

  int _firstUnlockedTableLevel() {
    final userLevel = _currentUserLevel();
    final unlocked = LevelMatcher.levelOrder.where((level) {
      final required = LevelMatcher.tableLevelToRequiredUserLevel(
        level,
        defaultLevel: level,
      );
      return userLevel >= required;
    }).toList();
    if (unlocked.isNotEmpty) return unlocked.first;
    return LevelMatcher.levelOrder.first;
  }

  @override
  void initState() {
    super.initState();
    _selectedGameType = widget.selectedGameType;
    _selectedTableLevel = _firstUnlockedTableLevel();
  }

  Future<void> _onCreateRoomPressed() async {
    if (_isSubmitting || _createdSummary != null) return;
    final roomSettings = <String, dynamic>{
      'permission': 'private',
      'gameType': _selectedGameType,
      'maxPlayers': 4,
      'minPlayers': 2,
      'autoStart': false,
      'gameLevel': _selectedTableLevel,
    };
    setState(() => _isSubmitting = true);
    try {
      final result = await widget.onCreateRoom(roomSettings);
      if (!mounted) return;
      final ok = result['success'] == true && result['error'] == null;
      if (!ok) {
        final err = result['message'] ?? result['error'] ?? 'Failed to create room';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err.toString()),
            backgroundColor: AppColors.errorColor,
          ),
        );
        setState(() => _isSubmitting = false);
        return;
      }

      String? roomId;
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (!mounted) return;
        final st = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        final cid = st['currentRoomId']?.toString();
        if (cid != null && cid.isNotEmpty) {
          roomId = cid;
          break;
        }
      }

      setState(() {
        _isSubmitting = false;
        _createdSummary = {
          'room_id': roomId ?? '',
          'gameType': roomSettings['gameType'],
          'maxPlayers': roomSettings['maxPlayers'],
          'minPlayers': roomSettings['minPlayers'],
          'gameLevel': roomSettings['gameLevel'],
          'permission': roomSettings['permission'],
        };
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create room: $e'),
            backgroundColor: AppColors.errorColor,
          ),
        );
        setState(() => _isSubmitting = false);
      }
    }
  }

  Widget _buildCreatedSummary(BuildContext context) {
    final s = _createdSummary!;
    final roomId = s['room_id']?.toString() ?? '';
    final gameType = s['gameType']?.toString() ?? 'classic';
    final gameLabel = _kGameTypeLabels[gameType] ?? gameType;
    final level = s['gameLevel'] is int ? s['gameLevel'] as int : int.tryParse('${s['gameLevel']}') ?? 1;
    final levelTitle = LevelMatcher.levelToTitle(level);
    final maxP = s['maxPlayers'] ?? 4;
    final minP = s['minPlayers'] ?? 2;
    final permission = s['permission']?.toString() ?? 'private';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Share this game ID so friends can join from the lobby.',
          style: AppTextStyles.bodySmall().copyWith(color: AppColors.textSecondary),
        ),
        SizedBox(height: AppPadding.defaultPadding.top),
        Text('Game ID', style: AppTextStyles.label().copyWith(color: AppColors.white)),
        SizedBox(height: AppPadding.smallPadding.top),
        Semantics(
          label: 'create_room_summary_room_id',
          identifier: 'create_room_summary_room_id',
          child: Container(
            width: double.infinity,
            padding: AppPadding.cardPadding,
            decoration: BoxDecoration(
              color: AppColors.primaryColor,
              borderRadius: BorderRadius.circular(AppBorderRadius.small),
              border: Border.all(color: AppColors.white.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    roomId.isEmpty ? '—' : roomId,
                    style: AppTextStyles.bodyMedium().copyWith(
                      color: AppColors.textOnPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (roomId.isNotEmpty)
                  IconButton(
                    tooltip: 'Copy game ID',
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: roomId));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Game ID copied'),
                            backgroundColor: AppColors.successColor,
                          ),
                        );
                      }
                    },
                    icon: Icon(Icons.copy, color: AppColors.textOnPrimary, size: 20),
                  ),
              ],
            ),
          ),
        ),
        if (roomId.isEmpty) ...[
          SizedBox(height: AppPadding.smallPadding.top),
          Text(
            'If the ID does not appear, close and check “Your created games” on the Join tab.',
            style: AppTextStyles.caption().copyWith(color: AppColors.warningColor),
          ),
        ],
        SizedBox(height: AppPadding.defaultPadding.top),
        _summaryRow('Game type', gameLabel),
        _summaryRow('Table', '$level — $levelTitle'),
        _summaryRow('Players', '$minP–$maxP'),
        _summaryRow('Visibility', permission == 'private' ? 'Private (invite by ID)' : permission),
        SizedBox(height: AppPadding.largePadding.top),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.white.withValues(alpha: 0.5)),
                  foregroundColor: AppColors.white,
                ),
                child: Text('Close', style: AppTextStyles.buttonText().copyWith(color: AppColors.white)),
              ),
            ),
            SizedBox(width: AppPadding.defaultPadding.left),
            Expanded(
              child: ElevatedButton(
                onPressed: roomId.isEmpty
                    ? null
                    : () {
                        Navigator.pop(context);
                        NavigationManager().navigateTo('/dutch/game-play');
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentColor,
                  foregroundColor: AppColors.textOnAccent,
                ),
                child: Text('Open table', style: AppTextStyles.buttonText()),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: AppPadding.smallPadding.top),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: AppTextStyles.bodySmall().copyWith(color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.bodyMedium().copyWith(color: AppColors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dropdownTheme = theme.copyWith(
      colorScheme: theme.colorScheme.copyWith(
        surface: AppColors.widgetContainerBackground,
        onSurface: AppColors.white,
        primary: AppColors.primaryColor,
        onPrimary: AppColors.textOnPrimary,
      ),
    );
    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          padding: AppPadding.screenPadding,
          decoration: BoxDecoration(
            color: AppColors.widgetContainerBackground,
            borderRadius: BorderRadius.vertical(top: Radius.circular(AppBorderRadius.large)),
          ),
          child: Theme(
            data: dropdownTheme,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Text(
                      _createdSummary != null ? 'Your game' : 'Create New Game',
                      style: AppTextStyles.headingSmall().copyWith(
                        color: AppColors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Semantics(
                      label: 'create_room_modal_close',
                      identifier: 'create_room_modal_close',
                      button: true,
                      child: IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.close, color: AppColors.white),
                      ),
                    ),
                  ],
                ),
                Divider(color: AppColors.white.withValues(alpha: 0.3)),

                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    child: _createdSummary != null
                        ? Padding(
                            padding: EdgeInsets.only(top: AppPadding.defaultPadding.top),
                            child: _buildCreatedSummary(context),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(height: AppPadding.defaultPadding.top),
                              Text(
                                'Game Type',
                                style: AppTextStyles.label().copyWith(color: AppColors.white),
                              ),
                              SizedBox(height: AppPadding.smallPadding.top),
                              Semantics(
                                label: 'create_room_dropdown_game_type',
                                identifier: 'create_room_dropdown_game_type',
                                child: DropdownButtonFormField<String>(
                                  value: _kGameTypeValues.contains(_selectedGameType) ? _selectedGameType : 'classic',
                                  decoration: InputDecoration(
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: AppPadding.defaultPadding.left,
                                      vertical: AppPadding.mediumPadding.top,
                                    ),
                                    border: OutlineInputBorder(
                                      borderSide: BorderSide(color: AppColors.white.withValues(alpha: 0.4)),
                                      borderRadius: BorderRadius.circular(AppBorderRadius.small),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderSide: BorderSide(color: AppColors.white.withValues(alpha: 0.4)),
                                      borderRadius: BorderRadius.circular(AppBorderRadius.small),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderSide: BorderSide(color: AppColors.borderFocused),
                                      borderRadius: BorderRadius.circular(AppBorderRadius.small),
                                    ),
                                    filled: true,
                                    fillColor: AppColors.primaryColor,
                                  ),
                                  dropdownColor: AppColors.widgetContainerBackground,
                                  style: AppTextStyles.bodyMedium().copyWith(color: AppColors.textOnPrimary),
                                  items: _kGameTypeValues.map((type) {
                                    return DropdownMenuItem<String>(
                                      value: type,
                                      child: Text(
                                        _kGameTypeLabels[type] ?? type,
                                        style: AppTextStyles.bodyMedium().copyWith(color: AppColors.white),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    final v = value ?? 'classic';
                                    setState(() => _selectedGameType = v);
                                    widget.onGameTypeChanged(v);
                                  },
                                ),
                              ),
                              SizedBox(height: AppPadding.defaultPadding.top),
                              Text(
                                'Table level',
                                style: AppTextStyles.label().copyWith(color: AppColors.white),
                              ),
                              SizedBox(height: AppPadding.smallPadding.top),
                              Semantics(
                                label: 'create_room_dropdown_table_level',
                                identifier: 'create_room_dropdown_table_level',
                                child: DropdownButtonFormField<int>(
                                  value: LevelMatcher.levelOrder.contains(_selectedTableLevel)
                                      ? _selectedTableLevel
                                      : _firstUnlockedTableLevel(),
                                  decoration: InputDecoration(
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: AppPadding.defaultPadding.left,
                                      vertical: AppPadding.mediumPadding.top,
                                    ),
                                    border: OutlineInputBorder(
                                      borderSide: BorderSide(color: AppColors.white.withValues(alpha: 0.4)),
                                      borderRadius: BorderRadius.circular(AppBorderRadius.small),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderSide: BorderSide(color: AppColors.white.withValues(alpha: 0.4)),
                                      borderRadius: BorderRadius.circular(AppBorderRadius.small),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderSide: BorderSide(color: AppColors.borderFocused),
                                      borderRadius: BorderRadius.circular(AppBorderRadius.small),
                                    ),
                                    filled: true,
                                    fillColor: AppColors.primaryColor,
                                  ),
                                  dropdownColor: AppColors.widgetContainerBackground,
                                  style: AppTextStyles.bodyMedium().copyWith(color: AppColors.textOnPrimary),
                                  items: LevelMatcher.levelOrder.map((level) {
                                    final title = LevelMatcher.levelToTitle(level);
                                    final requiredLevel = LevelMatcher.tableLevelToRequiredUserLevel(
                                      level,
                                      defaultLevel: level,
                                    );
                                    final isLocked = _currentUserLevel() < requiredLevel;
                                    return DropdownMenuItem<int>(
                                      value: level,
                                      enabled: !isLocked,
                                      child: Text(
                                        isLocked
                                            ? '$level — $title (Level $requiredLevel)'
                                            : '$level — $title',
                                        style: AppTextStyles.bodyMedium().copyWith(
                                          color: isLocked ? AppColors.textSecondary : AppColors.white,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(() => _selectedTableLevel = value);
                                    }
                                  },
                                ),
                              ),
                              SizedBox(height: AppPadding.largePadding.top),
                            ],
                          ),
                  ),
                ),

                if (_createdSummary == null)
                  Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          label: 'create_room_cancel',
                          identifier: 'create_room_cancel',
                          button: true,
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: AppColors.white.withValues(alpha: 0.5)),
                              foregroundColor: AppColors.white,
                            ),
                            child: Text('Cancel', style: AppTextStyles.buttonText().copyWith(color: AppColors.white)),
                          ),
                        ),
                      ),
                      SizedBox(width: AppPadding.defaultPadding.left),
                      Expanded(
                        child: Semantics(
                          label: 'create_room_submit',
                          identifier: 'create_room_submit',
                          button: true,
                          child: ElevatedButton(
                            onPressed: _isSubmitting ? null : () => _onCreateRoomPressed(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accentColor,
                              foregroundColor: AppColors.textOnAccent,
                            ),
                            child: _isSubmitting
                                ? SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.textOnAccent,
                                    ),
                                  )
                                : Text('Create', style: AppTextStyles.buttonText()),
                          ),
                        ),
                      ),
                    ],
                  ),
            ],
          ),
        ),
      );
      },
    );
  }
}
