import 'dart:math';
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
  bool communication = false;

  RSU({required Position position, required int id, required int range, required int sensingRange, required int signalDuration, int timer = 0}) : super(id, position, range, sensingRange, signalDuration, timer);

  Signal? step(int tick, Signal? signalToRead) {
    
    timer++;

    // ---- RESET COUNTER LOGIC ----
    if (communication && timeout > 0) {
      timeout--;
    } else {
      timeout = RESETTIME;
      communicationCar = null;
      enqueuedQuerySender = -1;
      enqueuedRtsSender = -1;
      communication = false;
      response = false;
      resend = false;
    }

    // ---- SENSING LOGIC ----
    if (timer % SIFS == 0 || timer % DIFS == 0) {
      if (signalToRead != null && signalToRead.ownerId != id) { // OCCUPIED MEDIUM
        timer = 0;
        timer -= backOff();
        if (signalToRead.destinationId != id && signalToRead.destinationId != -1) {
          print('$tick-$id)\t🚦\t\t🛌\t:\tbackoff=${backOff()}');
        }
      }
    }

    // ---- SIGNAL PROCESSING AND EMISSION LOGIC ----
    Signal? signal;
    if (signalToRead != null && (signalToRead.destinationId == id || signalToRead.destinationId == -1)) { // OCCUPIED MEDIUM
      if (signalToRead.type == SignalType.rts) {
        updateKnowledge(signalToRead.car!, tick);
        if (!communication) {
          communication = true;
          enqueuedRtsSender = signalToRead.ownerId;
          timeout = RESETTIME;
        }
      } else if (signalToRead.data == SignalData.position || resend) {
          enqueuedQuerySender = signalToRead.ownerId;
          response = collision();
          response ? print('RSU $id detects potential collision for Car ${communicationCar!.id} at position ${communicationCar!.position}') : print('No collision detected for ${signalToRead.ownerId}');
          timeout = RESETTIME;
      } else if (signalToRead.type == SignalType.ack) {
        communication = false;
      }
    } else if (signalToRead == null) { // FREE MEDIUM

      // ---- SEND RESPONSES AFTER IFS ----
      //    send cts
      if (timer % SIFS == 0 && enqueuedRtsSender != -1) {
          signal = Signal(
            type: SignalType.cts,
            data: SignalData.ack,
            x: position.x,
            y: position.y,
            duration: signalDuration,
            ownerId: id,
            destinationId: enqueuedRtsSender,
          );
          enqueuedRtsSender = -1;

      //    send stop
      } else if ((enqueuedQuerySender != -1 && timer % SIFS == 0) || (resend && timer % SIFS == 0)) {
        signal = Signal(
          type: SignalType.data,
          data: response ? SignalData.stop : SignalData.free,
          x: position.x,
          y: position.y,
          duration: signalDuration,
          ownerId: id,
          destinationId: enqueuedQuerySender,
        );
        enqueuedQuerySender = -1;
        resend = false;
      }

    } // END FREE MEDIUM

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
      if (other.id == communicationCar!.id) continue;

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