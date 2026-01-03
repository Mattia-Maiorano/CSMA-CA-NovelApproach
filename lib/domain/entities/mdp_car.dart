import 'dart:math';

import 'package:daemon/domain/entities/classic_car.dart';
import 'package:daemon/domain/entities/entity.dart';
import 'package:daemon/utils/config.dart';
import 'package:daemon/utils/measurement.dart';
import 'package:daemon/domain/ai/agent.dart';

/// Decision-based MDP Car: queries agent only at decision points, learns after outcome.
class MDPCar extends Car {
  final Agent agent;

  // Decision tracking
  Map<String, dynamic>? _decisionState;  // State when decision was made
  String? _pendingAction;                 // Action waiting for outcome
  bool _waitingOutcome = false;           // Whether we're waiting for an outcome

  MDPCar({
    required super.id,
    required super.model,
    required super.position,
    required super.manhattanGrid,
    required super.range,
    required super.sensingRange,
    super.timer = 0,
    super.analyzer,
    required this.agent,
  }) {
    analyzer?.registerMdpAgent(id, agent);
    analyzer?.registerMdpEntity(id, this);
  }

  Map<String, dynamic> _state() => {
    'tick': (tick * 4) ~/ SUBFRAMES,
    'busy': nav > 0 ? 1 : 0,
    'resolved': (free || stop) ? 1 : 0,
  };

  /// Check if we're at a decision point: idle, medium free, not already resolved
  bool _canDecide() =>
      state == NodeState.idle && nav == 0 && !(free || stop) && !_waitingOutcome;

  /// Check if the pending action's outcome is resolved
  bool _outcomeResolved() {
    if (!_waitingOutcome || _pendingAction == null) return false;

    if (_pendingAction == 'startComm') {
      // Outcome: communication completed (back to idle) or collision happened
      final commDone = state == NodeState.idle && stage == TalkingStage.idle;
      final resolved = free || stop;
      final collision = softRst || hardRst;
      return commDone || resolved || collision;
    } else if (_pendingAction == 'defer') {
      // Outcome: backoff expired (backoffSlots back to -1 or 0) and still idle
      return backoffSlots <= 0 && state == NodeState.idle;
    }
    return false;
  }

  /// Non-linear congestion factor: penalties softened when many cars nearby
  /// Returns value in (0, 1] - lower when more congested
  double _congestionFactor() {
    final n = seenCarIds.length;
    // Quadratic scaling: 1/(1 + 0.5*n²)
    // n=0: 1.0, n=1: 0.67, n=2: 0.33, n=3: 0.18, n=4: 0.11
    return 1.0 / (1.0 + 0.5 * n * n);
  }

  /// Compute reward for the completed action
  double _computeReward() {
    double r = 0.0;
    final cf = _congestionFactor();

    if (_pendingAction == 'startComm') {
      if (free || stop) r += 3.0;                 // Success: full reward
      else if (softRst) r -= 1.0 * cf;            // Collision: scaled penalty
      else if (hardRst) r -= 2.0 * cf;            // Hard reset: scaled penalty
      else r -= 0.5 * cf;                         // Comm failed: scaled penalty
    } else if (_pendingAction == 'defer') {
      r -= 0.1;                                   // Deferral: flat cost
    }

    return r;
  }

  @override
  void handleState() {
    // Decision point: agent chooses action only when it can actually act
    if (_canDecide()) {
      _decisionState = _state();
      _pendingAction = agent.chooseAction(_decisionState!);
      _waitingOutcome = true;
      analyzer?.recordMDPAction(id, _pendingAction!);

      // Apply the action
      if (_pendingAction == 'startComm') {
        broadcastTimer = 0;  // Trigger query
      } else if (_pendingAction == 'defer') {
        backoffSlots = Random().nextInt(3) + 1;
      }
    }

    super.handleState();
  }

  @override
  Measurement specificStep() {
    final result = super.specificStep();

    // Check if outcome is resolved → learn immediately
    if (_outcomeResolved()) {
      final reward = _computeReward();
      final nextState = _state();
      final done = (free || stop) || tick == SUBFRAMES - 1;

      agent.learn(_decisionState!, _pendingAction!, reward, nextState, done: done);
      analyzer?.recordMDPProgress(id, 'Car', reward, nextState, agent.parameters());

      // Reset decision tracking
      _decisionState = null;
      _pendingAction = null;
      _waitingOutcome = false;
    }

    // End of frame cleanup
    if (tick == SUBFRAMES - 1) {
      // If still waiting for outcome at frame end, learn with penalty
      if (_waitingOutcome && _decisionState != null && _pendingAction != null) {
        final penalty = (free || stop) ? 1.0 : -3.0;  // Unfinished action
        agent.learn(_decisionState!, _pendingAction!, penalty, _state(), done: true);
        analyzer?.recordMDPProgress(id, 'Car', penalty, _state(), agent.parameters());
      }

      prevKnownCars = seenCarIds.length;
      seenCarIds.clear();
      _decisionState = null;
      _pendingAction = null;
      _waitingOutcome = false;
    }

    return result;
  }
}
