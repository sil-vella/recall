import 'package:flutter/material.dart';
import '../../../../core/managers/state_manager.dart';
import '../../../../core/managers/websockets/websocket_manager.dart';
import '../../../../core/managers/websockets/ws_event_manager.dart';
import '../../../../tools/logging/logger.dart';
import 'widgets/create_game_widget.dart';
import 'widgets/join_game_widget.dart';
import 'widgets/current_games_widget.dart';
import '../../utils/recall_game_helpers.dart';

/// ## LobbyScreen
/// 
/// The main lobby screen for the Recall card game, providing functionality to:
/// - Create new games with customizable settings
/// - Join existing games by ID
/// - View and manage currently joined games
/// - Monitor WebSocket connection status
/// 
/// ### Features:
/// - **Game Creation**: Create new games with player limits, permissions, and settings
/// - **Game Joining**: Join existing games by entering game ID and password
/// - **Game Management**: View all joined games with real-time updates
/// - **Connection Status**: Monitor WebSocket connection and reconnect if needed
/// - **State-Driven UI**: All widgets automatically update based on state changes
/// 
/// ### State Management:
/// - Subscribes to `recall_game` state for game information
/// - Subscribes to `websocket` state for connection status
/// - Uses `ListenableBuilder` for automatic UI updates
/// 
/// ### Event Flow:
/// - Game creation emits `create_room` WebSocket event
/// - Game joining emits `join_room` WebSocket event
/// - Game leaving uses `WSEventManager.leaveRoom()`
/// - All events update state automatically via backend hooks

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({Key? key}) : super(key: key);

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  final Logger _log = Logger();

  @override
  void initState() {
    super.initState();
    _log.info('🎮 [LobbyScreen] Initializing lobby screen');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recall Game Lobby'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          // Connection status indicator
          _buildConnectionStatus(),
        ],
      ),
      body: _buildContent(context),
    );
  }

  Widget _buildConnectionStatus() {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final websocketState = StateManager().getModuleState<Map<String, dynamic>>('websocket') ?? {};
        final isConnected = websocketState['isConnected'] ?? false;

        return Container(
          margin: const EdgeInsets.only(right: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isConnected ? Icons.wifi : Icons.wifi_off,
                color: isConnected ? Colors.green : Colors.red,
                size: 20,
              ),
              const SizedBox(width: 4),
              Text(
                isConnected ? 'Connected' : 'Disconnected',
                style: TextStyle(
                  color: isConnected ? Colors.green : Colors.red,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContent(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Welcome message
              _buildWelcomeMessage(),
              const SizedBox(height: 24),

              // Create and Join buttons side by side
              Row(
                children: [
                  Expanded(
                    child: CreateGameWidget(onCreateGame: _createGame),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: JoinGameWidget(onJoinGame: _joinGame),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Current games below the buttons
              CurrentGamesWidget(onJoinGame: _joinGame),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWelcomeMessage() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.emoji_events, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
                Text(
                  'Welcome to Recall!',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Create a new game or join an existing one to start playing the classic card game.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Handle game creation
  void _createGame(Map<String, dynamic> gameData) async {
    try {
      _log.info('🎮 [LobbyScreen] Creating game with data: $gameData');

      // Get WebSocket manager
      final wsManager = WebSocketManager.instance;
      
      if (wsManager.socket != null) {
        // Emit create room event
        wsManager.socket?.emit('create_room', gameData);
        
        _log.info('🎮 [LobbyScreen] Create room event emitted successfully');
        
        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Game creation request sent!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('WebSocket not connected');
      }

    } catch (e) {
      _log.error('❌ [LobbyScreen] Error creating game: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating game: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Handle game joining
  void _joinGame(String gameId) async {
    try {
      _log.info('🎮 [LobbyScreen] Joining game: $gameId');

      // Get WebSocket manager
      final wsManager = WebSocketManager.instance;
      
      if (wsManager.socket != null) {
        // Emit join room event
        wsManager.socket?.emit('join_room', {'room_id': gameId});
        
        _log.info('🎮 [LobbyScreen] Join room event emitted successfully');
        
        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Join request sent!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('WebSocket not connected');
      }

    } catch (e) {
      _log.error('❌ [LobbyScreen] Error joining game: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error joining game: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
} 