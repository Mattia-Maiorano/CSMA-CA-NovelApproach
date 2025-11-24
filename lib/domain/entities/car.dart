import 'package:daemon/domain/entities/position.dart';
import 'package:daemon/domain/entities/entity.dart';
import 'package:daemon/domain/network/signal.dart';
import 'package:daemon/utils/config.dart';

class Car extends Entity {
  final List<List<int>> manhattanGrid;
  final int model;

  int _timer = 0;
  int enqueuedStopSender = -1;
  int enqueuedCtsSender = -1;
  bool sendRts = false;

  Car({required int id, required this.model, required Position position, required this.manhattanGrid, required int range, required int sensingRange, required int signalDuration}) : super(id, position, range, sensingRange, signalDuration);

  (Car, Signal?) step(int tick, Signal? signalToRead) {

    _timer++;

    // ---- SIGNAL PROCESSING AND EMISSION LOGIC ----
    Signal? signal;
    if (signalToRead != null) {
      // NEED TO IMPLEMENT BACKOFF
      _timer = 0;
      if (signalToRead.data == SignalData.stop) {
        enqueuedStopSender = signalToRead.ownerId;
      } else if (signalToRead.type == SignalType.cts) {
        enqueuedCtsSender = signalToRead.ownerId;
      }
    } else if (tick % BROADCASTINTERVAL == 0) {
        sendRts = true;
    }

    // ---- SEND RESPONSES AFTER IFS ----
    if (tick % SUBFRAMES != 0 || enqueuedStopSender != -1) {
        signal = Signal(
          type: SignalType.ack,
          data: SignalData.ack,
          x: position.x,
          y: position.y,
          duration: signalDuration,
          ownerId: id,
          destinationId: enqueuedStopSender,
        );
      return (Car(id: id, model: model, position: position, manhattanGrid: manhattanGrid, range: range, sensingRange: sensingRange, signalDuration: signalDuration), signal);
    } else if (enqueuedCtsSender != -1 && _timer % SIFS == 0) {
      signal = Signal(
        type: SignalType.data,
        data: SignalData.position,
        x: position.x,
        y: position.y,
        duration: signalDuration,
        ownerId: id,
        destinationId: enqueuedCtsSender,
      );
      return (Car(id: id, model: model, position: position, manhattanGrid: manhattanGrid, range: range, sensingRange: sensingRange, signalDuration: signalDuration), signal);
    } else if (sendRts && _timer % SIFS == 0) {
      sendRts = false;
      signal = Signal(
        type: SignalType.rts,
        data: SignalData.query,
        x: position.x,
        y: position.y,
        duration: signalDuration,
        ownerId: id,
        destinationId: -1, // broadcast
      );
      return (Car(id: id, model: model, position: position, manhattanGrid: manhattanGrid, range: range, sensingRange: sensingRange, signalDuration: signalDuration), signal);
    }

    // ---- MOVEMENT LOGIC ----
    if (manhattanGrid[position.y][position.x] == 5) {
      position.direction = position.newDirection();
    }

    Position newPosition = moveForward();
    int maxRetries = 10;
    while(manhattanGrid[newPosition.y][newPosition.x] == 0 ||
          (manhattanGrid[newPosition.y][newPosition.x] != position.direction.index + 1 && manhattanGrid[newPosition.y][newPosition.x] != 5)
    ) {
      if (maxRetries-- <= 0) {
        return (Car(id: id, model: model, position: position, manhattanGrid: manhattanGrid, range: range, sensingRange: sensingRange, signalDuration: signalDuration), signal);
      }
      position.direction = position.newDirection();
      newPosition = moveForward();
    }

    return (Car(id: id, model: model, position: newPosition, manhattanGrid: manhattanGrid, range: range, sensingRange: sensingRange, signalDuration: signalDuration), signal);
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