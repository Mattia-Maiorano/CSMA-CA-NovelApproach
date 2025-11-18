import 'package:daemon/domain/entities/position.dart';

class Car {
  final String id;
  final int model;
  final Position position;

  Car({required this.id, required this.model, required this.position});

  Position getPosition() {
    return position;
  }

  Car step() {
    Position newPosition;

    switch (position.direction) {
      case Direction.up:
        newPosition = position.movedBy(0, -1);
        break;
      case Direction.down:
        newPosition = position.movedBy(0, 1);
        break;
      case Direction.left:
        newPosition = position.movedBy(-1, 0);
        break;
      case Direction.right:
        newPosition = position.movedBy(1, 0);
        break;
    }

    return Car(id: id, model: model, position: newPosition);
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

    return Car(id: id, model: model, position: newPosition);
  }
}