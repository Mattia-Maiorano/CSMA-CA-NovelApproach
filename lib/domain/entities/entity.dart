import 'package:daemon/domain/entities/position.dart';
import 'package:daemon/utils/config.dart';

abstract class Entity<T> {
  final int id;
  final Position position;
  final int range;
  final int sensingRange;
  final int signalDuration;
  int timer = 0;
  int timeout = RESETTIME;

  Entity(this.id, this.position, this.range, this.sensingRange, this.signalDuration, this.timer);

  Position getPosition() {
    return position;
  }
}