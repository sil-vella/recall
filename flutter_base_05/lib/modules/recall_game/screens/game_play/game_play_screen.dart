import 'package:flutter/material.dart';

import '../../../../core/00_base/screen_base.dart';
import 'widgets/game_info_widget.dart';
import 'widgets/opponents_panel_widget.dart';
import 'widgets/draw_pile_widget.dart';
import 'widgets/discard_pile_widget.dart';
import 'widgets/my_hand_widget.dart';
import 'widgets/card_peek_widget.dart';
import '../../../../core/managers/websockets/websocket_manager.dart';

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
    return Stack(
      children: [
        // Main game content
        SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              
              // Game Information Widget
              const GameInfoWidget(),
              const SizedBox(height: 20),
              
              // Opponents Panel Section
              const OpponentsPanelWidget(),
              const SizedBox(height: 20),
              
              // Game Board Section
              Card(
                margin: const EdgeInsets.only(bottom: 20),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.casino, color: Colors.green),
                          const SizedBox(width: 8),
                          const Text(
                            'Game Board',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // Game board content in a row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Draw Pile Widget
                          const DrawPileWidget(),
                          
                          // Discard Pile Widget
                          const DiscardPileWidget(),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              
              // My Hand Section
              const MyHandWidget(),
            ],
          ),
        ),
        
        // Card Peek Modal Widget - handles its own state subscription
        const CardPeekWidget(),
      ],
    );
  }
}


