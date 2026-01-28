import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Reusable felt texture widget with configurable parameters
/// Creates a grainy noise effect that simulates felt material
/// 
/// Usage:
/// ```dart
/// FeltTextureWidget(
///   backgroundColor: AppColors.pokerTableGreen,
///   seed: 42,
///   pointDensity: 0.15,
///   opacityRange: FeltOpacityRange(min: 0.1, max: 0.4),
///   grainColor: Colors.black,
///   grainRadius: 0.5,
///   strokeWidth: 0.5,
/// )
/// ```
class FeltTextureWidget extends StatelessWidget {
  /// Background color that shows through the texture
  final Color backgroundColor;
  
  /// Random seed for consistent texture pattern (default: 42)
  /// Use different seeds for different patterns
  final int seed;
  
  /// Point density multiplier (default: 0.15)
  /// Higher values = more grain points (0.1 = sparse, 0.3 = dense)
  final double pointDensity;
  
  /// Opacity range for grain points (default: 0.1 to 0.4)
  final FeltOpacityRange opacityRange;
  
  /// Color of the grain points (default: Colors.black)
  final Color grainColor;
  
  /// Radius of each grain point (default: 0.5)
  final double grainRadius;
  
  /// Stroke width for grain points (default: 0.5)
  final double strokeWidth;
  
  const FeltTextureWidget({
    Key? key,
    required this.backgroundColor,
    this.seed = 42,
    this.pointDensity = 0.15,
    this.opacityRange = const FeltOpacityRange(min: 0.1, max: 0.4),
    this.grainColor = Colors.black,
    this.grainRadius = 0.5,
    this.strokeWidth = 0.5,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          color: backgroundColor,
          child: CustomPaint(
            painter: FeltTexturePainter(
              seed: seed,
              pointDensity: pointDensity,
              opacityRange: opacityRange,
              grainColor: grainColor,
              grainRadius: grainRadius,
              strokeWidth: strokeWidth,
            ),
            size: Size(constraints.maxWidth, constraints.maxHeight),
          ),
        );
      },
    );
  }
}

/// Opacity range configuration for felt texture grain points
class FeltOpacityRange {
  final double min;
  final double max;
  
  const FeltOpacityRange({
    required this.min,
    required this.max,
  }) : assert(min >= 0.0 && min <= 1.0, 'Min opacity must be between 0.0 and 1.0'),
       assert(max >= 0.0 && max <= 1.0, 'Max opacity must be between 0.0 and 1.0'),
       assert(min <= max, 'Min opacity must be less than or equal to max opacity');
}

/// Custom painter for felt texture - creates grainy noise effect
/// Uses seeded random for consistent, stable texture pattern
class FeltTexturePainter extends CustomPainter {
  final int seed;
  final double pointDensity;
  final FeltOpacityRange opacityRange;
  final Color grainColor;
  final double grainRadius;
  final double strokeWidth;
  
  // Cache the generated pattern points to avoid regenerating on every paint
  List<_GrainPoint>? _cachedPoints;
  Size? _cachedSize;
  int? _cachedSeed;
  double? _cachedPointDensity;
  FeltOpacityRange? _cachedOpacityRange;
  
  FeltTexturePainter({
    this.seed = 42,
    this.pointDensity = 0.15,
    this.opacityRange = const FeltOpacityRange(min: 0.1, max: 0.4),
    this.grainColor = Colors.black,
    this.grainRadius = 0.5,
    this.strokeWidth = 0.5,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    // Regenerate pattern only if size or parameters changed
    if (_cachedPoints == null || 
        _cachedSize != size || 
        _cachedSeed != seed ||
        _cachedPointDensity != pointDensity ||
        _cachedOpacityRange != opacityRange) {
      _cachedSize = size;
      _cachedSeed = seed;
      _cachedPointDensity = pointDensity;
      _cachedOpacityRange = opacityRange;
      _cachedPoints = [];
      
      // Reset random with same seed for consistent pattern
      final random = math.Random(seed);
      final pointCount = (size.width * size.height * pointDensity).round();
      
      for (int i = 0; i < pointCount; i++) {
        final opacity = random.nextDouble() * (opacityRange.max - opacityRange.min) + opacityRange.min;
        _cachedPoints!.add(_GrainPoint(
          x: random.nextDouble() * size.width,
          y: random.nextDouble() * size.height,
          opacity: opacity.clamp(0.0, 1.0),
        ));
      }
    }
    
    final paint = Paint()
      ..color = grainColor
      ..strokeWidth = strokeWidth;
    
    // Draw cached pattern
    for (final point in _cachedPoints!) {
      paint.color = grainColor.withValues(alpha: point.opacity);
      canvas.drawCircle(Offset(point.x, point.y), grainRadius, paint);
    }
  }
  
  @override
  bool shouldRepaint(FeltTexturePainter oldDelegate) {
    // Repaint if size or any parameter changed
    return oldDelegate._cachedSize != _cachedSize ||
           oldDelegate.seed != seed ||
           oldDelegate.pointDensity != pointDensity ||
           oldDelegate.opacityRange != opacityRange ||
           oldDelegate.grainColor != grainColor ||
           oldDelegate.grainRadius != grainRadius ||
           oldDelegate.strokeWidth != strokeWidth;
  }
}

/// Helper class to store grain point data
class _GrainPoint {
  final double x;
  final double y;
  final double opacity;
  
  _GrainPoint({
    required this.x,
    required this.y,
    required this.opacity,
  });
}
