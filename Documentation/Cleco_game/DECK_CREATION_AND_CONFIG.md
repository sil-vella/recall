# Deck Creation and Configuration Documentation - Cleco Game

## Overview

This document describes the deck creation and configuration system for the Cleco game. It covers YAML configuration files, deck factory implementation, platform-specific file loading, and how decks are created and used during gameplay.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [YAML Configuration Files](#yaml-configuration-files)
3. [Deck Configuration Structure](#deck-configuration-structure)
4. [Deck Factory System](#deck-factory-system)
5. [Platform-Specific Implementation](#platform-specific-implementation)
6. [Deck Creation Flow](#deck-creation-flow)
7. [Testing vs Standard Decks](#testing-vs-standard-decks)
8. [Card ID Generation](#card-id-generation)
9. [Related Files](#related-files)
10. [Configuration Examples](#configuration-examples)

---

## Architecture Overview

The deck creation system uses a YAML-based configuration approach that allows for flexible deck composition without code changes. The system consists of:

1. **YAML Configuration Files** - Define deck composition, card properties, and settings
2. **DeckConfig Parser** - Platform-specific parser that loads YAML files
3. **YamlDeckFactory** - Factory class that creates decks from configuration
4. **Card Model** - Represents individual cards with properties

### Key Components

- **DeckConfig** (`yaml_config_parser.dart`) - Parses and provides access to YAML configuration
- **YamlDeckFactory** (`deck_factory.dart`) - Creates decks from configuration
- **Card** (`card.dart`) - Card model with properties (rank, suit, points, specialPower)

---

## YAML Configuration Files

### File Locations

The deck configuration YAML files are located in different paths depending on the platform:

#### Flutter (Frontend)
- **Primary Location**: `flutter_base_05/assets/deck_config.yaml`
- **Referenced as**: `assets/deck_config.yaml` (via `DECK_CONFIG_PATH` constant)
- **Constant Definition**: `flutter_base_05/lib/modules/cleco_game/utils/platform/shared_imports.dart`
  ```dart
  const String DECK_CONFIG_PATH = 'assets/deck_config.yaml';
  ```

#### Dart Backend
- **Primary Location**: `dart_bkend_base_01/lib/modules/cleco_game/backend_core/config/deck_config.yaml`
- **Fallback Location**: `dart_bkend_base_01/lib/modules/cleco_game/config/deck_config.yaml`
- **Referenced as**: `assets/deck_config.yaml` (resolved to actual file path)

### File Loading

#### Flutter Implementation
- Uses `rootBundle.loadString()` to load from assets
- Path mapping: Any path containing `deck_config.yaml` is mapped to `assets/deck_config.yaml`
- Location: `flutter_base_05/lib/modules/cleco_game/utils/platform/yaml_config_parser.dart`

```dart
static Future<DeckConfig> fromFile(String filePath) async {
  // Flutter: map file path to asset path
  String assetPath = filePath;
  if (filePath.contains('deck_config.yaml')) {
    assetPath = 'assets/deck_config.yaml';
  }
  final yamlString = await rootBundle.loadString(assetPath);
  // ... parse and return DeckConfig
}
```

#### Dart Backend Implementation
- Uses `File.readAsString()` to load from file system
- Path resolution: Checks `backend_core/config/` first, then falls back to `config/`
- Location: `dart_bkend_base_01/lib/modules/cleco_game/utils/platform/yaml_config_parser.dart`

```dart
static Future<DeckConfig> fromFile(String filePath) async {
  var resolvedPath = filePath;
  if (filePath.startsWith('assets/')) {
    final backendCoreCandidate = File('lib/modules/cleco_game/backend_core/config/deck_config.yaml');
    final regularCandidate = File('lib/modules/cleco_game/config/deck_config.yaml');
    if (backendCoreCandidate.existsSync()) {
      resolvedPath = backendCoreCandidate.path;
    } else if (regularCandidate.existsSync()) {
      resolvedPath = regularCandidate.path;
    }
  }
  final yamlString = await File(resolvedPath).readAsString();
  // ... parse and return DeckConfig
}
```

---

## Deck Configuration Structure

The YAML configuration file has the following structure:

### Global Settings

```yaml
deck_settings:
  include_jokers: true          # Whether to include joker cards
  testing_mode: true            # Use testing deck (true) or standard deck (false)
```

### Standard Deck Configuration

```yaml
standard_deck:
  suits:
    - hearts
    - diamonds
    - clubs
    - spades
  
  ranks:
    ace:
      points: 1
      special_power: null
      quantity_per_suit: 1
    "2":
      points: 2
      special_power: null
      quantity_per_suit: 1
    # ... more ranks
    jack:
      points: 10
      special_power: "switch_cards"
      quantity_per_suit: 1
    queen:
      points: 10
      special_power: "peek_at_card"
      quantity_per_suit: 1
    king:
      points: 10
      special_power: null
      quantity_per_suit: 1
  
  jokers:
    joker:
      points: 0
      special_power: null
      quantity_total: 2
      suit: "joker"
```

### Testing Deck Configuration

```yaml
testing_deck:
  suits:
    - hearts
    - diamonds
    - clubs
    - spades
  
  ranks:
    ace:
      points: 1
      special_power: null
      quantity_per_suit: 1
    "2":
      points: 2
      special_power: null
      quantity_per_suit: 1
    "3":
      points: 3
      special_power: null
      quantity_per_suit: 1
    "4":
      points: 4
      special_power: null
      quantity_per_suit: 1
    king:
      points: 10
      special_power: null
      quantity_per_suit: 1
  
  jokers:
    joker:
      points: 0
      special_power: null
      quantity_total: 0  # No jokers for smaller deck
      suit: "joker"
```

### Card Display Configuration

```yaml
card_display:
  suits:
    hearts: "♥"
    diamonds: "♦"
    clubs: "♣"
    spades: "♠"
    joker: "🃏"
  
  ranks:
    ace: "A"
    jack: "J"
    queen: "Q"
    king: "K"
    joker: "🃏"
  
  names:
    ace: "Ace"
    jack: "Jack"
    queen: "Queen"
    king: "King"
    joker: "Joker"
```

### Special Powers Configuration

```yaml
special_powers:
  peek_at_card:
    name: "Peek at Card"
    description: "Look at any one card from any player's hand"
    icon: "👁️"
  
  switch_cards:
    name: "Switch Cards"
    description: "Switch any two cards between any players"
    icon: "🔄"
```

### Deck Statistics

```yaml
deck_stats:
  standard:
    total_cards: 54
    suits: 4
    ranks_per_suit: 13
    jokers: 2
    special_cards: 8  # 4 queens + 4 jacks
  
  testing:
    total_cards: 20
    suits: 4
    special_cards: 0  # No special cards (jacks/queens removed)
    numbered_cards: 16  # 2, 3, 4 of each suit (3×4 = 12) + ace counts as numbered
    face_cards: 4  # 4 kings
    jokers: 0
```

---

## Deck Factory System

### YamlDeckFactory

The `YamlDeckFactory` class is responsible for creating decks from YAML configuration.

**Location**: `lib/modules/cleco_game/backend_core/shared_logic/utils/deck_factory.dart`

#### Key Methods

```dart
class YamlDeckFactory {
  final String gameId;
  final DeckConfig config;
  final Random _random = Random();

  /// Create factory from YAML file
  static Future<YamlDeckFactory> fromFile(String gameId, String configPath) async {
    final config = await DeckConfig.fromFile(configPath);
    return YamlDeckFactory(gameId, config);
  }

  /// Create factory from YAML string
  static YamlDeckFactory fromString(String gameId, String yamlString) {
    final config = DeckConfig.fromString(yamlString);
    return YamlDeckFactory(gameId, config);
  }

  /// Build deck using YAML configuration
  List<Card> buildDeck({bool? includeJokers}) {
    final shouldIncludeJokers = includeJokers ?? config.includeJokers;
    final cards = config.buildCards(gameId);
    
    if (!shouldIncludeJokers) {
      cards.removeWhere((card) => card.isJoker);
    }
    
    cards.shuffle(_random);
    return cards;
  }

  /// Get configuration summary
  Map<String, dynamic> getSummary() => config.getSummary();

  /// Validate configuration
  Map<String, dynamic> validateConfig() => config.validateConfig();
}
```

### DeckConfig

The `DeckConfig` class provides structured access to YAML configuration.

**Location**: `lib/modules/cleco_game/utils/platform/yaml_config_parser.dart`

#### Key Properties

```dart
class DeckConfig {
  // Deck settings
  bool get isTestingMode => deckSettings['testing_mode'] ?? false;
  bool get includeJokers => deckSettings['include_jokers'] ?? true;
  
  // Deck configurations
  Map<String, dynamic> get currentDeck => isTestingMode ? testingDeck : standardDeck;
  List<String> get suits => List<String>.from(currentDeck['suits'] ?? []);
  Map<String, dynamic> get ranks => currentDeck['ranks'] ?? {};
  Map<String, dynamic> get jokers => currentDeck['jokers'] ?? {};
  
  /// Build cards from configuration
  List<Card> buildCards(String gameId) {
    final cards = <Card>[];
    
    // Add cards for each suit and rank
    for (final suit in suits) {
      for (final rankEntry in ranks.entries) {
        final rank = rankEntry.key;
        final rankConfig = rankEntry.value as Map<String, dynamic>;
        final quantityPerSuit = rankConfig['quantity_per_suit'] ?? 1;
        
        for (int i = 0; i < quantityPerSuit; i++) {
          final cardId = _generateCardId(gameId, rank, suit, i);
          final card = Card(
            cardId: cardId,
            rank: rank,
            suit: suit,
            points: rankConfig['points'] ?? 0,
            specialPower: rankConfig['special_power'],
          );
          cards.add(card);
        }
      }
    }
    
    // Add jokers if enabled
    if (includeJokers) {
      // ... joker creation logic
    }
    
    return cards;
  }
}
```

---

## Platform-Specific Implementation

### Flutter (Frontend)

**File Loading**:
- Uses `rootBundle.loadString()` from `package:flutter/services.dart`
- Files must be declared in `pubspec.yaml`:
  ```yaml
  flutter:
    assets:
      - assets/deck_config.yaml
  ```

**Path Resolution**:
- All paths containing `deck_config.yaml` are mapped to `assets/deck_config.yaml`
- Uses `DECK_CONFIG_PATH` constant from `shared_imports.dart`

**Usage**:
```dart
import '../../utils/platform/shared_imports.dart'; // Provides DECK_CONFIG_PATH

final deckFactory = await YamlDeckFactory.fromFile(roomId, DECK_CONFIG_PATH);
final List<Card> fullDeck = deckFactory.buildDeck();
```

### Dart Backend

**File Loading**:
- Uses `File.readAsString()` from `dart:io`
- Direct file system access

**Path Resolution**:
- Checks `backend_core/config/deck_config.yaml` first
- Falls back to `config/deck_config.yaml` if not found
- Resolves `assets/` prefix to actual file paths

**Usage**:
```dart
import '../utils/platform/shared_imports.dart'; // Provides DECK_CONFIG_PATH

final deckFactory = await YamlDeckFactory.fromFile(roomId, DECK_CONFIG_PATH);
final List<Card> fullDeck = deckFactory.buildDeck();
```

---

## Deck Creation Flow

### Game Initialization

When a game starts, the deck is created in `GameEventCoordinator._handleStartMatch()`:

**Location**: `lib/modules/cleco_game/backend_core/coordinator/game_event_coordinator.dart`

```dart
Future<void> _handleStartMatch(String roomId, ClecoGameRound round, Map<String, dynamic> data) async {
  // ... player setup ...
  
  // Build deck and deal 4 cards per player
  // Use YamlDeckFactory to respect testing_mode setting from YAML config
  final deckFactory = await YamlDeckFactory.fromFile(roomId, DECK_CONFIG_PATH);
  final List<Card> fullDeck = deckFactory.buildDeck();
  
  _logger.info('GameEventCoordinator: Built deck with ${fullDeck.length} cards (testing_mode: ${deckFactory.getSummary()['testing_mode']})');
  
  // Convert cards to maps for game state
  final originalDeckMaps = fullDeck.map(_cardToMap).toList();
  
  // Deal cards to players
  // ... deal logic ...
  
  // Set up discard pile and draw pile
  // ... pile setup ...
}
```

### Step-by-Step Flow

1. **Load Configuration**
   - `YamlDeckFactory.fromFile()` is called with `gameId` and `DECK_CONFIG_PATH`
   - `DeckConfig.fromFile()` loads and parses the YAML file
   - Platform-specific path resolution occurs

2. **Select Deck Type**
   - `DeckConfig.isTestingMode` checks `deck_settings.testing_mode`
   - Returns `testingDeck` if `true`, `standardDeck` if `false`

3. **Build Cards**
   - `DeckConfig.buildCards(gameId)` iterates through suits and ranks
   - Creates `Card` objects with unique IDs
   - Adds jokers if `includeJokers` is true

4. **Shuffle Deck**
   - `YamlDeckFactory.buildDeck()` shuffles cards using `Random`
   - Returns shuffled `List<Card>`

5. **Convert to Game State**
   - Cards are converted to maps for JSON serialization
   - Stored in `originalDeck` for card lookup
   - Split into `drawPile` and dealt to players

---

## Testing vs Standard Decks

### Testing Deck

**Purpose**: Smaller deck for faster testing and reshuffle testing

**Configuration**: Set `testing_mode: true` in `deck_settings`

**Current Composition** (20 cards):
- ace: 4 cards (1 per suit)
- 2: 4 cards (1 per suit)
- 3: 4 cards (1 per suit)
- 4: 4 cards (1 per suit)
- king: 4 cards (1 per suit)
- No jacks, queens, or jokers

**Use Cases**:
- Practice mode
- Reshuffle testing
- Quick game testing

### Standard Deck

**Purpose**: Full deck for production gameplay

**Configuration**: Set `testing_mode: false` in `deck_settings`

**Current Composition** (54 cards):
- All ranks (ace, 2-10, jack, queen, king): 52 cards
- Jokers: 2 cards

**Use Cases**:
- Production multiplayer games
- Full game experience

### Switching Between Modes

The deck type is determined by the `testing_mode` setting in the YAML file:

```yaml
deck_settings:
  testing_mode: true   # Use testing deck
  # testing_mode: false  # Use standard deck
```

The `DeckConfig.currentDeck` property automatically selects the correct deck:

```dart
Map<String, dynamic> get currentDeck => isTestingMode ? testingDeck : standardDeck;
```

---

## Card ID Generation

Each card receives a unique ID when created. The ID format is:

```
card_{gameId}_{rank}_{suit}_{index}_{random}
```

**Example**: `card_practice_room_123_ace_hearts_0_3149337001`

### Generation Logic

```dart
String _generateCardId(String gameId, String rank, String suit, int index) {
  final timestamp = DateTime.now().microsecondsSinceEpoch.toString();
  final random = (timestamp.hashCode + gameId.hashCode + rank.hashCode + suit.hashCode + index).abs();
  return 'card_${gameId}_${rank}_${suit}_${index}_$random';
}
```

**Components**:
- `gameId`: Room/game identifier
- `rank`: Card rank (ace, 2, 3, etc.)
- `suit`: Card suit (hearts, diamonds, clubs, spades)
- `index`: Quantity index (0, 1, 2, etc. for multiple cards of same rank/suit)
- `random`: Hash-based random number for uniqueness

---

## Related Files

### Configuration Files
- `flutter_base_05/assets/deck_config.yaml` - Flutter deck configuration
- `dart_bkend_base_01/lib/modules/cleco_game/backend_core/config/deck_config.yaml` - Dart backend deck configuration

### Implementation Files
- `lib/modules/cleco_game/utils/platform/yaml_config_parser.dart` - YAML parser (platform-specific)
- `lib/modules/cleco_game/backend_core/shared_logic/utils/deck_factory.dart` - Deck factory
- `lib/modules/cleco_game/backend_core/shared_logic/models/card.dart` - Card model
- `lib/modules/cleco_game/backend_core/coordinator/game_event_coordinator.dart` - Deck creation during game start
- `lib/modules/cleco_game/utils/platform/shared_imports.dart` - `DECK_CONFIG_PATH` constant

### Documentation
- `Documentation/Cleco_game/STATE_MANAGEMENT.md` - State management documentation
- `Documentation/Cleco_game/PLAYER_ACTIONS_FLOW.md` - Player actions documentation

---

## Configuration Examples

### Example: Adding a New Rank

To add a new rank to the testing deck:

```yaml
testing_deck:
  ranks:
    # ... existing ranks ...
    "5":
      points: 5
      special_power: null
      quantity_per_suit: 1
```

### Example: Changing Special Power

To modify a card's special power:

```yaml
standard_deck:
  ranks:
    jack:
      points: 10
      special_power: "switch_cards"  # Change this value
      quantity_per_suit: 1
```

### Example: Disabling Jokers

To disable jokers in testing deck:

```yaml
testing_deck:
  jokers:
    joker:
      points: 0
      special_power: null
      quantity_total: 0  # Set to 0 to disable
      suit: "joker"
```

### Example: Multiple Cards Per Suit

To have multiple cards of the same rank per suit:

```yaml
testing_deck:
  ranks:
    ace:
      points: 1
      special_power: null
      quantity_per_suit: 2  # Creates 2 aces per suit (8 total)
```

---

## Best Practices

1. **Keep Configs Synchronized**: Ensure Flutter and Dart backend configs match
2. **Update Stats**: When modifying deck composition, update `deck_stats` section
3. **Test Both Modes**: Test with both `testing_mode: true` and `testing_mode: false`
4. **Validate Configuration**: Use `validateConfig()` method to check configuration
5. **Document Changes**: Update this documentation when making significant changes

---

## Troubleshooting

### Deck Not Loading

**Issue**: `Failed to load deck config from...`

**Solutions**:
- Flutter: Ensure file is in `assets/` and declared in `pubspec.yaml`
- Dart Backend: Check file path exists in `backend_core/config/` or `config/`
- Verify `DECK_CONFIG_PATH` constant is correctly defined

### Wrong Deck Type

**Issue**: Using standard deck when testing deck expected

**Solutions**:
- Check `deck_settings.testing_mode` in YAML file
- Verify `DeckConfig.isTestingMode` returns expected value
- Check logs for `testing_mode` value in deck build message

### Cards Missing

**Issue**: Expected cards not in deck

**Solutions**:
- Verify rank is defined in correct deck section (`standard_deck` or `testing_deck`)
- Check `quantity_per_suit` is greater than 0
- For jokers, verify `quantity_total` is greater than 0 and `include_jokers` is true

---

## Future Improvements

1. **Dynamic Deck Configuration**: Allow per-game deck configuration
2. **Deck Validation**: Enhanced validation with detailed error messages
3. **Deck Presets**: Pre-defined deck configurations for different game modes
4. **Card Customization**: Allow custom card properties per game
5. **Deck Statistics**: Real-time deck statistics and validation
