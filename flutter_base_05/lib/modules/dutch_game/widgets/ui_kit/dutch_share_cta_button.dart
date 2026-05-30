import 'package:flutter/material.dart';

import '../../utils/dutch_share_helper.dart';
import '../../utils/dutch_share_moment.dart';
import 'dutch_animated_cta_button.dart';

/// Opens the share platform picker (Facebook image / TikTok video templates).
class DutchShareCtaButton extends StatelessWidget {
  const DutchShareCtaButton({
    super.key,
    required this.moment,
    this.semanticIdentifier,
  });

  final DutchShareMoment moment;
  final String? semanticIdentifier;

  @override
  Widget build(BuildContext context) {
    return DutchAnimatedCtaButton(
      label: 'Share',
      onPressed: () => DutchShareHelper.showSharePicker(
        context: context,
        moment: moment,
      ),
      leadingIcon: Icons.share_outlined,
      variant: DutchCtaVariant.ghost,
      expand: false,
      semanticIdentifier: semanticIdentifier ?? 'dutch_share_${moment.name}',
    );
  }
}
