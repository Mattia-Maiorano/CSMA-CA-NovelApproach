import 'dart:math';

import 'package:daemon/domain/entities/classic_rsu.dart';
import 'package:daemon/domain/entities/position.dart';
import 'package:daemon/domain/network/signal.dart';
import 'package:daemon/domain/ai/agent.dart';
import 'package:daemon/utils/measurement.dart';
import 'package:daemon/utils/config.dart';

class MDPRSU extends RSU {
  final Agent agent;
  Map<String, dynamic>? _lastState;
  String? _lastAction;

  // local knowledge for the RSU agent
  int _responsesGivenInterval = 0;
  int prevKnownCars = 0;
  final Set<int> _answeredCars = {};

  MDPRSU({required int id, required Position position, required int range, required int sensingRange, int timer = 0, super.analyzer, required this.agent})
      : super(id: id, position: position, range: range, sensingRange: sensingRange, timer: timer) {
    analyzer?.registerMdpAgent(id, agent);
    // Register the entity to allow visual markers for epsilon changes
    analyzer?.registerMdpEntity(id, this);
  }

  Map<String, dynamic> _buildState() {
    final int tickBin = (tick * 4) ~/ SUBFRAMES; // 0..3
    // state for RSU MDP agents:
    // - 'seenCars': number of unique cars seen during current subframe (episode)
    // - 'prevKnownCars': number of cars in RSU's known list at the last subframe end
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
      case 'defer':
        backoffSlots = Random().nextInt(3) + 1;
        break;
      default:
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
    _lastState = state;
    _lastAction = action;

    super.handleState();
  }

  @override
  void handleSignal(Signal? signalToRead) {
    if (signalToRead != null) {
      if (signalToRead.type == SignalType.response) {
        if (!_answeredCars.contains(signalToRead.ownerId)) {
          _answeredCars.add(signalToRead.ownerId);
          _responsesGivenInterval++;
        }
      }
    }
    super.handleSignal(signalToRead);
  }

  @override
  Signal? handleResponse() {
    final signal = super.handleResponse();

    if (signal != null && signal.type == SignalType.response) {

      if (!_answeredCars.contains(signal.ownerId)) {
        _answeredCars.add(signal.ownerId);
        _responsesGivenInterval++;
      }
    }
    return signal;
  }

  @override
  Measurement specificStep() {
    final m = super.specificStep();

    handleRewards();

    if (tick == SUBFRAMES - 1) {
      prevKnownCars = knownCars.length;
      // snapshot seenCars for the previous interval; the base RSU clears seenCarIds in its specificStep
      // we keep prevKnownCars here as the RSU-knowledge snapshot
      _responsesGivenInterval = 0;
      _answeredCars.clear();
    }

    return m;
  }

  void handleRewards() {
    double reward = 0.0;

    // reward for communicating or sleeping
    if (communicationOngoing) reward += 0.5;
    else if (nav > 0) reward += 0.5;

    // penalize if talking to a car that has already answered
    if (_answeredCars.contains(communicationCar?.id)) reward -= 0.1;

    // last tick big reward
    if (tick == SUBFRAMES - 1 && knownCars.isNotEmpty) reward += _responsesGivenInterval / knownCars.length * 10 - 5 + knownCars.length * 1;

    /*
    // Functioning but based on full step logic
    final carsSeenThisInterval = knownCars.length;
    if (carsSeenThisInterval > 0) reward += _responsesGivenInterval / carsSeenThisInterval - 0.5 + carsSeenThisInterval * 0.1;
    */

    final sPrime = _buildState();

    if (_lastState != null && _lastAction != null) {
      try {
        final int remainingTicks = SUBFRAMES - 1 - tick;
        final bool done = remainingTicks <= 0;
        double? gammaOverride;
        if (!done && remainingTicks > 0) {
          gammaOverride = pow(GAMMA_FRAME, remainingTicks / SUBFRAMES).toDouble();
        }
        agent.learn(_lastState!, _lastAction!, reward, sPrime, done: done, gammaOverride: gammaOverride);
        if (tick == SUBFRAMES - 1) analyzer?.recordMDPProgress(id, 'RSU', reward, sPrime, agent.parameters());
      } catch (e) {
        print('MDPRSU learn failed: $e');
      }
    }
  }
}