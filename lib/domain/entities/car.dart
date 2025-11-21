import 'package:daemon/domain/entities/position.dart';
import 'package:daemon/domain/entities/entity.dart';
import 'package:daemon/domain/network/signal.dart';

class Car extends Entity {
  final int model;
  final int duration = 5;
  final List<List<int>> manhattanGrid;

  Car({required int id, required this.model, required Position position, required this.manhattanGrid, required int range, required int updateInterval, required int sensingRange}) : super(id, position, range, updateInterval, sensingRange);

  (Car, Signal?) step(int tick, Signal? signalToRead) {

    if (signalToRead != null) {
      return (Car(id: id, model: model, position: position, manhattanGrid: manhattanGrid, range: range, updateInterval: updateInterval, sensingRange: sensingRange), signalToRead);
    }

    if (manhattanGrid[position.y][position.x] == 5) {
      position.direction = position.newDirection();
    }

    Position newPosition = moveForward();

    Signal? signal;
    if (tick % updateInterval != 0) {
      signal = Signal(ownerId: id, destinationId: -1, duration: duration, x: position.x, y: position.y, type: SignalType.data);
    }

    int maxRetries = 10;
    while(manhattanGrid[newPosition.y][newPosition.x] == 0 ||
          (manhattanGrid[newPosition.y][newPosition.x] != position.direction.index + 1 && manhattanGrid[newPosition.y][newPosition.x] != 5)
    ) {
      if (maxRetries-- <= 0) {
        return (Car(id: id, model: model, position: position, manhattanGrid: manhattanGrid, range: range, updateInterval: updateInterval, sensingRange: sensingRange), signal);
      }
      position.direction = position.newDirection();
      newPosition = moveForward();
    }

    return (Car(id: id, model: model, position: newPosition, manhattanGrid: manhattanGrid, range: range, updateInterval: updateInterval, sensingRange: sensingRange), signal);
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