# Home Screen Feature System

This document explains the home screen feature system in Flutter Base 05, which allows modules to register full-width buttons with customizable appearance and behavior.

## Overview

The home screen feature system provides a flexible way for modules to dynamically add, remove, and manage full-width buttons on the home screen. The system integrates with the existing `FeatureRegistryManager` and supports priority ordering, custom heights (including percentage-based), images, colors, and text styling.

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

Home screen buttons are rendered as full-width containers with:
- **Background**: Solid color (`backgroundColor`) or image (`imagePath`)
- **Content**: Centered text (horizontally and vertically)
- **Styling**: Custom text style, padding, and height
- **Interaction**: Tap callback (`onTap`)

**Rendering Example**:
```dart
Container(
  width: double.infinity,
  height: calculatedHeight,
  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  decoration: BoxDecoration(
    color: feature.backgroundColor,
    image: feature.imagePath != null
        ? DecorationImage(
            image: AssetImage(feature.imagePath!),
            fit: BoxFit.cover,
          )
        : null,
    borderRadius: BorderRadius.circular(12),
  ),
  child: Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: feature.onTap,
      borderRadius: BorderRadius.circular(12),
      child: Center(
        child: Text(
          feature.text,
          style: feature.textStyle ?? AppTextStyles.headingMedium(),
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

The home screen uses `FeatureSlot` to render registered buttons:

```dart
// In home_screen.dart
FeatureSlot(
  scopeKey: HomeScreenFeatureSlots.scopeKey,
  slotId: HomeScreenFeatureSlots.slotButtons,
)
```

### Feature Slots

**Scope Key**: `'home_screen_main'`

**Slot ID**: `'home_screen_buttons'`

**Constants**:
```dart
class HomeScreenFeatureSlots {
  static const String scopeKey = 'home_screen_main';
  static const String slotButtons = 'home_screen_buttons';
}
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

2. **Priority Management**:
   - Use consistent priority ranges (e.g., 100, 200, 300)
   - Leave gaps for future features
   - Document priority assignments

3. **Styling Consistency**:
   - Use theme constants (`AppColors`, `AppTextStyles`)
   - Maintain consistent button appearance
   - Follow app design guidelines

4. **Lifecycle Management**:
   - Register features in module initialization
   - Unregister features in module disposal
   - Clean up resources properly

5. **Error Handling**:
   - Handle navigation errors gracefully
   - Provide user feedback for failed actions
   - Log errors for debugging

## Related Files

- `lib/core/widgets/feature_slot.dart` - Feature rendering widget
- `lib/modules/dutch_game/managers/feature_registry_manager.dart` - Feature registry
- `lib/modules/dutch_game/managers/feature_contracts.dart` - Feature descriptors
- `lib/modules/dutch_game/screens/home_screen/features/home_screen_features.dart` - Home screen feature registration
- `lib/modules/dutch_game/screens/home_screen/home_screen.dart` - Home screen implementation
- `lib/core/00_base/screen_base.dart` - BaseScreen with feature helpers

## Future Improvements

1. **Animation Support**: Add entrance/exit animations for buttons
2. **State-Aware Buttons**: Support buttons that update based on state
3. **Badge Support**: Add badge indicators to buttons
4. **Accessibility**: Enhanced accessibility features
5. **Analytics**: Built-in analytics tracking for button taps

---

**Last Updated**: 2025-01-XX

