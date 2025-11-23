import 'package:daemon/domain/entities/position.dart';
import 'package:daemon/domain/entities/entity.dart';
import 'package:daemon/domain/network/signal.dart';

class Car extends Entity {
  final int model;
  final List<List<int>> manhattanGrid;
  bool enqueuedStopSignal = false;

  Car({required int id, required this.model, required Position position, required this.manhattanGrid, required int range, required int updateInterval, required int sensingRange, required int signalDuration}) : super(id, position, range, updateInterval, sensingRange, signalDuration);

  (Car, Signal?) step(int tick, Signal? signalToRead) {

    Signal? signal;
    if (tick % updateInterval == 1) {
      signal = Signal(ownerId: id, destinationId: -1, duration: signalDuration, x: position.x, y: position.y, type: SignalType.data);
      signal.setData(SignalData.query);
    }

    if (signalToRead != null && signalToRead.data == SignalData.stop) {
      enqueuedStopSignal = true;
    }

    // Stop the car if it has received a stop signal or it is not its time to move
    if (enqueuedStopSignal) {
      print ('$tick-$id) Car stopping');
      enqueuedStopSignal = false;
      return (Car(id: id, model: model, position: position, manhattanGrid: manhattanGrid, range: range, updateInterval: updateInterval, sensingRange: sensingRange, signalDuration: signalDuration), signal);
    }
    if (tick % updateInterval != 0) {
      return (Car(id: id, model: model, position: position, manhattanGrid: manhattanGrid, range: range, updateInterval: updateInterval, sensingRange: sensingRange, signalDuration: signalDuration), signal);
    }

    if (manhattanGrid[position.y][position.x] == 5) {
      position.direction = position.newDirection();
    }

    Position newPosition = moveForward();


    int maxRetries = 10;
    while(manhattanGrid[newPosition.y][newPosition.x] == 0 ||
          (manhattanGrid[newPosition.y][newPosition.x] != position.direction.index + 1 && manhattanGrid[newPosition.y][newPosition.x] != 5)
    ) {
      if (maxRetries-- <= 0) {
        return (Car(id: id, model: model, position: position, manhattanGrid: manhattanGrid, range: range, updateInterval: updateInterval, sensingRange: sensingRange, signalDuration: signalDuration), signal);
      }
      position.direction = position.newDirection();
      newPosition = moveForward();
    }

    return (Car(id: id, model: model, position: newPosition, manhattanGrid: manhattanGrid, range: range, updateInterval: updateInterval, sensingRange: sensingRange, signalDuration: signalDuration), signal);
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