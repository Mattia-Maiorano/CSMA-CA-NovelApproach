import 'dart:math' as math;

import 'package:daemon/domain/entities/classic_car.dart';
import 'package:daemon/domain/entities/entity.dart';
import 'package:daemon/domain/network/signal.dart';
import 'package:daemon/domain/ai/mdp_agent.dart';
import 'package:daemon/domain/ai/car_mdp_state.dart';
import 'package:daemon/utils/config.dart';
import 'package:daemon/utils/measurement.dart';

/// MDP-enhanced Car that learns optimal parameters
class MDPCar extends Car {
  // MDP components
  final CarMDPParameters params = CarMDPParameters();
  final CarMDPState currentState = CarMDPState();
  final CarMDPState previousState = CarMDPState();
  final QLearningPolicy policy = QLearningPolicy();
  
  // Training tracking
  int completedSteps = 0;
  int stepsSinceLastTraining = 0;
  // Rolling mean buffer for seenCars
  final List<int> _seenCarsWindow = [];
  static const int _seenCarsWindowSize = 3;
  // latency to start first new conversation in the step (tick) - -1 if none
  int _firstNewConversationTick = -1;
  // whether a conversation was already ongoing at the start of the step
  bool _conversationOngoingAtStepStart = false;
  // Unused but kept for clarity: previous requested send state is captured at handleStage
  
  MDPCar({
    required super.id,
    required super.model,
    required super.position,
    required super.manhattanGrid,
    required super.range,
    required super.sensingRange,
    super.timer,
    super.analyzer,
  });

  @override
Measurement specificStep() {
    // Track state observations
    if (tick == SUBFRAMES - 1) {
      _observeStateAtEndOfStep();
    }
    // At the beginning of a subframe, track whether a conversation is already ongoing
    if (tick == 0) {
      _conversationOngoingAtStepStart = stage != TalkingStage.idle && stage != TalkingStage.rts;
      _firstNewConversationTick = -1;
    }

    return super.specificStep();
  }

  @override
  Signal? handleResponse() {
    Signal? signal = super.handleResponse();

    return signal;
  }

  @override
  void handleStage() {
    // Detect newly requested sends to record request time for latency measurement
    final wasRequesting = requestedSend;
    super.handleStage();
    if (!wasRequesting && requestedSend && stage != TalkingStage.idle && stage != TalkingStage.rts) {
      if (!_conversationOngoingAtStepStart && _firstNewConversationTick == -1) {
        _firstNewConversationTick = tick;
      }
    }

    // Track when car completes full communication (gets processed)
    // Note: processing counts were removed as a simplification; metric kept in analyzer only
  }

  @override
  void softReset() {
    currentState.softResets++;
    super.softReset();
  }

  @override
  void reset({bool resetNav = true}) {
    currentState.hardResets++;
    super.reset(resetNav: resetNav);
  }

  @override
  void handleTimers() {
    if (nav > 0) {
      nav--;

      if (nav == 0) {
        /* nav expired - previously used for debugging */
      }
      // Apply learned broadcast multiplier + jitter when NAV expires
      if (nav == 0) {
        final baseWindow = (BROADCAST * params.broadcastIntervalMultiplier).round();
        final jitterWindow = math.max(1, (baseWindow * params.jitterMultiplier).round());
        broadcastTimer = math.Random().nextInt(jitterWindow);
      }

    } else if (state == NodeState.idle) {
      // Apply learned broadcast multiplier
      if (broadcastTimer > 0) {
        broadcastTimer--;
      }
    } else if (requestedSend) {
      ifsTimer = 0;

      if (backoffSlots == -1) {
        int maxSlots = ((2 << consecutiveCollisions) - 1);
        backoffSlots = math.Random().nextInt(math.max(1, maxSlots));
      } else if (backoffSlots > 0) {
        backoffSlots--;
      } else {
        backoffSlots = -1;
        backoffExpired = true;
      }
    } else if (state == NodeState.querying) {
      ifsTimer++;
    }

    // Apply learned timeout multiplier
    if (timeout >= (RESETTIME * params.timeoutMultiplier).round()) {
      if (consecutiveCollisions < MAX_BACKOFF_EXPONENT) {
        softReset();
        softRst = true;
      } else {
        reset();
        hardRst = true;
      }
      timeout = 0;
    } else if (nav == 0 && state != NodeState.idle && state != NodeState.sleeping) {
      timeout++;
    }
  }

  @override
  void handleState() {
    // Apply learned broadcast interval
    if (broadcastTimer == 0 && state == NodeState.idle) {
      timeout = 0;
      final baseWindow = (BROADCAST * params.broadcastIntervalMultiplier).round();
      final jitterWindow = math.max(1, (baseWindow * params.jitterMultiplier).round());
      broadcastTimer = math.Random().nextInt(jitterWindow);
      nextState(NodeState.querying);
    } else {
      super.handleState();
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
    // Calculate reward based on performance
    double reward = _computeReward();

    // Update simplified state fields
    currentState.carsInRange = seenCarsCount;
    currentState.consecutiveCollisions = consecutiveCollisions;
    // update rolling mean
    _seenCarsWindow.add(seenCarsCount);
    if (_seenCarsWindow.length > _seenCarsWindowSize) _seenCarsWindow.removeAt(0);
    final mean = _seenCarsWindow.isNotEmpty ? _seenCarsWindow.reduce((a, b) => a + b) / _seenCarsWindow.length : 0.0;
    currentState.carsInRangeRollingMean = mean;

    // Set hashed param buckets in state so the agent knows its current params
    currentState.broadcastBucket = bucketParam3(params.broadcastIntervalMultiplier);
    currentState.timeoutBucket = bucketParam3(params.timeoutMultiplier);
    currentState.jitterBucket = bucketParam3(params.jitterMultiplier);

    // Get state hashes
    int prevHash = previousState.getStateHash();
    int currHash = currentState.getStateHash();

    // Select action using epsilon-greedy
    ParameterAction action = policy.selectAction(prevHash);
    // record action for analysis
    analyzer?.recordMDPAction(id, action.toString());

    // Apply the selected action
    params.applyAction(action);

    // Update Q-values
    policy.update(prevHash, action, reward, currHash);

    // Decay exploration rate
    policy.decayEpsilon();

    // Report progress to analyzer
    final stateMap = Map<String, dynamic>.from(currentState.toMap());
    // ensure we include seen cars even if not already included
    stateMap['carsInRange'] = currentState.carsInRange;
    stateMap['rsusInRange'] = seenRsusCount;
    analyzer?.recordMDPProgress(
      id,
      'Car',
      reward,
      stateMap,
      params.toMap(),
    );

    _copyState(currentState, previousState);
    currentState.reset();
    // Reset conversation-start tracking for the next step
    // Reset conversation-start tracking for the next step
    _firstNewConversationTick = -1;
    _conversationOngoingAtStepStart = false;
  }

  /// Compute reward based on Car performance with focus on efficiency
  double _computeReward() {
    double reward = 0.0;
    const double collisionPenalty = 2.0; // penalty multiplier for collisions

    reward -= (consecutiveCollisions * collisionPenalty);
    if (!free && !stop) reward -= 10.0;
    else reward += 5.0;

    // Reward for starting conversations quickly: higher normalized value (near 1) yields higher reward
    const double startLatencyWeight = 4.0;
    // compute normalized start latency: 1.0 if ongoing at step start, 0.0 if no new convo started in step
    double startLatencyNormalized;
    if (_conversationOngoingAtStepStart) {
      startLatencyNormalized = 1.0;
    } else if (_firstNewConversationTick != -1) {
      startLatencyNormalized = 1.0 - (_firstNewConversationTick / (SUBFRAMES - 1).toDouble());
      if (startLatencyNormalized < 0.0) startLatencyNormalized = 0.0;
    } else {
      startLatencyNormalized = 0.0;
    }
    reward += startLatencyWeight * startLatencyNormalized;

    return reward;
  }

  /// Copy state values
  void _copyState(CarMDPState from, CarMDPState to) {
    to.softResets = from.softResets;
    to.hardResets = from.hardResets;
    to.carsInRange = from.carsInRange;
    to.carsInRangeRollingMean = from.carsInRangeRollingMean;
    to.consecutiveCollisions = from.consecutiveCollisions;
    to.broadcastBucket = from.broadcastBucket;
    to.timeoutBucket = from.timeoutBucket;
    to.jitterBucket = from.jitterBucket;
  }
}
