import 'package:flutter/material.dart';

import '../../backend_core/utils/dutch_rank_level_change_checker.dart';
import '../../utils/dutch_share_helper.dart';
import '../../utils/dutch_share_moment.dart';
import 'dutch_animated_cta_button.dart';

/// Ghost CTA that opens the native share sheet for a celebration moment.
class DutchShareCtaButton extends StatelessWidget {
  const DutchShareCtaButton({
    super.key,
    required this.moment,
    this.winnerMessage,
    this.change,
    this.semanticIdentifier,
  });

  final DutchShareMoment moment;
  final String? winnerMessage;
  final DutchRankLevelChangeResult? change;
  final String? semanticIdentifier;

  @override
  Widget build(BuildContext context) {
    return DutchAnimatedCtaButton(
      label: 'Share',
      onPressed: () => _onShare(context),
      leadingIcon: Icons.share_outlined,
      variant: DutchCtaVariant.ghost,
      expand: false,
      semanticIdentifier: semanticIdentifier ?? 'dutch_share_${moment.name}',
    );
  }

  Future<void> _onShare(BuildContext context) async {
    final payload = DutchShareHelper.buildPayload(
      moment: moment,
      winnerMessage: winnerMessage,
      change: change,
    );
    await DutchShareHelper.share(
      context: context,
      payload: payload,
      moment: moment,
    );
  }
}
