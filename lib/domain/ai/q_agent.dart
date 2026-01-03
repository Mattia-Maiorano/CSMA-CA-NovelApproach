/// ============================================================================
/// Q-Learning Agent Implementation
/// ============================================================================
/// Tabular Q-Learning agent with epsilon-greedy exploration.
///
/// Key Parameters:
/// - alpha: Learning rate (default 0.1)
/// - gamma: Discount factor (default 0.99)
/// - epsilon: Exploration rate (adjustable, starts at 0.9)
///
/// The Q-table maps state strings to action-value dictionaries.
/// States are serialized as "key1=value1|key2=value2|..." strings.
/// ============================================================================

import 'dart:math';
import 'agent.dart';

class QAgent extends Agent {
  final Map<String, Map<String, double>> _qTable = {};
  double alpha;
  double gamma;
  double epsilon;
  final Random _rnd = Random();

  QAgent(
    int id,
    List<String> actions, {
    this.alpha = 0.1,
    this.gamma = 0.99,
    this.epsilon = 0.9,
  }) : super(id, actions);

  String _keyFromState(Map<String, dynamic> s) {
    final sorted = s.keys.toList()..sort();
    return sorted.map((k) => '$k=${s[k]}').join('|');
  }

  Map<String, double> _initActionMap() {
    final map = <String, double>{};
    for (final a in actions) map[a] = 0.0;
    return map;
  }

  @override
  String chooseAction(Map<String, dynamic> state) {
    final key = _keyFromState(state);
    if (!_qTable.containsKey(key)) _qTable[key] = _initActionMap();
    final actionsMap = _qTable[key]!;
    // epsilon-greedy
    if (_rnd.nextDouble() < epsilon) {
      return actions[_rnd.nextInt(actions.length)];
    }
    // choose greedy action
    String best = actions.first;
    double bestV = double.negativeInfinity;
    for (final a in actions) {
      final v = actionsMap[a]!;
      if (v > bestV) {
        bestV = v;
        best = a;
      }
    }
    return best;
  }

  @override
  void learn(
    Map<String, dynamic> state,
    String action,
    double reward,
    Map<String, dynamic> nextState, {
    bool done = false,
    double? gammaOverride,
  }) {
    final sKey = _keyFromState(state);
    final nsKey = _keyFromState(nextState);
    if (!_qTable.containsKey(sKey)) _qTable[sKey] = _initActionMap();
    if (!_qTable.containsKey(nsKey)) _qTable[nsKey] = _initActionMap();
    final qsa = _qTable[sKey]!;
    final qns = _qTable[nsKey]!;
    final old = qsa[action] ?? 0.0;
    final bestNext = done ? 0.0 : qns.values.reduce((a, b) => a > b ? a : b);
    final g = gammaOverride ?? gamma;
    final td = reward + g * bestNext - old;
    qsa[action] = old + alpha * td;
  }

  /// Serialize Q-table as a Map for persistence or analysis
  Map<String, dynamic> toJson() {
    final out = <String, Map<String, double>>{};
    _qTable.forEach((key, value) {
      out[key] = Map<String, double>.from(value);
    });
    return out;
  }

  /// Load a Q-table JSON structure
  void fromJson(Map<String, dynamic> json) {
    _qTable.clear();
    json.forEach((k, v) {
      if (v is Map) {
        _qTable[k] = Map<String, double>.from(v.map((kk, vv) => MapEntry(kk.toString(), (vv as num).toDouble())));
      }
    });
  }

  @override
  Map<String, dynamic> stateFromEntity(entity) => throw UnimplementedError('QAgent requires a domain-specific stateFromEntity');

  @override
  Map<String, double> parameters() => {'alpha': alpha, 'gamma': gamma, 'epsilon': epsilon};

  @override
  double getEpsilon() => epsilon;

  @override
  void setEpsilon(double e) {
    epsilon = e.clamp(0.0, 1.0);
  }
}
