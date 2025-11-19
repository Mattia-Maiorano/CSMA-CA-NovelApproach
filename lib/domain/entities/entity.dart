import 'package:daemon/domain/entities/position.dart';

abstract class Entity<T> {
  final int id;
  final Position position;

  Entity(this.id, this.position);

  Position getPosition() {
    return position;
  }
}