import 'package:daemon/domain/entities/entity.dart';
import 'package:daemon/domain/entities/car.dart';
import 'package:daemon/domain/entities/position.dart';
import 'package:daemon/domain/network/signal.dart';
import 'package:daemon/utils/config.dart';

class RSU extends Entity{

  Car? communicationCar;
  List<(Car, int)> knownCars = [];

  int enqueuedRtsSender = -1;
  int enqueuedQuerySender = -1;
  int enqueuedPositionSender = -1;

  bool resend = false;
  bool response = false;

  RSU({required Position position, required int id, required int range, required int sensingRange, int timer = 0}) : super(id, position, range, sensingRange, timer){
    emoji = "🚦";
  }

  Signal? step(int tick, Signal? signalToRead) {

    // ---- RESET COUNTER LOGIC ----
    if (communication && timeout > 0) {
      timeout--;
    } else if (waiting && timeout == 0) {
      print("RESETTING RSU $id AT TICK $tick");
      timer = 0;
      timeout = RESETTIME;
      communicationCar = null;
      enqueuedPositionSender = -1;
      enqueuedQuerySender = -1;
      enqueuedRtsSender = -1;
      communication = false;
      response = false;
      resend = false;
    }


    // ---- SENSING LOGIC ----
    Signal? signal;
    sense(signalToRead, tick);
    if (nav == 0) {
      timer++;

      // ---- SIGNAL PROCESSING AND EMISSION LOGIC ----
      if (signalToRead != null && (signalToRead.destinationId == id || signalToRead.destinationId == -1)) { // OCCUPIED MEDIUM
        if (signalToRead.type == SignalType.rts) {
          updateKnowledge(signalToRead.car!, tick);
          if (!communication) {
            communication = true;
            enqueuedRtsSender = signalToRead.ownerId;
            timeout = RESETTIME;
          }
          waiting = false;
        } else if (signalToRead.type == SignalType.query || resend) {
            enqueuedQuerySender = signalToRead.ownerId;
            response = collision();
            response ? print('RSU $id detects potential collision for Car ${communicationCar!.id} at position ${communicationCar!.position}') : print('No collision detected for ${signalToRead.ownerId}');
            timeout = RESETTIME;
            waiting = false;
        } else if (signalToRead.type == SignalType.ack) {
          communication = false;
          waiting = false;
        }
      } else if (signalToRead == null && backoffSlots == 0) { // FREE MEDIUM

        // ---- SEND RESPONSES AFTER IFS ----
        //    send cts
        if (enqueuedRtsSender != -1) {
            signal = Signal(
              type: SignalType.cts,
              x: position.x,
              y: position.y,
              ownerId: id,
              destinationId: enqueuedRtsSender,
            );
            enqueuedRtsSender = -1;
            waiting = true;
        //    send stop
        } else if ((enqueuedQuerySender != -1) || (resend)) {
          signal = Signal(
            type: SignalType.response,
            data: response ? SignalData.stop : SignalData.free,
            x: position.x,
            y: position.y,
            ownerId: id,
            destinationId: enqueuedQuerySender,
          );
          enqueuedQuerySender = -1;
          resend = false;
          waiting = true;
        }

      } // END FREE MEDIUM LOGIC
      else {
        backoffHelper();
      }
    } // END NAV == 0 LOGIC

    // ---- CLEANUP OLD KNOWLEDGE ----

    if (tick == SUBFRAMES - 1) {
      knownCars.clear();
    }

    return signal;
  }

  void updateKnowledge(Car newcar, int tick) {
    knownCars.add((newcar, tick));
    communicationCar = newcar;
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