import 'package:flutter_test/flutter_test.dart';
import 'package:daemon/utils/slope_utils.dart' as slope_utils;
// no config constants imported here; Analyzer helpers use defaults from config

void main() {
  test('computeSlopeForWindow returns expected slope for simple linear series', () {
    final W = 10;
    // linear series from 10 to 0 across 10 points -> slope = (0 - 10) / (W-1) = -10/9
    final rewards = List<double>.generate(W, (i) => 10 - (10 * i / (W - 1)));
    final slope = slope_utils.computeSlopeForWindow(rewards, window: W);
    final expected = -10.0 / 9.0;
    expect((slope - expected).abs() < 1e-9, true);
  });

  test('recommendThresholdForDrop suggests threshold for 0.8 -> 0.7 drop', () {
    final W = 100;
    final start = 0.8;
    final end = 0.7;
    final rec = slope_utils.recommendThresholdForDrop(start, end, window: W, sensitivity: 1.0, margin: 0.9);
    // slope ≈ -0.1/(W-1), so recommended threshold should be about 0.9 * slope
    final expectedSlope = (end - start) / (W - 1);
    final expectedRec = expectedSlope * 0.9;
    expect((rec - expectedRec).abs() < 1e-12, true);
  });
}
