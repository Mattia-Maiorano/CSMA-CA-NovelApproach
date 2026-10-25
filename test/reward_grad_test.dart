import 'package:flutter_test/flutter_test.dart';
import 'package:daemon/utils/analyzer.dart';
import 'package:daemon/domain/ai/q_agent.dart';
import 'package:daemon/utils/config.dart';

void main() {
  test('Analyzer triggers epsilon increase when recent window avg < previous window avg', () {
    ENABLE_EPSILON_ADAPT = true;
    final analyzer = Analyzer();
    analyzer.enableMDPTracking();
    final agent = QAgent(0, ['noop', 'startQuery']);
    analyzer.registerMdpAgent(0, agent);
    expect(analyzer.getRegisteredMdpAgent(0), isNotNull);

    // Need 2 * EPSILON_WINDOW frames
    final w = EPSILON_WINDOW;
    final rewards = <double>[];
    // First window: high rewards
    for (int i = 0; i < w; i++) rewards.add(10.0);
    // Second window: very low rewards (should trigger)
    for (int i = 0; i < w; i++) rewards.add(1.0);
    // Third window: even lower (should trigger again after cooldown)
    for (int i = 0; i < w; i++) rewards.add(-1.0);

    bool seenIncrease = false;
    double prevEps = agent.getEpsilon();
    for (final r in rewards) {
      analyzer.recordMDPProgress(0, 'Car', r, {}, {'alpha': 0.1, 'epsilon': agent.getEpsilon()});
      final curr = agent.getEpsilon();
      if (curr > prevEps) seenIncrease = true;
      prevEps = curr;
    }

    // Check that we saw it happen
    expect(seenIncrease, true);
  });

  test('Analyzer respects cooldown after epsilon increase', () {
    ENABLE_EPSILON_ADAPT = true;
    final analyzer = Analyzer();
    analyzer.enableMDPTracking();
    final agent = QAgent(0, ['noop', 'startQuery']);
    analyzer.registerMdpAgent(0, agent);

    final w = EPSILON_WINDOW;
    // First window: high rewards
    for (int i = 0; i < w; i++) {
      analyzer.recordMDPProgress(0, 'Car', 10.0, {}, {});
    }
    // Second window: low rewards (triggers)
    for (int i = 0; i < w; i++) {
      analyzer.recordMDPProgress(0, 'Car', 2.0, {}, {});
    }
    final epsAfterTrigger = agent.getEpsilon();

    // Immediately try another bad window - should be blocked by cooldown
    final epsBeforeNext = agent.getEpsilon();
    analyzer.recordMDPProgress(0, 'Car', 1.0, {}, {});
    final epsAfterOne = agent.getEpsilon();
    // Epsilon should not have jumped (may decay slightly)
    expect(epsAfterOne <= epsBeforeNext, true);
  });
}
