import 'package:daemon/domain/entities/position.dart';

abstract class Entity<T> {
  final int id;
  final Position position;
  final int updateInterval;
  final int range;
  final int sensingRange;

  Entity(this.id, this.position, this.range, this.updateInterval, this.sensingRange);

  Position getPosition() {
    return position;
  }
}