/// ============================================================================
/// Classic Car Entity - CSMA/CA Vehicle Implementation
/// ============================================================================
/// Represents a vehicle in the V2X simulation using standard CSMA/CA protocol.
///
/// Behavior:
/// - Periodically broadcasts RTS to request RSU assistance
/// - Follows RTS→CTS→Query→Response→ACK handshake
/// - Moves on the road grid according to direction tiles
/// - Receives "stop" or "free" responses from RSUs for collision avoidance
/// ============================================================================

import 'dart:math';

import 'package:daemon/domain/entities/position.dart';
import 'package:daemon/domain/entities/entity.dart';
import 'package:daemon/domain/network/signal.dart';
import 'package:daemon/utils/config.dart';
import 'package:daemon/utils/measurement.dart';

/// Vehicle entity using classic CSMA/CA MAC protocol.
class Car extends Entity {
  // ─────────────────────────────────────────────────────────────────────────
  // Configuration
  // ─────────────────────────────────────────────────────────────────────────
  final List<List<int>> manhattanGrid; // Road grid for movement
  final int model; // Visual model variant

  // ─────────────────────────────────────────────────────────────────────────
  // Knowledge & Timers
  // ─────────────────────────────────────────────────────────────────────────
  final Set<int> seenCarIds = {}; // IDs of cars seen in signals
  int prevKnownCars = 0;
  int broadcastTimer = BROADCAST; // Countdown to next RTS broadcast

  // ─────────────────────────────────────────────────────────────────────────
  // Movement State
  // ─────────────────────────────────────────────────────────────────────────
  bool stop = false; // RSU told car to stop (collision risk)
  bool free = false; // RSU told car it's free to move

  Car({
    required int id,
    required this.model,
    required Position position,
    required this.manhattanGrid,
    required int range,
    required int sensingRange,
    int timer = 0,
    super.analyzer,
  }) : super(id, position, range, sensingRange, timer) {
    emoji = "🚗";
  }

  @override
  void reset({bool resetNav = true}) {
    super.reset(resetNav: resetNav);
    seenCarIds.clear();
  }

  @override
  Measurement specificStep() {
    // ---- MOVEMENT LOGIC ----
    if (tick != 0) {
      if (!stop && tick == SUBFRAMES - 1) {
        _movementStep();
      }
    } else {
      stop = false;
      free = false;
    }

    return Measurement(
      state: state,
      stage: stage,
      free: free,
      answered: requestedExit,
      softReset: softRst,
      hardReset: hardRst,
    );
  }

  @override
  void handleState() {
    if (broadcastTimer == 0 && state == NodeState.idle) {
      timeout = 0;
      broadcastTimer = BROADCAST;
      nextState(NodeState.querying);
    }
    //    COLLISION HANDLING
    else if (state == NodeState.collision && lastReachedStage == stage) {
      restoreState();
    }
    //    SLEEP/WAKE CONDITIONS
    else if (queuedSleep) {
      timeout = 0;
      nextState(NodeState.sleeping);
      queuedSleep = false;
    } else if (queuedWake) {
      timeout = 0;
      nextState(NodeState.idle);
      queuedWake = false;
    }
    //    MAIN LOOP OF STATE MACHINE
    else if (state == NodeState.querying && confirmedSend) {
      timeout = 0;
      switchState();
      confirmedSend = false;
    } else if (state == NodeState.waiting && queuedReceive) {
      timeout = 0;
      switchState();
      queuedReceive = false;
    }
    //    EXIT CONDITIONS
    else if (requestedExit) {
      timeout = 0;
      nextState(NodeState.idle);
      requestedExit = false;
      communicationOngoing = false;
    }
  }

  @override
  void handleTimers() {
    if (nav > 0) {
      nav--;

      if (nav == 0) print('$tick-$id-$state)\t$emoji\t⏰​\t: nav expired');
      if (nav == 0) broadcastTimer = BROADCAST;
    } else if (state == NodeState.idle) {
      broadcastTimer--;
    } else if (requestedSend) {
      ifsTimer = 0;

      if (backoffSlots == -1) {
        backoffSlots = Random().nextInt((2 << consecutiveCollisions) - 1);
      } else if (backoffSlots > 0) {
        backoffSlots--;
      } else {
        backoffSlots = -1;
        backoffExpired = true;
      }
    } else if (state == NodeState.querying){
      ifsTimer++;
    }

    else if (timeout >= RESETTIME) {
      if (consecutiveCollisions < MAX_BACKOFF_EXPONENT) {
        softReset();
        softRst = true;
      } else {
        reset();
        hardRst = true;
      }
      timeout = 0;
    } else {
      timeout++;
    }
  }

  @override
  void handleSignal(Signal? signalToRead) {
    if (signalToRead != null) {
      if (signalToRead.car != null) seenCarIds.add(signalToRead.car!.id);

      if (state != NodeState.querying && validateSignal(signalToRead)) {
        requestedQueueReceive = true;
        pal = signalToRead.ownerId;
        ifsTimer = 0;

        if (signalToRead.type == SignalType.response) {
          if (signalToRead.data == SignalData.stop) {
            stop = true;
          } else if (signalToRead.data == SignalData.free) {
            free = true;
          }
        }
      } else if (signalToRead.type == SignalType.broken) {
      } else if (signalToRead.communicationOngoing && lastSeenSignal != signalToRead && signalToRead.ownerId != id) {
        lastSeenSignal = signalToRead;
        nav = max(nav, getNav(signalToRead.type));
        reset(resetNav: false);
        print('$tick-$id-$state)\t$emoji\t💤​\t: new nav -> $nav');
      } else if (requestedQueueReceive) {
        queuedReceive = true;
        requestedQueueReceive = false;
      }
    } else {
      if (requestedQueueReceive) queuedReceive = true;
      requestedQueueReceive = false;
    }
  }

  bool validateSignal(Signal signal) {

    if (signal.destinationId == id && (signal.ownerId == pal || pal == -1) && (state == NodeState.waiting || state == NodeState.collision)) {
      if (signal.type == SignalType.cts && stage == TalkingStage.rts) {
        return true;
      } else if (signal.type == SignalType.response && stage == TalkingStage.query) {
        return true;
      }
    }

    return false;
  }

  @override
  Signal? handleResponse() {
    if (requestedSend && backoffExpired) {
      if (stage == TalkingStage.idle) {
        stage = TalkingStage.rts;
        requestedSend = false;
        confirmedSend = true;

        final txRange = range;
        final signal = Signal(
          ownerId: id,
          destinationId: -1,
          x: position.x,
          y: position.y,
          type: SignalType.rts,
          car: this,
          txRange: txRange,
        );
        return signal;
      } else if (stage == TalkingStage.cts) {
        stage = TalkingStage.query;
        requestedSend = false;
        confirmedSend = true;
        communicationOngoing = true;

        final txRange = range;
        final signal = Signal(
          ownerId: id,
          destinationId: pal,
          x: position.x,
          y: position.y,
          type: SignalType.query,
          car: this,
          communicationOngoing: true,
          txRange: txRange,
        );
        return signal;
      } else if (stage == TalkingStage.response) {
        stage = TalkingStage.ack;
        requestedSend = false;
        requestedExit = true;

        final txRange = range;
        final signal = Signal(
          ownerId: id,
          destinationId: pal,
          x: position.x,
          y: position.y,
          type: SignalType.ack,
          car: this,
          communicationOngoing: true,
          txRange: txRange,
        );
        return signal;
      }
    }

    return null;
  }

  @override
  void handleStage() {
    if (state == NodeState.querying) {
      if (stage == TalkingStage.idle && ifsTimer == DIFS) {
        requestedSend = true;
      } else if (stage == TalkingStage.cts && ifsTimer == SIFS) {
        requestedSend = true;
      } else if (stage == TalkingStage.response && ifsTimer == SIFS) {
        requestedSend = true;
      }
    }

    else {
      if (queuedReceive) {
        if (stage == TalkingStage.rts) {
          stage = TalkingStage.cts;
        } else if (stage == TalkingStage.query) {
          stage = TalkingStage.response;
        }
      } else if (stage == TalkingStage.ack) {
        stage = TalkingStage.idle;
        requestedExit = true;
      }
    }
  }

  @override
  softReset() {
    if (state != NodeState.waiting) print("$tick-$id-$state)\t$emoji\t💥​\t: collision detected, no handling");
    if (state == NodeState.waiting) {
      enterCollisionHandling();
      requestedSend = true;
      confirmedSend = false;
      queuedReceive = false;
      backoffSlots = -1;
      backoffExpired = false;
      ifsTimer = 0;
    }
  }

  void _movementStep() {
    if (manhattanGrid[position.y][position.x] == 5) {
      position.direction = position.newDirection();
    }

    Position newPosition = moveForward();
    int maxRetries = 100;
    while (manhattanGrid[newPosition.y][newPosition.x] == 0 ||
        (manhattanGrid[newPosition.y][newPosition.x] != position.direction.index + 1 && manhattanGrid[newPosition.y][newPosition.x] != 5)) {
      if (maxRetries-- <= 0) break;
      position.direction = position.newDirection();
      newPosition = moveForward();
    }

    position = Position(
      x: newPosition.x,
      y: newPosition.y,
      direction: position.direction,
    );
  }

  Position moveForward() {
    switch (position.direction) {
      case Direction.up:
        return position.movedBy(0, -1);
      case Direction.down:
        return position.movedBy(0, 1);
      case Direction.left:
        return position.movedBy(-1, 0);
      case Direction.right:
        return position.movedBy(1, 0);
    }
  }
}
