# Backend Core Shared Logic Architecture

## Overview

The Dutch game implementation uses a **shared logic architecture** that allows the same core game logic to run in two different environments:

1. **Flutter Frontend** (`flutter_base_05`) - Client-side game logic for mobile/web apps
2. **Dart Backend** (`dart_bkend_base_01`) - Server-side game logic for standalone backend

Both projects share identical game logic in `backend_core/shared_logic/`, while using platform-specific implementations for file I/O, logging, and server communication.

## Architecture Principles

### 1. Shared Logic Isolation

The `backend_core/shared_logic/` directory contains **platform-agnostic** game logic that:
- Contains no platform-specific imports (no `dart:io`, no Flutter packages)
- Uses abstract interfaces for platform-specific operations
- Relies on dependency injection for platform-specific services

### 2. Platform Abstraction Layer

Platform-specific code is isolated in `utils/platform/`:
- **File I/O**: Different implementations for Flutter (assets) vs Dart backend (file system)
- **Logging**: Different logger implementations
- **Server Communication**: Different WebSocket/server implementations

### 3. Dependency Injection via `shared_imports.dart`

The `shared_imports.dart` file provides a **unified import interface** that:
- Exports common Dart core libraries (`dart:math`, `dart:async`)
- Provides platform-specific implementations (logger, server types)
- Uses type aliases for dependency injection compatibility

## Directory Structure

### Shared Logic (`backend_core/shared_logic/`)

Both projects have identical structure:

```
backend_core/shared_logic/
├── dutch_game_round.dart          # Core game round logic
├── game_state_callback.dart       # Abstract interface for state management
├── models/
│   ├── card.dart                  # Card model
│   └── card_deck.dart             # Deck model
└── utils/
    ├── computer_player_factory.dart  # AI decision-making
    ├── deck_factory.dart            # Deck creation
    └── yaml_rules_engine.dart        # YAML rules interpreter
```

### Platform-Specific (`utils/platform/`)

Platform-specific implementations differ:

**Flutter (`flutter_base_05`):**
```
utils/platform/
├── shared_imports.dart              # Flutter-specific exports
├── computer_player_config_parser.dart
├── yaml_config_parser.dart          # Loads from assets
├── predefined_hands_loader.dart
└── practice/
    └── stubs/                       # Practice mode stubs
        ├── room_manager_stub.dart
        └── websocket_server_stub.dart
```

**Dart Backend (`dart_bkend_base_01`):**
```
utils/platform/
├── shared_imports.dart              # Backend-specific exports
├── computer_player_config_parser.dart
├── yaml_config_parser.dart          # Loads from file system
└── predefined_hands_loader.dart
```

## Core Components

### 1. `dutch_game_round.dart`

**Purpose**: Core game round logic that manages:
- Turn progression
- Player actions (draw, play, collect)
- Special card powers (Jack swap, Queen peek)
- Timer management
- Game state transitions

**Key Features**:
- Platform-agnostic: Uses `GameStateCallback` interface
- Imports: Only `shared_imports.dart` (no platform-specific code)
- State Management: Delegates to `GameStateCallback` implementation

**Usage Pattern**:
```dart
import '../../utils/platform/shared_imports.dart';

class DutchGameRound {
  final GameStateCallback _stateCallback;
  
  // All game logic here - platform independent
}
```

### 2. `game_state_callback.dart`

**Purpose**: Abstract interface that defines how game state is managed

**Interface Methods**:
- `onGameStateChanged()` - Broadcast state updates
- `sendGameStateToPlayer()` - Send to specific player
- `broadcastGameStateExcept()` - Broadcast excluding one player
- `getCurrentGameState()` - Get current state
- `getCardById()` - Card lookup

**Implementations**:
- **Flutter**: `ServerGameStateCallbackImpl` (uses StateManager)
- **Dart Backend**: Backend-specific implementation (uses WebSocket broadcasts)

### 3. `computer_player_factory.dart`

**Purpose**: AI decision-making for computer players

**Features**:
- YAML-driven behavior configuration
- Timer-based decision delays (40-80% of action timer) - see [Computer Player Delay System](../COMPUTER_PLAYER_DELAY_SYSTEM.md)
- Miss chance mechanics (difficulty-based error simulation)
- Strategy selection based on difficulty

**Platform Dependencies**:
- Imports `computer_player_config_parser.dart` (platform-specific)
- Uses `shared_imports.dart` for logging/Random

### 4. `deck_factory.dart`

**Purpose**: Deck creation and card generation

**Features**:
- YAML configuration support
- Random card ID generation
- Testing mode support

**Platform Dependencies**:
- Imports `yaml_config_parser.dart` (platform-specific file loading)
- Uses `shared_imports.dart` for Random

### 5. `yaml_rules_engine.dart`

**Purpose**: Generic YAML rules interpreter

**Features**:
- Priority-based rule evaluation
- Conditional logic support
- Action execution

**Platform Dependencies**:
- Only `shared_imports.dart` (fully platform-agnostic)

## Platform-Specific Files

### 1. `shared_imports.dart`

**Purpose**: Unified import interface that abstracts platform differences

#### Flutter Version (`flutter_base_05`)

```dart
// Common Dart core imports
export 'dart:math';
export 'dart:async';
// Note: dart:io removed for Flutter compatibility

// Flutter logger (replaces backend server_logger)
export '../../../../tools/logging/logger.dart';

// Type aliases for dependency injection
// Allows same code to work with real or stub implementations
typedef WebSocketServer = dynamic;
typedef RoomManager = dynamic;
typedef HooksManager = dynamic;

// Platform-specific config paths (Flutter)
const String DECK_CONFIG_PATH = 'assets/deck_config.yaml';
```

**Key Differences**:
- **No `dart:io`**: Flutter doesn't support file system access
- **Flutter Logger**: Uses Flutter-specific logging
- **Type Aliases**: Uses `dynamic` for dependency injection (allows stubs)
- **Assets Path**: Config files loaded from Flutter assets

#### Dart Backend Version (`dart_bkend_base_01`)

```dart
// Common Dart core imports
export 'dart:math';
export 'dart:async';
export 'dart:io';  // Backend has file system access

// Backend-specific logger
export '../../../../utils/server_logger.dart';

// Backend server and manager types (export actual classes)
export '../../../../server/websocket_server.dart' hide LOGGING_SWITCH;
export '../../../../server/room_manager.dart';
export '../../../../managers/hooks_manager.dart' hide LOGGING_SWITCH;

// Platform-specific config paths (Dart backend)
const String DECK_CONFIG_PATH = 'assets/deck_config.yaml';
```

**Key Differences**:
- **Has `dart:io`**: Backend can access file system
- **Backend Logger**: Uses server-specific logging
- **Real Exports**: Exports actual classes (not type aliases)
- **File System**: Can load configs from file system

### 2. `yaml_config_parser.dart`

**Purpose**: YAML configuration file loading

#### Flutter Version

**File Loading**:
- Uses `rootBundle.loadString()` from Flutter services
- Maps file paths to asset paths
- Example: `'lib/modules/.../deck_config.yaml'` → `'assets/deck_config.yaml'`

**Key Code**:
```dart
import 'package:flutter/services.dart' show rootBundle;

static Future<DeckConfig> fromFile(String filePath) async {
  // Map to asset path
  String assetPath = 'assets/deck_config.yaml';
  final yamlString = await rootBundle.loadString(assetPath);
  // ... parse YAML
}
```

#### Dart Backend Version

**File Loading**:
- Uses `File().readAsString()` from `dart:io`
- Checks multiple locations (backend_core/config, config/)
- Direct file system access

**Key Code**:
```dart
import 'dart:io';

static Future<DeckConfig> fromFile(String filePath) async {
  var resolvedPath = filePath;
  // Try backend_core/config first, then config/
  final backendCoreCandidate = File('lib/modules/.../backend_core/config/deck_config.yaml');
  if (backendCoreCandidate.existsSync()) {
    resolvedPath = backendCoreCandidate.path;
  }
  final yamlString = await File(resolvedPath).readAsString();
  // ... parse YAML
}
```

**Shared Features**:
- Both use `_parseBoolValue()` helper for robust boolean parsing
- Both use `_convertYamlMap()` for YAML to Dart conversion
- Identical API surface (same methods, same return types)

### 3. `computer_player_config_parser.dart`

**Purpose**: Parse computer player YAML configuration

**Status**: Identical in both projects (no platform-specific differences)

**Features**:
- Difficulty level configuration
- Miss chance percentages (see [Computer Player Delay System](../COMPUTER_PLAYER_DELAY_SYSTEM.md))
- Strategy rules
- **Note**: Decision delays are now timer-based (not from YAML) - see [Computer Player Delay System](../COMPUTER_PLAYER_DELAY_SYSTEM.md)

### 4. `predefined_hands_loader.dart`

**Purpose**: Load predefined hand configurations for testing

**Status**: Platform-specific implementations (different file loading)

## How Shared Logic Works

### Import Pattern

All shared logic files follow this pattern:

```dart
// 1. Import shared_imports (provides platform-agnostic utilities)
import '../../../utils/platform/shared_imports.dart';

// 2. Import platform-specific parsers directly (if needed)
import '../../../utils/platform/computer_player_config_parser.dart';
import '../../../utils/platform/yaml_config_parser.dart';

// 3. No direct platform imports (no dart:io, no Flutter packages)
```

### Dependency Injection

The `shared_imports.dart` file enables dependency injection:

**Flutter**:
```dart
typedef WebSocketServer = dynamic;
typedef RoomManager = dynamic;
```
- Allows code to compile with type aliases
- Runtime can inject real implementations or stubs (for practice mode)

**Dart Backend**:
```dart
export '../../../../server/websocket_server.dart';
export '../../../../server/room_manager.dart';
```
- Exports actual classes
- Direct usage of real implementations

### State Management Abstraction

The `GameStateCallback` interface abstracts state management:

**Flutter Implementation**:
```dart
class ServerGameStateCallbackImpl implements GameStateCallback {
  final StateManager _stateManager;
  
  @override
  void onGameStateChanged(Map<String, dynamic> updates) {
    _stateManager.updateModuleState('dutch_game', updates);
  }
}
```

**Dart Backend Implementation**:
```dart
class BackendGameStateCallbackImpl implements GameStateCallback {
  final WebSocketServer _wsServer;
  
  @override
  void onGameStateChanged(Map<String, dynamic> updates) {
    _wsServer.broadcastToRoom(roomId, 'game_state_update', updates);
  }
}
```

## Key Design Decisions

### 1. Why Separate Platform Files?

**Problem**: Flutter and Dart backend have different:
- File I/O capabilities (assets vs file system)
- Logging systems
- Server communication (StateManager vs WebSocket)

**Solution**: Platform-specific files in `utils/platform/` handle these differences while shared logic remains identical.

### 2. Why `shared_imports.dart`?

**Problem**: Shared logic needs platform-specific utilities (logger, Random, etc.) but can't import them directly.

**Solution**: `shared_imports.dart` provides a unified interface that exports the right implementation for each platform.

### 3. Why Type Aliases in Flutter?

**Problem**: Flutter code needs to work with both real WebSocket servers (production) and stubs (practice mode).

**Solution**: Type aliases (`typedef WebSocketServer = dynamic`) allow dependency injection at runtime.

### 4. Why Abstract `GameStateCallback`?

**Problem**: State management differs between Flutter (StateManager) and backend (WebSocket broadcasts).

**Solution**: Abstract interface allows shared logic to work with either implementation.

## Maintaining Shared Logic

### Rules for Shared Files

1. **No Platform Imports**: Never import `dart:io`, Flutter packages, or backend-specific code
2. **Use `shared_imports.dart`**: Always import shared utilities via `shared_imports.dart`
3. **Abstract Interfaces**: Use abstract classes/interfaces for platform-specific operations
4. **Direct Platform Imports**: Only import platform-specific parsers directly (they're designed for this)

### Adding New Shared Logic

1. Create file in `backend_core/shared_logic/`
2. Import `shared_imports.dart` for common utilities
3. Import platform-specific parsers directly if needed
4. Test in both Flutter and Dart backend projects

### Adding New Platform-Specific Code

1. Create file in `utils/platform/`
2. Implement platform-specific logic
3. Export via `shared_imports.dart` if it's a common utility
4. Import directly in shared logic if it's a parser/loader

## Testing Strategy

### Shared Logic Tests

- Write tests that work in both environments
- Mock `GameStateCallback` interface
- Use dependency injection for platform-specific services

### Platform-Specific Tests

- Test file loading separately (assets vs file system)
- Test logger implementations separately
- Test server communication separately

## Common Pitfalls

### ❌ Don't Do This

```dart
// In shared logic file
import 'dart:io';  // ❌ Platform-specific import
import 'package:flutter/services.dart';  // ❌ Flutter-specific import
```

### ✅ Do This Instead

```dart
// In shared logic file
import '../../../utils/platform/shared_imports.dart';  // ✅ Unified interface
import '../../../utils/platform/yaml_config_parser.dart';  // ✅ Platform-specific parser (OK)
```

### ❌ Don't Do This

```dart
// Direct file system access in shared logic
final file = File('config.yaml');
final content = await file.readAsString();  // ❌ Won't work in Flutter
```

### ✅ Do This Instead

```dart
// Use platform-specific parser
import '../../../utils/platform/yaml_config_parser.dart';
final config = await DeckConfig.fromFile('config.yaml');  // ✅ Works in both
```

## File Comparison Summary

### Identical Files (100% Same)

- `dutch_game_round.dart` - Core game logic
- `game_state_callback.dart` - Abstract interface
- `models/card.dart` - Card model
- `models/card_deck.dart` - Deck model
- `utils/yaml_rules_engine.dart` - Rules interpreter
- `utils/platform/computer_player_config_parser.dart` - Player config parser

### Platform-Specific Files (Different Implementations)

- `utils/platform/shared_imports.dart` - Different exports
- `utils/platform/yaml_config_parser.dart` - Different file loading
- `utils/platform/predefined_hands_loader.dart` - Different file loading

### Shared Logic with Platform Dependencies

- `utils/computer_player_factory.dart` - Uses platform parser
- `utils/deck_factory.dart` - Uses platform parser

## Conclusion

The shared logic architecture enables:
- **Code Reuse**: Same game logic in both Flutter and Dart backend
- **Platform Flexibility**: Platform-specific implementations where needed
- **Maintainability**: Single source of truth for game logic
- **Testability**: Shared logic can be tested independently

The key to maintaining this architecture is:
1. Keep shared logic platform-agnostic
2. Use `shared_imports.dart` for common utilities
3. Abstract platform-specific operations via interfaces
4. Isolate platform differences in `utils/platform/`
