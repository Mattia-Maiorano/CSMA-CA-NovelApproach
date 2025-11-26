import 'package:daemon/domain/entities/position.dart';
import 'package:daemon/domain/entities/entity.dart';
import 'package:daemon/domain/network/signal.dart';
import 'package:daemon/utils/config.dart';

class Car extends Entity {
  final List<List<int>> manhattanGrid;
  final int model;

  int enqueuedStopSender = -1;
  int enqueuedCtsSender = -1;

  bool stop = false;
  bool free = false;

  Car({required int id, required this.model, required Position position, required this.manhattanGrid, required int range, required int sensingRange, int timer = 0}) : super(id, position, range, sensingRange, timer) {
    emoji = "🚗";
  }

  Signal? step(int tick, Signal? signalToRead) {

    // ---- RESET COUNTER LOGIC ----
    if (communication && timeout > 0) {
      timeout--;
    } else if (waiting && timeout == 0) {
      print('$tick-$id)\t$emoji\t⏰');
      timer = 0;
      timeout = RESETTIME;
      enqueuedStopSender = -1;
      enqueuedCtsSender = -1;
      communication = false;
      waiting = false;
    }

    // ---- SENSING LOGIC ----
    Signal? signal;
    sense(signalToRead, tick);
    if (nav == 0) {
      timer++;

      print("TIMER $timer AT TICK $tick WITH BACKOFF $backoffSlots AND ENQUEUEDSTOPSENDER $enqueuedStopSender WITH STATUS COMMUNICATION $communication AND WAITING $waiting");

      // ---- SIGNAL PROCESSING AND EMISSION LOGIC ----
      if (signalToRead != null && signalToRead.destinationId == id) {
        if (signalToRead.type == SignalType.cts) {
          enqueuedCtsSender = signalToRead.ownerId;
          timeout = RESETTIME;
          waiting = false;
        } else if (signalToRead.data == SignalData.stop || signalToRead.data == SignalData.free) {
          stop = signalToRead.data == SignalData.stop;
          free = signalToRead.data == SignalData.free;
          enqueuedStopSender = signalToRead.ownerId;
          timeout = RESETTIME;
          waiting = false;
        }
      } else if (signalToRead == null && backoffSlots == 0) { // FREE MEDIUM

        // ---- SEND RESPONSES AFTER IFS ----
        //    send ack for stop/free
        if (enqueuedStopSender != -1) {
          signal = Signal(
            type: SignalType.ack,
            x: position.x,
            y: position.y,
            ownerId: id,
            destinationId: enqueuedStopSender,
          );
          enqueuedStopSender = -1;
          waiting = false;
          communication = false;

        //    send position
        } else if (enqueuedCtsSender != -1) {
          signal = Signal(
            type: SignalType.query,
            x: position.x,
            y: position.y,
            ownerId: id,
            destinationId: enqueuedCtsSender,
          );
          enqueuedCtsSender = -1;
          waiting = true;

        //    send rts
        } else if (!communication) {
          signal = Signal(
            type: SignalType.rts,
            x: position.x,
            y: position.y,
            ownerId: id,
            car: this,
            destinationId: -1, // broadcast
          );
          communication = true;
          waiting = true;
        }

      } // END FREE MEDIUM LOGIC
      else {
        backoffHelper();
      }
    } // END NAV == 0 LOGIC

    // ---- MOVEMENT LOGIC ----
    if (tick % BROADCASTINTERVAL == 0) {
      if (!stop) {
        if (manhattanGrid[position.y][position.x] == 5) {
          position.direction = position.newDirection();
        }

        Position newPosition = moveForward();
        int maxRetries = 10;
        while(manhattanGrid[newPosition.y][newPosition.x] == 0 ||
              (manhattanGrid[newPosition.y][newPosition.x] != position.direction.index + 1 && manhattanGrid[newPosition.y][newPosition.x] != 5)
        ) {
          if (maxRetries-- <= 0) {
            break;
          }
          position.direction = position.newDirection();
          newPosition = moveForward();
        }

        position = Position(x: newPosition.x, y: newPosition.y, direction: position.direction);
      }

      stop = false;
      free = false;
    }

    return signal;
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