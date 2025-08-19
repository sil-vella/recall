import 'package:flutter/material.dart';
import '../../../models/player.dart';
import '../../../../../../utils/consts/theme_consts.dart';
import '../../../../../tools/logging/logger.dart';

class OpponentsPanel extends StatelessWidget {
  static final Logger _log = Logger();
  final List<Player> opponents;

  const OpponentsPanel({Key? key, required this.opponents}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    _log.info('🎮 OpponentsPanel: Building with ${opponents.length} opponents');
    
    if (opponents.isEmpty) {
      _log.info('🎮 OpponentsPanel: No opponents, hiding panel');
      return const SizedBox.shrink();
    }
    
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: opponents.map((p) => _OpponentTile(player: p)).toList(),
      ),
    );
  }
}

class _OpponentTile extends StatelessWidget {
  static final Logger _log = Logger();
  final Player player;
  const _OpponentTile({required this.player});

  @override
  Widget build(BuildContext context) {
    _log.info('🎮 OpponentTile: Building tile for player ${player.name} with ${player.handSize} cards and ${player.totalScore} points');
    
    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.lightGray.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(player.name, style: AppTextStyles.bodyLarge),
          const SizedBox(height: 4),
          Text('Cards: ${player.handSize}', style: AppTextStyles.bodyMedium),
          Text('Score: ${player.totalScore}', style: AppTextStyles.bodyMedium),
        ],
      ),
    );
  }
}


