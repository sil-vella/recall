import 'package:flutter/material.dart' hide Card;
import '../../00_base/screen_base.dart';
import '../models/game_state.dart';
import '../models/player.dart';
import '../models/game_events.dart';
import '../managers/recall_websocket_manager.dart';
import '../../../utils/consts/theme_consts.dart';
import '../../../core/managers/state_manager.dart';
import '../../../core/managers/app_manager.dart';
import '../recall_game_main.dart';

class GameLobbyScreen extends BaseScreen {
  const GameLobbyScreen({Key? key}) : super(key: key);

  @override
  String computeTitle(BuildContext context) => 'Recall Game Lobby';

  @override
  GameLobbyScreenState createState() => GameLobbyScreenState();
}

class GameLobbyScreenState extends BaseScreenState<GameLobbyScreen> {
  final TextEditingController _playerNameController = TextEditingController();
  final TextEditingController _gameNameController = TextEditingController();
  
  // Get Recall game managers through AppManager
  late final RecallGameCore _recallGameCore;
  late final RecallWebSocketManager _recallWebSocketManager;
  final StateManager _stateManager = StateManager();
  
  bool _isLoading = false;
  List<GameState> _availableGames = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeRecallGame();
    _loadCurrentUserData();
  }

  void _initializeRecallGame() {
    final appManager = AppManager();
    _recallGameCore = appManager.recallGameCore;
    _recallWebSocketManager = _recallGameCore.recallWebSocketManager;
    
    _initializeWebSocket().then((_) {
      _loadAvailableGames();
      _setupEventCallbacks();
    });
  }

  Future<void> _initializeWebSocket() async {
    try {
      // Check if Recall WebSocket is already connected
      if (_recallWebSocketManager.isConnected) {
        log.info("✅ Recall WebSocket already connected");
        return;
      }
      
      // Initialize Recall WebSocket if needed
      final success = await _recallWebSocketManager.initialize();
      if (success) {
        log.info("✅ Recall WebSocket connected successfully");
      } else {
        log.error("❌ Recall WebSocket connection failed");
        log.info("ℹ️ Assuming WebSocket is already connected from another screen");
      }
    } catch (e) {
      log.error("❌ Error initializing Recall WebSocket: $e");
      log.info("ℹ️ Assuming WebSocket is already connected from another screen");
    }
  }

  void _setupEventCallbacks() {
    // Listen for recall game events through RecallWebSocketManager
    _recallWebSocketManager.gameEvents.listen((event) {
      log.info("📨 Received Recall game event: ${event.type}");
      
      switch (event.type) {
        case GameEventType.gameJoined:
          _showSnackBar('Joined game successfully!');
          // TODO: Navigate to game room
          break;
        case GameEventType.gameError:
          final gameErrorEvent = event as GameErrorEvent;
          _showSnackBar('Game error: ${gameErrorEvent.error}', isError: true);
          break;
        default:
          log.info("📨 Unhandled game event: ${event.type}");
      }
    });

    // Listen for errors
    _recallWebSocketManager.errors.listen((error) {
      _showSnackBar('Error: $error', isError: true);
    });
  }

  @override
  void dispose() {
    _playerNameController.dispose();
    _gameNameController.dispose();
    super.dispose();
  }

  /// Load current user data from the system
  void _loadCurrentUserData() {
    final loginState = _stateManager.getModuleState<Map<String, dynamic>>("login");
    
    if (loginState != null) {
      final username = loginState["username"];
      
      if (username != null && username.isNotEmpty) {
        _playerNameController.text = username;
      } else {
        // Fallback to generated name if no username
        _playerNameController.text = 'Player${DateTime.now().millisecondsSinceEpoch % 1000}';
      }
    } else {
      // No login state, use generated name
      _playerNameController.text = 'Player${DateTime.now().millisecondsSinceEpoch % 1000}';
    }
  }

  Future<void> _loadAvailableGames() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Check if connected before loading games
      if (!_recallWebSocketManager.isConnected) {
        log.error("❌ Cannot load games: Recall WebSocket not connected");
        setState(() {
          _isLoading = false;
          _errorMessage = 'Cannot load games: WebSocket not connected';
        });
        return;
      }

      // Request available games from backend using RecallWebSocketManager
      log.info("🎮 Requesting available games from backend...");
      final result = await _recallWebSocketManager.sendMessage('lobby', 'recall_get_games', {
        'player_name': _playerNameController.text.trim(),
      });

      if (result['success'] == true) {
        final gamesData = result['data'] as List<dynamic>;
        final games = gamesData.map((gameData) {
          return GameState.fromJson(Map<String, dynamic>.from(gameData));
        }).toList();

        setState(() {
          _availableGames = games;
          _isLoading = false;
        });
      } else {
        // Fallback to mock data for now
        log.info("⚠️ Using mock games data");
        await Future.delayed(const Duration(seconds: 1));
        
        setState(() {
          _availableGames = [
            GameState(
              gameId: 'game_1',
              gameName: 'Quick Match',
              players: [
                Player(
                  id: 'player_1',
                  name: 'Alice',
                  type: PlayerType.human,
                  hand: [],
                  visibleCards: [],
                  score: 0,
                  status: PlayerStatus.ready,
                ),
                Player(
                  id: 'player_2',
                  name: 'AI Player',
                  type: PlayerType.computer,
                  hand: [],
                  visibleCards: [],
                  score: 0,
                  status: PlayerStatus.ready,
                ),
              ],
              currentPlayer: Player(
                id: 'player_1',
                name: 'Alice',
                type: PlayerType.human,
              ),
              phase: GamePhase.waiting,
              status: GameStatus.active,
              turnNumber: 0,
              roundNumber: 1,
              gameSettings: {'maxPlayers': 4, 'minPlayers': 2},
            ),
            GameState(
              gameId: 'game_2',
              gameName: 'Tournament Mode',
              players: [
                Player(
                  id: 'player_3',
                  name: 'Bob',
                  type: PlayerType.human,
                  hand: [],
                  visibleCards: [],
                  score: 0,
                  status: PlayerStatus.ready,
                ),
              ],
              currentPlayer: Player(
                id: 'player_3',
                name: 'Bob',
                type: PlayerType.human,
              ),
              phase: GamePhase.waiting,
              status: GameStatus.active,
              turnNumber: 0,
              roundNumber: 1,
              gameSettings: {'maxPlayers': 4, 'minPlayers': 2},
            ),
          ];
          _isLoading = false;
        });
      }
    } catch (e) {
      log.error("Error loading games: $e");
      setState(() {
        _errorMessage = 'Failed to load games: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _createGame() async {
    if (_gameNameController.text.trim().isEmpty) {
      _showSnackBar('Please enter a game name', isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Check if connected before creating game
      if (!_recallWebSocketManager.isConnected) {
        log.error("❌ Cannot create game: Recall WebSocket not connected");
        setState(() {
          _isLoading = false;
        });
        _showSnackBar('Cannot create game: WebSocket not connected', isError: true);
        return;
      }

      // Create game via RecallWebSocketManager
      log.info("🎮 Creating new game: ${_gameNameController.text.trim()}");
      final result = await _recallWebSocketManager.sendMessage('lobby', 'recall_create_game', {
        'game_name': _gameNameController.text.trim(),
        'player_name': _playerNameController.text.trim(),
        'max_players': 4,
        'min_players': 2,
      });

      log.info("🎮 Create game result: $result");

      if (result['success'] == true) {
        _showSnackBar('Game created successfully!');
        _gameNameController.clear();
        _loadAvailableGames(); // Refresh the game list
      } else {
        throw Exception(result['error'] ?? 'Failed to create game');
      }
    } catch (e) {
      log.error("Error creating game: $e");
      setState(() {
        _isLoading = false;
      });
      _showSnackBar('Failed to create game: $e', isError: true);
    }
  }

  Future<void> _joinGame(String gameId) async {
    if (_playerNameController.text.trim().isEmpty) {
      _showSnackBar('Please enter your player name', isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Check if connected before joining game
      if (!_recallWebSocketManager.isConnected) {
        log.error("❌ Cannot join game: Recall WebSocket not connected");
        setState(() {
          _isLoading = false;
        });
        _showSnackBar('Cannot join game: WebSocket not connected', isError: true);
        return;
      }

      // Join game via RecallWebSocketManager
      log.info("🎮 Joining game: $gameId");
      final result = await _recallWebSocketManager.joinGame(gameId, _playerNameController.text.trim());

      if (result['success'] == true) {
        _showSnackBar('Joined game successfully!');
        // TODO: Navigate to game room
        log.info('✅ Joined game successfully: $gameId');
      } else {
        throw Exception(result['error'] ?? 'Failed to join game');
      }
    } catch (e) {
      log.error("Error joining game: $e");
      setState(() {
        _isLoading = false;
      });
      _showSnackBar('Failed to join game: $e', isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
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
    return StreamBuilder<GameState?>(
      stream: _recallWebSocketManager.gameStateUpdates,
      builder: (context, snapshot) {
        final isConnected = _recallWebSocketManager.isConnected;
        
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Connection Status
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isConnected ? Colors.green : Colors.red,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      isConnected ? Icons.wifi : Icons.wifi_off,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isConnected ? 'Connected' : 'Disconnected',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Player Name Input
              buildContentCard(
                context,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    buildSectionTitle('Your Player Name'),
                    buildFormField(
                      label: 'Player Name',
                      controller: _playerNameController,
                      hint: 'Enter your player name',
                    ),
                  ],
                ),
              ),

              buildSpacer(),

              // Create Game Section
              buildContentCard(
                context,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    buildSectionTitle('Create New Game'),
                    buildFormField(
                      label: 'Game Name',
                      controller: _gameNameController,
                      hint: 'Enter game name',
                    ),
                    buildSpacer(),
                    BaseButton(
                      text: 'Create Game',
                      onPressed: isConnected && !_isLoading ? () => _createGame() : () {},
                      icon: Icons.add,
                      isFullWidth: true,
                    ),
                  ],
                ),
              ),

              buildSpacer(),

              // Available Games Section
              buildContentCard(
                context,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    buildSectionTitle('Available Games'),
                    if (_isLoading)
                      buildLoadingIndicator()
                    else if (_errorMessage != null)
                      buildErrorView(_errorMessage!)
                    else if (_availableGames.isEmpty)
                      buildErrorView('No games available')
                    else
                      ..._availableGames.map((game) => _buildGameCard(game)),
                  ],
                ),
              ),

              buildSpacer(),

              // Refresh Button
              BaseButton(
                text: 'Refresh Games',
                onPressed: isConnected && !_isLoading ? () => _loadAvailableGames() : () {},
                icon: Icons.refresh,
                isFullWidth: true,
                isPrimary: false,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGameCard(GameState game) {
    final playerCount = game.players.length;
    final maxPlayers = game.gameSettings['maxPlayers'] ?? 4;
    final isFull = playerCount >= maxPlayers;
    final canJoin = !isFull && game.status == GameStatus.active;

    return BaseCard(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    game.gameName,
                    style: AppTextStyles.headingSmall(),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: game.status == GameStatus.active 
                        ? AppColors.accentColor 
                        : AppColors.redAccent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    game.status.name.toUpperCase(),
                    style: AppTextStyles.buttonText.copyWith(
                      color: AppColors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            buildSpacer(height: 8),
            Row(
              children: [
                Icon(
                  Icons.people,
                  color: AppColors.accentColor,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  '$playerCount/$maxPlayers Players',
                  style: AppTextStyles.bodyMedium,
                ),
                const Spacer(),
                if (game.gameSettings['aiDifficulty'] != null)
                  Text(
                    'AI: ${game.gameSettings['aiDifficulty']}',
                    style: AppTextStyles.bodyMedium,
                  ),
              ],
            ),
            buildSpacer(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Players: ${game.players.map((p) => p.name).join(', ')}',
                    style: AppTextStyles.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (canJoin)
                  BaseButton(
                    text: 'Join',
                    onPressed: () => _joinGame(game.gameId),
                    isPrimary: true,
                  )
                else
                  Text(
                    isFull ? 'Full' : 'In Progress',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.lightGray,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
} 