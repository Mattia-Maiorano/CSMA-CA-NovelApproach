import 'package:daemon/domain/entities/entity.dart';
import 'package:daemon/domain/entities/classic_car.dart';
import 'package:daemon/domain/entities/position.dart';
import 'package:daemon/domain/network/signal.dart';
import 'package:daemon/utils/config.dart';

class RSU extends Entity {

  Car? communicationCar;
  Set<(Car, int)> knownCars = {};


  RSU({required Position position, required int id, required int range, required int sensingRange, int timer = 0}) : super(id, position, range, sensingRange, timer) {
    emoji = "🚦";
  }

  @override
  void specificStep(int tick) {

    // ---- CLEANUP OLD KNOWLEDGE ----
    if (tick == SUBFRAMES - 1) {
      //knownCars.clear();
    }

  }
  
  @override
  void handleState(int tick) {

    if (tick % BROADCAST == 0 && state == NodeState.idle) {
      nextState(NodeState.querying);
    }
    
    //    SLEEP/WAKE CONDITIONS
    else if (queuedSleep) {
      nextState(NodeState.sleeping);
      queuedSleep = false;
    } else if (queuedWake) {
      nextState(NodeState.idle);
      queuedWake = false;
    }

    //    MAIN LOOP OF STATE MACHINE
    else if (state == NodeState.querying && requestedSend) {
      switchState();
      requestedSend = false;
    } else if (state == NodeState.waiting && queuedReceive) {
      switchState();
      queuedReceive = false;
    }

    //    EXIT CONDITIONS
    else if (state == NodeState.querying && requestedExit) {
      nextState(NodeState.idle);
      requestedExit = false;
    }

  }
  
  @override
  void handleStage(int tick) {
    // TODO: implement handleQueryingState
  }

  @override
  bool handleSignal(int tick, Signal? signalToRead) {

    return false;
  }

  @override
  Signal? handleResponse() {
    // TODO: implement handleResponse
    throw UnimplementedError();
  }

  @override
  void handleTimers() {

  }

  @override
  void softReset() {

  }
  
  void updateKnowledge(Car newcar, int tick) {
    if (knownCars.any((entry) => entry.$1.id == newcar.id)) {
      knownCars = knownCars.map((entry) => entry.$1.id == newcar.id ? (entry.$1, tick) : entry).toSet();
    } else {
    knownCars.add((newcar, tick));
    }
  }

  bool collision() {
    final int cx = communicationCar!.position.x;
    final int cy = communicationCar!.position.y;
    final int cxNext = cx + communicationCar!.position.xVerse;
    final int cyNext = cy + communicationCar!.position.yVerse;

    print("KNOWN POSITIONS OF RSU $id: ");
    for (final (other, t) in knownCars) {
      print(" - Car ${other.id} at (${other.position.x}, ${other.position.y}) seen at tick $t");
    }

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
