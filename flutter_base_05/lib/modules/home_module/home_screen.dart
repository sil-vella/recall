import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/00_base/screen_base.dart';
import '../../core/managers/app_manager.dart';
import '../../core/managers/navigation_manager.dart';
import '../../core/managers/websockets/websocket_manager.dart';
import '../../utils/consts/theme_consts.dart';

class HomeScreen extends BaseScreen {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  BaseScreenState<HomeScreen> createState() => _HomeScreenState();

  @override
  String computeTitle(BuildContext context) => 'Home';
}

class _HomeScreenState extends BaseScreenState<HomeScreen> {
  final WebSocketManager _websocketManager = WebSocketManager.instance;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    // Trigger home screen main hook
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appManager = Provider.of<AppManager>(context, listen: false);
      appManager.triggerHomeScreenMainHook(context);
      
      // Update connection status for UI display
      _updateConnectionStatus();
    });
  }

  void _updateConnectionStatus() {
    setState(() {
      _isConnected = _websocketManager.isConnected;
    });
  }

  // Note: Global app bar features are now handled automatically by GlobalAppBarManager
  // Individual screen features can still be added here if needed

  @override
  void dispose() {
    // Clean up app bar features when screen is disposed
    clearAppBarActions();
    super.dispose();
  }

  @override
  Widget buildContent(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Welcome text with app title
          const Text(
            'Welcome to Cleco',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Check out the new app bar action buttons!',
            style: AppTextStyles.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          // Connection status indicator
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primaryColor.withOpacity(0.8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isConnected ? Colors.green : Colors.red,
                width: 2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isConnected ? Icons.wifi : Icons.wifi_off,
                  color: _isConnected ? Colors.green : Colors.red,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  _isConnected ? 'WebSocket Connected' : 'WebSocket Disconnected',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: _isConnected ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Connect/Disconnect button for testing
          ElevatedButton(
            onPressed: () async {
              if (_isConnected) {
                // Disconnect
                _websocketManager.disconnect();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Disconnected from WebSocket'),
                    backgroundColor: Colors.orange,
                  ),
                );
              } else {
                // Connect
                final success = await _websocketManager.connect();
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Connected to WebSocket'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Failed to connect to WebSocket'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _isConnected ? Colors.red : Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_isConnected ? Icons.link_off : Icons.link),
                const SizedBox(width: 8),
                Text(_isConnected ? 'Disconnect' : 'Connect'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Profile navigation button for testing
          ElevatedButton.icon(
            onPressed: () {
              final navigationManager = Provider.of<NavigationManager>(context, listen: false);
              navigationManager.navigateTo('/account');
            },
            icon: const Icon(Icons.account_circle),
            label: const Text('Go to Account'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
} 