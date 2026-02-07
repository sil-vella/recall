import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
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

  // Create modal state
  final TextEditingController _createPasswordController = TextEditingController();
  String _selectedPermission = 'public';
  String _selectedGameType = 'classic';
  int _turnTimeLimit = 30;
  bool _autoStart = true;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _setupWebSocketListeners();
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
    _roomIdController.dispose();
    _passwordController.dispose();
    _createPasswordController.dispose();
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Unable to connect to game server'),
              backgroundColor: AppColors.errorColor,
            ),
          );
        }
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final joinData = <String, dynamic>{
        'room_id': roomId,
      };

      if (password.isNotEmpty) {
        joinData['password'] = password;
      }

      // Use joinRoom helper which will ensure WebSocket is ready
      final result = await DutchGameHelpers.joinRoom(roomId: roomId);
      
      if (result['success'] == true) {
      _roomIdController.clear();
      _passwordController.clear();

      widget.onJoinRoom?.call();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Join game request sent successfully'),
            backgroundColor: AppColors.successColor,
          ),
        );
        }
      } else {
        final errorMessage = result['error'] ?? 'Failed to join game';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to join game: $errorMessage'),
              backgroundColor: AppColors.errorColor,
            ),
          );
        }
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

    final roomSettings = {
      'permission': _selectedPermission,
      'gameType': _selectedGameType,
      'maxPlayers': 4,
      'minPlayers': 4,
      'turnTimeLimit': _turnTimeLimit,
      'autoStart': _autoStart,
      'password': _createPasswordController.text.trim(),
    };

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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _CreateRoomModal(
        selectedPermission: _selectedPermission,
        selectedGameType: _selectedGameType,
        turnTimeLimit: _turnTimeLimit,
        autoStart: _autoStart,
        passwordController: _createPasswordController,
        onPermissionChanged: (value) => setState(() => _selectedPermission = value),
        onGameTypeChanged: (value) => setState(() => _selectedGameType = value),
        onTurnTimeLimitChanged: (value) => setState(() => _turnTimeLimit = value),
        onAutoStartChanged: (value) => setState(() => _autoStart = value),
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
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: AppPadding.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          // Mode Toggle
          Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
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
        padding: EdgeInsets.symmetric(vertical: AppPadding.smallPadding.top),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? AppColors.textOnAccent : AppColors.textSecondary,
            ),
            SizedBox(width: AppPadding.smallPadding.left),
            Text(
              label,
              style: AppTextStyles.bodyMedium().copyWith(
                color: isSelected ? AppColors.textOnAccent : AppColors.textSecondary,
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
          style: AppTextStyles.headingSmall(),
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
            style: AppTextStyles.headingSmall(),
          ),
          SizedBox(height: AppPadding.defaultPadding.top),

          // Room ID Field
          TextFormField(
            controller: _roomIdController,
            decoration: InputDecoration(
              labelText: 'Game ID',
              hintText: 'Enter game ID to join',
              prefixIcon: const Icon(Icons.room),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
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
            TextFormField(
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: 'Password',
                hintText: 'Enter game password',
                prefixIcon: const Icon(Icons.lock),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
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

class _CreateRoomModal extends StatelessWidget {
  final String selectedPermission;
  final String selectedGameType;
  final int turnTimeLimit;
  final bool autoStart;
  final TextEditingController passwordController;
  final Function(String) onPermissionChanged;
  final Function(String) onGameTypeChanged;
  final Function(int) onTurnTimeLimitChanged;
  final Function(bool) onAutoStartChanged;
  final VoidCallback onCreateRoom;
  final bool isCreating;

  const _CreateRoomModal({
    required this.selectedPermission,
    required this.selectedGameType,
    required this.turnTimeLimit,
    required this.autoStart,
    required this.passwordController,
    required this.onPermissionChanged,
    required this.onGameTypeChanged,
    required this.onTurnTimeLimitChanged,
    required this.onAutoStartChanged,
    required this.onCreateRoom,
    required this.isCreating,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          padding: AppPadding.screenPadding,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Text(
                    'Create New Game',
                    style: AppTextStyles.headingSmall().copyWith(
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
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ],
              ),
              const Divider(),

              // Scrollable content
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: AppPadding.defaultPadding.top),

                      // Game Type
                      Semantics(
                        label: 'create_room_dropdown_game_type',
                        identifier: 'create_room_dropdown_game_type',
                        child: DropdownButtonFormField<String>(
                          value: selectedGameType,
                          decoration: const InputDecoration(
                            labelText: 'Game Type',
                            border: OutlineInputBorder(),
                          ),
                          items: ['classic', 'tournament', 'practice'].map((type) {
                            return DropdownMenuItem(
                              value: type,
                              child: Text(type.toUpperCase()),
                            );
                          }).toList(),
                          onChanged: (value) => onGameTypeChanged(value ?? 'classic'),
                        ),
                      ),

                      SizedBox(height: AppPadding.defaultPadding.top),

                      // Permission Level
                      Semantics(
                        label: 'create_room_dropdown_permission',
                        identifier: 'create_room_dropdown_permission',
                        child: DropdownButtonFormField<String>(
                          value: selectedPermission,
                          decoration: const InputDecoration(
                            labelText: 'Permission Level',
                            border: OutlineInputBorder(),
                            helperText: 'Public: Anyone can join | Private: Password required',
                          ),
                          items: ['public', 'private'].map((permission) {
                            return DropdownMenuItem(
                              value: permission,
                              child: Text(permission.toUpperCase()),
                            );
                          }).toList(),
                          onChanged: (value) => onPermissionChanged(value ?? 'public'),
                        ),
                      ),

                      SizedBox(height: AppPadding.defaultPadding.top),

                      // Password (for private rooms)
                      if (selectedPermission != 'public') ...[
                        Semantics(
                          label: 'create_room_field_password',
                          identifier: 'create_room_field_password',
                          textField: true,
                          child: TextField(
                            controller: passwordController,
                            decoration: const InputDecoration(
                              labelText: 'Room Password',
                              border: OutlineInputBorder(),
                              hintText: 'Optional password for private room',
                            ),
                            obscureText: true,
                          ),
                        ),
                        SizedBox(height: AppPadding.defaultPadding.top),
                      ],

                      // Game Settings
                      Text(
                        'Game Settings',
                        style: AppTextStyles.bodyMedium().copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: AppPadding.smallPadding.top),

                      // Turn Time Limit
                      Row(
                        children: [
                          Text('Turn Time Limit: ', style: AppTextStyles.bodyMedium()),
                          Expanded(
                            child: Semantics(
                              label: 'create_room_slider_turn_time',
                              identifier: 'create_room_slider_turn_time',
                              child: Slider(
                                value: turnTimeLimit.toDouble(),
                                min: 15,
                                max: 120,
                                divisions: 7,
                                label: '${turnTimeLimit}s',
                                onChanged: (value) => onTurnTimeLimitChanged(value.round()),
                              ),
                            ),
                          ),
                          Text('${turnTimeLimit}s', style: AppTextStyles.bodyMedium()),
                        ],
                      ),

                      // Auto Start Toggle
                      Semantics(
                        label: 'create_room_switch_auto_start',
                        identifier: 'create_room_switch_auto_start',
                        child: SwitchListTile(
                          title: const Text('Auto-start when full'),
                          subtitle: const Text('Start game automatically when max players join'),
                          value: autoStart,
                          onChanged: onAutoStartChanged,
                        ),
                      ),

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
                        child: const Text('Cancel'),
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
                        onPressed: isCreating ? null : onCreateRoom,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accentColor,
                          foregroundColor: AppColors.textOnAccent,
                        ),
                        child: isCreating
                            ? SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.textOnAccent,
                                ),
                              )
                            : const Text('Create Game'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
