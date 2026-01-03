/// ============================================================================
/// Base Entity Class for V2X Simulation
/// ============================================================================
/// Abstract base class for all network entities (Cars and RSUs).
/// Implements the CSMA/CA-like MAC protocol state machine with:
/// - NodeState: idle, sleeping, waiting, querying, collision
/// - TalkingStage: idle, rts, cts, query, response, ack (handshake phases)
///
/// Subclasses must implement:
/// - specificStep(): Entity-specific logic per tick
/// - handleState/handleStage/handleSignal/handleResponse/handleTimers
/// - softReset(): Collision recovery behavior
/// ============================================================================

import 'package:daemon/domain/entities/position.dart';
import 'package:daemon/domain/network/signal.dart';
import 'package:daemon/utils/analyzer.dart';
import 'package:daemon/utils/config.dart';
import 'package:daemon/utils/measurement.dart';

/// States of the MAC protocol state machine.
enum NodeState {
  idle, // Not communicating
  sleeping, // Temporarily inactive
  waiting, // Waiting for response after transmission
  querying, // Actively transmitting
  collision, // Detected collision, handling backoff
}

/// Stages of the RTS/CTS/Query/Response/ACK handshake.
enum TalkingStage {
  idle, // No active handshake
  rts, // Request-To-Send sent/expected
  cts, // Clear-To-Send sent/expected
  query, // Query data sent/expected
  response, // Response data sent/expected
  ack, // Acknowledgment sent/expected
}

/// Base class for all simulation entities (Cars, RSUs).
abstract class Entity<T> {
  // ─────────────────────────────────────────────────────────────────────────
  // Identity & Configuration
  // ─────────────────────────────────────────────────────────────────────────
  final int id;
  final int range; // Transmission range in tiles
  final int sensingRange; // Reception/sensing range in tiles
  Position position;
  final Analyzer? analyzer;

  // ─────────────────────────────────────────────────────────────────────────
  // Protocol State
  // ─────────────────────────────────────────────────────────────────────────
  NodeState state = NodeState.idle;
  TalkingStage stage = TalkingStage.idle;

  String emoji = "❓";

  bool requestedSend = false;
  bool confirmedSend = false;
  bool requestedQueueReceive = false;
  bool queuedReceive = false;
  bool queuedSleep = false;
  bool queuedWake = false;
  bool requestedExit = false;
  bool backoffExpired = false;
  bool softRst = false;
  bool hardRst = false;
  bool communicationOngoing = false;

  int ifsTimer = 0;
  int nav = 0;
  int pal = -1;
  int consecutiveCollisions = STARTING_EXPONENT;
  int backoffSlots = -1;
  int timeout = 0;
  int tick = 0;
  int frame = 0;

  // Count of visible entities on the last tick (entity-local knowledge)
  int seenCarsCount = 0;
  int seenRsusCount = 0;

  Signal? lastSeenSignal;
  TalkingStage? lastReachedStage;
  NodeState? lastReachedState;
  // Marker set by Analyzer when an agent's epsilon was increased.
  // The flag is visible for one frame (tick) so UI painters can render it.
  bool epsilonChanged = false;
  // Last episode index when epsilon changed for this node; useful for debugging
  int lastEpsilonChangeEpisode = -1;

  Entity(
    this.id,
    this.position,
    this.range,
    this.sensingRange,
    this.ifsTimer, {
    this.analyzer,
  });

  (Signal?, Measurement) step(int tick, int frame, Signal? signalToRead) {
    this.tick = tick;
    this.frame = frame;

    // UI marker for epsilon changes to reset at start of each step
    if (tick == 0) epsilonChanged = false;

    softRst = false;
    hardRst = false;

    handleState();
    handleTimers();
    handleSignal(signalToRead);

    Signal? signal;
    if (state == NodeState.querying || state == NodeState.collision) {
      signal = handleResponse();
    }

    handleStage();

    return (signal, specificStep());
  }

  Measurement specificStep();

  void handleState();

  void handleStage();

  void handleSignal(Signal? signalToRead);

  Signal? handleResponse();

  void handleTimers();

  void nextState(NodeState newState) {
    state = newState;
  }

  void enterCollisionHandling() {
    lastReachedStage = stage;
    lastReachedState = state;
    previousStage();
    state = NodeState.collision;
    consecutiveCollisions++;
  }

  void switchState() {
    if (state == NodeState.querying) {
      state = NodeState.waiting;
    } else if (state == NodeState.waiting) {
      state = NodeState.querying;
    }
  }

  void nextStage(TalkingStage newStage) {
    stage = newStage;
  }

  void restoreState() {
    if (lastReachedState != null) {
      state = lastReachedState!;
      if (state == NodeState.waiting) confirmedSend = false;
    }
  }

  void reset({bool resetNav = true}) {
    ifsTimer = 0;
    state = NodeState.idle;
    stage = TalkingStage.idle;
    requestedSend = false;
    confirmedSend = false;
    queuedReceive = false;
    queuedSleep = false;
    queuedWake = false;
    requestedExit = false;
    backoffExpired = false;
    pal = -1;
    consecutiveCollisions = STARTING_EXPONENT;
    backoffSlots = -1;
    timeout = 0;
    lastSeenSignal = null;
    requestedQueueReceive = false;
    if (resetNav) nav = 0;
  }

  void softReset();

  void previousStage() {
    if (stage == TalkingStage.rts) {
      stage = TalkingStage.idle;
    } else if (stage == TalkingStage.cts) {
      stage = TalkingStage.rts;
    } else if (stage == TalkingStage.query) {
      stage = TalkingStage.cts;
    } else if (stage == TalkingStage.response) {
      stage = TalkingStage.query;
    }
  }

  int getNav(SignalType type) {
    switch (type) {
      case SignalType.rts:
        return NAVTIME;
      case SignalType.cts:
        return NAVTIMECTS;
      case SignalType.query:
        return NAVTIMEQUERY;
      case SignalType.response:
        return NAVTIMERESPONSE;
      case SignalType.ack:
        return NAVTIMEACK;
      default:
        return 0;
    }
  }
}
