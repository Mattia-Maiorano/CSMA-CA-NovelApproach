import 'package:flutter_test/flutter_test.dart';
import 'package:daemon/domain/entities/mdp_car.dart';
import 'package:daemon/domain/ai/agent.dart';
import 'package:daemon/domain/entities/position.dart';

class TestAgent implements Agent {
  @override
  final int id;
  @override
  final List<String> actions;

  bool chooseCalled = false;
  bool learnCalled = false;
  Map<String, dynamic>? lastState;
  String? lastAction;
  Map<String, dynamic>? lastNextState;

  double _epsilon = 0.0;

  TestAgent(this.id, this.actions);

  @override
  Map<String, dynamic> stateFromEntity(entity) => throw UnimplementedError();

  @override
  String chooseAction(Map<String, dynamic> state) {
    chooseCalled = true;
    lastState = state;
    return actions.first;
  }

  @override
  void learn(Map<String, dynamic> state, String action, double reward, Map<String, dynamic> nextState, {bool done = false, double? gammaOverride}) {
    learnCalled = true;
    lastState = state;
    lastAction = action;
    lastNextState = nextState;
  }

  @override
  Map<String, double> parameters() => {'alpha': 0.1, 'gamma': 0.0, 'epsilon': _epsilon};

  @override
  double getEpsilon() => _epsilon;

  @override
  void setEpsilon(double value) {
    _epsilon = value;
  }
}

void main() {
  test('MDPCarClean chooses actions and triggers learn', () {
    final agent = TestAgent(0, ['noop', 'startQuery']);
    final mdpCar = MDPCar(
      id: 0,
      model: 0,
      position: Position(x: 1, y: 1, direction: Direction.right),
      manhattanGrid: List.generate(3, (_) => List<int>.filled(3, 1)),
      range: 3,
      sensingRange: 3,
      timer: 0,
      agent: agent,
    );

    // step should cause chooseAction and learn to be invoked
    mdpCar.step(0, 0, null);

    expect(agent.chooseCalled, true);
    expect(agent.learnCalled, true);
    expect(agent.lastAction, isNotNull);
  });
}
