import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../tools/logging/logger.dart';
import '../../../../utils/consts/config.dart';
import '../../../../utils/consts/theme_consts.dart';

/// Circle avatar with deterministic colored initials fallback.
///
/// Image precedence (first wins):
///   1. [imageBytes]  — already-decoded photo bytes (e.g. profile uploads).
///   2. [imageUrl]    — remote URL (web/native).
///   3. [assetPath]   — local asset (`assets/...`).
///   4. Initials fallback derived from [displayName].
///
/// The initials background is hashed from `displayName` so the same player
/// always gets the same shade — useful for leaderboard rows / opponent chips.
class DutchAvatar extends StatelessWidget {
  static const bool LOGGING_SWITCH = true; // Avatar render/fallback trace (enable-logging-switch.mdc) — set false after debugging
  static final Logger _logger = Logger();

  const DutchAvatar({
    super.key,
    required this.displayName,
    this.imageBytes,
    this.imageUrl,
    this.assetPath,
    this.size = 56,
    this.borderColor,
    this.onTap,
    this.semanticIdentifier,
  });

  final String displayName;
  final Uint8List? imageBytes;
  final String? imageUrl;
  final String? assetPath;
  final double size;
  final Color? borderColor;
  final VoidCallback? onTap;
  final String? semanticIdentifier;

  /// Normalize backend-provided profile image URLs for real devices.
  ///
  /// In local debug flows, the backend can emit `http://localhost:...` or
  /// `http://127.0.0.1:...` media URLs. Those only work on the same host and
  /// fail on Android/iOS devices. We rewrite host/scheme/port to `Config.apiUrl`
  /// while preserving the original media path/query.
  String _effectiveImageUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return trimmed;

    final base = Uri.tryParse(Config.apiUrl);
    final incoming = Uri.tryParse(trimmed);
    if (base == null || incoming == null) return trimmed;

    if (!incoming.hasScheme || incoming.host.isEmpty) {
      if (trimmed.startsWith('/')) {
        return '${base.scheme}://${base.authority}$trimmed';
      }
      return trimmed;
    }

    final host = incoming.host.toLowerCase();
    final needsRewrite = host == 'localhost' || host == '127.0.0.1' || host == '10.0.2.2';
    if (!needsRewrite) return trimmed;

    final rewritten = incoming.replace(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
    );
    return rewritten.toString();
  }

  String _initialsFor(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      final p = parts.first;
      return p.length >= 2
          ? p.substring(0, 2).toUpperCase()
          : p.substring(0, 1).toUpperCase();
    }
    final first = parts.first.isNotEmpty ? parts.first[0] : '';
    final last = parts.last.isNotEmpty ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }

  Color _bgFor(String name) {
    if (name.trim().isEmpty) return AppColors.accentContrast;
    final hash = name.codeUnits.fold<int>(0, (a, b) => (a + b * 31) & 0x7fffffff);
    // Mix the accentContrast with a light shift derived from the hash so each
    // player gets a stable yet on-theme tint.
    final shift = ((hash % 60) - 30) / 100.0; // -0.30..+0.30
    final base = AppColors.accentContrast;
    final blendTarget = shift >= 0
        ? AppColors.accentColor2
        : AppColors.scaffoldBackgroundColor;
    return Color.lerp(base, blendTarget, shift.abs()) ?? base;
  }

  @override
  Widget build(BuildContext context) {
    final inner = _buildInner();

    final framed = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: borderColor ?? AppColors.accentColor2.withValues(alpha: 0.65),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(child: inner),
    );

    final wrapped = onTap != null
        ? Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: framed,
            ),
          )
        : framed;

    return Semantics(
      identifier: semanticIdentifier,
      label: displayName,
      image: imageBytes != null || imageUrl != null || assetPath != null,
      child: wrapped,
    );
  }

  Widget _buildInner() {
    if (imageBytes != null && imageBytes!.isNotEmpty) {
      if (LOGGING_SWITCH) {
        _logger.info('DutchAvatar: rendering Image.memory bytes=${imageBytes!.length} semantic="$semanticIdentifier"');
      }
      return Image.memory(
        imageBytes!,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    }
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      final resolvedUrl = _effectiveImageUrl(imageUrl!);
      if (LOGGING_SWITCH) {
        _logger.info(
          'DutchAvatar: rendering Image.network raw="$imageUrl" resolved="$resolvedUrl" semantic="$semanticIdentifier"',
        );
      }
      return Image.network(
        resolvedUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, error, stack) {
          if (LOGGING_SWITCH) {
            _logger.warning('DutchAvatar: Image.network failed url="$resolvedUrl" error=$error');
          }
          return _buildInitials();
        },
      );
    }
    if (assetPath != null && assetPath!.isNotEmpty) {
      if (LOGGING_SWITCH) {
        _logger.info('DutchAvatar: rendering Image.asset path="$assetPath" semantic="$semanticIdentifier"');
      }
      return Image.asset(
        assetPath!,
        fit: BoxFit.cover,
        errorBuilder: (_, error, stack) {
          if (LOGGING_SWITCH) {
            _logger.warning('DutchAvatar: Image.asset failed path="$assetPath" error=$error');
          }
          return _buildInitials();
        },
      );
    }
    if (LOGGING_SWITCH) {
      _logger.info('DutchAvatar: no image source provided, using initials fallback semantic="$semanticIdentifier"');
    }
    return _buildInitials();
  }

  Widget _buildInitials() {
    final bg = _bgFor(displayName);
    final initials = _initialsFor(displayName);
    final fontSize = size * 0.38;
    if (LOGGING_SWITCH) {
      _logger.info('DutchAvatar: initials fallback initials="$initials" displayName="$displayName" semantic="$semanticIdentifier"');
    }
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            bg,
            Color.lerp(bg, AppColors.scaffoldBackgroundColor, 0.35) ?? bg,
          ],
        ),
      ),
      child: Text(
        initials,
        style: TextStyle(
          color: AppColors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
