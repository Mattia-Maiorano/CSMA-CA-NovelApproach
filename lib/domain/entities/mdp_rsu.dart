/// ============================================================================
/// MDP RSU Entity - Reinforcement Learning Roadside Unit
/// ============================================================================
/// Extends the classic RSU with Q-Learning based decision making.
///
/// Decision Points:
/// - When idle and medium is free: choose 'ready' or 'defer'
/// - Agent learns from outcomes: successful responses, collisions, timeouts
///
/// Reward Structure:
/// - Successful response: +2.0
/// - Soft reset (collision): -0.5 * congestion_factor
/// - Hard reset: -1.0 * congestion_factor
/// - Ready but no car: -0.2 * congestion_factor
/// - Deferral: -0.1 (small cost for waiting)
/// ============================================================================

import 'dart:math';

import 'package:daemon/domain/entities/classic_rsu.dart';
import 'package:daemon/domain/entities/entity.dart';
import 'package:daemon/domain/network/signal.dart';
import 'package:daemon/domain/ai/agent.dart';
import 'package:daemon/utils/measurement.dart';
import 'package:daemon/utils/config.dart';

/// Decision-based MDP RSU: queries agent only at decision points, learns after outcome.
class MDPRSU extends RSU {
  final Agent agent;

  // Decision tracking
  Map<String, dynamic>? _decisionState; // State when decision was made
  String? _pendingAction; // Action waiting for outcome
  bool _waitingOutcome = false; // Whether we're waiting for an outcome

  // Response tracking
  final Set<int> _answered = {};
  int _responsesAtDecision = 0; // Responses when decision was made

  MDPRSU({
    required super.id,
    required super.position,
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
    'queue': (knownCars.length - _answered.length).clamp(0, 4),
  };

  /// Check if we're at a decision point: idle and medium free
  bool _canDecide() => state == NodeState.idle && nav == 0 && !_waitingOutcome;

  /// Check if the pending action's outcome is resolved
  bool _outcomeResolved() {
    if (!_waitingOutcome || _pendingAction == null) return false;

    if (_pendingAction == 'ready') {
      // Outcome: communication completed (back to idle) or collision
      final commDone = state == NodeState.idle && stage == TalkingStage.idle;
      final collision = softRst || hardRst;
      // Also resolve if we gave a response
      final gaveResponse = _answered.length > _responsesAtDecision;
      return (commDone && gaveResponse) || collision;
    } else if (_pendingAction == 'defer') {
      // Outcome: backoff expired and back to idle
      return backoffSlots <= 0 && state == NodeState.idle;
    }
    return false;
  }

  /// Non-linear congestion factor: penalties softened when many cars nearby
  /// Returns value in (0, 1] - lower when more congested
  double _congestionFactor() {
    final n = knownCars.length;
    // Quadratic scaling: 1/(1 + 0.5*n²)
    // n=0: 1.0, n=1: 0.67, n=2: 0.33, n=3: 0.18, n=4: 0.11
    return 1.0 / (1.0 + 0.5 * n * n);
  }

  /// Compute reward for the completed action
  double _computeReward() {
    double r = 0.0;
    final newResponses = _answered.length - _responsesAtDecision;
    final cf = _congestionFactor();

    if (_pendingAction == 'ready') {
      if (newResponses > 0) r += 2.0;             // Success: full reward
      else if (softRst) r -= 0.5 * cf;            // Collision: scaled penalty
      else if (hardRst) r -= 1.0 * cf;            // Hard reset: scaled penalty
      else r -= 0.2 * cf;                         // Ready but no car: scaled penalty
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
      _responsesAtDecision = _answered.length;
      analyzer?.recordMDPAction(id, _pendingAction!);

      // Apply the action
      if (_pendingAction == 'defer') {
        backoffSlots = Random().nextInt(3) + 1;
      }
      // 'ready' = no action needed, just be available
    }

    super.handleState();
  }

  @override
  void handleSignal(Signal? signalToRead) {
    if (signalToRead != null) {
      // Track responses we've given
      if (signalToRead.type == SignalType.response && !_answered.contains(signalToRead.ownerId)) {
        _answered.add(signalToRead.ownerId);
      }
    }
    super.handleSignal(signalToRead);
  }

  @override
  Signal? handleResponse() {
    final signal = super.handleResponse();
    if (signal?.type == SignalType.response && !_answered.contains(signal!.ownerId)) {
      _answered.add(signal.ownerId);
    }
    return signal;
  }

  @override
  Measurement specificStep() {
    final m = super.specificStep();

    // Check if outcome is resolved → learn immediately
    if (_outcomeResolved()) {
      final reward = _computeReward();
      final nextState = _state();
      final done = tick == SUBFRAMES - 1;

      agent.learn(
        _decisionState!,
        _pendingAction!,
        reward,
        nextState,
        done: done,
      );
      analyzer?.recordMDPProgress(
        id,
        'RSU',
        reward,
        nextState,
        agent.parameters(),
      );

      // Reset decision tracking
      _decisionState = null;
      _pendingAction = null;
      _waitingOutcome = false;
    }

    // End of frame cleanup
    if (tick == SUBFRAMES - 1) {
      // If still waiting for outcome at frame end, learn with appropriate reward
      if (_waitingOutcome && _decisionState != null && _pendingAction != null) {
        final newResponses = _answered.length - _responsesAtDecision;
        final penalty = newResponses > 0 ? 1.0 : -1.0;
        agent.learn(
          _decisionState!,
          _pendingAction!,
          penalty,
          _state(),
          done: true,
        );
        analyzer?.recordMDPProgress(
          id,
          'RSU',
          penalty,
          _state(),
          agent.parameters(),
        );
      }

      _answered.clear();
      _decisionState = null;
      _pendingAction = null;
      _waitingOutcome = false;
    }

    return m;
  }
}
