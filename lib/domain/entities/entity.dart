import 'dart:math';

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
  int consecutiveCollisions = 1;
  Random random = Random();

  Entity(this.id, this.position, this.range, this.sensingRange, this.signalDuration, this.timer);

  Position getPosition() {
    return position;
  }

  int backOff() {
    int k = min(consecutiveCollisions, MAX_BACKOFF_EXPONENT);
    int r = random.nextInt(1 << k);
    return r * BACKOFF_SLOT_TIME;
  }
}