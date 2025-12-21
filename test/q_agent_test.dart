import 'package:flutter_test/flutter_test.dart';
import 'package:daemon/domain/ai/q_agent.dart';

void main() {
  test('QAgent performs Q-learning update', () {
    final agent = QAgent(0, ['noop', 'startQuery'], alpha: 0.5, gamma: 0.9, epsilon: 0.0);
    final s = {'carsInRange': 1, 'consecutiveCollisions': 0};
    final s2 = {'carsInRange': 2, 'consecutiveCollisions': 0};
    final action = 'startQuery';
    // learn: reward 1.0
    agent.learn(s, action, 1.0, s2);
    // chooseAction should pick the learned (higher) action after update
    final chosen = agent.chooseAction(s);
    expect(chosen, action);
  });

  test('QAgent can serialize and deserialize Q-table', () {
    final agent = QAgent(0, ['noop', 'startQuery'], alpha: 0.5, gamma: 0.9, epsilon: 0.0);
    final s = {'carsInRange': 1, 'consecutiveCollisions': 0};
    final s2 = {'carsInRange': 2, 'consecutiveCollisions': 0};
    final action = 'startQuery';
    agent.learn(s, action, 1.0, s2);
    final json = agent.toJson();
    expect(json.isNotEmpty, true);
    final newAgent = QAgent(0, ['noop', 'startQuery']);
    newAgent.fromJson(json);
    final sKey = 'carsInRange=1|consecutiveCollisions=0';
    expect(newAgent.toJson().containsKey(sKey), true);
  });
}
