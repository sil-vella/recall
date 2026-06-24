import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dutch/modules/dutch_game/utils/dutch_dot_lottie.dart';
import 'package:lottie/lottie.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> expectLoads(String path) async {
    Object? loadErr;
    try {
      await rootBundle.load(path);
    } catch (e) {
      loadErr = e;
    }
    expect(loadErr, isNull, reason: 'rootBundle.load failed for $path: $loadErr');

    Object? decodeErr;
    LottieComposition? composition;
    try {
      final data = await rootBundle.load(path);
      composition = await decodeDotLottieBytes(data.buffer.asUint8List());
    } catch (e) {
      decodeErr = e;
    }
    expect(decodeErr, isNull, reason: 'decode threw for $path: $decodeErr');
    expect(composition, isNotNull, reason: 'decode returned null for $path');
    expect(composition!.duration.inMilliseconds, greaterThan(0));
  }

  test('loads winner01 dotLottie (known-good)', () async {
    await expectLoads('assets/lottie/winner01.lottie');
  });

  test('loads same_rank_poof dotLottie', () async {
    await expectLoads(kSameRankPoofLottie);
  });

  test('loads final_round_call dotLottie', () async {
    await expectLoads(kFinalRoundCallLottie);
  });
}
