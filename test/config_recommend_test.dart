import 'package:flutter_test/flutter_test.dart';
import 'package:daemon/utils/config.dart';
import 'package:daemon/utils/slope_utils.dart' as slope_utils;

void main() {
  test('config computed REWARD_GRAD_THRESHOLD matches slope_utils recommendation', () {
    final rec = slope_utils.recommendThresholdForDrop(TARGET_DROP_START, TARGET_DROP_END,
        window: TARGET_DROP_WINDOW, sensitivity: TARGET_DROP_SENSITIVITY);
    expect((REWARD_GRAD_THRESHOLD - rec).abs() < 1e-12, true);
  });
}
