import 'package:flutter/material.dart';

/// Card size options for the Dutch game
enum CardSize {
  small,
  medium,
  large,
  extraLarge,
}

/// Theme preset options - change this to switch themes
enum ThemePreset {
  defaultTheme, // Current brown/gold theme
  blue,
  red,
  green,
  purple,
  orange,
  teal,
  magenta, // New magenta/purple theme (#7C3358)
  dutch, // Dutch game branding theme (olive-green #6B9950)
}

/// Theme configuration that generates colors based on preset
class ThemeConfig {
  static ThemePreset currentTheme = ThemePreset.dutch;

  /// Get primary color based on current theme
  static Color get primaryColor {
    switch (currentTheme) {
      case ThemePreset.blue:
        return const Color(0xFF1E3A5F);
      case ThemePreset.magenta:
        return const Color(0xFF7C3358);
      case ThemePreset.red:
        return const Color(0xFF5F1E1E);
      case ThemePreset.green:
        return const Color(0xFF1E5F3A);
      case ThemePreset.purple:
        return const Color(0xFF4A1E5F);
      case ThemePreset.orange:
        return const Color(0xFF5F3A1E);
      case ThemePreset.teal:
        return const Color(0xFF1E5F5F);
      case ThemePreset.defaultTheme:
        return const Color(0xFF41282F); // Current brown
      case ThemePreset.dutch:
        return const Color(0xFF6B9950); // Dutch branding olive-green
    }
  }

  /// Get accent color - auto-generated based on primary
  static Color get accentColor {
    switch (currentTheme) {
      case ThemePreset.blue:
        return const Color(0xFF4A90E2);
      case ThemePreset.red:
        return const Color(0xFFE24A4A);
      case ThemePreset.green:
        return const Color(0xFF4AE24A);
      case ThemePreset.purple:
        return const Color(0xFF904AE2);
      case ThemePreset.orange:
        return const Color(0xFFE2904A);
      case ThemePreset.teal:
        return const Color(0xFF4AE2E2);
      case ThemePreset.magenta:
        return const Color(0xFFF4A147); // Orange accent
      case ThemePreset.defaultTheme:
        return const Color.fromARGB(255, 120, 67, 82); // Current
      case ThemePreset.dutch:
        return const Color(0xFF8BC34A); // Lighter green accent for Dutch theme
    }
  }

  /// Get secondary accent color
  static Color get accentColor2 {
    switch (currentTheme) {
      case ThemePreset.blue:
        return const Color(0xFF6BB6FF);
      case ThemePreset.red:
        return const Color(0xFFFF6B6B);
      case ThemePreset.green:
        return const Color(0xFF6BFF6B);
      case ThemePreset.purple:
        return const Color(0xFFB66BFF);
      case ThemePreset.orange:
        return const Color(0xFFFFB66B);
      case ThemePreset.teal:
        return const Color(0xFF6BFFFF);
      case ThemePreset.magenta:
        return const Color(0xFFD47BA3); // Even lighter magenta for secondary accent
      case ThemePreset.defaultTheme:
        return const Color(0xFFFBC02D); // Current gold
      case ThemePreset.dutch:
        return const Color(0xFFAED581); // Light green secondary accent for Dutch theme
    }
  }

  /// Get scaffold background color
  static Color get scaffoldBackgroundColor {
    switch (currentTheme) {
      case ThemePreset.blue:
        return const Color(0xFF1A2332);
      case ThemePreset.red:
        return const Color(0xFF2A1F1F);
      case ThemePreset.green:
        return const Color(0xFF1F2A1F);
      case ThemePreset.purple:
        return const Color(0xFF2A1F2A);
      case ThemePreset.orange:
        return const Color(0xFF2A251F);
      case ThemePreset.teal:
        return const Color(0xFF1F2A2A);
      case ThemePreset.magenta:
        return const Color(0xFF2A1F25); // Dark background with magenta tint
      case ThemePreset.defaultTheme:
        return const Color(0xFF1F1A1A); // Dark background
      case ThemePreset.dutch:
        return const Color(0xFF2A3A1F); // Dark green-tinted background for Dutch theme
    }
  }

  /// Semantic colors - auto-adjusted based on theme
  static Color get successColor {
    // Green variant that complements the theme
    switch (currentTheme) {
      case ThemePreset.green:
        return const Color(0xFF4CAF50);
      default:
        return const Color(0xFF4CAF50); // Standard green
    }
  }

  static Color get errorColor {
    // Red variant that complements the theme
    switch (currentTheme) {
      case ThemePreset.red:
        return const Color(0xFFE53935);
      default:
        return const Color(0xFFE53935); // Standard red
    }
  }

  static Color get warningColor {
    // Orange variant that complements the theme
    switch (currentTheme) {
      case ThemePreset.orange:
        return const Color(0xFFFF9800);
      default:
        return const Color(0xFFFF9800); // Standard orange
    }
  }

  static Color get infoColor {
    // Blue variant that complements the theme
    switch (currentTheme) {
      case ThemePreset.blue:
        return const Color(0xFF2196F3);
      default:
        return const Color(0xFF2196F3); // Standard blue
    }
  }

  // Player status colors - theme-aware status colors
  static Color get statusWaiting => const Color(0xFF9E9E9E); // Grey
  static Color get statusReady => const Color(0xFF2196F3); // Blue (uses infoColor)
  static Color get statusDrawing => const Color(0xFFFF9800); // Orange (uses warningColor)
  static Color get statusPlaying => const Color(0xFF4CAF50); // Green (uses successColor)
  static Color get statusSameRank => const Color(0xFF4CAF50);  // Green (uses successColor)
  static Color get statusQueenPeek => const Color(0xFFE91E63); // Pink
  static Color get statusJackSwap => const Color(0xFF00BCD4); // Cyan
  static Color get statusPeeking => const Color(0xFFD131A6); // Pink/Magenta
  static Color get statusInitialPeek => const Color(0xFFD131A6); // Pink/Magenta
  static Color get statusWinner => const Color(0xFF4CAF50); // Green (uses successColor)
  static Color get statusFinished => const Color(0xFFE53935); // Red (uses errorColor)

  /// Calculate text color for a given background color
  static Color getTextColorForBackground(Color backgroundColor) {
    final luminance = backgroundColor.computeLuminance();
    // Return dark text for light backgrounds, light text for dark backgrounds
    // Use direct color constants to avoid circular dependency
    return luminance > 0.5 ? const Color(0xFF333333) : Colors.white;
  }

  /// Get text color for primary background
  static Color getTextColorForPrimary() {
    return getTextColorForBackground(primaryColor);
  }

  /// Get text color for accent background
  static Color getTextColorForAccent() {
    return getTextColorForBackground(accentColor);
  }

  /// Get casino border color - brownish accent for casino table borders
  static Color get casinoBorderColor {
    // Rich brown color that works well for casino table edges
    return const Color(0xFF8B6F47); // Warm brown/sienna color
  }

  /// Get casino outer border color - dark gray/charcoal for outer table edge
  static Color get casinoOuterBorderColor {
    // Dark gray/charcoal color for the outer border layer
    return const Color(0xFF2C2C2C); // Dark charcoal gray
  }
}

/// App colors - now theme-aware and dynamic
class AppColors {
  // Base theme colors
  static Color get primaryColor => ThemeConfig.primaryColor;
  static Color get accentColor => ThemeConfig.accentColor;
  static Color get accentColor2 => ThemeConfig.accentColor2;
  static Color get scaffoldBackgroundColor => ThemeConfig.scaffoldBackgroundColor;

  // Neutral colors (theme-independent)
  static const Color white = Colors.white;
  static const Color black = Colors.black;
  static const Color darkGray = Color(0xFF333333);
  static const Color lightGray = Color(0xFFB0BEC5);

  // Semantic colors
  static Color get successColor => ThemeConfig.successColor;
  static Color get errorColor => ThemeConfig.errorColor;
  static Color get warningColor => ThemeConfig.warningColor;
  static Color get infoColor => ThemeConfig.infoColor;
  static Color get redAccent => ThemeConfig.errorColor;

  // Player status colors (for status chips and player highlighting)
  static Color get statusWaiting => ThemeConfig.statusWaiting;
  static Color get statusReady => ThemeConfig.statusReady;
  static Color get statusDrawing => ThemeConfig.statusDrawing;
  static Color get statusPlaying => ThemeConfig.statusPlaying;
  static Color get statusSameRank => ThemeConfig.statusSameRank;
  static Color get statusQueenPeek => ThemeConfig.statusQueenPeek;
  static Color get statusJackSwap => ThemeConfig.statusJackSwap;
  static Color get statusPeeking => ThemeConfig.statusPeeking;
  static Color get statusInitialPeek => ThemeConfig.statusInitialPeek;
  static Color get statusWinner => ThemeConfig.statusWinner;
  static Color get statusFinished => ThemeConfig.statusFinished;

  // State colors
  static Color get disabledColor => lightGray.withOpacity(0.5);
  static Color get hoverColor => primaryColor.withOpacity(0.1);
  static Color get pressedColor => primaryColor.withOpacity(0.2);
  static Color get focusedColor => accentColor;

  // Border colors
  static Color get borderDefault => lightGray;
  static Color get borderFocused => accentColor;
  static Color get borderError => errorColor;
  static Color get borderSuccess => successColor;

  // Background variants
  static Color get surface => white;
  static Color get surfaceVariant => lightGray.withOpacity(0.1);
  static Color get card => white;
  static Color get cardVariant => primaryColor.withOpacity(0.05);
  static Color get widgetContainerBackground => Color.lerp(
    scaffoldBackgroundColor,
    Colors.white,
    0.05,
  ) ?? scaffoldBackgroundColor;
  
  // Poker table green for game screens
  static const Color pokerTableGreen = Color.fromARGB(255, 18, 109, 79); // Dark green similar to poker table felt

  // Casino border colors - for layered casino table borders
  static Color get casinoBorderColor => ThemeConfig.casinoBorderColor;
  static Color get casinoOuterBorderColor => ThemeConfig.casinoOuterBorderColor;

  // Warm spotlight color for casino table lighting effects
  static const Color warmSpotlightColor = Color(0xFFFFD4A3); // Warm amber/peach color

  /// Gold for winning pot / coins — theme-independent so it stays gold in every theme (e.g. Dutch green).
  static const Color matchPotGold = Color(0xFFFBC02D); // Material amber 300 / gold

  // Text color variants
  static Color get textPrimary => darkGray;
  static Color get textSecondary => lightGray;
  static Color get textTertiary => lightGray.withOpacity(0.7);
  static Color get textOnPrimary => ThemeConfig.getTextColorForPrimary();
  static Color get textOnAccent => ThemeConfig.getTextColorForAccent();
  static Color get textOnSurface => textPrimary;
  static Color get textOnCard => textPrimary;
}

class AppBackgrounds {
  static const List<String> backgrounds = [
    // Background images temporarily removed
  ];
}

class AppTextStyles {
  // Heading Styles with theme-aware colors
  static TextStyle headingLarge({Color? color}) {
    return TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.bold,
      color: color ?? AppColors.accentColor,
    );
  }

  static TextStyle headingMedium({Color? color}) {
    return TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      color: color ?? AppColors.accentColor,
    );
  }

  static TextStyle headingSmall({Color? color}) {
    return TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w500,
      color: color ?? AppColors.accentColor,
    );
  }

  // Body Text with theme-aware colors
  static TextStyle bodySmall({Color? color}) {
    return TextStyle(
      fontSize: 12,
      color: color ?? AppColors.textSecondary,
    );
  }

  static TextStyle bodyMedium({Color? color}) {
    return TextStyle(
      fontSize: 16,
      color: color ?? AppColors.textOnPrimary,
    );
  }

  static TextStyle bodyLarge({Color? color}) {
    return TextStyle(
      fontSize: 18,
      color: color ?? AppColors.textSecondary,
    );
  }

  // Small text styles
  static TextStyle caption({Color? color}) {
    return TextStyle(
      fontSize: 12,
      color: color ?? AppColors.textSecondary,
    );
  }

  static TextStyle overline({Color? color}) {
    return TextStyle(
      fontSize: 10,
      color: color ?? AppColors.textTertiary,
      fontWeight: FontWeight.w500,
    );
  }

  // Label text (for form labels, metadata)
  static TextStyle label({Color? color}) {
    return TextStyle(
      fontSize: 14,
      color: color ?? AppColors.textSecondary,
      fontWeight: FontWeight.w500,
    );
  }

  // Button Text
  static TextStyle buttonText({Color? color}) {
    return TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: color ?? AppColors.textOnAccent,
    );
  }

  // Semantic text styles
  static TextStyle successText({Color? color}) {
    return TextStyle(
      fontSize: 16,
      color: color ?? AppColors.successColor,
    );
  }

  static TextStyle errorText({Color? color}) {
    return TextStyle(
      fontSize: 16,
      color: color ?? AppColors.errorColor,
    );
  }

  static TextStyle warningText({Color? color}) {
    return TextStyle(
      fontSize: 16,
      color: color ?? AppColors.warningColor,
    );
  }

  static TextStyle infoText({Color? color}) {
    return TextStyle(
      fontSize: 16,
      color: color ?? AppColors.infoColor,
    );
  }
}

class AppPadding {
  static const EdgeInsets defaultPadding = EdgeInsets.all(16.0);
  static const EdgeInsets cardPadding = EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0);
  static const EdgeInsets screenPadding = EdgeInsets.all(24.0);
  static const EdgeInsets smallPadding = EdgeInsets.all(8.0);
  static const EdgeInsets mediumPadding = EdgeInsets.all(12.0);
  static const EdgeInsets largePadding = EdgeInsets.all(20.0);
}

class AppBorderRadius {
  static const double small = 8.0;
  static const double medium = 10.0;
  static const double large = 12.0;
  
  static BorderRadius get smallRadius => BorderRadius.circular(small);
  static BorderRadius get mediumRadius => BorderRadius.circular(medium);
  static BorderRadius get largeRadius => BorderRadius.circular(large);
  
  static BorderRadius only({
    double? topLeft,
    double? topRight,
    double? bottomLeft,
    double? bottomRight,
  }) {
    return BorderRadius.only(
      topLeft: Radius.circular(topLeft ?? 0),
      topRight: Radius.circular(topRight ?? 0),
      bottomLeft: Radius.circular(bottomLeft ?? 0),
      bottomRight: Radius.circular(bottomRight ?? 0),
    );
  }
}

class AppSizes {
  static const double iconSmall = 20.0;
  static const double iconMedium = 24.0;
  static const double iconLarge = 32.0;
  
  static const double shadowBlur = 10.0;
  static const Offset shadowOffset = Offset(0, 4);
  
  static const double modalMargin = 20.0;
  static const double modalMaxWidthPercent = 0.9;
  static const double modalMaxHeightPercent = 0.9;
}

class AppOpacity {
  static const double barrier = 0.54;
  static const double shadow = 0.3;
  static const double subtle = 0.1;
  static const double selection = 0.5;
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData.dark().copyWith(
      primaryColor: AppColors.primaryColor,
      scaffoldBackgroundColor: AppColors.scaffoldBackgroundColor,
      hintColor: AppColors.accentColor,
      cardColor: AppColors.card,

      // Apply Global Text Styles
      textTheme: TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: AppColors.accentColor,
        ),
        bodyMedium: TextStyle(
          fontSize: 16,
          color: AppColors.textOnPrimary,
        ),
        bodyLarge: TextStyle(
          fontSize: 18,
          color: AppColors.textSecondary,
        ),
      ),

      // Buttons: Accent Background
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: AppTextStyles.buttonText(),
          backgroundColor: AppColors.accentColor,
          foregroundColor: AppColors.textOnAccent,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          textStyle: AppTextStyles.buttonText(),
          backgroundColor: AppColors.accentColor,
          foregroundColor: AppColors.textOnAccent,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),

      // Input Fields: Accent Glow + Primary Background
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.primaryColor,
        border: OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.borderDefault),
          borderRadius: BorderRadius.circular(8.0),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.borderFocused),
          borderRadius: BorderRadius.circular(8.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.accentColor2),
          borderRadius: BorderRadius.circular(8.0),
        ),
        errorBorder: OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.borderError),
          borderRadius: BorderRadius.circular(8.0),
        ),
        labelStyle: AppTextStyles.label(),
        hintStyle: AppTextStyles.bodySmall(),
        errorStyle: AppTextStyles.errorText(),
      ),

      // Cursor + Selection Color: Accent Theme
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.accentColor,
        selectionColor: AppColors.accentColor.withOpacity(0.5),
        selectionHandleColor: AppColors.accentColor2,
      ),

      // Drawer & NavigationBar Styles
      drawerTheme: DrawerThemeData(
        backgroundColor: AppColors.scaffoldBackgroundColor,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.primaryColor,
        indicatorColor: AppColors.accentColor2.withOpacity(0.2),
        labelTextStyle: MaterialStateProperty.all(
          AppTextStyles.label(),
        ),
      ),

      // Divider theme
      dividerTheme: DividerThemeData(
        color: AppColors.borderDefault,
        thickness: 1,
      ),

      // Icon theme
      iconTheme: IconThemeData(
        color: AppColors.accentColor,
      ),
    );
  }
}
