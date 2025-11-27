import 'package:daemon/domain/entities/entity.dart';
import 'package:daemon/domain/entities/car.dart';
import 'package:daemon/domain/entities/position.dart';
import 'package:daemon/domain/network/signal.dart';
import 'package:daemon/utils/config.dart';

class RSU extends Entity {

  Car? communicationCar;
  List<(Car, int)> knownCars = [];

  int enqueuedRtsSender = -1;
  int enqueuedQuerySender = -1;
  int enqueuedPositionSender = -1;

  bool resend = false;
  bool response = false;

  RSU({required Position position, required int id, required int range, required int sensingRange, int timer = 0}) : super(id, position, range, sensingRange, timer){
    emoji = "🚦";
    waiting = true;
  }

  Signal? step(int tick, Signal? signalToRead) {
    // ---- RESET / TIMEOUT ----
    final bool timeoutExpired = consumeTimeoutIfExpired();
    if (timeoutExpired) {
      if (consecutiveCollisions >= MAX_BACKOFF_EXPONENT) {
        connectionState = ConnectionState.idle;
        print('$tick-$id)\t$emoji\t☠️\t: new state: $connectionState');
        consecutiveCollisions = 0;
        communicationCar = null;
        enqueuedPositionSender = -1;
        enqueuedQuerySender = -1;
        enqueuedRtsSender = -1;
        communication = false;
        waiting = true;
        response = false;
        resend = false;
      } else {
        connectionState = previousState();
        print('$tick-$id)\t$emoji\t⏰\t: new state: $connectionState');
        consecutiveCollisions++;
      }
    }

    // ---- SENSING / SIGNAL PROCESSING ----
    Signal? signal;
    final bool forMe = sense(signalToRead, tick);
    if (forMe) print('RSU $id detected signal FORME at tick $tick (nav=$nav / timer=$timer / backoff=$backoffSlots / timeout=$timeout)');

    if (nav == 0) {
      timer++;

      if (forMe && signalToRead != null) {
        _handleOccupiedMedium(signalToRead, tick);
      } else if (signalToRead == null && backoffSlots == 0) {
        signal = _handleFreeMedium();
      } else {
        backoffHelper();
      }
    }

    // ---- CLEANUP OLD KNOWLEDGE ----
    if (tick == SUBFRAMES - 1) {
      knownCars.clear();
    }

    return signal;
  }

  void _handleOccupiedMedium(Signal signalToRead, int tick) {

    consecutiveCollisions = 0;

    //    receive rts
    if (signalToRead.type == SignalType.rts && connectionState == ConnectionState.idle) {
      print('$tick-$id)\t$emoji\t👁️\t: DETECTED RTS FROM ${signalToRead.ownerId} AND COMMUNICATION IS $communication');
      updateKnowledge(signalToRead.car!, tick);
      if (!communication) {
        print('$tick-$id)\t$emoji\t\t🏁\t: STARTING COMMUNICATION WITH ${signalToRead.ownerId}');
        communication = true;
        communicationCar = signalToRead.car;
        enqueuedRtsSender = signalToRead.ownerId;
        timeout = RESETTIME;
      }

      waiting = false;
      connectionState = nextState();
    }
    
    //    receive position (query)
    else if ((signalToRead.type == SignalType.query || resend) && connectionState == ConnectionState.ctsSent) {
      enqueuedRtsSender = -1;
      enqueuedQuerySender = signalToRead.ownerId;

      response = collision();
      response ? print('RSU $id detects potential collision for Car ${communicationCar!.id} at position ${communicationCar!.position}') : print('No collision detected for ${signalToRead.ownerId}');
      timeout = RESETTIME;
      waiting = false;
      connectionState = nextState();
    }
    
    //    receive ack for stop/free
    else if (signalToRead.type == SignalType.ack && connectionState == ConnectionState.responseSent) {
      enqueuedQuerySender = -1;
      communication = false;
      waiting = true;
      connectionState = nextState();
    }

  }

  Signal? _handleFreeMedium() {

    //    send cts
    if (enqueuedRtsSender != -1 && connectionState == ConnectionState.rtsReceived) {
      final s = Signal(
        type: SignalType.cts,
        x: position.x,
        y: position.y,
        ownerId: id,
        destinationId: enqueuedRtsSender,
      );

      waiting = true;
      timeout = RESETTIME;
      backoffSlots = -1;
      connectionState = nextState();
      return s;
    }

    //    send stop/free response
    else if ((enqueuedQuerySender != -1 || resend) && connectionState == ConnectionState.queryReceived) {
      final s = Signal(
        type: SignalType.response,
        data: response ? SignalData.stop : SignalData.free,
        x: position.x,
        y: position.y,
        ownerId: id,
        destinationId: enqueuedQuerySender,
      );

      resend = false;
      waiting = true;
      timeout = RESETTIME;
      backoffSlots = -1;
      connectionState = nextState();
      return s;
    }

    return null;
  }

  void updateKnowledge(Car newcar, int tick) {
    knownCars.add((newcar, tick));
  }

  bool collision() {
    final int cx = communicationCar!.position.x;
    final int cy = communicationCar!.position.y;
    final int cxNext = cx + communicationCar!.position.xVerse;
    final int cyNext = cy + communicationCar!.position.yVerse;

    // iterate once over known cars and look for potential conflicts
    for (final (other, _) in knownCars) {
      if (other.id == communicationCar!.id || other.stop == true) continue;

      final int ox = other.position.x;
      final int oy = other.position.y;

      // crossing at next step: if both cars will move into the same cell next tick
      final int oxNext = ox + other.position.xVerse;
      final int oyNext = oy + other.position.yVerse;
      if (oxNext == cxNext && oyNext == cyNext) return true;

      // approaching into each other's next position (swap)
      if (oxNext == cx && oyNext == cy && ox == cxNext && oy == cyNext) return true;
    }

    return false;
  }
}
