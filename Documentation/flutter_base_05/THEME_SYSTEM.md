# Flutter Base 05 - Theme System Documentation

## Overview

The Flutter Base 05 application uses a comprehensive, centralized theme system that provides dynamic, theme-aware styling throughout the application. The theme system is designed to be:

- **Centralized**: All theme constants are defined in a single file (`lib/utils/consts/theme_consts.dart`)
- **Dynamic**: Colors and styles automatically adapt based on the selected theme preset
- **Consistent**: Enforces uniform styling across all screens and widgets
- **Maintainable**: Easy to modify themes and add new theme presets
- **Type-safe**: Uses Flutter's type system to prevent styling errors

## Table of Contents

1. [Architecture](#architecture)
2. [Theme Presets](#theme-presets)
3. [Color System](#color-system)
4. [Text Styles](#text-styles)
5. [Padding Constants](#padding-constants)
6. [Theme Configuration](#theme-configuration)
7. [Usage Examples](#usage-examples)
8. [Best Practices](#best-practices)
9. [Migration Guide](#migration-guide)

---

## Architecture

The theme system is built on a layered architecture:

```
ThemePreset (enum)
    ↓
ThemeConfig (class)
    ↓
AppColors (class) → AppTextStyles (class) → AppPadding (class)
    ↓
AppTheme (class) → Flutter ThemeData
```

### Key Components

1. **`ThemePreset`**: Enum defining available theme options
2. **`ThemeConfig`**: Core configuration class that generates colors based on the selected preset
3. **`AppColors`**: Public API for accessing theme-aware colors
4. **`AppTextStyles`**: Public API for accessing consistent text styles
5. **`AppPadding`**: Static constants for consistent spacing
6. **`AppTheme`**: Flutter `ThemeData` configuration

### File Location

All theme constants are defined in:
```
lib/utils/consts/theme_consts.dart
```

---

## Theme Presets

The application supports multiple theme presets, each with its own color palette:

### Available Presets

```dart
enum ThemePreset {
  defaultTheme,  // Brown/gold theme
  blue,          // Blue theme
  red,           // Red theme
  green,         // Green theme
  purple,        // Purple theme
  orange,        // Orange theme
  teal,          // Teal theme
}
```

### Current Theme

The active theme is controlled by:
```dart
ThemeConfig.currentTheme = ThemePreset.blue; // Change this to switch themes
```

### Theme Color Palettes

Each preset defines:
- **Primary Color**: Main brand color (dark)
- **Accent Color**: Highlight color (medium brightness)
- **Accent Color 2**: Secondary highlight (lighter)
- **Scaffold Background**: Main screen background (dark)

#### Example: Blue Theme
- Primary: `#1E3A5F` (Dark blue)
- Accent: `#4A90E2` (Medium blue)
- Accent 2: `#6BB6FF` (Light blue)
- Background: `#1A2332` (Very dark blue)

---

## Color System

### AppColors Class

The `AppColors` class provides a unified interface for accessing all colors in the application. All colors are theme-aware and automatically adapt to the selected theme preset.

#### Base Theme Colors

```dart
AppColors.primaryColor          // Main brand color
AppColors.accentColor          // Primary accent/highlight
AppColors.accentColor2         // Secondary accent
AppColors.scaffoldBackgroundColor  // Main screen background
```

#### Neutral Colors (Theme-Independent)

```dart
AppColors.white                // Pure white
AppColors.black                // Pure black
AppColors.darkGray             // #333333
AppColors.lightGray           // #B0BEC5
```

#### Semantic Colors

```dart
AppColors.successColor         // Green for success states
AppColors.errorColor           // Red for errors
AppColors.warningColor         // Orange for warnings
AppColors.infoColor            // Blue for informational messages
AppColors.redAccent            // Alias for errorColor
```

#### Player Status Colors

```dart
AppColors.statusWaiting        // Grey - waiting status
AppColors.statusReady          // Blue - ready status
AppColors.statusDrawing        // Orange - drawing card status
AppColors.statusPlaying        // Green - playing card status
AppColors.statusSameRank       // Purple - same rank window status
AppColors.statusQueenPeek      // Pink - queen peek status
AppColors.statusJackSwap       // Indigo - jack swap status
AppColors.statusPeeking        // Cyan - peeking status
AppColors.statusInitialPeek   // Teal - initial peek status
AppColors.statusWinner         // Green - winner status
AppColors.statusFinished       // Red - finished status
```

**Note**: These colors are used by `PlayerStatusChip` and for current player highlighting in the opponents panel. They provide consistent, theme-aware status indication throughout the game.

#### State Colors

```dart
AppColors.disabledColor        // For disabled UI elements
AppColors.hoverColor           // For hover states
AppColors.pressedColor         // For pressed states
AppColors.focusedColor         // For focused elements
```

#### Border Colors

```dart
AppColors.borderDefault        // Default border color
AppColors.borderFocused        // Focused border color
AppColors.borderError          // Error border color
AppColors.borderSuccess        // Success border color
```

#### Background Variants

```dart
AppColors.surface              // White surface
AppColors.surfaceVariant       // Light gray variant (10% opacity)
AppColors.card                 // White card background
AppColors.cardVariant          // Primary color variant (5% opacity)
AppColors.widgetContainerBackground  // Lightened scaffold background (5% white blend)
```

#### Text Colors

```dart
AppColors.textPrimary          // Primary text color (dark gray)
AppColors.textSecondary        // Secondary text color (light gray)
AppColors.textTertiary         // Tertiary text color (lighter gray, 70% opacity)
AppColors.textOnPrimary        // Text color for primary backgrounds
AppColors.textOnAccent         // Text color for accent backgrounds
AppColors.textOnSurface        // Text color for surface backgrounds
AppColors.textOnCard           // Text color for card backgrounds
```

### Usage Examples

```dart
// Container with theme-aware background
Container(
  color: AppColors.scaffoldBackgroundColor,
  child: Text('Hello', style: TextStyle(color: AppColors.textPrimary)),
)

// Widget container with lightened background
Container(
  decoration: BoxDecoration(
    color: AppColors.widgetContainerBackground,
    borderRadius: BorderRadius.circular(12),
  ),
  child: ...,
)

// Button with accent color
ElevatedButton(
  style: ElevatedButton.styleFrom(
    backgroundColor: AppColors.accentColor,
    foregroundColor: AppColors.textOnAccent,
  ),
  child: Text('Click me'),
)
```

---

## Text Styles

### AppTextStyles Class

The `AppTextStyles` class provides consistent typography throughout the application. All text styles are functions that return `TextStyle` objects and can optionally accept a custom color parameter.

#### Heading Styles

```dart
AppTextStyles.headingLarge({Color? color})   // 28px, bold, accent color
AppTextStyles.headingMedium({Color? color}) // 24px, w600, accent color
AppTextStyles.headingSmall({Color? color})  // 20px, w500, accent color
```

#### Body Text Styles

```dart
AppTextStyles.bodySmall({Color? color})     // 12px, textSecondary
AppTextStyles.bodyMedium({Color? color})    // 16px, textOnPrimary
AppTextStyles.bodyLarge({Color? color})     // 18px, textSecondary
```

#### Specialized Text Styles

```dart
AppTextStyles.caption({Color? color})       // 12px, textSecondary
AppTextStyles.overline({Color? color})      // 10px, textTertiary, w500
AppTextStyles.label({Color? color})         // 14px, textSecondary, w500
AppTextStyles.buttonText({Color? color})    // 18px, textOnAccent, w600
```

#### Semantic Text Styles

```dart
AppTextStyles.successText({Color? color})   // 16px, successColor
AppTextStyles.errorText({Color? color})     // 16px, errorColor
AppTextStyles.warningText({Color? color})   // 16px, warningColor
AppTextStyles.infoText({Color? color})      // 16px, infoColor
```

### Usage Examples

```dart
// Basic heading
Text(
  'Welcome',
  style: AppTextStyles.headingLarge(),
)

// Heading with custom color
Text(
  'Custom Heading',
  style: AppTextStyles.headingSmall().copyWith(color: AppColors.errorColor),
)

// Body text
Text(
  'This is body text',
  style: AppTextStyles.bodyMedium(),
)

// Label text
Text(
  'Form Label',
  style: AppTextStyles.label(),
)

// Semantic text
Text(
  'Success!',
  style: AppTextStyles.successText(),
)
```

### Important Notes

- **Always call as functions**: `AppTextStyles.headingSmall()` not `AppTextStyles.headingSmall`
- **Use `copyWith` for modifications**: `AppTextStyles.bodyMedium().copyWith(fontWeight: FontWeight.bold)`
- **Avoid hardcoded styles**: Never use `TextStyle(fontSize: 16)` directly

---

## Padding Constants

### AppPadding Class

The `AppPadding` class provides consistent spacing values throughout the application. All padding values are static constants.

#### Available Padding Constants

```dart
AppPadding.defaultPadding    // EdgeInsets.all(16.0)
AppPadding.cardPadding        // EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0)
AppPadding.screenPadding      // EdgeInsets.all(24.0)
AppPadding.smallPadding       // EdgeInsets.all(8.0)
AppPadding.mediumPadding      // EdgeInsets.all(12.0)
AppPadding.largePadding       // EdgeInsets.all(20.0)
```

### Usage Examples

```dart
// Container padding
Container(
  padding: AppPadding.cardPadding,
  child: ...,
)

// Widget spacing
Column(
  children: [
    Widget1(),
    SizedBox(height: AppPadding.smallPadding.top),
    Widget2(),
    SizedBox(height: AppPadding.defaultPadding.top),
    Widget3(),
  ],
)

// Screen padding
SingleChildScrollView(
  padding: AppPadding.screenPadding,
  child: ...,
)
```

---

## Theme Configuration

### AppTheme Class

The `AppTheme` class provides a pre-configured Flutter `ThemeData` object that applies the theme system to all Material widgets.

#### Usage

```dart
MaterialApp(
  theme: AppTheme.darkTheme,
  // ... rest of app configuration
)
```

#### Configured Components

The `AppTheme.darkTheme` automatically configures:

- **Primary Colors**: Uses `AppColors.primaryColor`
- **Scaffold Background**: Uses `AppColors.scaffoldBackgroundColor`
- **Text Theme**: Applies global text styles
- **Button Themes**: Configures `TextButton` and `ElevatedButton` styles
- **Input Decoration Theme**: Styles all `TextField` widgets
- **Text Selection Theme**: Configures cursor and selection colors
- **Drawer Theme**: Styles the navigation drawer
- **Navigation Bar Theme**: Styles bottom navigation
- **Divider Theme**: Styles dividers
- **Icon Theme**: Styles icons

---

## Usage Examples

### Complete Widget Example

```dart
import 'package:flutter/material.dart';
import '../../../../utils/consts/theme_consts.dart';

class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: AppPadding.smallPadding.left),
      decoration: BoxDecoration(
        color: AppColors.widgetContainerBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: AppPadding.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Widget Title',
              style: AppTextStyles.headingSmall(),
            ),
            SizedBox(height: AppPadding.defaultPadding.top),
            Text(
              'Widget description text',
              style: AppTextStyles.bodyMedium(),
            ),
            SizedBox(height: AppPadding.defaultPadding.top),
            ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentColor,
                foregroundColor: AppColors.textOnAccent,
              ),
              child: Text(
                'Action Button',
                style: AppTextStyles.buttonText(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

### Screen Layout Example

```dart
@override
Widget buildContent(BuildContext context) {
  return SingleChildScrollView(
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MyWidget1(),
        SizedBox(height: AppPadding.smallPadding.top),
        MyWidget2(),
        SizedBox(height: AppPadding.smallPadding.top),
        MyWidget3(),
      ],
    ),
  );
}
```

### Form Field Example

```dart
TextField(
  decoration: InputDecoration(
    labelText: 'Email',
    hintText: 'Enter your email',
    // Theme is automatically applied via AppTheme.darkTheme
  ),
  style: AppTextStyles.bodyMedium(),
)
```

---

## Best Practices

### ✅ DO

1. **Always use theme constants**:
   ```dart
   // ✅ Correct
   color: AppColors.primaryColor
   style: AppTextStyles.headingSmall()
   padding: AppPadding.cardPadding
   
   // ❌ Incorrect
   color: Color(0xFF41282F)
   style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)
   padding: EdgeInsets.all(16)
   ```

2. **Use appropriate text styles for hierarchy**:
   ```dart
   // ✅ Correct
   Text('Title', style: AppTextStyles.headingSmall())
   Text('Body', style: AppTextStyles.bodyMedium())
   Text('Label', style: AppTextStyles.label())
   
   // ❌ Incorrect
   Text('Title', style: AppTextStyles.bodyLarge().copyWith(fontWeight: FontWeight.bold))
   ```

3. **Use widgetContainerBackground for widget containers**:
   ```dart
   // ✅ Correct
   Container(
     decoration: BoxDecoration(
       color: AppColors.widgetContainerBackground,
       borderRadius: BorderRadius.circular(12),
     ),
   )
   ```

4. **Use consistent spacing**:
   ```dart
   // ✅ Correct
   SizedBox(height: AppPadding.smallPadding.top)
   SizedBox(height: AppPadding.defaultPadding.top)
   ```

5. **Call text style functions properly**:
   ```dart
   // ✅ Correct
   style: AppTextStyles.headingSmall()
   style: AppTextStyles.bodyMedium().copyWith(color: AppColors.errorColor)
   
   // ❌ Incorrect
   style: AppTextStyles.headingSmall  // Missing parentheses
   ```

### ❌ DON'T

1. **Don't hardcode colors**:
   ```dart
   // ❌ Wrong
   color: Colors.blue
   color: Color(0xFF2196F3)
   color: Colors.white.withOpacity(0.2)
   
   // ✅ Correct
   color: AppColors.infoColor
   color: AppColors.widgetContainerBackground
   ```

2. **Don't hardcode text styles**:
   ```dart
   // ❌ Wrong
   TextStyle(fontSize: 20, fontWeight: FontWeight.bold)
   Theme.of(context).textTheme.headlineMedium
   
   // ✅ Correct
   AppTextStyles.headingSmall()
   ```

3. **Don't hardcode padding**:
   ```dart
   // ❌ Wrong
   padding: EdgeInsets.all(16)
   padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16)
   
   // ✅ Correct
   padding: AppPadding.defaultPadding
   padding: AppPadding.cardPadding
   ```

4. **Don't use `withOpacity`**:
   ```dart
   // ❌ Wrong (deprecated)
   color: AppColors.primaryColor.withOpacity(0.8)
   
   // ✅ Correct
   color: AppColors.primaryColor.withValues(alpha: 0.8)
   // Or better: use existing constants like widgetContainerBackground
   ```

5. **Don't use `const` with dynamic theme values**:
   ```dart
   // ❌ Wrong
   const Text('Hello', style: AppTextStyles.headingSmall())
   const Container(color: AppColors.primaryColor)
   
   // ✅ Correct
   Text('Hello', style: AppTextStyles.headingSmall())
   Container(color: AppColors.primaryColor)
   ```

---

## Migration Guide

### Migrating Existing Code

If you have existing code that uses hardcoded values, follow these steps:

#### Step 1: Replace Colors

```dart
// Before
Container(color: Colors.blue)
Text('Hello', style: TextStyle(color: Colors.white))

// After
Container(color: AppColors.infoColor)
Text('Hello', style: TextStyle(color: AppColors.white))
```

#### Step 2: Replace Text Styles

```dart
// Before
Text('Title', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))
Text('Body', style: Theme.of(context).textTheme.bodyLarge)

// After
Text('Title', style: AppTextStyles.headingSmall())
Text('Body', style: AppTextStyles.bodyLarge())
```

#### Step 3: Replace Padding

```dart
// Before
padding: EdgeInsets.all(16)
SizedBox(height: 20)

// After
padding: AppPadding.defaultPadding
SizedBox(height: AppPadding.largePadding.top)
```

#### Step 4: Replace Card Widgets

```dart
// Before
Card(
  child: Padding(
    padding: EdgeInsets.all(16),
    child: ...,
  ),
)

// After
Container(
  margin: EdgeInsets.symmetric(horizontal: AppPadding.smallPadding.left),
  decoration: BoxDecoration(
    color: AppColors.widgetContainerBackground,
    borderRadius: BorderRadius.circular(12),
  ),
  child: Padding(
    padding: AppPadding.cardPadding,
    child: ...,
  ),
)
```

---

## Advanced Usage

### Custom Color Overrides

You can override colors in text styles:

```dart
Text(
  'Custom Color Text',
  style: AppTextStyles.headingSmall().copyWith(
    color: AppColors.errorColor,
  ),
)
```

### Dynamic Theme Switching

To switch themes programmatically:

```dart
// Change theme
ThemeConfig.currentTheme = ThemePreset.red;

// Trigger rebuild (if needed)
setState(() {});
```

### Creating Custom Widget Styles

For reusable widget patterns:

```dart
class ThemedCard extends StatelessWidget {
  final Widget child;
  
  const ThemedCard({required this.child});
  
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: AppPadding.smallPadding.left),
      decoration: BoxDecoration(
        color: AppColors.widgetContainerBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: AppPadding.cardPadding,
        child: child,
      ),
    );
  }
}
```

---

## Theme System Architecture Details

### Color Generation Flow

1. **Theme Selection**: `ThemeConfig.currentTheme` determines the active preset
2. **Color Generation**: `ThemeConfig` methods generate colors based on the preset
3. **Color Access**: `AppColors` delegates to `ThemeConfig` for theme-aware colors
4. **Text Color Calculation**: `ThemeConfig.getTextColorForBackground()` calculates appropriate text colors based on background luminance

### Text Color Adaptation

The system automatically calculates appropriate text colors:

```dart
// Automatically returns white for dark backgrounds, dark for light backgrounds
ThemeConfig.getTextColorForBackground(Color backgroundColor)
```

This ensures text is always readable regardless of the background color.

### Widget Container Background

The `widgetContainerBackground` color is dynamically generated by blending the scaffold background with white:

```dart
Color.lerp(scaffoldBackgroundColor, Colors.white, 0.05)
```

This creates a subtle lightening effect (5% blend) that provides visual separation while maintaining theme consistency.

---

## File Structure

```
lib/utils/consts/
└── theme_consts.dart          # All theme constants and configuration
```

---

## Felt Texture Widget

### Overview

The `FeltTextureWidget` provides a reusable felt texture effect that simulates the grainy appearance of felt material. This is commonly used for poker table backgrounds and other surfaces that need a textured appearance.

### Location

```dart
lib/utils/widgets/felt_texture_widget.dart
```

### Basic Usage

```dart
import '../../../../utils/widgets/felt_texture_widget.dart';

FeltTextureWidget(
  backgroundColor: AppColors.pokerTableGreen,
)
```

### Parameters

The `FeltTextureWidget` accepts the following configurable parameters:

#### Required Parameters

- **`backgroundColor`** (`Color`): The base color that shows through the texture
  ```dart
  backgroundColor: AppColors.pokerTableGreen
  ```

#### Optional Parameters

- **`seed`** (`int`, default: `42`): Random seed for consistent texture pattern
  - Use different seeds to generate different patterns
  - Same seed always produces the same pattern
  ```dart
  seed: 42  // Default - consistent pattern
  seed: 100 // Different pattern
  ```

- **`pointDensity`** (`double`, default: `0.15`): Multiplier for grain point density
  - Range: `0.1` (sparse) to `0.3` (dense)
  - Formula: `pointCount = width * height * pointDensity`
  ```dart
  pointDensity: 0.15  // Default - medium density
  pointDensity: 0.1   // Sparse texture
  pointDensity: 0.25  // Dense texture
  ```

- **`opacityRange`** (`FeltOpacityRange`, default: `FeltOpacityRange(min: 0.1, max: 0.4)`): Opacity range for grain points
  - Each grain point gets a random opacity within this range
  ```dart
  opacityRange: FeltOpacityRange(min: 0.1, max: 0.4)  // Default
  opacityRange: FeltOpacityRange(min: 0.2, max: 0.5)  // More visible
  opacityRange: FeltOpacityRange(min: 0.05, max: 0.2) // Subtle
  ```

- **`grainColor`** (`Color`, default: `Colors.black`): Color of the grain points
  ```dart
  grainColor: Colors.black  // Default
  grainColor: Colors.white  // Light texture on dark background
  grainColor: AppColors.primaryColor  // Themed texture
  ```

- **`grainRadius`** (`double`, default: `0.5`): Radius of each grain point in pixels
  ```dart
  grainRadius: 0.5  // Default - fine grain
  grainRadius: 1.0  // Larger grain
  grainRadius: 0.3  // Finer grain
  ```

- **`strokeWidth`** (`double`, default: `0.5`): Stroke width for grain points
  ```dart
  strokeWidth: 0.5  // Default
  strokeWidth: 1.0  // Thicker strokes
  ```

### Complete Example

```dart
// Default felt texture (poker table style)
FeltTextureWidget(
  backgroundColor: AppColors.pokerTableGreen,
)

// Custom felt texture with different parameters
FeltTextureWidget(
  backgroundColor: AppColors.scaffoldBackgroundColor,
  seed: 100,
  pointDensity: 0.2,
  opacityRange: FeltOpacityRange(min: 0.15, max: 0.5),
  grainColor: Colors.white,
  grainRadius: 0.8,
  strokeWidth: 0.6,
)

// Subtle texture for card backgrounds
FeltTextureWidget(
  backgroundColor: AppColors.card,
  pointDensity: 0.08,
  opacityRange: FeltOpacityRange(min: 0.05, max: 0.15),
  grainRadius: 0.3,
)
```

### Performance Considerations

- **Caching**: The texture pattern is cached and only regenerated when:
  - Size changes
  - Any parameter changes
  - Different seed is used
  
- **Repaint Optimization**: Uses `RepaintBoundary` in the widget to minimize repaints

- **Point Count**: Higher `pointDensity` values increase the number of points and may impact performance on very large surfaces

### Best Practices

1. **Use consistent seeds** for the same surface type to maintain visual consistency
2. **Adjust pointDensity** based on surface size - larger surfaces may need lower density
3. **Match grainColor** to the background for subtle effects, or use contrasting colors for more visible texture
4. **Consider opacity range** - wider ranges create more variation, narrower ranges create more uniform texture

### FeltOpacityRange Class

```dart
class FeltOpacityRange {
  final double min;  // Minimum opacity (0.0 to 1.0)
  final double max;  // Maximum opacity (0.0 to 1.0)
  
  const FeltOpacityRange({
    required this.min,
    required this.max,
  });
}
```

**Constraints:**
- `min` and `max` must be between 0.0 and 1.0
- `min` must be less than or equal to `max`

---

## Related Documentation

- [ARCHITECTURE.md](./ARCHITECTURE.md) - Overall application architecture
- [STATE_MANAGEMENT_SYSTEM.md](./STATE_MANAGEMENT_SYSTEM.md) - State management patterns

---

## Summary

The Flutter Base 05 theme system provides:

- ✅ **7 theme presets** with distinct color palettes
- ✅ **50+ color constants** covering all UI needs
- ✅ **12 text style functions** for consistent typography
- ✅ **6 padding constants** for consistent spacing
- ✅ **Automatic text color adaptation** for readability
- ✅ **Centralized configuration** in a single file
- ✅ **Type-safe API** preventing styling errors
- ✅ **Easy theme switching** via enum change
- ✅ **Reusable felt texture widget** with configurable parameters

By following this system, developers can create consistent, maintainable, and beautiful UIs that automatically adapt to theme changes.
