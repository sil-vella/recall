import 'package:flutter/material.dart';

import '../../../../core/00_base/screen_base.dart';
import '../../../../core/managers/websockets/websocket_manager.dart';
import '../../../../core/managers/navigation_manager.dart';
import '../../../../tools/logging/logger.dart';
import '../../game_logic/practice_match/practice_game.dart';
import 'widgets/rules_modal_widget.dart';

const bool LOGGING_SWITCH = true;

class PracticeScreen extends BaseScreen {
  const PracticeScreen({Key? key}) : super(key: key);

  @override
  String computeTitle(BuildContext context) => 'Recall Room';

  @override
  _PracticeScreenState createState() => _PracticeScreenState();
}

class _PracticeScreenState extends BaseScreenState<PracticeScreen> {
  final WebSocketManager _websocketManager = WebSocketManager.instance;
  late final PracticeGameCoordinator _recallCoordinator;
  
  // Form controllers and values
  final _formKey = GlobalKey<FormState>();
  int _numberOfOpponents = 3;
  String _difficultyLevel = 'easy';
  int? _turnTimer; // null means "Off", seconds for timer values
  bool _instructionsEnabled = true; // Default to enabled for new players
  
  // Available options
  final List<int> _opponentOptions = [3, 4, 5, 6];
  final List<String> _difficultyOptions = ['easy', 'mid', 'hard'];
  final List<int?> _timerOptions = [null, 15, 30, 60, 120, 300]; // null = "Off", then 15s to 5min

  @override
  void initState() {
    super.initState();
    
    // Initialize recall coordinator (singleton - will return same instance if already created)
    _recallCoordinator = PracticeGameCoordinator();
    
    _initializeWebSocket().then((_) {
      _setupEventCallbacks();
    });
  }

  Future<void> _initializeWebSocket() async {
    try {
      // Initialize WebSocket manager if not already initialized
      if (!_websocketManager.isInitialized) {
        final initialized = await _websocketManager.initialize();
        if (!initialized) {
          _showSnackBar('Failed to initialize WebSocket', isError: true);
          return;
        }
      }
      
      // Connect to WebSocket if not already connected
      if (!_websocketManager.isConnected) {
        final connected = await _websocketManager.connect();
        if (!connected) {
          _showSnackBar('Failed to connect to WebSocket', isError: true);
          return;
        }
        _showSnackBar('WebSocket connected successfully!');
        return;
      } else {
        _showSnackBar('WebSocket already connected!');
      }
    } catch (e) {
      _showSnackBar('WebSocket initialization error: $e', isError: true);
    }
  }
  
  @override
  void dispose() {
    // Don't dispose recall coordinator when navigating to game play
    // The recall game should continue in the game play screen
    // The coordinator will be disposed when the recall game actually ends
    // or when the app is closed (it's now a singleton)
    
    // Clean up event callbacks - now handled by WSEventManager
    super.dispose();
  }

  void _setupEventCallbacks() {
    // Event callbacks are now handled by WSEventManager
    // No need to set up specific callbacks here
    // The WSEventManager handles all WebSocket events automatically
  }

  Future<void> _startPracticeGame() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    try {
      // Show loading message
      _showSnackBar('Starting recall game...', isError: false);
      
      // Create recall session data
      final sessionId = 'practice_${DateTime.now().millisecondsSinceEpoch}';
      final practiceData = {
        'sessionId': sessionId,
        'numberOfOpponents': _numberOfOpponents,
        'difficultyLevel': _difficultyLevel,
        'turnTimer': _turnTimer, // null means "Off"
        'instructionsEnabled': _instructionsEnabled,
        'gameMode': 'practice',
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      // Use recall coordinator to handle start match
      final success = await _recallCoordinator.handlePracticeEvent(
        sessionId, 
        'start_match', 
        practiceData
      );
      
      if (success) {
        _showSnackBar('Recall game started successfully!', isError: false);

        // Navigate to game play screen
        _navigateToGamePlay();
      } else {
        _showSnackBar('Failed to start recall game', isError: true);
      }
      
    } catch (e) {
      if (mounted) _showSnackBar('Failed to start recall game: $e', isError: true);
    }
  }

  /// Navigate to game play screen for recall game
  void _navigateToGamePlay() {
    try {
      Logger().info('Recall: Starting navigation to game play screen', isOn: LOGGING_SWITCH);
      
      // Check if recall game is active
      if (_recallCoordinator.isPracticeGameActive) {
        Logger().info('Recall: Recall game is active, proceeding with navigation', isOn: LOGGING_SWITCH);
        Logger().info('Recall: Current recall game ID: ${_recallCoordinator.currentPracticeGameId}', isOn: LOGGING_SWITCH);
      } else {
        Logger().warning('Recall: No active recall game found', isOn: LOGGING_SWITCH);
      }
      
      // Use NavigationManager to navigate to game play screen
      NavigationManager().navigateTo('/recall/game-play');
      
      Logger().info('Recall: Navigation command sent to NavigationManager', isOn: LOGGING_SWITCH);
    } catch (e) {
      Logger().error('Recall: Failed to navigate to game play: $e', isOn: LOGGING_SWITCH);
      if (mounted) {
        _showSnackBar('Failed to navigate to game: $e', isError: true);
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    // Check if the widget is still mounted before accessing context
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }
  
  /// Show the rules modal
  void _showRulesModal() {
    RulesModalWidget.show(context);
  }

  String _formatTimer(int? seconds) {
    if (seconds == null || seconds == 0) {
      return 'Off';
    }
    if (seconds < 60) {
      return '${seconds}s';
    } else {
      final minutes = seconds ~/ 60;
      final remainingSeconds = seconds % 60;
      return remainingSeconds > 0 ? '${minutes}m ${remainingSeconds}s' : '${minutes}m';
    }
  }

  @override
  Widget buildContent(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Text(
              'Recall Game Settings',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Configure your recall game settings and start playing against AI opponents.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
            const SizedBox(height: 24),
            
            // Number of Opponents
            Text(
              'Number of Opponents',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              value: _numberOfOpponents,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                hintText: 'Select number of opponents',
              ),
              items: _opponentOptions.map((int value) {
                return DropdownMenuItem<int>(
                  value: value,
                  child: Text('$value opponents'),
                );
              }).toList(),
              onChanged: (int? newValue) {
                if (newValue != null) {
                  setState(() {
                    _numberOfOpponents = newValue;
                  });
                }
              },
              validator: (value) {
                if (value == null) {
                  return 'Please select number of opponents';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            
            // Difficulty Level
            Text(
              'Difficulty Level',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _difficultyLevel,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                hintText: 'Select difficulty level',
              ),
              items: _difficultyOptions.map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value.toUpperCase()),
                );
              }).toList(),
              onChanged: (String? newValue) {
                if (newValue != null) {
                  setState(() {
                    _difficultyLevel = newValue;
                  });
                }
              },
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please select difficulty level';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            
            // Turn Timer
            Text(
              'Turn Timer',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int?>(
              value: _turnTimer,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                hintText: 'Select turn timer',
                enabled: !_instructionsEnabled, // Disable when instructions are enabled
              ),
              items: _timerOptions.map((int? value) {
                return DropdownMenuItem<int?>(
                  value: value,
                  child: Text(value == null ? 'Off' : _formatTimer(value)),
                );
              }).toList(),
              onChanged: _instructionsEnabled ? null : (int? newValue) {
                setState(() {
                  _turnTimer = newValue;
                });
              },
              validator: (value) {
                // Timer is optional now, no validation needed
                return null;
              },
            ),
            if (_instructionsEnabled) ...[
              const SizedBox(height: 8),
              Text(
                'Timer is disabled when instructions are enabled',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).textTheme.bodySmall?.color,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 24),
            
            // Instructions Enabled
            Text(
              'Game Instructions',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Switch(
                  value: _instructionsEnabled,
                  onChanged: (bool value) {
                    setState(() {
                      _instructionsEnabled = value;
                      // When instructions are enabled, set timer to "Off"
                      if (value) {
                        _turnTimer = null;
                      }
                    });
                  },
                  activeColor: Theme.of(context).primaryColor,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _instructionsEnabled 
                      ? 'Instructions will be shown during gameplay to help you learn the game'
                      : 'No instructions will be shown - for experienced players',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // View Rules Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _showRulesModal,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).primaryColor,
                  side: BorderSide(color: Theme.of(context).primaryColor),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.rule, size: 20),
                label: const Text('View Rules'),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Start Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _startPracticeGame,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.play_arrow,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Start Recall Game',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // Recall Events Debug Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.list_alt,
                          color: Theme.of(context).primaryColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Available Recall Events',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Registered Events: ${_recallCoordinator.getEventCount()}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: _recallCoordinator.getRegisteredEvents().map((event) {
                        return Chip(
                          label: Text(
                            event,
                            style: const TextStyle(fontSize: 12),
                          ),
                          backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                          labelStyle: TextStyle(
                            color: Theme.of(context).primaryColor,
                            fontWeight: FontWeight.w500,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Game Info Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Theme.of(context).primaryColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Game Summary',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow('Total Players', '${_numberOfOpponents + 1}'),
                    _buildInfoRow('Difficulty', _difficultyLevel.toUpperCase()),
                    _buildInfoRow('Turn Timer', _formatTimer(_turnTimer)),
                    _buildInfoRow('Game Type', 'Recall (AI Opponents)'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
} 