import 'package:daemon/domain/entities/position.dart';

abstract class Entity<T> {
  final int id;
  final Position position;
  final int range;
  final int sensingRange;
  final int signalDuration;

  Entity(this.id, this.position, this.range, this.sensingRange, this.signalDuration);

  Position getPosition() {
    return position;
  }
}