import 'dart:math' as math;

import 'package:daemon/domain/entities/classic_rsu.dart';
import 'package:daemon/domain/entities/entity.dart';
import 'package:daemon/domain/network/signal.dart';
import 'package:daemon/domain/ai/mdp_agent.dart';
import 'package:daemon/domain/ai/rsu_mdp_state.dart';
import 'package:daemon/utils/config.dart';
import 'package:daemon/utils/measurement.dart';

/// MDP-enhanced RSU that learns optimal parameters
class MDPRSU extends RSU {
  // MDP components
  final RSUMDPParameters params = RSUMDPParameters();
  final RSUMDPState currentState = RSUMDPState();
  final RSUMDPState previousState = RSUMDPState();
  final QLearningPolicy policy = QLearningPolicy();
  final Set<int> processedCarIds = {};
  final Set<int> seenCarIds = {};
  final Set<int> _seenCarIdsInterval = {};
  int get seenCarsCount => seenCarIds.length;

  // Training tracking
  int completedSteps = 0;
  int stepsSinceLastTraining = 0;

  MDPRSU({
    required super.position,
    required super.id,
    required super.range,
    required super.sensingRange,
    super.timer,
    super.analyzer,
  });

  @override
  Measurement specificStep() {
    // Cleanup old knowledge
    if (tick == SUBFRAMES - 1) {
      for (final (car, t) in knownCars.toList()) {
        if (tick + frame * SUBFRAMES - t > PRUNECARS) {
          knownCars.remove((car, t));
        }
      }

      _observeStateAtEndOfStep();
    }

    return Measurement(
      state: state,
      stage: stage,
      free: false,
      answered: requestedExit,
      softReset: softRst,
      hardReset: hardRst,
    );
  }

  @override
  void handleSignal(Signal? signal) {
    super.handleSignal(signal);

    if (signal != null && signal.car != null) {
      seenCarIds.add(signal.car!.id);
      _seenCarIdsInterval.add(signal.car!.id);
    }
  }

  @override
  void handleStage() {
    super.handleStage();

    // Track when RSU completes full communication (car gets processed)
    if (requestedExit) {
      // Track unique different cars processed
      final carId = communicationCar?.id ?? pal;
      if (carId != -1) {
        processedCarIds.add(carId);
        // Debug: report processed car id
        print(
          'DEBUG_MDP_RSU: RSU $id processed car $carId (total processed: ${processedCarIds.length})',
        );
      }
    }
  }

  @override
  void softReset() {
    super.softReset();
  }

  @override
  void reset({bool resetNav = true}) {
    currentState.hardResets++;
    super.reset(resetNav: resetNav);
  }

  @override
  void handleTimers() {
    if (timeout >= (RESETTIME * params.timeoutMultiplier).round()) {
      if (consecutiveCollisions < MAX_BACKOFF_EXPONENT) {
        softReset();
        softRst = true;
      } else {
        reset();
        hardRst = true;
      }
      timeout = 0;
    } else if (nav == 0 &&
        state != NodeState.idle &&
        state != NodeState.sleeping) {
      timeout++;
    }

    if (nav > 0) {
      nav--;
    } else if (requestedSend) {
      ifsTimer = 0;

      if (backoffSlots == -1) {
        int maxSlots = ((2 << consecutiveCollisions) - 1);
        // Apply jitter multiplier to increase/decrease randomized backoff window
        final jitterWindow = math.max(
          1,
          (maxSlots * params.jitterMultiplier).round(),
        );
        backoffSlots = math.Random().nextInt(jitterWindow);
      } else if (backoffSlots > 0) {
        backoffSlots--;
      } else {
        backoffSlots = -1;
        backoffExpired = true;
      }
    } else if (state == NodeState.querying) {
      ifsTimer++;
    }
  }

  /// Observe state at the end of each step (SUBFRAMES)
  void _observeStateAtEndOfStep() {
    completedSteps++;
    stepsSinceLastTraining++;

    // Check if it's time to train
    if (stepsSinceLastTraining >= TRAINING_INTERVAL) {
      _trainPolicy();
      stepsSinceLastTraining = 0;
    }
  }

  /// Train the policy and update parameters
  void _trainPolicy() {
    // Update simplified state fields first using per-interval values
    // processedRate: processedCars / carsSeen in the last interval
    final seenInterval = _seenCarIdsInterval.length;
    currentState.processedRate = (seenInterval > 0)
        ? (processedCarIds.length / seenInterval)
        : 0.0;
    currentState.consecutiveCollisions = consecutiveCollisions;
    // consecutiveCollisions covers the collisions metric for this interval

    // Set param buckets in state
    currentState.timeoutBucket = bucketParam3(params.timeoutMultiplier);
    currentState.jitterBucket = bucketParam3(params.jitterMultiplier);

    // Calculate reward based on the updated currentState
    double reward = _computeReward();

    // Debug: log processed/seen counts and computed reward (post-update)
    print(
      'DEBUG_MDP_RSU: id=$id seenCarsInterval=$seenInterval processedCars=${processedCarIds.length} processedRate=${currentState.processedRate} reward=$reward',
    );

    // Get state hashes
    int prevHash = previousState.getStateHash();
    int currHash = currentState.getStateHash();

    // Select action using epsilon-greedy, excluding broadcast adjustments for RSU
    final nonBroadcastActions = ParameterAction.values
        .where(
          (a) =>
              a != ParameterAction.increaseBroadcastSmall &&
              a != ParameterAction.increaseBroadcastLarge &&
              a != ParameterAction.decreaseBroadcastSmall &&
              a != ParameterAction.decreaseBroadcastLarge,
        )
        .toList();

    // Provide the allowed actions list so RSUs don't attempt broadcast-related adjustments
    ParameterAction action = policy.selectAction(
      prevHash,
      allowedActions: nonBroadcastActions,
    );
    // record action
    analyzer?.recordMDPAction(id, action.toString());

    // Apply the selected action
    params.applyAction(action);

    // Update Q-values only considering the allowed actions
    policy.update(
      prevHash,
      action,
      reward,
      currHash,
      allowedActions: nonBroadcastActions,
    );

    // Decay exploration rate
    policy.decayEpsilon();

    // Report progress to analyzer
    final stateMap = Map<String, dynamic>.from(currentState.toMap());
    stateMap['carsInRange'] = seenCarsCount;
    stateMap['rsusInRange'] = seenRsusCount;
    stateMap['processedCount'] = processedCarIds.length;
    analyzer?.recordMDPProgress(id, 'RSU', reward, stateMap, params.toMap());

    _copyState(currentState, previousState);
    currentState.reset();
    // Reset processed ID set and interval seen cars for the next interval
    processedCarIds.clear();
    _seenCarIdsInterval.clear();
    // processed car ids reset below
  }

  /// Compute reward based on RSU performance with focus on efficiency
  double _computeReward() {
    double reward = 0.0;

    // Penalty for collisions during the last interval
    const double collisionPenalty = 2.0;
    reward -= collisionPenalty * currentState.consecutiveCollisions;

    // Provide a contribution for processedRate
    reward += currentState.processedRate * 10.0;

    return reward;
  }

  /// Copy state values
  void _copyState(RSUMDPState from, RSUMDPState to) {
    to.processedRate = from.processedRate;
    // No 'responses' field to copy (removed from MDPState)
    to.hardResets = from.hardResets;
    to.consecutiveCollisions = from.consecutiveCollisions;
    to.jitterBucket = from.jitterBucket;
    to.timeoutBucket = from.timeoutBucket;
    // use softResets for interval collisions
  }
}
