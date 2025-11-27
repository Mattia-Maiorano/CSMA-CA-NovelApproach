import 'dart:math';

import 'package:daemon/domain/entities/position.dart';
import 'package:daemon/domain/entities/rsu.dart';
import 'package:daemon/domain/network/signal.dart';
import 'package:daemon/utils/config.dart';

enum ConnectionState {
  idle,
  rtsSent, rtsReceived,
  ctsSent, ctsReceived,
  querySent, queryReceived,
  responseSent, responseReceived,
}

abstract class Entity<T> {
  final int id;
  final int range;
  final int sensingRange;

  Position position;
  ConnectionState connectionState = ConnectionState.idle;

  Signal? lastSeenSignal;
  String emoji = "❓";

  bool communication = false;
  bool waiting = false;
  bool attemptedNewCommunicationWhileBusy = false;

  int nav = 0;
  int timer = 0;
  int backoffSlots = -1;
  int timeout = RESETTIME;
  int consecutiveCollisions = 0;
  int lastNodeID = -1;
  Random random = Random();

  Entity(this.id, this.position, this.range, this.sensingRange, this.timer);

  Position getPosition() {
    return position;
  }

  bool sense(Signal? signalToRead, int tick) {

    if (signalToRead != null && signalToRead.ownerId != id) {
      timer = 0;
      if (signalToRead.destinationId != id && !(this is RSU && signalToRead.destinationId == -1)) {
        if (signalToRead != lastSeenSignal) {
          lastSeenSignal = signalToRead;
          nav = signalToRead.navTime();
        } else {
          nav--;
        }
        print('$tick-$id)\t$emoji\t\t🛌\t: DUE TO ${signalToRead.ownerId}');
      } else {
        if (!waiting && communication) {
          attemptedNewCommunicationWhileBusy = true;
        } else {
          return true;
        }
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
        if (!communication || consecutiveCollisions != 0) {
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
    int k = min(consecutiveCollisions + 1, MAX_BACKOFF_EXPONENT);
    int r = random.nextInt(1 << k);
    print('$id)\t$emoji\t⏱️\t: BACKOFF SLOTS SET TO $r (k=$k)');
    return r * BACKOFF_SLOT_TIME;
  }

  /// Decrement timeout and return true if a communication timeout just expired.
  /// Subclasses should call this at the start of their `step` and handle
  /// consequences (collision count, state reset) themselves because actions
  /// differ between `Car` and `RSU`.
  bool consumeTimeoutIfExpired() {
    attemptedNewCommunicationWhileBusy = false;
    if (communication && timeout > 0) {
      timeout--;
      return false;
    } else if (communication && timeout == 0) {
      timer = 0;
      timeout = RESETTIME;
      return true;
    }
    return false;
  }

  ConnectionState nextState() {
    switch(connectionState) {
      case ConnectionState.idle:
        if (this is RSU){
          return ConnectionState.rtsReceived;
        } else {
          return ConnectionState.rtsSent;
        }
      case ConnectionState.rtsReceived:
        return ConnectionState.ctsSent;
      case ConnectionState.ctsSent:
        return ConnectionState.queryReceived;
      case ConnectionState.queryReceived:
        return ConnectionState.responseSent;
      case ConnectionState.responseSent:
        return ConnectionState.idle;
      case ConnectionState.rtsSent:
        return ConnectionState.ctsReceived;
      case ConnectionState.ctsReceived:
        return ConnectionState.querySent;
      case ConnectionState.querySent:
        return ConnectionState.responseReceived;
      case ConnectionState.responseReceived:
        return ConnectionState.idle;
    }
  }

  ConnectionState previousState() {
    switch (connectionState) {
      case ConnectionState.idle:
        if (this is RSU){
          return ConnectionState.responseSent;
        } else {
          return ConnectionState.responseReceived;
        }
      case ConnectionState.responseSent:
        return ConnectionState.queryReceived;
      case ConnectionState.queryReceived:
        return ConnectionState.ctsSent;
      case ConnectionState.ctsSent:
        return ConnectionState.rtsReceived;
      case ConnectionState.rtsReceived:
        return ConnectionState.idle;
      case ConnectionState.responseReceived:
        return ConnectionState.querySent;
      case ConnectionState.querySent:
        return ConnectionState.ctsReceived;
      case ConnectionState.ctsReceived:
        return ConnectionState.rtsSent;
      case ConnectionState.rtsSent:
        return ConnectionState.idle;
    }
  }
}