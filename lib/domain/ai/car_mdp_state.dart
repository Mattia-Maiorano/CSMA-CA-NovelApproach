import 'package:daemon/domain/ai/mdp_agent.dart';
// no direct config required in CarMDPState

/// State observation for Car agents
class CarMDPState extends MDPState {
  // Replace complex state with the requested features
  int carsInRange = 0; // number of cars in sensing range
  int consecutiveCollisions = 0; // entity-level consecutive collisions
  double carsInRangeRollingMean = 0.0; // recent rolling mean of seen cars
  // Discretized parameters
  int broadcastBucket = 1;
  int timeoutBucket = 1;
  int jitterBucket = 1;

  @override
  void reset() {
    super.reset();
    carsInRange = 0;
    consecutiveCollisions = 0;
    carsInRangeRollingMean = 0.0;
    broadcastBucket = 1;
    timeoutBucket = 1;
    jitterBucket = 1;
  }

  // No medium utilization kept here for the simplified state

  @override
  @override
  Map<String, dynamic> toMap() {
    return {
      'carsInRange': carsInRange,
      'carsInRangeRollingMean': carsInRangeRollingMean,
      'consecutiveCollisions': consecutiveCollisions,
      'broadcastBucket': broadcastBucket,
      'timeoutBucket': timeoutBucket,
      'jitterBucket': jitterBucket,
    };
  }

  /// Generate a hash code for the state (for Q-table indexing)
  int getStateHash() {
    // Use the simplified features with coarse buckets
    final int carsBucket = carsInRange >= 3 ? 2 : (carsInRange >= 1 ? 1 : 0);
    final int collBucket = consecutiveCollisions >= 2 ? 2 : consecutiveCollisions;
    final int meanBucket = carsInRangeRollingMean >= 3.0 ? 2 : (carsInRangeRollingMean >= 1.0 ? 1 : 0);
    return Object.hash(carsBucket, collBucket, meanBucket, broadcastBucket, timeoutBucket, jitterBucket);
  }

  @override
  String toString() {
      return 'CarState(carsInRange: $carsInRange, rollingMean: ${carsInRangeRollingMean.toStringAsFixed(2)}, '
           'consecutiveCollisions: $consecutiveCollisions, bB: $broadcastBucket, tB: $timeoutBucket, jB: $jitterBucket)';
  }
}

/// Car-specific parameters
class CarMDPParameters extends MDPParameters {
  @override
  String toString() {
    // Delegate formatting to MDPParameters helper for consistency
    return 'CarParams(${paramsToString()})';
  }
}
