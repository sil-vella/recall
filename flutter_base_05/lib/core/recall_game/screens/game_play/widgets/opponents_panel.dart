import 'package:flutter/material.dart';
import '../../../models/player.dart';
import '../../../../../../utils/consts/theme_consts.dart';

class OpponentsPanel extends StatelessWidget {
  final List<Player> opponents;

  const OpponentsPanel({Key? key, required this.opponents}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (opponents.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: opponents.map((p) => _OpponentTile(player: p)).toList(),
      ),
    );
  }
}

class _OpponentTile extends StatelessWidget {
  final Player player;
  const _OpponentTile({required this.player});

  @override
  Widget build(BuildContext context) {
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
          Text('Score: ${player.totalScore}', style: AppTextStyles.bodySmall),
        ],
      ),
    );
  }
}


