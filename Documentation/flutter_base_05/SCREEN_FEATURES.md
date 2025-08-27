# Screen Features System

This document explains the comprehensive screen features system in Flutter Base 05, including the feature registry, state-aware features, and how to create and manage dynamic UI components across screens.

## Overview

The screen features system provides a flexible, state-aware way to dynamically add, remove, and manage UI components across screens. It integrates with the existing `FeatureRegistryManager` and uses state-aware widgets that automatically update when their underlying state changes.

## Architecture

### Core Components

1. **FeatureRegistryManager** (`lib/modules/recall_game/managers/feature_registry_manager.dart`)
   - Central registry for all features across the app
   - Manages feature registration, unregistration, and scope clearing
   - Provides change notifications via streams
   - Supports both local and global scopes

2. **FeatureSlot** (`lib/core/widgets/feature_slot.dart`)
   - Core rendering widget for features
   - Listens to registry changes and rebuilds automatically
   - Supports both local and global scopes
   - Renders features in priority order
   - Provides template support for styled containers

3. **State-Aware Feature Widgets** (`lib/core/widgets/state_aware_features/`)
   - Individual widgets that subscribe to state changes
   - Use `ListenableBuilder` with `StateManager()` for reactive updates
   - Follow the same pattern as other widgets in the app
   - Automatically update when state changes

4. **Feature Contracts** (`lib/modules/recall_game/managers/feature_contracts.dart`)
   - Defines feature descriptors and contracts
   - Ensures consistent feature implementation
   - Provides type safety for feature registration

### Directory Structure

```
lib/
├── core/
│   ├── widgets/
│   │   ├── feature_slot.dart                    # Core feature rendering widget
│   │   └── state_aware_features/
│   │       ├── index.dart                       # Exports all state-aware features
│   │       ├── connection_status_feature.dart   # WebSocket connection status widget
│   │       ├── profile_feature.dart             # User profile widget
│   │       └── state_aware_feature_registry.dart # Registration helper
│   └── 00_base/
│       └── screen_base.dart                     # BaseScreen with feature integration
└── modules/
    └── recall_game/
        └── managers/
            ├── feature_registry_manager.dart     # Feature registry
            └── feature_contracts.dart            # Feature descriptors
```

## Feature Registry System

### Feature Registration

Features are registered with a scope key and slot ID:

```dart
// Register a feature
FeatureRegistryManager.instance.register(
  scopeKey: 'MyScreen',           // Screen-specific scope
  feature: myFeature,             // Feature descriptor
  context: context,               // BuildContext for navigation
);

// Register a global feature
FeatureRegistryManager.instance.register(
  scopeKey: 'global_app_bar',     // Global scope
  feature: globalFeature,         // Feature descriptor
  context: context,               // BuildContext for navigation
);
```

### Feature Descriptors

Features are defined using `FeatureDescriptor` or specialized descriptors:

```dart
// Generic feature descriptor
final feature = FeatureDescriptor(
  featureId: 'my_feature',
  slotId: 'my_slot',
  builder: (context) => MyWidget(),
  priority: 100,
  onInit: () => print('Feature initialized'),
  onDispose: () => print('Feature disposed'),
  metadata: {'key': 'value'},
);

// Icon action feature descriptor
final iconFeature = IconActionFeatureDescriptor(
  featureId: 'my_icon',
  slotId: 'app_bar_actions',
  icon: Icons.star,
  onTap: () => print('Icon tapped'),
  tooltip: 'My Icon',
  priority: 50,
  metadata: {'color': Colors.blue},
);
```

### Feature Scopes

- **Global Scope** (`'global_app_bar'`): Features that appear across all screens
- **Local Scope** (`widget.runtimeType.toString()`): Features specific to individual screens
- **Module Scope** (`'module_name'`): Features specific to a module

## State-Aware Feature System

### How State-Aware Features Work

State-aware features use the same state subscription pattern as other widgets in the app:

```dart
class StateAwareFeature extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        // Get state from StateManager
        final state = StateManager().getModuleState<Map<String, dynamic>>('module_name');
        final isEnabled = state?['isEnabled'] ?? false;
        
        // Build widget based on current state
        return Container(
          color: isEnabled ? Colors.green : Colors.red,
          child: Text(isEnabled ? 'Enabled' : 'Disabled'),
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
- **`notifications`**: Notification state and counts
- **`theme`**: Theme and appearance settings

## Creating Custom Features

### Step 1: Create the Feature Widget

Create a new widget that follows the state-aware pattern:

```dart
// lib/core/widgets/state_aware_features/custom_feature.dart
import 'package:flutter/material.dart';
import '../../managers/state_manager.dart';
import '../../../tools/logging/logger.dart';

class StateAwareCustomFeature extends StatelessWidget {
  static final Logger _log = Logger();
  
  const StateAwareCustomFeature({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        // Get your state from StateManager
        final customState = StateManager().getModuleState<Map<String, dynamic>>('custom_module');
        final isEnabled = customState?['isEnabled'] ?? false;
        final count = customState?['count'] ?? 0;
        
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isEnabled ? Colors.green : Colors.red,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isEnabled ? Icons.check_circle : Icons.cancel,
                color: Colors.white,
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                'Count: $count',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
```

### Step 2: Register the Feature

Register the feature with the appropriate scope:

```dart
// For global features
void registerGlobalFeature(BuildContext context) {
  final feature = FeatureDescriptor(
    featureId: 'global_custom_feature',
    slotId: 'global_slot',
    builder: (context) => const StateAwareCustomFeature(),
    priority: 100,
  );
  
  FeatureRegistryManager.instance.register(
    scopeKey: 'global_app_bar',
    feature: feature,
    context: context,
  );
}

// For screen-specific features
void registerScreenFeature(BuildContext context, String screenScope) {
  final feature = FeatureDescriptor(
    featureId: 'screen_custom_feature',
    slotId: 'screen_slot',
    builder: (context) => const StateAwareCustomFeature(),
    priority: 50,
  );
  
  FeatureRegistryManager.instance.register(
    scopeKey: screenScope,
    feature: feature,
    context: context,
  );
}
```

### Step 3: Use the Feature in UI

Add a `FeatureSlot` to render the feature:

```dart
class MyScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Screen'),
        actions: [
          // Render features in app bar
          FeatureSlot(
            scopeKey: 'MyScreen',
            slotId: 'app_bar_actions',
            useTemplate: false,
          ),
        ],
      ),
      body: Column(
        children: [
          // Render features in body
          FeatureSlot(
            scopeKey: 'MyScreen',
            slotId: 'body_features',
            title: 'My Features',
            useTemplate: true,
          ),
        ],
      ),
    );
  }
}
```

## Feature Slot Templates

### Using Templates

The `FeatureSlot` supports templates for styled containers:

```dart
// With template (styled container)
FeatureSlot(
  scopeKey: 'MyScreen',
  slotId: 'my_slot',
  title: 'My Features',
  useTemplate: true,  // Uses SlotTemplate
);

// Without template (plain row)
FeatureSlot(
  scopeKey: 'MyScreen',
  slotId: 'my_slot',
  useTemplate: false,  // Plain row layout
);
```

### Custom Templates

You can create custom templates by extending `SlotTemplate`:

```dart
class CustomSlotTemplate extends StatelessWidget {
  final String title;
  final List<Widget> children;
  
  const CustomSlotTemplate({
    Key? key,
    required this.title,
    required this.children,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: children,
            ),
          ],
        ),
      ),
    );
  }
}
```

## Feature Lifecycle Management

### Automatic Lifecycle

Features can have initialization and cleanup hooks:

```dart
final feature = FeatureDescriptor(
  featureId: 'my_feature',
  slotId: 'my_slot',
  builder: (context) => MyWidget(),
  onInit: () {
    // Called when feature is registered
    print('Feature initialized');
  },
  onDispose: () {
    // Called when feature is unregistered
    print('Feature disposed');
  },
);
```

### Manual Lifecycle Management

You can manually manage feature lifecycle:

```dart
class MyScreenState extends State<MyScreen> {
  @override
  void initState() {
    super.initState();
    
    // Register features
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _registerFeatures();
    });
  }

  void _registerFeatures() {
    // Register screen-specific features
    final feature = FeatureDescriptor(
      featureId: 'screen_feature',
      slotId: 'screen_slot',
      builder: (context) => const MyWidget(),
    );
    
    FeatureRegistryManager.instance.register(
      scopeKey: widget.runtimeType.toString(),
      feature: feature,
      context: context,
    );
  }

  @override
  void dispose() {
    // Clean up features
    FeatureRegistryManager.instance.clearScope(widget.runtimeType.toString());
    super.dispose();
  }
}
```

## Feature Priority System

### Priority Order

Features are rendered in priority order (lowest number first):

```dart
// High priority (rendered first)
final highPriorityFeature = FeatureDescriptor(
  featureId: 'high_priority',
  slotId: 'my_slot',
  builder: (context) => const HighPriorityWidget(),
  priority: 10,
);

// Low priority (rendered last)
final lowPriorityFeature = FeatureDescriptor(
  featureId: 'low_priority',
  slotId: 'my_slot',
  builder: (context) => const LowPriorityWidget(),
  priority: 100,
);
```

### Priority Guidelines

- **0-50**: Critical features (navigation, status indicators)
- **51-100**: Important features (actions, notifications)
- **101-200**: Standard features (help, settings)
- **201+**: Optional features (debug, experimental)

## Integration with Existing Systems

### Navigation Integration

Features can integrate with the navigation system:

```dart
class StateAwareNavigationFeature extends StatelessWidget {
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

Features can respond to WebSocket events:

```dart
class StateAwareWebSocketFeature extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final websocketState = StateManager().getModuleState<Map<String, dynamic>>('websocket');
        final isConnected = websocketState?['isConnected'] ?? false;
        final lastError = websocketState?['lastError'];
        
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isConnected ? Colors.green : Colors.red,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isConnected ? Icons.wifi : Icons.wifi_off,
                color: Colors.white,
                size: 16,
              ),
              if (lastError != null) ...[
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    lastError,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
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
- Use meaningful state slice names

### 2. Performance
- Keep feature widgets lightweight
- Avoid expensive operations in the build method
- Use `const` constructors where possible
- Minimize rebuilds by subscribing to specific state slices

### 3. Error Handling
- Always handle navigation errors
- Provide fallback UI for error states
- Log errors appropriately
- Gracefully handle missing state

### 4. Accessibility
- Always provide meaningful tooltips
- Use semantic labels for screen readers
- Ensure proper contrast ratios
- Support keyboard navigation

### 5. Testing
- Test state-aware features with different state values
- Mock StateManager for unit tests
- Test feature registration and cleanup
- Test feature priority ordering

### 6. Code Organization
- Keep feature widgets in appropriate directories
- Use consistent naming conventions
- Document complex feature logic
- Follow the established patterns

## Troubleshooting

### Common Issues

1. **Features not appearing**
   - Check if features are registered with correct scope
   - Verify FeatureSlot is listening to correct scopes
   - Ensure features have valid priority values
   - Check if FeatureSlot is properly placed in widget tree

2. **State not updating**
   - Verify StateManager is properly updating state
   - Check if ListenableBuilder is wrapping the widget
   - Ensure state slice name is correct
   - Verify state updates are triggering notifications

3. **Navigation not working**
   - Verify NavigationManager is available via Provider
   - Check route names are correct
   - Handle navigation errors gracefully
   - Ensure context is valid

4. **Performance issues**
   - Check for unnecessary rebuilds
   - Verify state subscriptions are specific
   - Use const constructors where possible
   - Monitor feature complexity

### Debug Logging

The system provides comprehensive logging:

```dart
// Feature registration
log.info('🌐 Registering feature: ${feature.featureId} for scope: $scopeKey');

// FeatureSlot operations
log.info('🎮 FeatureSlot building with ${features.length} features for scope: ${widget.scopeKey}, slot: ${widget.slotId}');

// State changes
log.info('🔄 State-aware feature updating due to state change');

// Feature lifecycle
log.info('✅ Feature initialized: ${feature.featureId}');
log.info('🗑️ Feature disposed: ${feature.featureId}');
```

### Debug Tools

You can inspect the feature registry:

```dart
// Get all features for a scope
final features = FeatureRegistryManager.instance.getFeaturesForSlot(
  scopeKey: 'MyScreen',
  slotId: 'my_slot',
);

// Print feature information
for (final feature in features) {
  print('Feature: ${feature.featureId}, Priority: ${feature.priority}');
}
```

## Summary

The screen features system provides:

1. **State-Aware Updates**: Features automatically update when state changes
2. **Core Architecture**: Proper separation of concerns with core components
3. **Global Features**: Features that appear across all screens
4. **Screen-Specific Features**: Features specific to individual screens
5. **Real-time Updates**: Dynamic updates based on app state
6. **Navigation Integration**: Seamless integration with existing navigation
7. **Priority System**: Flexible ordering of features
8. **Lifecycle Management**: Automatic cleanup and resource management
9. **Extensibility**: Easy to add new state-aware features
10. **Performance**: Optimized rendering and state management
11. **Templates**: Styled containers for feature organization
12. **Error Handling**: Comprehensive error handling and fallbacks

This creates a powerful, flexible, and maintainable system for managing dynamic UI components across your entire application.
