import 'package:daemon/domain/entities/position.dart';
import 'package:daemon/domain/entities/entity.dart';

class Car extends Entity {
  final int model;
  final List<List<int>> manhattanGrid;

  Car({required int id, required this.model, required Position position, required this.manhattanGrid}) : super(id, position);

  Car step() {
    Position newPosition = moveForward();

    while(manhattanGrid[newPosition.y][newPosition.x] == 0) {
        newPosition = moveForward();
    }

    return Car(id: id, model: model, position: newPosition, manhattanGrid: manhattanGrid);
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

  Car stop() {
    Position newPosition;

    switch (position.direction) {
      case Direction.up:
        newPosition = position.movedBy(0, 1);
        break;
      case Direction.down:
        newPosition = position.movedBy(0, -1);
        break;
      case Direction.left:
        newPosition = position.movedBy(1, 0);
        break;
      case Direction.right:
        newPosition = position.movedBy(-1, 0);
        break;
    }

    return Car(id: id, model: model, position: newPosition, manhattanGrid: manhattanGrid);
  }
}