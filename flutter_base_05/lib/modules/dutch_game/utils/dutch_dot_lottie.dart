import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

import '../../../../../utils/dev_logger.dart';

const bool LOGGING_SWITCH = false;

/// Bundle path for the same-rank hand-slot poof celebration.
const String kSameRankPoofLottie = 'assets/lottie/same_rank_poof.lottie';

/// Bundle path for the final-round (Call Dutch) stopwatch celebration.
const String kFinalRoundCallLottie = 'assets/lottie/final_round_call.lottie';

/// Decoder for `.lottie` (dotlottie zip) assets: picks the first `.json` animation.
Future<LottieComposition?> decodeDotLottieBytes(List<int> bytes) {
  return LottieComposition.decodeZip(
    bytes,
    filePicker: (files) {
      for (final f in files) {
        final name = f.name.toLowerCase();
        if (name.endsWith('.json') && !name.endsWith('manifest.json')) {
          return f;
        }
      }
      for (final f in files) {
        if (f.name.endsWith('.json')) return f;
      }
      return files.isNotEmpty ? files.first : null;
    },
  );
}

Future<LottieComposition?> loadDotLottieFromAsset(String assetPath) async {
  try {
    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List();
    final composition = await decodeDotLottieBytes(bytes).catchError((Object e, StackTrace _) {
      if (LOGGING_SWITCH) {
        customlog('dutch_dot_lottie: decode failed asset=$assetPath err=$e');
      }
      return null;
    });
    if (LOGGING_SWITCH) {
      customlog(
        'dutch_dot_lottie: load asset=$assetPath '
        'ok=${composition != null} duration=${composition?.duration.inMilliseconds}ms',
      );
    }
    return composition;
  } catch (e) {
    if (LOGGING_SWITCH) {
      customlog('dutch_dot_lottie: load failed asset=$assetPath err=$e');
    }
    return null;
  }
}
