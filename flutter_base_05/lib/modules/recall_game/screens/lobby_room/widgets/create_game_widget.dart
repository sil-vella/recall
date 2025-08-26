/// ## CreateGameWidget
/// 
/// A widget that allows users to create new games with customizable settings.
/// 
/// ### Features:
/// - **Game Settings**: Configure player limits, permissions, and game options
/// - **Real-time Validation**: Instant feedback on input validation
/// - **Permission Selection**: Choose between public and private games
/// - **Password Protection**: Optional password for private games
/// - **Auto-Start Option**: Configure whether games start automatically
/// 
/// ### Usage:
/// ```dart
/// CreateGameWidget(
///   onCreateGame: (gameData) {
///     // Handle game creation
///   },
/// )
/// ```
/// 
/// ### Event Emissions:
/// - Emits `create_room` WebSocket event (backend handles room/game creation)
/// - Backend automatically creates both room and game instances
/// - Frontend receives `create_room_success` and `room_joined` events
/// 
/// ### State Updates:
/// - Updates `recall_game` state with new game information
/// - Triggers UI refresh via `ListenableBuilder`
/// 
/// ### Integration:
/// - Uses `WSEventManager` for WebSocket communication
/// - Integrates with `StateManager` for state updates
/// - Follows core WebSocket event patterns

import 'package:flutter/material.dart';
import '../../../../../core/managers/websockets/ws_event_manager.dart';
import '../../../../../tools/logging/logger.dart';

class CreateGameWidget extends StatelessWidget {
  final Function(Map<String, dynamic>) onCreateGame;
  static final Logger _log = Logger();

  const CreateGameWidget({
    Key? key,
    required this.onCreateGame,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.add_circle, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
                Text(
                  'Create New Game',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildGameSettingsForm(context),
          ],
        ),
      ),
    );
  }

  Widget _buildGameSettingsForm(BuildContext context) {
    return _CreateGameForm(onCreateGame: onCreateGame);
  }
}

class _CreateGameForm extends StatefulWidget {
  final Function(Map<String, dynamic>) onCreateGame;

  const _CreateGameForm({required this.onCreateGame});

  @override
  State<_CreateGameForm> createState() => _CreateGameFormState();
}

class _CreateGameFormState extends State<_CreateGameForm> {
  final _formKey = GlobalKey<FormState>();
  final _gameNameController = TextEditingController();
  final _maxPlayersController = TextEditingController(text: '6');
  final _minPlayersController = TextEditingController(text: '2');
  final _passwordController = TextEditingController();
  final _turnTimeLimitController = TextEditingController(text: '30');
  
  String _permission = 'public';
  bool _autoStart = true;
  bool _isLoading = false;
  final Logger _log = Logger();

  @override
  void dispose() {
    _gameNameController.dispose();
    _maxPlayersController.dispose();
    _minPlayersController.dispose();
    _passwordController.dispose();
    _turnTimeLimitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Game Name
          TextFormField(
            controller: _gameNameController,
            decoration: const InputDecoration(
              labelText: 'Game Name (Optional)',
              hintText: 'Enter a name for your game',
              prefixIcon: Icon(Icons.games),
            ),
            validator: (value) {
              if (value != null && value.length > 50) {
                return 'Game name must be less than 50 characters';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Player Limits
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _minPlayersController,
                  decoration: const InputDecoration(
                    labelText: 'Min Players',
                    prefixIcon: Icon(Icons.people),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    final min = int.tryParse(value ?? '');
                    if (min == null || min < 2 || min > 10) {
                      return 'Min players: 2-10';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextFormField(
                  controller: _maxPlayersController,
                  decoration: const InputDecoration(
                    labelText: 'Max Players',
                    prefixIcon: Icon(Icons.people_outline),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    final max = int.tryParse(value ?? '');
                    if (max == null || max < 2 || max > 10) {
                      return 'Max players: 2-10';
                    }
                    return null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Permission Selection
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Game Privacy',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  RadioListTile<String>(
                    title: const Text('Public Game'),
                    subtitle: const Text('Anyone can join'),
                    value: 'public',
                    groupValue: _permission,
                    onChanged: (value) {
                      setState(() {
                        _permission = value!;
                        if (_permission == 'public') {
                          _passwordController.clear();
                        }
                      });
                    },
                  ),
                  RadioListTile<String>(
                    title: const Text('Private Game'),
                    subtitle: const Text('Password required to join'),
                    value: 'private',
                    groupValue: _permission,
                    onChanged: (value) {
                      setState(() {
                        _permission = value!;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Password Field (for private games)
          if (_permission == 'private') ...[
            TextFormField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'Game Password',
                hintText: 'Enter password for private game',
                prefixIcon: Icon(Icons.lock),
              ),
              obscureText: true,
              validator: (value) {
                if (_permission == 'private' && (value == null || value.isEmpty)) {
                  return 'Password required for private games';
                }
                if (value != null && value.length < 3) {
                  return 'Password must be at least 3 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
          ],

          // Game Options
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Game Options',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _turnTimeLimitController,
                          decoration: const InputDecoration(
                            labelText: 'Turn Time Limit (seconds)',
                            prefixIcon: Icon(Icons.timer),
                          ),
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            final limit = int.tryParse(value ?? '');
                            if (limit == null || limit < 10 || limit > 300) {
                              return 'Time limit: 10-300 seconds';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('Auto-Start Game'),
                    subtitle: const Text('Start automatically when minimum players join'),
                    value: _autoStart,
                    onChanged: (value) {
                      setState(() {
                        _autoStart = value;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Create Game Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _createGame,
              icon: _isLoading 
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add),
              label: Text(_isLoading ? 'Creating Game...' : 'Create Game'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _createGame() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final gameData = {
        'game_name': _gameNameController.text.trim(),
        'max_players': int.parse(_maxPlayersController.text),
        'min_players': int.parse(_minPlayersController.text),
        'permission': _permission,
        'password': _permission == 'private' ? _passwordController.text : null,
        'turn_time_limit': int.parse(_turnTimeLimitController.text),
        'auto_start': _autoStart,
        'game_type': 'classic',
      };

      // Remove null values
      gameData.removeWhere((key, value) => value == null);

      _log.info('🎮 [CreateGameWidget] Creating game with data: $gameData');

      // Call the callback to handle game creation
      widget.onCreateGame(gameData);

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Game creation request sent!'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Reset form
      _formKey.currentState!.reset();
      _gameNameController.clear();
      _passwordController.clear();
      setState(() {
        _permission = 'public';
        _autoStart = true;
      });

    } catch (e) {
      _log.error('❌ [CreateGameWidget] Error creating game: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating game: $e'),
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
} 