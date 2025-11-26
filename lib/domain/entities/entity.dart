import 'dart:math';

import 'package:daemon/domain/entities/position.dart';
import 'package:daemon/domain/entities/rsu.dart';
import 'package:daemon/domain/network/signal.dart';
import 'package:daemon/utils/config.dart';

abstract class Entity<T> {
  final int id;
  final int range;
  final int sensingRange;
  Position position;

  String emoji = "❓";

  bool communication = false;
  bool waiting = false;
  int nav = 0;
  int timer = 0;
  int backoffSlots = -1;
  int timeout = RESETTIME;
  int consecutiveCollisions = 1;
  Random random = Random();

  Entity(this.id, this.position, this.range, this.sensingRange, this.timer);

  Position getPosition() {
    return position;
  }

  bool sense(Signal? signalToRead, int tick) {

    if (signalToRead != null && signalToRead.ownerId != id) {
      timer = 0;

      if (signalToRead.destinationId != id && !(this is RSU && signalToRead.destinationId == -1)) {
        nav = max(nav, signalToRead.duration);
        print('$tick-$id)\t$emoji\t\t🛌\t: DUE TO ${signalToRead.ownerId}');
      }
    } else {
      if (nav > 0) {
        nav--;
      }
    }

    return false;
  }

  bool backoffHelper() {
    if (backoffSlots == -1) {
        if (!communication) {
            if (timer == DIFS) {
              backoffSlots = backOff();
            }
        } else if (timer == SIFS) {
          backoffSlots = backOff();
        }
        return false;
    } else if (backoffSlots > 0) {
      backoffSlots--;
      return false;
    } else {
      backoffSlots = -1;
      return true;
    }
  }

  int backOff() {
    int k = min(consecutiveCollisions, MAX_BACKOFF_EXPONENT);
    int r = random.nextInt(1 << k);
    return r * BACKOFF_SLOT_TIME;
  }
}