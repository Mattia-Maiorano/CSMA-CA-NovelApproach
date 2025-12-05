import 'dart:math';

import 'package:daemon/domain/entities/entity.dart';
import 'package:daemon/domain/entities/classic_car.dart';
import 'package:daemon/domain/entities/position.dart';
import 'package:daemon/domain/network/signal.dart';
import 'package:daemon/utils/config.dart';
import 'package:daemon/utils/measurement.dart';

class RSU extends Entity {

  Car? communicationCar;
  Set<(Car, int)> knownCars = {};


  RSU({required Position position, required int id, required int range, required int sensingRange, int timer = 0, super.analyzer}) : super(id, position, range, sensingRange, timer) {
    emoji = "🚦";
  }

  @override
  Measurement specificStep() {

    // ---- CLEANUP OLD KNOWLEDGE ----
    if (tick == SUBFRAMES - 1) {
      for (final (car, t) in knownCars.toList()) {
        if (tick + frame * SUBFRAMES - t > PRUNECARS) {
          knownCars.remove((car, t));
        }
      }
    }

    return Measurement(state: state, stage: stage, free: false, answered: requestedExit, softReset: softRst, hardReset: hardRst);
  }
  
  @override
  void handleState() {

    //    COLLISION HANDLING
    if (state == NodeState.collision && lastReachedStage == stage) {
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
    } else if ((state == NodeState.waiting || state == NodeState.idle) && queuedReceive) {
      timeout = 0;
      nextState(NodeState.querying);
      queuedReceive = false;
    }

    //    EXIT CONDITIONS
    else if (requestedExit) {
      timeout = 0;
      nextState(NodeState.idle);
      requestedExit = false;
    }

  }

  @override
  void handleTimers() {
    if (nav > 0) {
      nav--;

      if (nav == 0) print('$tick-$id-$state)\t$emoji\t⏰​\t: nav expired');

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

    if (timeout >= RESETTIME) {
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

      if (signalToRead.car != null) {
        communicationCar = signalToRead.car;
        updateKnowledge(signalToRead.car!);
      }

      if (state != NodeState.querying && validateSignal(signalToRead)) {

        requestedQueueReceive = true;
        pal = signalToRead.ownerId;
        ifsTimer = 0;
        
      } else if (signalToRead.type == SignalType.broken) {
      } else if (signalToRead.communicationOngoing && lastSeenSignal != signalToRead && signalToRead.ownerId != id) {
        lastSeenSignal = signalToRead;
        nav = max(nav, getNav(signalToRead.type));
        reset(resetNav: false);
        print('$tick-$id-$state)\t$emoji\t💤​\t: new nav -> $nav');
      }

    } else {

      if (requestedQueueReceive) queuedReceive = true;
      requestedQueueReceive = false;
    }
  }

  bool validateSignal(Signal signal) {

    if ((signal.destinationId == id && state == NodeState.waiting) || (signal.destinationId == -1)) {
      if (signal.type == SignalType.rts && (stage == TalkingStage.idle || stage == TalkingStage.rts)) {
        return true;
      } else if (signal.type == SignalType.query && stage == TalkingStage.query) {
        return true;
      } else if (signal.type == SignalType.ack && stage == TalkingStage.ack) {
        return true;
      }
    }

    return false;
  }

  @override
  Signal? handleResponse() {

    if (requestedSend && backoffExpired) {
      if (stage == TalkingStage.cts) {
        stage = TalkingStage.query;
        requestedSend = false;
        confirmedSend = true;

        final txRange = range;
        return Signal(
          ownerId: id,
          destinationId: pal,
          x: position.x,
          y: position.y,
          type: SignalType.cts,
          txRange: txRange,
        );
      } else if (stage == TalkingStage.response) {
        stage = TalkingStage.ack;
        requestedSend = false;
        confirmedSend = true;

        final txRange = range;
        return Signal(
          ownerId: id,
          destinationId: pal,
          x: position.x,
          y: position.y,
          type: SignalType.response,
          data: collision() ? SignalData.stop : SignalData.free,
          communicationOngoing: true,
          txRange: txRange,
        );
      }
    }

    return null;
  }
  
  @override
  void handleStage() {

    if (state == NodeState.querying || state == NodeState.collision) {
      if (stage == TalkingStage.cts && ifsTimer == SIFS) {
        requestedSend = true;
      } else if (stage == TalkingStage.response && ifsTimer == SIFS) {
        requestedSend = true;
      }
    }

    else {
      if (queuedReceive) {
        if (stage == TalkingStage.idle || stage == TalkingStage.rts) {
          stage = TalkingStage.cts;
        } else if (stage == TalkingStage.query) {
          stage = TalkingStage.response;
        } else if (stage == TalkingStage.ack) {
          stage = TalkingStage.idle;
          requestedExit = true;
        }
      }
    }

  }

  @override
  void softReset() {

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
  
  void updateKnowledge(Car newcar) {
    if (knownCars.any((entry) => entry.$1.id == newcar.id)) {
      knownCars = knownCars.map((entry) => entry.$1.id == newcar.id ? (entry.$1, tick + frame * SUBFRAMES) : entry).toSet();
    } else {
      knownCars.add((newcar, tick + frame * SUBFRAMES));
    }
  }

  bool collision() {
    final int cx = communicationCar!.position.x;
    final int cy = communicationCar!.position.y;
    final int cxNext = cx + communicationCar!.position.xVerse;
    final int cyNext = cy + communicationCar!.position.yVerse;

    print("KNOWN POSITIONS OF RSU $id: ");
    for (final (other, t) in knownCars) {
      print(" - Car ${other.id} at (${other.position.x}, ${other.position.y}) seen at tick $t");
    }

    // iterate once over known cars and look for potential conflicts
    for (final (other, _) in knownCars) {
      if (other.id == communicationCar!.id || other.stop == true) continue;

      final int ox = other.position.x;
      final int oy = other.position.y;

      // crossing at next step: if both cars will move into the same cell next tick
      final int oxNext = ox + other.position.xVerse;
      final int oyNext = oy + other.position.yVerse;
      if (oxNext == cxNext && oyNext == cyNext) return true;

      // approaching into each other's next position (swap)
      if (oxNext == cx && oyNext == cy && ox == cxNext && oy == cyNext) return true;
    }

    return false;
  }
}
