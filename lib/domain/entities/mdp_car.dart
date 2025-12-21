import 'dart:math';

import 'package:daemon/domain/entities/classic_car.dart';
import 'package:daemon/domain/entities/position.dart';
import 'package:daemon/utils/config.dart';
import 'package:daemon/utils/measurement.dart';
import 'package:daemon/domain/ai/agent.dart';

class MDPCar extends Car {
  final Agent agent;
  Map<String, dynamic>? _lastState;
  String? _lastAction;

  MDPCar({required int id, required int model, required Position position, required List<List<int>> manhattanGrid, required int range, required int sensingRange, int timer = 0, super.analyzer, required this.agent})
      : super(id: id, model: model, position: position, manhattanGrid: manhattanGrid, range: range, sensingRange: sensingRange, timer: timer) {
    // Register this agent in Analyzer (when available) for live epsilon adaptations
    analyzer?.registerMdpAgent(id, agent);
    // Register entity too so Analyzer can toggle a visual marker on epsilon changes
    analyzer?.registerMdpEntity(id, this);
  }

  Map<String, dynamic> _buildState() {
    final int tickBin = (tick * 4) ~/ SUBFRAMES; // 0..3
    // state for MDP agents:
    // - 'seenCars': number of unique cars seen during current subframe (episode)
    // - 'prevKnownCars': snapshot of seen cars count at the previous subframe end
    return {
      'seenCars': seenCarIds.length,
      'prevKnownCars': prevKnownCars,
      'tickBin': tickBin,
      'comm': communicationOngoing ? 1 : 0,
    };
  }

  void _applyAction(String action) {
    switch (action) {
      case 'noop':
        break;
      case 'startQuery':
        // trigger immediate broadcast
        broadcastTimer = 0;
        break;
      case 'defer':
        backoffSlots = Random().nextInt(3) + 1;
        break;
      default:
        // unknown action; noop
        break;
    }
  }

  @override
  void handleState() {

    final state = _buildState();
    final action = agent.chooseAction(state);

    // print('$tick-$id-${state})\t$emoji\tSEL\t: action=$action state=$state');

    analyzer?.recordMDPAction(id, action);

    _applyAction(action);

    super.handleState();

    // Keep last state/action for learning update later
    _lastState = state;
    _lastAction = action;
  }

  @override
  Measurement specificStep() {
    Measurement result = super.specificStep();

    // After step is done, provide reward feedback to agent
    handleRewards();

    if (tick == SUBFRAMES - 1) {
      prevKnownCars = seenCarIds.length;
      seenCarIds.clear();
    }

    return result;
  }

  void handleRewards() {

    // reward design: +1 for answered (response received)
    double reward = 0.0;

    // reward for communicating or sleeping
    if (communicationOngoing) reward += 0.5;
    else if (nav > 0) reward += 0.5;

    // penalize talking after having already been answered
    if ((free || stop) && communicationOngoing) reward -= 1.0;

    // last tick big reward
    if (tick == SUBFRAMES - 1 && (free || stop)) reward += 10;
    else if (tick == SUBFRAMES - 1) reward -= 10;

    /*
    // Functioning but based on full step logic
    if (tick == SUBFRAMES - 1) {
      if (free || stop) reward += 1.0;
      else reward -= 1.0;
    }
    */

    // Build next-state representation
    final sPrime = _buildState();

    // Report learning step to agent and analyzer
    if (_lastState != null && _lastAction != null) {
      try {
        final int remainingTicks = SUBFRAMES - 1 - tick;
        final bool done = remainingTicks <= 0;
        double? gammaOverride;
        if (!done && remainingTicks > 0) {
          gammaOverride = pow(GAMMA_FRAME, remainingTicks / SUBFRAMES).toDouble();
        }
        agent.learn(_lastState!, _lastAction!, reward, sPrime, done: done, gammaOverride: gammaOverride);
        if (tick == SUBFRAMES - 1) analyzer?.recordMDPProgress(id, 'Car', reward, sPrime, agent.parameters());
      } catch (e) {
        print('Agent learn failed for car $id: $e');
      }
    }
  }
}
