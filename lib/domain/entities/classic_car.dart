import 'dart:math';

import 'package:daemon/domain/entities/position.dart';
import 'package:daemon/domain/entities/entity.dart';
import 'package:daemon/domain/network/signal.dart';
import 'package:daemon/utils/config.dart';

class Car extends Entity {
  final List<List<int>> manhattanGrid;
  final int model;

  bool stop = false;
  bool free = false;

  Car({required int id, required this.model, required Position position, required this.manhattanGrid, required int range, required int sensingRange, int timer = 0}) : super(id, position, range, sensingRange, timer) {
    emoji = "🚗";
  }

  @override
void specificStep(int tick) {

    // ---- MOVEMENT LOGIC ----
    if (tick != 0) {
      if (!stop && tick == SUBFRAMES - 1) {
        _movementStep();
      }
    } else {
      stop = false;
      free = false;
    }
  }

  @override
  void handleState(int tick) {

    if (tick % BROADCAST == 0 && state == NodeState.idle) {
      timeout = 0;
      nextState(NodeState.querying);
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
    else if (state == NodeState.querying && requestedExit) {
      timeout = 0;
      nextState(NodeState.idle);
      requestedExit = false;
    }

  }

  @override
  void handleStage(int tick) {
    
    if (state == NodeState.querying) {
      if (stage == TalkingStage.idle && ifsTimer == DIFS) {
        requestedSend = true;
        stage = TalkingStage.rts;
      } else if (stage == TalkingStage.cts && ifsTimer == SIFS) {
        requestedSend = true;
        stage = TalkingStage.query;
      } else if (stage == TalkingStage.response && ifsTimer == SIFS) {
        requestedSend = true;
        stage = TalkingStage.ack;
      }
    }

    else {
      if (queuedReceive) {
        if (stage == TalkingStage.rts) {
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
  void handleSignal(int tick, Signal? signalToRead) {
    if (signalToRead != null) {
      
      if (validateSignal(signalToRead)) {
        
        queuedReceive = true;
        pal = signalToRead.ownerId;
        ifsTimer = 0;
        
        if (signalToRead.type == SignalType.response) {
          if (signalToRead.data == SignalData.stop) {
            stop = true;
          } else if (signalToRead.data == SignalData.free) {
            free = true;
          }
        }
      } else {
        nav = max(nav, getNav(signalToRead.type));
      }

    }
  }

  bool validateSignal(Signal signal) {

    if (signal.destinationId == id && state == NodeState.waiting) {
      if (signal.type == SignalType.cts && stage == TalkingStage.cts) {
        return true;
      } else if (signal.type == SignalType.response && stage == TalkingStage.response) {
        return true;
      }
    }

    return false;
  }

  @override
  Signal? handleResponse() {

    if (requestedSend && backoffExpired) {

      if (stage == TalkingStage.rts) {
        requestedSend = false;
        confirmedSend = true;

        return Signal(
          ownerId: id,
          destinationId: -1,
          x: position.x,
          y: position.y,
          type: SignalType.rts,
        );
      } else if (stage == TalkingStage.query) {
        requestedSend = false;
        confirmedSend = true;

        return Signal(
          ownerId: id,
          destinationId: pal,
          x: position.x,
          y: position.y,
          type: SignalType.query,
          car: this,
        );
      }
    }

    return null;
  }

  @override
  void handleTimers() {
    timeout++;

    if (nav > 0) {
      nav--;
    } else if (requestedSend) {
      ifsTimer = 0;

      if (backoffSlots == -1) {
        backoffSlots = Random().nextInt(2 >> consecutiveCollisions);
      } else if (backoffSlots > 0) {
        backoffSlots--;
      } else {
        backoffSlots = -1;
        backoffExpired = true;
      }
    } else {
      ifsTimer++;
    }

    if (timeout >= RESETTIME) {
      if (consecutiveCollisions < MAX_BACKOFF_EXPONENT) {
        softReset();
      } else {
        reset();
      }
    }
  }

  @override
  softReset() {
    consecutiveCollisions++;
    switchState();
    requestedSend = false;
    confirmedSend = false;
    queuedReceive = false;
    ifsTimer = 0;
  }

  void _movementStep() {
    if (manhattanGrid[position.y][position.x] == 5) {
      position.direction = position.newDirection();
    }

    Position newPosition = moveForward();
    int maxRetries = 10;
    while (manhattanGrid[newPosition.y][newPosition.x] == 0 ||
        (manhattanGrid[newPosition.y][newPosition.x] != position.direction.index + 1 && manhattanGrid[newPosition.y][newPosition.x] != 5)) {
      if (maxRetries-- <= 0) break;
      position.direction = position.newDirection();
      newPosition = moveForward();
    }

    position = Position(x: newPosition.x, y: newPosition.y, direction: position.direction);
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