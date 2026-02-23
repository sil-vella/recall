import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../../../core/managers/navigation_manager.dart';
import '../../../../../core/managers/hooks_manager.dart';
import '../../../../../core/managers/websockets/websocket_manager.dart';
import '../../../../dutch_game/utils/dutch_game_helpers.dart';
import '../../../../../utils/consts/theme_consts.dart';

/// Unified widget for creating and joining games
class CreateJoinGameWidget extends StatefulWidget {
  final Function(Map<String, dynamic>) onCreateRoom;
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
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isFinding = false;
  bool _isPrivateRoom = false;

  /// Callback for room_creation hook; switch to Join tab on successful create (not random join)
  void _onRoomCreation(Map<String, dynamic> data) {
    if (!mounted) return;
    final status = data['status']?.toString();
    final isRandomJoin = data['is_random_join'] == true;
    if (status == 'success' && !isRandomJoin) {
      setState(() => _mode = 'join');
    }
  }

  // Create modal state
  final TextEditingController _createPasswordController = TextEditingController();
  final TextEditingController _tournamentNameController = TextEditingController();
  String _selectedPermission = 'public';
  String _selectedGameType = 'classic';
  String _tournamentFormat = 'F1';
  int _turnTimeLimit = 30;
  bool _isCreating = false;

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
        final error = data['error'] ?? 'Unknown error';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Join game failed: $error'),
            backgroundColor: AppColors.errorColor,
          ),
        );
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
    _passwordController.dispose();
    _createPasswordController.dispose();
    _tournamentNameController.dispose();
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
      final hasEnoughCoins = await DutchGameHelpers.checkCoinsRequirement(fetchFromAPI: true);
      if (!hasEnoughCoins) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Insufficient coins to join a game. Required: 25'),
              backgroundColor: AppColors.errorColor,
            ),
          );
        }
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final roomId = _roomIdController.text.trim();
      final password = _passwordController.text.trim();

      if (_isPrivateRoom && password.isEmpty) {
        throw Exception('Password is required for private games');
      }

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
          _passwordController.clear();
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
      _passwordController.clear();
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

  void _createRoom() {
    setState(() {
      _isCreating = true;
    });

    // Private: password required, min 4 characters
    if (_selectedPermission == 'private') {
      final password = _createPasswordController.text.trim();
      if (password.isEmpty) {
        setState(() => _isCreating = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Password is required for private rooms'),
              backgroundColor: AppColors.errorColor,
            ),
          );
        }
        return;
      }
      if (password.length < 4) {
        setState(() => _isCreating = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Password must be at least 4 characters'),
              backgroundColor: AppColors.errorColor,
            ),
          );
        }
        return;
      }
    }

    // Tournament: name required
    if (_selectedGameType == 'tournament') {
      final name = _tournamentNameController.text.trim();
      if (name.isEmpty) {
        setState(() => _isCreating = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Tournament name is required'),
              backgroundColor: AppColors.errorColor,
            ),
          );
        }
        return;
      }
    }

    final roomSettings = {
      'permission': _selectedPermission,
      'gameType': _selectedGameType,
      'maxPlayers': 4,
      'minPlayers': 4,
      'turnTimeLimit': _turnTimeLimit,
      'autoStart': false, // Classic and tournament: no auto-start
      'password': _createPasswordController.text.trim(),
    };
    if (_selectedGameType == 'tournament') {
      roomSettings['tournamentName'] = _tournamentNameController.text.trim();
      roomSettings['tournamentFormat'] = _tournamentFormat;
    }

    widget.onCreateRoom(roomSettings);

    setState(() {
      _isCreating = false;
    });
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Game created successfully!'),
          backgroundColor: AppColors.successColor,
        ),
      );
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
        selectedPermission: _selectedPermission,
        selectedGameType: _selectedGameType,
        passwordController: _createPasswordController,
        tournamentNameController: _tournamentNameController,
        tournamentFormat: _tournamentFormat,
        onPermissionChanged: (value) => setState(() => _selectedPermission = value),
        onGameTypeChanged: (value) => setState(() => _selectedGameType = value),
        onTournamentFormatChanged: (value) => setState(() => _tournamentFormat = value),
        onCreateRoom: _createRoom,
        isCreating: _isCreating,
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
          // Mode Toggle (aligned with lobby section headers: accent bar + textOnAccent)
          Container(
            decoration: BoxDecoration(
              color: AppColors.accentColor,
              borderRadius: BorderRadius.circular(AppBorderRadius.large),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildModeButton('create', Icons.add, 'Create'),
                ),
                Expanded(
                  child: _buildModeButton('join', Icons.login, 'Join'),
                ),
              ],
            ),
          ),
          SizedBox(height: AppPadding.defaultPadding.top),

          // Content based on mode
          if (_mode == 'create')
            _buildCreateContent()
          else
            _buildJoinContent(),
          ],
        ),
      ),
    );
  }

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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Create New Game',
          style: AppTextStyles.headingSmall().copyWith(color: AppColors.white),
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
              icon: const Icon(Icons.add),
              label: const Text('Create New Room'),
            ),
          ),
        ),
      ],
    );
  }

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

          // Password Field (shown only for private rooms)
          if (_isPrivateRoom) ...[
            Text(
              'Password',
              style: AppTextStyles.label().copyWith(color: AppColors.white),
            ),
            SizedBox(height: AppPadding.smallPadding.top),
            TextFormField(
              controller: _passwordController,
              style: AppTextStyles.bodyMedium().copyWith(color: AppColors.textOnPrimary),
              decoration: InputDecoration(
                hintText: 'Enter game password',
                prefixIcon: const Icon(Icons.lock),
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
              obscureText: true,
              validator: (value) {
                if (_isPrivateRoom && (value == null || value.trim().isEmpty)) {
                  return 'Password is required for private games';
                }
                return null;
              },
              textInputAction: TextInputAction.done,
            ),
            SizedBox(height: AppPadding.defaultPadding.top),
          ],

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
                  ? 'This is a private game. Password required.'
                  : 'This is a public game. No password needed.',
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

class _CreateRoomModal extends StatefulWidget {
  final String selectedPermission;
  final String selectedGameType;
  final TextEditingController passwordController;
  final TextEditingController tournamentNameController;
  final String tournamentFormat;
  final Function(String) onPermissionChanged;
  final Function(String) onGameTypeChanged;
  final Function(String) onTournamentFormatChanged;
  final VoidCallback onCreateRoom;
  final bool isCreating;

  const _CreateRoomModal({
    required this.selectedPermission,
    required this.selectedGameType,
    required this.passwordController,
    required this.tournamentNameController,
    required this.tournamentFormat,
    required this.onPermissionChanged,
    required this.onGameTypeChanged,
    required this.onTournamentFormatChanged,
    required this.onCreateRoom,
    required this.isCreating,
  });

  @override
  State<_CreateRoomModal> createState() => _CreateRoomModalState();
}

class _CreateRoomModalState extends State<_CreateRoomModal> {
  late String _selectedPermission;
  late String _selectedGameType;
  late String _tournamentFormat;

  @override
  void initState() {
    super.initState();
    _selectedPermission = widget.selectedPermission;
    _selectedGameType = widget.selectedGameType;
    _tournamentFormat = widget.tournamentFormat;
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
                      'Create New Game',
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

                // Scrollable content — labels above fields to avoid clipping
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: AppPadding.defaultPadding.top),

                      // Game Type
                      Text(
                        'Game Type',
                        style: AppTextStyles.label().copyWith(color: AppColors.white),
                      ),
                      SizedBox(height: AppPadding.smallPadding.top),
                      Semantics(
                        label: 'create_room_dropdown_game_type',
                        identifier: 'create_room_dropdown_game_type',
                        child: DropdownButtonFormField<String>(
                          value: _selectedGameType,
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
                          items: ['classic', 'tournament'].map((type) {
                            return DropdownMenuItem<String>(
                              value: type,
                              child: Text(
                                type.toUpperCase(),
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

                      // Permission Level
                      Text(
                        'Permission Level',
                        style: AppTextStyles.label().copyWith(color: AppColors.white),
                      ),
                      SizedBox(height: AppPadding.smallPadding.top),
                      Semantics(
                        label: 'create_room_dropdown_permission',
                        identifier: 'create_room_dropdown_permission',
                        child: DropdownButtonFormField<String>(
                          value: _selectedPermission,
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
                            helperText: 'Public: Anyone can join | Private: Password required',
                            helperStyle: AppTextStyles.caption().copyWith(color: AppColors.white),
                            filled: true,
                            fillColor: AppColors.primaryColor,
                          ),
                          dropdownColor: AppColors.widgetContainerBackground,
                          style: AppTextStyles.bodyMedium().copyWith(color: AppColors.textOnPrimary),
                          items: ['public', 'private'].map((permission) {
                            return DropdownMenuItem<String>(
                              value: permission,
                              child: Text(
                                permission.toUpperCase(),
                                style: AppTextStyles.bodyMedium().copyWith(color: AppColors.white),
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            final v = value ?? 'public';
                            setState(() => _selectedPermission = v);
                            widget.onPermissionChanged(v);
                          },
                        ),
                      ),

                      SizedBox(height: AppPadding.defaultPadding.top),

                      // Password (for private rooms) — required, min 4 characters
                      if (_selectedPermission == 'private') ...[
                        Text(
                          'Room Password',
                          style: AppTextStyles.label().copyWith(color: AppColors.white),
                        ),
                        SizedBox(height: AppPadding.smallPadding.top),
                        Semantics(
                          label: 'create_room_field_password',
                          identifier: 'create_room_field_password',
                          textField: true,
                          child: TextField(
                            controller: widget.passwordController,
                            style: AppTextStyles.bodyMedium().copyWith(color: AppColors.textOnPrimary),
                            decoration: InputDecoration(
                              hintText: 'Required, min 4 characters',
                              hintStyle: AppTextStyles.caption().copyWith(color: AppColors.textOnPrimary),
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
                            obscureText: true,
                          ),
                        ),
                        SizedBox(height: AppPadding.defaultPadding.top),
                      ],

                      // Tournament fields (when game type is tournament)
                      if (_selectedGameType == 'tournament') ...[
                        Text(
                          'Tournament Name',
                          style: AppTextStyles.label().copyWith(color: AppColors.white),
                        ),
                        SizedBox(height: AppPadding.smallPadding.top),
                        Semantics(
                          label: 'create_room_field_tournament_name',
                          identifier: 'create_room_field_tournament_name',
                          textField: true,
                          child: TextField(
                            controller: widget.tournamentNameController,
                            style: AppTextStyles.bodyMedium().copyWith(color: AppColors.textOnPrimary),
                            decoration: InputDecoration(
                              hintText: 'Enter tournament name',
                              hintStyle: AppTextStyles.caption().copyWith(color: AppColors.textOnPrimary),
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
                          ),
                        ),
                        SizedBox(height: AppPadding.defaultPadding.top),
                        Text(
                          'Tournament Format',
                          style: AppTextStyles.label().copyWith(color: AppColors.white),
                        ),
                        SizedBox(height: AppPadding.smallPadding.top),
                        Semantics(
                          label: 'create_room_dropdown_tournament_format',
                          identifier: 'create_room_dropdown_tournament_format',
                          child: DropdownButtonFormField<String>(
                            value: _tournamentFormat,
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
                            items: ['F1', 'F2', 'F3'].map((format) {
                              return DropdownMenuItem<String>(
                                value: format,
                                child: Text(
                                  format,
                                  style: AppTextStyles.bodyMedium().copyWith(color: AppColors.white),
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              final v = value ?? 'F1';
                              setState(() => _tournamentFormat = v);
                              widget.onTournamentFormatChanged(v);
                            },
                          ),
                        ),
                        SizedBox(height: AppPadding.defaultPadding.top),
                      ],

                      // Game Settings (auto start hidden for tournaments; tournaments default to false)
                      if (_selectedGameType != 'tournament') ...[
                      ],

                      SizedBox(height: AppPadding.largePadding.top),
                    ],
                  ),
                ),
              ),

              // Action Buttons
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
                        onPressed: widget.isCreating ? null : widget.onCreateRoom,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accentColor,
                          foregroundColor: AppColors.textOnAccent,
                        ),
                        child: widget.isCreating
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
