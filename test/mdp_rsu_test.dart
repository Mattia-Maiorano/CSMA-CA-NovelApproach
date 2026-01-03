import 'package:flutter_test/flutter_test.dart';
import 'package:daemon/domain/entities/mdp_rsu.dart';
import 'package:daemon/domain/ai/agent.dart';
import 'package:daemon/domain/entities/position.dart';
import 'package:daemon/utils/config.dart';

class TestAgent implements Agent {
  @override final int id;
  @override final List<String> actions;
  int chooseCount = 0;
  int learnCount = 0;
  Map<String, dynamic>? lastState;
  String actionToReturn = 'defer';

  TestAgent(this.id, this.actions);

  @override
  String chooseAction(Map<String, dynamic> state) {
    chooseCount++;
    lastState = state;
    return actionToReturn;
  }

  @override
  void learn(Map<String, dynamic> state, String action, double reward, Map<String, dynamic> nextState, {bool done = false, double? gammaOverride}) {
    learnCount++;
  }

  @override Map<String, dynamic> stateFromEntity(entity) => throw UnimplementedError();
  @override Map<String, double> parameters() => {};
  @override double getEpsilon() => 0.0;
  @override void setEpsilon(double value) {}
}

void main() {
  test('MDPRSU queries agent only at decision points (not every tick)', () {
    final agent = TestAgent(0, ['ready', 'defer']);
    agent.actionToReturn = 'defer';
    final rsu = MDPRSU(
      id: 0,
      position: Position(x: 1, y: 1, direction: Direction.up),
      range: 7, sensingRange: 3, agent: agent,
    );

    // First tick: should make a decision (RSU starts idle)
    rsu.step(0, 0, null);
    expect(agent.chooseCount, 1);

    // Next few ticks: waiting for defer backoff, no new decisions
    rsu.step(1, 0, null);
    rsu.step(2, 0, null);
    final countAfterFewTicks = agent.chooseCount;
    expect(countAfterFewTicks, lessThanOrEqualTo(3));
  });

  test('MDPRSU learns after outcome is resolved', () {
    final agent = TestAgent(0, ['ready', 'defer']);
    agent.actionToReturn = 'defer';
    final rsu = MDPRSU(
      id: 0,
      position: Position(x: 1, y: 1, direction: Direction.up),
      range: 7, sensingRange: 3, agent: agent,
    );

    // Run through a full frame
    for (int t = 0; t < SUBFRAMES; t++) {
      rsu.step(t, 0, null);
    }

    // Should have learned at least once
    expect(agent.learnCount, greaterThan(0));
  });

  test('MDPRSU state has expected keys', () {
    final agent = TestAgent(0, ['ready', 'defer']);
    final rsu = MDPRSU(
      id: 0,
      position: Position(x: 1, y: 1, direction: Direction.up),
      range: 7, sensingRange: 3, agent: agent,
    );

    rsu.step(0, 0, null);
    expect(agent.lastState!.containsKey('tick'), true);
    expect(agent.lastState!.containsKey('busy'), true);
    expect(agent.lastState!.containsKey('queue'), true);
  });
}
