import 'package:flutter_test/flutter_test.dart';
import 'package:daemon/domain/entities/mdp_rsu.dart';
import 'package:daemon/domain/ai/agent.dart';
import 'package:daemon/domain/entities/position.dart';

class TestAgent implements Agent {
  @override
  final int id;
  @override
  final List<String> actions;

  bool chooseCalled = false;
  bool learnCalled = false;
  String? lastAction;

  double _epsilon = 0.01;

  TestAgent(this.id, this.actions);

  @override
  Map<String, dynamic> stateFromEntity(entity) => throw UnimplementedError();

  @override
  String chooseAction(Map<String, dynamic> state) {
    chooseCalled = true;
    return actions.first;
  }

  @override
  Map<String, double> parameters() => {'alpha': 0.1, 'gamma': 0.0, 'epsilon': _epsilon};

  @override
  void learn(Map<String, dynamic> state, String action, double reward, Map<String, dynamic> nextState, {bool done = false, double? gammaOverride}) {
    learnCalled = true;
    lastAction = action;
  }

  @override
  double getEpsilon() => _epsilon;

  @override
  void setEpsilon(double value) {
    _epsilon = value;
  }
}

void main() {
  test('MDPRSU chooses action and learns', () {
    final agent = TestAgent(0, ['noop', 'defer']);
    final rsu = MDPRSU(id: 0, position: Position(x: 1, y: 1, direction: Direction.up), range: 7, sensingRange: 3, analyzer: null, agent: agent);
    rsu.step(0, 0, null);
    expect(agent.chooseCalled, true);
    // Need to call specificStep to trigger learning
    rsu.specificStep();
    expect(agent.learnCalled, true);
  });
}
