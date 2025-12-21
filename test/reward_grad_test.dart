import 'package:flutter_test/flutter_test.dart';
import 'package:daemon/utils/analyzer.dart';
import 'package:daemon/domain/ai/q_agent.dart';

void main() {
  test('Analyzer triggers epsilon increase on negative reward gradient', () {
    final analyzer = Analyzer();
    analyzer.enableMDPTracking();
    final agent = QAgent(0, ['noop', 'startQuery']);
    analyzer.registerMdpAgent(0, agent);
    // ensure the agent is registered
    expect(analyzer.getRegisteredMdpAgent(0), isNotNull);

    // record 200 episodes of rewards to match the default REWARD_GRAD_WINDOW (100)
    final rewards = <double>[];
    for (int i = 0; i < 100; i++) rewards.add(10.0);
    for (int i = 0; i < 100; i++) rewards.add(-50.0);
    // Track whether epsilon was increased at any point during the sequence
    bool seenIncrease = false;
    double prevEps = agent.getEpsilon();
    for (final r in rewards) {
      analyzer.recordMDPProgress(0, 'Car', r, {}, {'alpha': 0.1});
      final curr = agent.getEpsilon();
      if (curr > prevEps) seenIncrease = true;
      prevEps = curr;
    }

    // At least one increase event must have happened inside the recorded rewards
    expect(seenIncrease, true);
    // test cooldown: immediate next update should not increase due to cooldown (it may slightly decay)
    final prev = prevEps;
    // feed a single more episode with bad reward to try to retrigger
    analyzer.recordMDPProgress(0, 'Car', 1.0, {}, {'epsilon': 0.05});
    final after = agent.getEpsilon();
    expect(after <= prev, true);
  });
}
