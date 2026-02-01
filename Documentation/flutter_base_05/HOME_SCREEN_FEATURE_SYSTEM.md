# Home Screen Feature System

This document explains the home screen feature system in Flutter Base 05, which allows modules to register full-width buttons with customizable appearance and behavior, displayed as a swipeable carousel.

## Overview

The home screen feature system provides a flexible way for modules to dynamically add, remove, and manage full-width buttons on the home screen. The system integrates with the existing `FeatureRegistryManager` and supports priority ordering, custom heights (including percentage-based), images, colors, and text styling. **Home screen buttons are displayed as a swipeable carousel** with visual effects and navigation arrows.

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
   - Handles home screen button rendering with height calculation
   - **Carousel Mode**: When `contract: 'home_screen_button'` is specified, renders buttons as a swipeable carousel

3. **HomeScreenButtonFeatureDescriptor** (`lib/modules/dutch_game/managers/feature_contracts.dart`)
   - Feature descriptor for home screen buttons
   - Supports text, background color, image, height, height percentage, padding, and text style

4. **BaseScreen Integration** (`lib/core/00_base/screen_base.dart`)
   - Provides helper methods for registering home screen buttons
   - Manages feature lifecycle automatically

### Directory Structure

```
lib/
├── core/
│   ├── widgets/
│   │   └── feature_slot.dart                    # Core feature rendering widget
│   └── 00_base/
│       └── screen_base.dart                     # BaseScreen with feature integration
└── modules/
    └── dutch_game/
        ├── managers/
        │   ├── feature_registry_manager.dart     # Feature registry
        │   └── feature_contracts.dart           # Feature descriptors
        └── screens/
            └── home_screen/
                └── features/
                    └── home_screen_features.dart # Home screen feature registration
```

## Home Screen Button Features

### Feature Descriptor

```dart
class HomeScreenButtonFeatureDescriptor extends FeatureDescriptor {
  final String text;
  final VoidCallback onTap;
  final Color? backgroundColor;
  final String? imagePath;
  final double? height;
  final double? heightPercentage;  // New: percentage of available height
  final EdgeInsetsGeometry? padding;
  final TextStyle? textStyle;

  HomeScreenButtonFeatureDescriptor({
    required String featureId,
    required String slotId,
    required this.text,
    required this.onTap,
    this.backgroundColor,
    this.imagePath,
    this.height,
    this.heightPercentage,  // 0.0 to 1.0 (e.g., 0.5 = 50%)
    this.padding,
    this.textStyle,
    int priority = 100,
    Map<String, dynamic>? metadata,
  });
}
```

### Height Calculation

The system supports two ways to specify button height:

1. **Fixed Height**: Use `height` property (in logical pixels)
2. **Percentage Height**: Use `heightPercentage` property (0.0 to 1.0)

**Height Calculation Logic**:
```dart
// In FeatureSlot._buildHomeScreenButtonFeature()
final mediaQuery = MediaQuery.of(context);
final availableHeight = mediaQuery.size.height 
    - mediaQuery.padding.top 
    - mediaQuery.padding.bottom;

double? calculatedHeight;
if (feature.heightPercentage != null) {
  calculatedHeight = availableHeight * feature.heightPercentage!;
} else {
  calculatedHeight = feature.height ?? 80;  // Default 80px
}
```

**Priority**: `heightPercentage` takes precedence over `height` if both are specified.

### Button Rendering

Home screen buttons are rendered in **carousel mode** when the `contract: 'home_screen_button'` is specified in `FeatureSlot`. The carousel provides an interactive, swipeable interface with visual effects.

#### Carousel Features

- **Viewport Fraction**: Each item takes 70% of the viewport width (`viewportFraction: 0.7`)
- **Opacity Effects**: 
  - Current item: 100% opacity
  - Adjacent items: 50% opacity
  - Smooth transitions between items
- **Navigation Arrows**: 
  - Left and right arrow buttons appear when navigation is possible
  - Arrows are vertically centered on each side
  - Circular design with semi-transparent background
- **Priority Sorting**: Items are automatically sorted by priority (ascending)
- **Initial Page**: Carousel starts on the item with the lowest priority (typically the "Demo" button with priority 90)
- **Swipeable**: Users can swipe left/right to navigate between items
- **Tap Navigation**: Arrow buttons provide tap-based navigation

#### Carousel Layout

```dart
// Carousel takes 50% of screen height
SizedBox(
  height: screenHeight * 0.5,
  child: Stack(
    children: [
      // PageView with 70% viewport fraction
      PageView.builder(
        viewportFraction: 0.7,
        // ... items with opacity transitions
      ),
      // Left arrow (when can go left)
      Positioned(left: 0, ...),
      // Right arrow (when can go right)
      Positioned(right: 0, ...),
    ],
  ),
)
```

#### Individual Button Rendering

Each button in the carousel is rendered as a **full-width** container with:
- **Width**: `double.infinity` so the button fills the carousel page (parent)
- **Background**: Solid color (`backgroundColor`) or image (`imagePath`)
- **Content**: Centered text with **wrapping** (`softWrap: true`); text is given a bounded width via `LayoutBuilder` so long labels wrap onto multiple lines
- **Styling**: Custom text style, padding, and height
- **Interaction**: Tap callback (`onTap`)

**Sizes** (defined in `feature_slot.dart`):
- **Button margin**: `EdgeInsets.symmetric(horizontal: 16, vertical: 8)`
- **Button padding** (inner): `feature.padding ?? EdgeInsets.symmetric(horizontal: 48, vertical: 32)`
- **Text container padding**: `EdgeInsets.symmetric(horizontal: 32, vertical: 24)`
- **Default text size**: `fontSize: 56` (headingLarge × 2)

**Button Example**:
```dart
Container(
  width: double.infinity,
  height: calculatedHeight,
  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  decoration: BoxDecoration(...),
  child: Material(
    child: InkWell(
      onTap: feature.onTap,
      child: Container(
        width: double.infinity,
        padding: feature.padding ?? EdgeInsets.symmetric(horizontal: 48, vertical: 32),
        child: Center(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Container(
                width: constraints.maxWidth,
                padding: EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                child: Text(
                  feature.text,
                  softWrap: true,  // Text wraps to multiple lines
                  textAlign: TextAlign.center,
                  ...
                ),
              );
            },
          ),
        ),
      ),
    ),
  ),
)
```

## Registering Home Screen Buttons

### Module Registration

Modules can register home screen buttons using the feature system:

```dart
// In module initialization (e.g., dutch_game_main.dart)
void _registerHomeScreenFeatures(BuildContext context) {
  final feature = HomeScreenButtonFeatureDescriptor(
    featureId: 'dutch_game_play',
    slotId: HomeScreenFeatureSlots.slotButtons,
    text: 'Play Dutch',
    onTap: () {
      final navigationManager = NavigationManager();
      navigationManager.navigateTo('/dutch/lobby');
    },
    backgroundColor: AppColors.primaryColor,
    heightPercentage: 0.5,  // 50% of available height
    priority: 100,
    textStyle: AppTextStyles.headingMedium().copyWith(
      color: AppColors.textOnPrimary,
      fontWeight: FontWeight.bold,
    ),
  );

  FeatureRegistryManager.instance.register(
    scopeKey: HomeScreenFeatureSlots.scopeKey,
    feature: feature,
    context: context,
  );
}
```

### Home Screen Integration

The home screen uses `FeatureSlot` to render registered buttons in carousel mode:

```dart
// In home_screen.dart
Center(
  child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 1000), // Max width constraint
    child: SingleChildScrollView(
      child: Column(
        children: [
          FeatureSlot(
            scopeKey: featureScopeKey, // 'HomeScreen'
            slotId: 'home_screen_buttons',
            contract: 'home_screen_button', // Enables carousel mode
            useTemplate: false, // No template wrapper
          ),
        ],
      ),
    ),
  ),
)
```

**Key Parameters**:
- `contract: 'home_screen_button'`: Enables carousel rendering mode
- `useTemplate: false`: Disables the default template wrapper
- **Max Width**: Home screen content is constrained to 1000px and centered for better desktop/web display

### Feature Slots

**Scope Key**: `'HomeScreen'` (Note: Updated from `'home_screen_main'`)

**Slot ID**: `'home_screen_buttons'`

**Contract**: `'home_screen_button'` (enables carousel mode)

**Constants**:
```dart
// In home_screen.dart
@override
String get featureScopeKey => 'HomeScreen';

// Usage
FeatureSlot(
  scopeKey: featureScopeKey, // 'HomeScreen'
  slotId: 'home_screen_buttons',
  contract: 'home_screen_button', // Carousel mode
)
```

## Priority System

Features are rendered in priority order (lowest number first):

```dart
// Example priorities
final playButton = HomeScreenButtonFeatureDescriptor(
  featureId: 'dutch_game_play',
  priority: 100,  // Renders first
  // ...
);

final settingsButton = HomeScreenButtonFeatureDescriptor(
  featureId: 'settings',
  priority: 200,  // Renders second
  // ...
);
```

## Usage Examples

### Basic Button (Solid Color)

```dart
final feature = HomeScreenButtonFeatureDescriptor(
  featureId: 'my_feature',
  slotId: HomeScreenFeatureSlots.slotButtons,
  text: 'My Feature',
  onTap: () {
    // Handle tap
  },
  backgroundColor: Colors.blue,
  height: 100,  // Fixed height
  priority: 100,
);
```

### Button with Image Background

```dart
final feature = HomeScreenButtonFeatureDescriptor(
  featureId: 'my_feature',
  slotId: HomeScreenFeatureSlots.slotButtons,
  text: 'My Feature',
  onTap: () {
    // Handle tap
  },
  imagePath: 'assets/images/feature_background.png',
  heightPercentage: 0.4,  // 40% of available height
  priority: 100,
  textStyle: TextStyle(
    color: Colors.white,
    fontSize: 24,
    fontWeight: FontWeight.bold,
  ),
);
```

### Button with Custom Styling

```dart
final feature = HomeScreenButtonFeatureDescriptor(
  featureId: 'my_feature',
  slotId: HomeScreenFeatureSlots.slotButtons,
  text: 'My Feature',
  onTap: () {
    // Handle tap
  },
  backgroundColor: AppColors.primaryColor,
  heightPercentage: 0.5,  // 50% of available height
  padding: EdgeInsets.all(16),
  textStyle: AppTextStyles.headingLarge().copyWith(
    color: AppColors.textOnPrimary,
    fontWeight: FontWeight.bold,
  ),
  priority: 100,
);
```

## Unregistering Features

Features can be unregistered when no longer needed:

```dart
// Unregister specific feature
FeatureRegistryManager.instance.unregister(
  scopeKey: HomeScreenFeatureSlots.scopeKey,
  featureId: 'dutch_game_play',
);

// Clear all features for a scope
FeatureRegistryManager.instance.clearScope(
  scopeKey: HomeScreenFeatureSlots.scopeKey,
);
```

## Best Practices

1. **Height Selection**:
   - Use `heightPercentage` for responsive designs
   - Use `height` for fixed-size buttons
   - Consider available screen space when setting percentages
   - Carousel height is fixed at 50% of screen height

2. **Priority Management**:
   - Use consistent priority ranges (e.g., 90, 100, 200, 300)
   - Lower priorities appear first in the carousel
   - Leave gaps for future features
   - Document priority assignments
   - **Recommended**: Use priority 90 for primary/demo features

3. **Styling Consistency**:
   - Use theme constants (`AppColors`, `AppTextStyles`)
   - Maintain consistent button appearance
   - Follow app design guidelines
   - Consider larger text sizes for carousel visibility (default is 56px)

4. **Carousel Usage**:
   - Always specify `contract: 'home_screen_button'` for carousel mode
   - Set `useTemplate: false` to avoid template wrapper
   - Each button is full width of its carousel page; text wraps for long labels
   - Ensure buttons have sufficient visual contrast for 50% opacity on adjacent items
   - Test swipe gestures and arrow navigation

5. **Layout Constraints**:
   - Home screen content is constrained to 1000px max width
   - Content is centered for better desktop/web display
   - Consider responsive design for different screen sizes

6. **Lifecycle Management**:
   - Register features in module initialization
   - Unregister features in module disposal
   - Clean up resources properly

7. **Error Handling**:
   - Handle navigation errors gracefully
   - Provide user feedback for failed actions
   - Log errors for debugging

## Carousel Implementation Details

### _HomeScreenCarousel Widget

The carousel is implemented as a private widget (`_HomeScreenCarousel`) within `FeatureSlot`:

**Key Features**:
- Uses `PageController` with `viewportFraction: 0.7` for 70% item width
- `AnimatedBuilder` provides smooth opacity transitions
- Navigation arrows use `Positioned` widgets for overlay placement
- Automatically sorts features by priority on initialization
- Finds and starts on the item with priority 90 (Demo button)

**Opacity Calculation**:
```dart
// Current page gets full opacity (1.0)
// Adjacent pages get 50% opacity
// Smooth transition based on page distance
double opacity = distance < 0.5 
  ? 1.0 - (distance * 1.0).clamp(0.5, 1.0)
  : 0.5;
```

**Navigation Arrows**:
- Circular buttons with semi-transparent background
- Only visible when navigation is possible (`canGoLeft`, `canGoRight`)
- Vertically centered using `Positioned` with `top: 0, bottom: 0` and `Center` widget
- 300ms animated transitions using `Curves.easeInOut`

## Where Sizes Are Defined

| What | Location | Value / logic |
|------|----------|----------------|
| **Feature height** | `home_screen_features.dart` (registration) | `heightPercentage: 0.5` (50% of available height) |
| **Feature height** | `feature_slot.dart` `_buildHomeScreenButtonFeature` | `availableHeight * feature.heightPercentage!` or `feature.height ?? 80` |
| **Button width** | `feature_slot.dart` | `double.infinity` (full width of carousel page) |
| **Button margin** | `feature_slot.dart` | `EdgeInsets.symmetric(horizontal: 16, vertical: 8)` |
| **Button padding** | `feature_contracts.dart` + `feature_slot.dart` | `feature.padding ?? EdgeInsets.symmetric(horizontal: 48, vertical: 32)` |
| **Text container padding** | `feature_slot.dart` | `EdgeInsets.symmetric(horizontal: 32, vertical: 24)` |
| **Default text size** | `feature_slot.dart` | `fontSize: 56` |
| **Carousel height** | `feature_slot.dart` `_HomeScreenCarousel` | `screenHeight * 0.5` (50%) |
| **Carousel item width** | `feature_slot.dart` `PageController` | `viewportFraction: 0.7` (70% of viewport) |
| **Carousel item padding** | `feature_slot.dart` | `EdgeInsets.symmetric(horizontal: 8.0)` |
| **Arrow buttons** | `feature_slot.dart` | 48×48 |
| **Home content max width** | `home_screen.dart` | `BoxConstraints(maxWidth: 1000)` |

Text wrapping is achieved by laying out the text label inside a `LayoutBuilder` and giving the text container `width: constraints.maxWidth`, with `Text(..., softWrap: true)`.

## Related Files

- `lib/core/widgets/feature_slot.dart` - Feature rendering widget (includes `_HomeScreenCarousel`, `_buildHomeScreenButtonFeature`)
- `lib/modules/dutch_game/managers/feature_registry_manager.dart` - Feature registry
- `lib/modules/dutch_game/managers/feature_contracts.dart` - Feature descriptors
- `lib/modules/dutch_game/screens/home_screen/features/home_screen_features.dart` - Home screen feature registration
- `lib/modules/home_module/home_screen.dart` - Home screen implementation
- `lib/core/00_base/screen_base.dart` - BaseScreen with feature helpers

## Recent Updates

### 2026-01-31 - Carousel and button layout
- **Changed**: Carousel viewport fraction 60% → 70% (`viewportFraction: 0.7`)
- **Changed**: Button content uses full width of parent (`width: double.infinity` on inner container)
- **Changed**: Button text wraps; text area uses `LayoutBuilder` and `width: constraints.maxWidth` with `softWrap: true`

### 2025-01-XX - Carousel implementation
- **Added**: Swipeable carousel mode for home screen buttons
- **Added**: Navigation arrows (left/right) with visual feedback
- **Added**: Opacity transitions (100% current, 50% adjacent)
- **Added**: 1000px max width constraint for home screen content
- **Changed**: Scope key from `'home_screen_main'` to `'HomeScreen'`
- **Changed**: Buttons use 70% viewport width in carousel
- **Changed**: Automatic priority-based sorting and initial page selection

## Future Improvements

1. **Animation Support**: Enhanced entrance/exit animations for carousel items
2. **State-Aware Buttons**: Support buttons that update based on state
3. **Badge Support**: Add badge indicators to buttons
4. **Accessibility**: Enhanced accessibility features for carousel navigation
5. **Analytics**: Built-in analytics tracking for button taps and carousel interactions
6. **Indicators**: Add page indicators (dots) to show current position
7. **Auto-play**: Optional auto-advancing carousel mode

---

**Last Updated**: 2026-01-31

