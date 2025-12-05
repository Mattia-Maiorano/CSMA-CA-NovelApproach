import 'dart:math';

/// Discrete actions for parameter adjustment
enum ParameterAction {
  // Timeout actions
  increaseTimeoutSmall,   // +0.05
  increaseTimeoutLarge,   // +0.15
  decreaseTimeoutSmall,   // -0.05
  decreaseTimeoutLarge,   // -0.15
  
  // Broadcast actions
  increaseBroadcastSmall, // +0.05
  increaseBroadcastLarge, // +0.15
  decreaseBroadcastSmall, // -0.05
  decreaseBroadcastLarge, // -0.15
  
  // Jitter actions
  increaseJitterSmall,    // +0.05
  increaseJitterLarge,    // +0.15
  decreaseJitterSmall,    // -0.05
  decreaseJitterLarge,    // -0.15
  
  // No-op
  noChange,
}

/// Base class for MDP parameters that can be learned
abstract class MDPParameters {
  double timeoutMultiplier = 1.0;           // Multiplier for reset time
  double broadcastIntervalMultiplier = 1.0; // Multiplier for broadcast interval
  double jitterMultiplier = 1.0;            // Multiplier for timing randomization

  /// Apply a discrete action
  void applyAction(ParameterAction action, {double min = 0.5, double max = 2.0}) {
    switch (action) {
      case ParameterAction.increaseTimeoutSmall:
        timeoutMultiplier = (timeoutMultiplier + 0.05).clamp(min, max);
        break;
      case ParameterAction.increaseTimeoutLarge:
        timeoutMultiplier = (timeoutMultiplier + 0.15).clamp(min, max);
        break;
      case ParameterAction.decreaseTimeoutSmall:
        timeoutMultiplier = (timeoutMultiplier - 0.05).clamp(min, max);
        break;
      case ParameterAction.decreaseTimeoutLarge:
        timeoutMultiplier = (timeoutMultiplier - 0.15).clamp(min, max);
        break;
        
      case ParameterAction.increaseBroadcastSmall:
        broadcastIntervalMultiplier = (broadcastIntervalMultiplier + 0.05).clamp(min, max);
        break;
      case ParameterAction.increaseBroadcastLarge:
        broadcastIntervalMultiplier = (broadcastIntervalMultiplier + 0.15).clamp(min, max);
        break;
      case ParameterAction.decreaseBroadcastSmall:
        broadcastIntervalMultiplier = (broadcastIntervalMultiplier - 0.05).clamp(min, max);
        break;
      case ParameterAction.decreaseBroadcastLarge:
        broadcastIntervalMultiplier = (broadcastIntervalMultiplier - 0.15).clamp(min, max);
        break;
      case ParameterAction.increaseJitterSmall:
        jitterMultiplier = (jitterMultiplier + 0.05).clamp(min, max);
        break;
      case ParameterAction.increaseJitterLarge:
        jitterMultiplier = (jitterMultiplier + 0.15).clamp(min, max);
        break;
      case ParameterAction.decreaseJitterSmall:
        jitterMultiplier = (jitterMultiplier - 0.05).clamp(min, max);
        break;
      case ParameterAction.decreaseJitterLarge:
        jitterMultiplier = (jitterMultiplier - 0.15).clamp(min, max);
        break;
        
      case ParameterAction.noChange:
        break;
    }
  }

  Map<String, double> toMap() {
    return {
      'timeout': timeoutMultiplier,
      'broadcastInterval': broadcastIntervalMultiplier,
      'jitter': jitterMultiplier,
    };
  }

  /// Returns a readable string representation of parameters
  String paramsToString() {
    return 'timeout: ${timeoutMultiplier.toStringAsFixed(2)}, '
           'broadcast: ${broadcastIntervalMultiplier.toStringAsFixed(2)}, '
           'jitter: ${jitterMultiplier.toStringAsFixed(2)}';
  }
}

/// Base class for MDP state observations
abstract class MDPState {
  int softResets = 0;
  int hardResets = 0;

  void reset() {
    softResets = 0;
    hardResets = 0;
  }

  Map<String, dynamic> toMap();
}

/// Q-learning policy with discrete actions
class QLearningPolicy {
  // Q-table: maps (state_hash, action) -> Q-value
  final Map<(int, ParameterAction), double> qTable = {};
  
  // Learning parameters
  final double learningRate;
  final double discountFactor;
  double epsilon; // Exploration rate (can decay over time)
  final Random _random = Random();
  
  QLearningPolicy({
    this.learningRate = 0.1,
    this.discountFactor = 0.9,
    this.epsilon = 0.2, // Start with more exploration
  });

  /// Select action based on epsilon-greedy policy
  /// Optional [allowedActions] restricts actions that can be chosen
  ParameterAction selectAction(int stateHash, {List<ParameterAction>? allowedActions}) {
    final actions = allowedActions ?? ParameterAction.values;
    if (_random.nextDouble() < epsilon) {
      // Explore: random action
      return actions[_random.nextInt(actions.length)];
    } else {
      // Exploit: choose action with highest Q-value; in case of ties pick randomly among maxes
      final bestActions = _actionsWithMaxQ(stateHash, actions);
      if (bestActions.isEmpty) {
        // No best found (shouldn't happen if values default to 0), fall back to random action
        return actions[_random.nextInt(actions.length)];
      }
      return bestActions[_random.nextInt(bestActions.length)];
    }
  }

  /// Return the list of actions that reach the maximum Q-value for [stateHash]
  List<ParameterAction> _actionsWithMaxQ(int stateHash, List<ParameterAction> actions) {
    double maxQ = double.negativeInfinity;
    for (final action in actions) {
      final q = getQValue(stateHash, action);
      if (q > maxQ) maxQ = q;
    }
    final best = <ParameterAction>[];
    for (final action in actions) {
      final q = getQValue(stateHash, action);
      if (q == maxQ) best.add(action);
    }
    return best;
  }

  /// Get Q-value for a state-action pair
  double getQValue(int stateHash, ParameterAction action) {
    return qTable[(stateHash, action)] ?? 0.0;
  }

  /// Update Q-value based on reward
  void update(int currentStateHash, ParameterAction action, double reward, int nextStateHash, {List<ParameterAction>? allowedActions}) {
    double currentQ = getQValue(currentStateHash, action);
    
    // Find max Q-value for next state across all actions
    final actions = allowedActions ?? ParameterAction.values;
    double maxNextQ = double.negativeInfinity;
    for (final nextAction in actions) {
      double q = getQValue(nextStateHash, nextAction);
      if (q > maxNextQ) maxNextQ = q;
    }
    
    // If no actions have been tried in next state, initialize to 0
    if (maxNextQ == double.negativeInfinity) maxNextQ = 0.0;
    
    // Q-learning update rule
    double newQ = currentQ + learningRate * (reward + discountFactor * maxNextQ - currentQ);
    qTable[(currentStateHash, action)] = newQ;
  }
  
  /// Decay exploration rate over time
  void decayEpsilon({double minEpsilon = 0.05, double decayRate = 0.995}) {
    epsilon = max(minEpsilon, epsilon * decayRate);
  }
}

/// Simple 3-bucket discretizer helper for parameter values.
int bucketParam3(double v, {double low = 0.8, double high = 1.2}) {
  if (v <= low) return 0;
  if (v <= high) return 1;
  return 2;
}
