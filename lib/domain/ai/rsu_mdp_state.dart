import 'package:daemon/domain/ai/mdp_agent.dart';

/// State observation for RSU agents
class RSUMDPState extends MDPState {
  // Simplified RSU state
  double processedRate = 0.0; // processed per subframe (or normalized rate)
  int consecutiveCollisions = 0;
  // collisions in interval tracked by consecutiveCollisions
  int timeoutBucket = 1;
  int jitterBucket = 1;

  @override
  void reset() {
    super.reset();
    processedRate = 0.0;
    consecutiveCollisions = 0;
    // base class resets soft/hard resets
    timeoutBucket = 1;
    jitterBucket = 1;
  }

  // No medium utilization kept here for the simplified RSU state

  @override
  @override
  Map<String, dynamic> toMap() {
    return {
      'processedRate': processedRate,
      // no interval collision count field here; consecutiveCollisions is used instead
      'consecutiveCollisions': consecutiveCollisions,
      'timeoutBucket': timeoutBucket,
      'jitterBucket': jitterBucket,
    };
  }

  /// Generate a hash code for the state (for Q-table indexing)
  int getStateHash() {
    // Coarse buckets: processedRate (0/low/high), diffProcessed (0/1/2+), collisions (0/1/2+)
    final int rateBucket = processedRate <= 0.0 ? 0 : (processedRate < 0.05 ? 1 : 2);
    final int collBucket = consecutiveCollisions >= 2 ? 2 : consecutiveCollisions;
    return Object.hash(rateBucket, collBucket, timeoutBucket, jitterBucket);
  }

  @override
  String toString() {
      return 'RSUState(processedRate: ${processedRate.toStringAsFixed(3)}, '
          'consecutiveCollisions: $consecutiveCollisions, tB: $timeoutBucket, jB: $jitterBucket)';
  }
}

/// RSU-specific parameters
class RSUMDPParameters extends MDPParameters {
  @override
  String toString() {
    return 'RSUParams(${paramsToString()})';
  }
  
  @override
  Map<String, double> toMap() {
    // RSUs don't use broadcast interval adjustments
    return {
      'timeout': timeoutMultiplier,
      'jitter': jitterMultiplier,
    };
  }
}
