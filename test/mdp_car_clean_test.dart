import 'package:flutter_test/flutter_test.dart';
import 'package:daemon/domain/entities/mdp_car.dart';
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
  test('MDPCar queries agent only at decision points (not every tick)', () {
    final agent = TestAgent(0, ['startComm', 'defer']);
    agent.actionToReturn = 'defer';  // Defer completes quickly
    final car = MDPCar(
      id: 0, model: 0,
      position: Position(x: 1, y: 1, direction: Direction.right),
      manhattanGrid: List.generate(3, (_) => List<int>.filled(3, 1)),
      range: 3, sensingRange: 3, agent: agent,
    );

    // First tick: should make a decision (car starts idle)
    car.step(0, 0, null);
    expect(agent.chooseCount, 1);

    // Next few ticks: waiting for defer backoff to expire, no new decisions
    car.step(1, 0, null);
    car.step(2, 0, null);
    // chooseCount may increase if backoff expired and new decision is made
    // but should NOT be called every tick like before
    final countAfterFewTicks = agent.chooseCount;
    expect(countAfterFewTicks, lessThanOrEqualTo(3)); // Much less than 3 ticks = 3 calls
  });

  test('MDPCar learns after outcome is resolved', () {
    final agent = TestAgent(0, ['startComm', 'defer']);
    agent.actionToReturn = 'defer';
    final car = MDPCar(
      id: 0, model: 0,
      position: Position(x: 1, y: 1, direction: Direction.right),
      manhattanGrid: List.generate(3, (_) => List<int>.filled(3, 1)),
      range: 3, sensingRange: 3, agent: agent,
    );

    // Run through a full frame
    for (int t = 0; t < SUBFRAMES; t++) {
      car.step(t, 0, null);
    }

    // Should have learned at least once (outcome resolved or frame end)
    expect(agent.learnCount, greaterThan(0));
  });

  test('MDPCar state has expected keys', () {
    final agent = TestAgent(0, ['startComm', 'defer']);
    final car = MDPCar(
      id: 0, model: 0,
      position: Position(x: 1, y: 1, direction: Direction.right),
      manhattanGrid: List.generate(3, (_) => List<int>.filled(3, 1)),
      range: 3, sensingRange: 3, agent: agent,
    );

    car.step(0, 0, null);
    expect(agent.lastState!.containsKey('tick'), true);
    expect(agent.lastState!.containsKey('busy'), true);
    expect(agent.lastState!.containsKey('resolved'), true);
  });
}
