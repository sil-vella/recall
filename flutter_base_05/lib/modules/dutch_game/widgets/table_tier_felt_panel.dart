import 'package:flutter/material.dart';

import '../../../../utils/consts/theme_consts.dart';
import '../../../../utils/widgets/felt_texture_widget.dart';
import '../utils/dutch_game_play_table_style_mapping.dart';

/// Felt + spotlight + border + scrim for a room table tier (`game_level` 1–4).
/// Used by Join Random content and create-room table dropdown items.
class TableTierFeltPanel extends StatelessWidget {
  final int tableLevel;

  const TableTierFeltPanel({super.key, required this.tableLevel});

  @override
  Widget build(BuildContext context) {
    final style = DutchGamePlayTableStyles.forLevel(tableLevel);
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: FeltTextureWidget(
            backgroundColor: style.feltBackground,
            seed: 40 + tableLevel,
            pointDensity: 0.18,
          ),
        ),
        Positioned(
          left: -20,
          top: -20,
          child: IgnorePointer(
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    style.spotlightColor.withValues(alpha: 0.35),
                    style.spotlightColor.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 0.85],
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.casinoBorderColor, width: 2),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.12),
                  Colors.black.withValues(alpha: 0.28),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
