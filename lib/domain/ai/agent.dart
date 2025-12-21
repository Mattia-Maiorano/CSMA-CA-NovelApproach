 
/// Minimal Agent interface for node-level RL in the simulation.
abstract class Agent {
  final int id;
  final List<String> actions;

  Agent(this.id, this.actions);

  /// Build a concise state representation from entity fields
  Map<String, dynamic> stateFromEntity(dynamic entity);

  /// Choose an action given a state. The returned action must be one of `actions`.
  String chooseAction(Map<String, dynamic> state);

  /// Learn/update policy using a single transition.
  void learn(Map<String, dynamic> state, String action, double reward, Map<String, dynamic> nextState, {bool done = false, double? gammaOverride});

  /// Return readable training parameters (hyperparameters) for logging.
  Map<String, double> parameters();

  /// Get agent's exploration epsilon (if applicable). Default: return 0.
  double getEpsilon();

  /// Set agent's exploration epsilon (if applicable). Default: no-op.
  void setEpsilon(double e);
}
