import 'package:flutter/material.dart';

import '../../../../core/00_base/screen_base.dart';
import '../lobby_room/widgets/connection_status_widget.dart';
import '../../../../core/managers/websockets/websocket_manager.dart';
import '../../../../core/managers/state_manager.dart';

class GamePlayScreen extends BaseScreen {
  const GamePlayScreen({Key? key}) : super(key: key);

  @override
  String computeTitle(BuildContext context) => 'Recall Game';

  @override
  GamePlayScreenState createState() => GamePlayScreenState();
}

class GamePlayScreenState extends BaseScreenState<GamePlayScreen> {
  final WebSocketManager _websocketManager = WebSocketManager.instance;

  @override
  void initState() {
    super.initState();
    
    _initializeWebSocket().then((_) {
      _setupEventCallbacks();
      _initializeGameState();
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
      } else {
        _showSnackBar('WebSocket already connected!');
      }
    } catch (e) {
      _showSnackBar('WebSocket initialization error: $e', isError: true);
    }
  }
  
  @override
  void dispose() {
    // Clean up any game-specific resources
    super.dispose();
  }

  void _initializeGameState() {
    // Initialize game-specific state
    // This will be expanded as we add more game functionality
  }

  void _setupEventCallbacks() {
    // Event callbacks are handled by WSEventManager
    // No need to set up specific callbacks here
    // The WSEventManager handles all WebSocket events automatically
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

  @override
  Widget buildContent(BuildContext context) {
    // Screen doesn't read state directly - widgets handle their own subscriptions
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Connection Status
          const ConnectionStatusWidget(),
          const SizedBox(height: 20),
          
          // Game Information Widget
          const GameInfoWidget(),
          const SizedBox(height: 20),
          
          // Game content will be added here in future iterations
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Text(
                'Game Play Screen - Coming Soon',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Widget to display current game information
class GameInfoWidget extends StatelessWidget {
  const GameInfoWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
        
        final currentGameId = recallGameState['currentGameId']?.toString() ?? '';
        final currentGameData = recallGameState['currentGameData'] as Map<String, dynamic>? ?? {};
        final isInGame = recallGameState['isInGame'] == true;
        final gameStartedAt = recallGameState['gameStartedAt']?.toString() ?? '';
        
        if (!isInGame || currentGameId.isEmpty) {
          return Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info, color: Colors.orange),
                      const SizedBox(width: 8),
                      const Text(
                        'Game Information',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No active game found',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        
        // Extract game state information
        final gameState = currentGameData['game_state'] as Map<String, dynamic>? ?? {};
        final roomName = gameState['gameName']?.toString() ?? 'Game $currentGameId';
        final currentSize = gameState['playerCount'] ?? 0;
        final maxSize = gameState['maxPlayers'] ?? 4;
        final gamePhase = gameState['phase']?.toString() ?? 'waiting';
        final gameStatus = gameState['status']?.toString() ?? 'inactive';
        
        return Card(
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.games, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        roomName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    _buildStatusChip(gamePhase, gameStatus),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                // Game details
                Row(
                  children: [
                    Icon(Icons.tag, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      'Game ID: $currentGameId',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 4),
                
                Row(
                  children: [
                    Icon(Icons.people, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      'Players: $currentSize/$maxSize',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                
                if (gameStartedAt.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        'Started: ${_formatTimestamp(gameStartedAt)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
  
  /// Build status chip based on game phase and status
  Widget _buildStatusChip(String gamePhase, String gameStatus) {
    Color chipColor;
    String chipText;
    IconData chipIcon;

    switch (gamePhase) {
      case 'waiting':
        chipColor = Colors.orange;
        chipText = 'Waiting';
        chipIcon = Icons.schedule;
        break;
      case 'playing':
        chipColor = Colors.green;
        chipText = 'Playing';
        chipIcon = Icons.play_arrow;
        break;
      case 'finished':
        chipColor = Colors.grey;
        chipText = 'Finished';
        chipIcon = Icons.stop;
        break;
      default:
        chipColor = Colors.grey;
        chipText = 'Unknown';
        chipIcon = Icons.help;
    }

    return Chip(
      avatar: Icon(chipIcon, size: 16, color: Colors.white),
      label: Text(
        chipText,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      backgroundColor: chipColor,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
  
  /// Format timestamp for display
  String _formatTimestamp(String timestamp) {
    try {
      final dateTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(dateTime);
      
      if (difference.inMinutes < 1) {
        return 'Just now';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours}h ago';
      } else {
        return '${difference.inDays}d ago';
      }
    } catch (e) {
      return 'Unknown';
    }
  }
}


