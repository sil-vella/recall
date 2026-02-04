# App Bar Action Feature Slot System

This document explains the comprehensive app bar action feature slot system in Flutter Base 05, including the new state-aware feature widgets and core architecture.

## Overview

The app bar action feature slot system provides a flexible, state-aware way to dynamically add, remove, and manage action buttons in the app bar (right side) of any screen that extends `BaseScreen`. The system integrates with the existing `FeatureRegistryManager` and uses state-aware widgets that automatically update when their underlying state changes.

## Architecture

### Core Components

1. **FeatureRegistryManager** (`lib/modules/dutch_game/managers/feature_registry_manager.dart`)
   - Central registry for all features across the app
   - Manages feature registration, unregistration, and scope clearing
   - Provides change notifications via streams

2. **FeatureSlot** (`lib/core/widgets/feature_slot.dart`)
   - Core rendering widget for features
   - Listens to registry changes and rebuilds automatically
   - Supports both local and global scopes
   - Renders features in priority order

3. **State-Aware Feature Widgets** (`lib/core/widgets/state_aware_features/`)
   - Individual widgets that subscribe to state changes
   - Use `ListenableBuilder` with `StateManager()` for reactive updates
   - Follow the same pattern as other widgets in the app

4. **BaseScreen Integration** (`lib/core/00_base/screen_base.dart`)
   - Automatically registers global features for all screens
   - Provides helper methods for screen-specific features
   - Manages feature lifecycle automatically

### Directory Structure

```
lib/
├── core/
│   ├── widgets/
│   │   ├── feature_slot.dart                    # Core feature rendering widget
│   │   └── state_aware_features/
│   │       ├── index.dart                       # Exports all state-aware features
│   │       ├── coins_display_feature.dart       # User coins display widget
│   │       ├── connection_status_feature.dart   # WebSocket connection status widget
│   │       ├── game_phase_chip_feature.dart     # Game phase chip widget (optional, screen-specific)
│   │       ├── profile_feature.dart             # User profile widget (available but not registered globally)
│   │       └── state_aware_feature_registry.dart # Registration helper
│   └── 00_base/
│       └── screen_base.dart                     # BaseScreen with feature integration
└── modules/
    └── dutch_game/
        └── managers/
            ├── feature_registry_manager.dart     # Feature registry
            └── feature_contracts.dart            # Feature descriptors
```

## State-Aware Feature System

### How State-Aware Features Work

State-aware features use the same state subscription pattern as other widgets in the app:

```dart
class StateAwareConnectionStatusFeature extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        // Get WebSocket state from StateManager
        final websocketState = StateManager().getModuleState<Map<String, dynamic>>('websocket');
        final isConnected = websocketState?['isConnected'] ?? false;
        
        // Build the feature based on current state
        return IconButton(
          icon: Icon(
            isConnected ? Icons.wifi : Icons.wifi_off,
            color: isConnected ? Colors.green : Colors.red,
          ),
          onPressed: () {
            // Handle tap
          },
          tooltip: isConnected ? 'Connected' : 'Disconnected',
        );
      },
    );
  }
}
```

### State Subscription Pattern

All state-aware features follow this pattern:

1. **ListenableBuilder**: Wraps the widget to listen for state changes
2. **StateManager()**: Accesses the centralized state management
3. **getModuleState()**: Retrieves specific state slices
4. **Reactive Updates**: Widget automatically rebuilds when state changes

### Available State Slices

- **`websocket`**: WebSocket connection status and events
- **`login`**: User authentication and profile information
- **`game`**: Game state and player information
- **`settings`**: App settings and preferences

## Global App Bar Features

### Automatic Global Features

The `BaseScreen` class automatically adds state-aware global features to **all screens** that extend it:

- **💰 Coins Display** (Priority: 50) - Shows user's coin count from game state
- **🔌 Connection Status Icon** (Priority: 100) - Shows real-time WebSocket connection status

### Global Feature Registration

Global features are registered automatically in `BaseScreen.initState()`:

```dart
void _registerGlobalAppBarFeatures() {
  log.info('🌐 Registering state-aware global app bar features for screen: ${widget.runtimeType}');
  
  // Register state-aware features using the new system
  StateAwareFeatureRegistry.registerGlobalAppBarFeatures(context);
  
  log.info('✅ Global app bar features registered for screen: ${widget.runtimeType}');
}
```

### State-Aware Feature Details

#### Coins Display
- **Widget**: `StateAwareCoinsDisplayFeature`
- **State**: Subscribes to `dutch_game` state slice, specifically `userStats.coins`
- **Updates**: Automatically updates when coin count changes
- **Display**: Chip widget with monetization icon and coin count
- **Visibility**: Hidden if `userStats` is null (user not logged in or stats not loaded)
- **Priority**: 50 (appears first, leftmost)

#### Connection Status Icon
- **Widget**: `StateAwareConnectionStatusFeature`
- **State**: Subscribes to `websocket` state slice
- **Updates**: Automatically updates when WebSocket connection changes
- **Icon**: WiFi icon (green when connected, red when disconnected), sync icon when connecting
- **Action**: Toggle WebSocket connection (tap to connect/disconnect)
- **Priority**: 100 (appears last, rightmost)

### Available But Unregistered Features

The following state-aware features are available but not automatically registered globally. They can be registered on a per-screen basis if needed:

#### Game Phase Chip
- **Widget**: `StateAwareGamePhaseChipFeature`
- **State**: Subscribes to `dutch_game` state slice, specifically `gameInfo.currentGameId`
- **Updates**: Automatically updates when game phase changes
- **Display**: Game phase chip showing current game phase
- **Usage**: Can be registered in screen-specific scope (e.g., `GamePlayScreen`)
- **Note**: Previously registered globally but removed for cleaner app bar

#### Profile Icon
- **Widget**: `StateAwareProfileFeature`
- **State**: Subscribes to `login` state slice
- **Updates**: Automatically updates when user profile changes
- **Icon**: Account circle icon
- **Action**: Navigates to account screen
- **Usage**: Available for registration but not currently used globally

## Creating Custom State-Aware Features

### Step 1: Create the Feature Widget

Create a new file in `lib/core/widgets/state_aware_features/`:

```dart
// lib/core/widgets/state_aware_features/custom_feature.dart
import 'package:flutter/material.dart';
import '../../managers/state_manager.dart';
import '../../../tools/logging/logger.dart';

class StateAwareCustomFeature extends StatelessWidget {
  static final Logger _logger = Logger();
  
  const StateAwareCustomFeature({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        // Get your state from StateManager
        final customState = StateManager().getModuleState<Map<String, dynamic>>('custom_module');
        final isEnabled = customState?['isEnabled'] ?? false;
        
        return IconButton(
          icon: Icon(
            isEnabled ? Icons.check_circle : Icons.cancel,
            color: isEnabled ? Colors.green : Colors.red,
          ),
          onPressed: () {
            // Handle tap
            _logger.info('Custom feature tapped');
          },
          tooltip: isEnabled ? 'Enabled' : 'Disabled',
        );
      },
    );
  }
}
```

### Step 2: Register the Feature

Add the feature to the global registration:

```dart
// In lib/core/widgets/state_aware_features/state_aware_feature_registry.dart
static void registerGlobalAppBarFeatures(BuildContext context) {
  _logger.info('🌐 Registering state-aware global app bar features');
  
  // Register your custom feature
  final customFeature = FeatureDescriptor(
    featureId: 'global_custom_feature',
    slotId: 'app_bar_actions',
    builder: (context) => const StateAwareCustomFeature(),
    priority: 30, // After connection and profile
  );
  
  FeatureRegistryManager.instance.register(
    scopeKey: 'global_app_bar',
    feature: customFeature,
    context: context,
  );
  
  _logger.info('✅ Custom feature registered for global scope');
}
```

### Step 3: Export the Feature

Add the export to the index file:

```dart
// In lib/core/widgets/state_aware_features/index.dart
export 'custom_feature.dart';
```

## Screen-Specific Features

### Adding Screen-Specific Features

Individual screens can add their own features alongside the global ones:

```dart
class MyScreenState extends BaseScreenState<MyScreen> {
  @override
  void initState() {
    super.initState();
    
    // Register screen-specific features after the widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _registerScreenSpecificFeatures();
    });
  }

  void _registerScreenSpecificFeatures() {
    // Register a help button (appears after global features)
    registerAppBarAction(
      featureId: 'help',
      icon: Icons.help_outline,
      onTap: () {
        // Handle help tap
        print('Help tapped!');
      },
      tooltip: 'Help',
      priority: 100, // Lower priority = appears after global features
    );
  }

  @override
  void dispose() {
    // Clean up screen-specific features when screen is disposed
    clearAppBarActions();
    super.dispose();
  }
}
```

### State-Aware Screen-Specific Features

For screen-specific features that need to be state-aware:

```dart
class StateAwareScreenFeature extends StatelessWidget {
  final String screenId;
  
  const StateAwareScreenFeature({Key? key, required this.screenId}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        // Get screen-specific state
        final screenState = StateManager().getModuleState<Map<String, dynamic>>('screen_$screenId');
        final hasNotifications = screenState?['hasNotifications'] ?? false;
        
        return IconButton(
          icon: Stack(
            children: [
              const Icon(Icons.notifications),
              if (hasNotifications)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 12,
                      minHeight: 12,
                    ),
                    child: const Text(
                      '!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          onPressed: () {
            // Handle notifications tap
          },
          tooltip: 'Notifications',
        );
      },
    );
  }
}
```

## Feature Scope System

### Global Scope vs Local Scope

- **Global Scope** (`'global_app_bar'`): Features that appear on all screens
- **Local Scope** (`widget.runtimeType.toString()`): Features specific to individual screens

### Scope Management

```dart
// Global features (appear on all screens)
FeatureRegistryManager.instance.register(
  scopeKey: 'global_app_bar',
  feature: globalFeature,
  context: context,
);

// Local features (appear only on specific screen)
FeatureRegistryManager.instance.register(
  scopeKey: widget.runtimeType.toString(),
  feature: localFeature,
  context: context,
);
```

### FeatureSlot Scope Listening

The `FeatureSlot` widget listens to changes in both scopes:

```dart
_sub = _registry.changes.listen((scope) {
  // Rebuild if the change is in our scope OR in the global scope
  if ((scope == widget.scopeKey || scope == 'global_app_bar') && mounted) {
    _logger.info('🎮 FeatureSlot rebuilding due to registry change for scope: $scope');
    setState(() {});
  }
});
```

## Optional GlobalKey for App Bar Feature Slot

Screens can opt in to having the app bar feature slot (the widget that contains coins display and connection status) built with a stable `GlobalKey`. When enabled, callers can resolve the slot's `RenderBox` to get its position and size (e.g. for overlay animations such as a coin stream from the winners popup to the coins display).

- **Override:** In your screen widget (e.g. `GamePlayScreen`), override `useGlobalKeyForAppBarFeatureSlot` to return `true`.
- **Access:** From the screen's state, use `appBarFeatureSlotKeyIfUsed` to get the key when non-null. Resolve position via `key.currentContext?.findRenderObject() as RenderBox?`, then `renderBox.localToGlobal(Offset.zero)` and `renderBox.size`.
- **Default:** `false`; only override to `true` on screens that need to target the app bar slot (e.g. game play for the winner coin stream).

## Priority System

Features are rendered in priority order (lowest number first):

```dart
// Global features (automatic)
// Coins Display: priority 50 (appears first, leftmost)
// Connection Status: priority 100 (appears last, rightmost)

// Screen-specific features
registerAppBarAction(featureId: 'help', priority: 150, ...);
registerAppBarAction(featureId: 'notifications', priority: 200, ...);
```

## Available Methods

### BaseScreen Helper Methods

#### `registerAppBarAction()`
Registers a new app bar action feature.

```dart
  registerAppBarAction(
  featureId: 'help',
  icon: Icons.help_outline,
  onTap: () => showHelp(),
  tooltip: 'Help',
  priority: 100,
  metadata: {'color': Colors.blue},
);
```

#### `unregisterAppBarAction()`
Removes a specific app bar action feature.

```dart
unregisterAppBarAction('help');
```

#### `clearAppBarActions()`
Removes all app bar action features for the current screen.

```dart
clearAppBarActions();
```

### StateAwareFeatureRegistry Methods

#### `registerGlobalAppBarFeatures()`
Registers all global state-aware features.

```dart
StateAwareFeatureRegistry.registerGlobalAppBarFeatures(context);
```

## Integration with Existing Systems

### Navigation Integration

State-aware features can integrate with the navigation system:

```dart
class StateAwareProfileFeature extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final loginState = StateManager().getModuleState<Map<String, dynamic>>('login');
        final isLoggedIn = loginState?['isLoggedIn'] ?? false;
        
        return IconButton(
          icon: Icon(
            isLoggedIn ? Icons.account_circle : Icons.login,
            color: isLoggedIn ? Colors.green : Colors.orange,
          ),
          onPressed: () {
            if (isLoggedIn) {
              // Navigate to account screen
              final navigationManager = Provider.of<NavigationManager>(context, listen: false);
              navigationManager.navigateTo('/account');
            } else {
              // Navigate to login screen
              final navigationManager = Provider.of<NavigationManager>(context, listen: false);
              navigationManager.navigateTo('/login');
            }
          },
          tooltip: isLoggedIn ? 'Account Settings' : 'Login',
        );
      },
    );
  }
}
```

### WebSocket Integration

State-aware features can respond to WebSocket events:

```dart
class StateAwareConnectionStatusFeature extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final websocketState = StateManager().getModuleState<Map<String, dynamic>>('websocket');
        final isConnected = websocketState?['isConnected'] ?? false;
        final lastError = websocketState?['lastError'];
        
        return IconButton(
          icon: Icon(
            isConnected ? Icons.wifi : Icons.wifi_off,
            color: isConnected ? Colors.green : Colors.red,
          ),
          onPressed: () {
            final status = isConnected ? 'Connected' : 'Disconnected';
            final message = lastError != null ? '$status: $lastError' : status;
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message),
                backgroundColor: isConnected ? Colors.green : Colors.red,
              ),
            );
          },
          tooltip: isConnected ? 'WebSocket Connected' : 'WebSocket Disconnected',
        );
      },
    );
  }
}
```

## Best Practices

### 1. State Management
- Always use `ListenableBuilder` with `StateManager()` for state-aware features
- Subscribe to specific state slices rather than the entire state
- Handle null/undefined state gracefully

### 2. Performance
- Keep feature widgets lightweight
- Avoid expensive operations in the build method
- Use `const` constructors where possible

### 3. Error Handling
- Always handle navigation errors
- Provide fallback UI for error states
- Log errors appropriately

### 4. Accessibility
- Always provide meaningful tooltips
- Use semantic labels for screen readers
- Ensure proper contrast ratios

### 5. Testing
- Test state-aware features with different state values
- Mock StateManager for unit tests
- Test feature registration and cleanup

## Troubleshooting

### Common Issues

1. **Features not appearing**
   - Check if features are registered with correct scope
   - Verify FeatureSlot is listening to correct scopes
   - Ensure features have valid priority values

2. **State not updating**
   - Verify StateManager is properly updating state
   - Check if ListenableBuilder is wrapping the widget
   - Ensure state slice name is correct

3. **Navigation not working**
   - Verify NavigationManager is available via Provider
   - Check route names are correct
   - Handle navigation errors gracefully

### Debug Logging

The system provides comprehensive logging:

```dart
// Feature registration
log.info('🌐 Registering state-aware global app bar features');

// FeatureSlot operations
log.info('🎮 FeatureSlot building with ${features.length} features for scope: ${widget.scopeKey}, slot: ${widget.slotId}');

// State changes
log.info('🔄 State-aware feature updating due to state change');
```

## Summary

The new state-aware feature system provides:

1. **State-Aware Updates**: Features automatically update when state changes
2. **Core Architecture**: Proper separation of concerns with core components
3. **Global Features**: Automatic features for all screens
4. **Screen-Specific Features**: Optional additional features per screen
5. **Real-time Updates**: Dynamic updates based on app state
6. **Navigation Integration**: Seamless integration with existing navigation
7. **Priority System**: Flexible ordering of features
8. **Lifecycle Management**: Automatic cleanup and resource management
9. **Extensibility**: Easy to add new state-aware features
10. **Performance**: Optimized rendering and state management

This creates a powerful, flexible, and maintainable system for managing app bar actions across your entire application.
