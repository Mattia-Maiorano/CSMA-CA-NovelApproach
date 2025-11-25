import 'package:daemon/domain/entities/position.dart';
import 'package:daemon/domain/entities/entity.dart';
import 'package:daemon/domain/network/signal.dart';
import 'package:daemon/utils/config.dart';

class Car extends Entity {
  final List<List<int>> manhattanGrid;
  final int model;

  int enqueuedStopSender = -1;
  int enqueuedCtsSender = -1;

  bool communication = false;
  bool stop = false;
  bool free = false;

  Car({required int id, required this.model, required Position position, required this.manhattanGrid, required int range, required int sensingRange, required int signalDuration, int timer = 0}) : super(id, position, range, sensingRange, signalDuration, timer);

  (Car, Signal?) step(int tick, Signal? signalToRead) {

    timer++;

    // ---- RESET COUNTER LOGIC ----
    if (communication && timeout > 0) {
      timeout--;
    } else {
      timeout = RESETTIME;
      enqueuedStopSender = -1;
      enqueuedCtsSender = -1;
      communication = false;
    }

    // ---- SENSING LOGIC ----
    if (signalToRead != null && signalToRead.ownerId != id) { // OCCUPIED MEDIUM
      // NEED TO IMPLEMENT BACKOFF
      timer = 0;
      timer -= backOff();
      if (signalToRead.destinationId != id) {
        print('$tick-$id)\t🚗\t\t🛌\t: backoff=${backOff()}');
      }
    }

    // ---- SIGNAL PROCESSING AND EMISSION LOGIC ----
    Signal? signal;
    if (signalToRead != null && signalToRead.destinationId == id) {
      if (signalToRead.type == SignalType.cts) {
        enqueuedCtsSender = signalToRead.ownerId;
        timeout = RESETTIME;
      } else if (signalToRead.data == SignalData.stop || signalToRead.data == SignalData.free) {
        stop = signalToRead.data == SignalData.stop;
        free = signalToRead.data == SignalData.free;
        enqueuedStopSender = signalToRead.ownerId;
        timeout = RESETTIME;
      }
    } else if (signalToRead == null) { // FREE MEDIUM

      // ---- SEND RESPONSES AFTER IFS ----
      if (timer % SIFS == 0 && enqueuedStopSender != -1) {
        signal = Signal(
          type: SignalType.ack,
          data: SignalData.ack,
          x: position.x,
          y: position.y,
          duration: signalDuration,
          ownerId: id,
          destinationId: enqueuedStopSender,
        );
        enqueuedStopSender = -1;
        communication = false;
      } else if (enqueuedCtsSender != -1 && timer % SIFS == 0) {
        signal = Signal(
          type: SignalType.data,
          data: SignalData.position,
          x: position.x,
          y: position.y,
          duration: signalDuration,
          ownerId: id,
          destinationId: enqueuedCtsSender,
        );
        enqueuedCtsSender = -1;
      } else if (timer % DIFS == 0) {
        signal = Signal(
          type: SignalType.rts,
          data: SignalData.query,
          x: position.x,
          y: position.y,
          duration: signalDuration,
          ownerId: id,
          car: this,
          destinationId: -1, // broadcast
        );
        communication = true;
      }

    } // END FREE MEDIUM LOGIC

    // ---- MOVEMENT LOGIC ----
    Car newCar = this;
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
        newCar = Car(
          id: id,
          model: model,
          position: Position(x: newPosition.x, y: newPosition.y, direction: position.direction),
          manhattanGrid: manhattanGrid,
          range: range,
          sensingRange: sensingRange,
          signalDuration: signalDuration,
          timer: timer,
        );
      }

      stop = false;
      free = false;
    }

    return (newCar, signal);
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