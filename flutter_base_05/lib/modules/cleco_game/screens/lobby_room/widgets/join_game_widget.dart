import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../../../core/managers/websockets/websocket_manager.dart';
import '../../../../cleco_game/utils/cleco_game_helpers.dart';
import '../../../managers/validated_event_emitter.dart';

class JoinRoomWidget extends StatefulWidget {
  final VoidCallback? onJoinRoom;

  const JoinRoomWidget({
    Key? key,
    this.onJoinRoom,
  }) : super(key: key);

  @override
  State<JoinRoomWidget> createState() => _JoinRoomWidgetState();
}

class _JoinRoomWidgetState extends State<JoinRoomWidget> {
  final _formKey = GlobalKey<FormState>();
  final _roomIdController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isFinding = false;
  bool _isPrivateRoom = false;

  @override
  void initState() {
    super.initState();
    _setupWebSocketListeners();
  }

  void _setupWebSocketListeners() {
    // Listen for join room errors from backend
    final wsManager = WebSocketManager.instance;
    wsManager.socket?.on('join_room_error', (data) {
      if (mounted) {
        final error = data['error'] ?? 'Unknown error';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Join game failed: $error'),
            backgroundColor: Colors.red,
          ),
        );
        // Reset loading state
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
    // Remove WebSocket listeners
    final wsManager = WebSocketManager.instance;
    wsManager.socket?.off('join_room_error');
    super.dispose();
  }

  void _onRoomIdChanged(String value) {
    // Reset private room state when room ID changes
    setState(() {
      _isPrivateRoom = false;
    });
    
    // Check if this is a private room by looking at available games
    final clecoState = StateManager().getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
    final availableGames = clecoState['availableGames'] as List<dynamic>? ?? [];
    
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
        const SnackBar(
          content: Text('Please enter a game ID to find'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isFinding = true;
    });

    try {
      // Import the helper method
      final result = await ClecoGameHelpers.findRoom(roomId);
      
      if (result['success'] == true) {
        final game = result['game'];
        final message = result['message'] ?? 'Game found successfully';
        
        // Update the private room state based on found game
        setState(() {
          _isPrivateRoom = game['permission'] == 'private';
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$message\nPhase: ${game['phase']}, Permission: ${game['permission']}'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } else {
        final errorMessage = result['error'] ?? 'Failed to find game';
        throw Exception(errorMessage);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to find game: $e'),
            backgroundColor: Colors.red,
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
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final roomId = _roomIdController.text.trim();
      final password = _passwordController.text.trim();

      // Validate private room password if required (frontend validation)
      if (_isPrivateRoom && password.isEmpty) {
        throw Exception('Password is required for private games');
      }

      // Get WebSocket manager to check connection
      final wsManager = WebSocketManager.instance;
      if (!wsManager.isConnected) {
        throw Exception('Not connected to server');
      }

      // Prepare join data
      final joinData = <String, dynamic>{
        'room_id': roomId,
      };

      // Add password if provided
      if (password.isNotEmpty) {
        joinData['password'] = password;
      }

      // Use validated event emitter for consistent validation and user ID injection
      final eventEmitter = ClecoGameEventEmitter.instance;
      await eventEmitter.emit(
        eventType: 'join_room',
        data: joinData,
      );

      // Clear form
      _roomIdController.clear();
      _passwordController.clear();

      // Call callback if provided
      widget.onJoinRoom?.call();

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Join game request sent successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to join game: $e'),
            backgroundColor: Colors.red,
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

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.login,
                    color: Theme.of(context).primaryColor,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Join Game',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Room ID Field
              TextFormField(
                controller: _roomIdController,
                decoration: const InputDecoration(
                  labelText: 'Game ID',
                  border: OutlineInputBorder(),
                  hintText: 'Enter game ID to join',
                  prefixIcon: Icon(Icons.room),
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
              const SizedBox(height: 16),
              
              // Password Field (shown only for private rooms)
              if (_isPrivateRoom) ...[
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                    hintText: 'Enter game password',
                    prefixIcon: Icon(Icons.lock),
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
                const SizedBox(height: 16),
              ],
              
              // Find and Join Buttons (Side by Side)
              Row(
                children: [
                  // Find Room Button (50% width)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isFinding ? null : _findRoom,
                      icon: _isFinding
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.search),
                      label: Text(_isFinding ? 'Finding...' : 'Find Games'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Join Room Button (50% width)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _joinRoom,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login),
                      label: Text(_isLoading ? 'Joining...' : 'Join Game'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
              
              // Help Text
              const SizedBox(height: 12),
              Text(
                _isPrivateRoom
                    ? 'This is a private game. Password required.'
                    : 'This is a public game. No password needed.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _isPrivateRoom ? Colors.orange : Colors.green,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
