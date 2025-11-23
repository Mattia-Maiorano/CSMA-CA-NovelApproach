import 'dart:math';
import 'package:daemon/domain/entities/entity.dart';
import 'package:daemon/domain/entities/position.dart';
import 'package:daemon/domain/entities/car.dart';
import 'package:daemon/domain/network/signal.dart';

class RSU extends Entity{

  final Random _rng = Random();

  RSU({required Position position, required int id, required int range, required int updateInterval, required int sensingRange, required int signalDuration}) : super(id, position, range, updateInterval, sensingRange, signalDuration);

  bool checkCollision(Position p1, Position p2) {

    final distance1 = sqrt(pow(position.x - p1.x, 2) + pow(position.y - p1.y, 2));
    final distance2 = sqrt(pow(position.x - p2.x, 2) + pow(position.y - p2.y, 2));
    final distance = max(distance1, distance2);
    if (distance > range) return false;

    final next1x = p1.x + p1.xVerse;
    final next1y = p1.y + p1.yVerse;
    final next2x = p2.x + p2.xVerse;
    final next2y = p2.y + p2.yVerse;

    if (next1x == next2x && next1y == next2y) return true;

    if (next1x == p2.x && next1y == p2.y && next2x == p1.x && next2y == p1.y) return true;

    if (p1.conflictingDirection(p2.direction)) {
      if (p1.x == p2.x) return true; // vertical head-on
      if (p1.y == p2.y) return true; // horizontal head-on
    }

    return false;
  }

  List<Signal> step(List<Car> cars, int tick, Signal signal) {
    
    final updated = cars.toList();
    final int n = updated.length;

    // Collect conflict pairs
    final List<List<int>> conflictPairs = [];
    final Set<int> involvedCars = {};
    final Set<int> stoppedCars = {};
    final Set<int> totalCars = {};

    for (int i = 0; i < n; i++) {
      for (int j = i + 1; j < n; j++) {
        if (checkCollision(updated[i].position, updated[j].position)) {
          conflictPairs.add([i, j]);
          involvedCars.add(updated[i].id);
          involvedCars.add(updated[j].id);
        }
        totalCars.add(updated[i].id);
        totalCars.add(updated[j].id);
      }
    }

    List<Signal> signals = [];
    for (final carId in totalCars.difference(involvedCars)) {
      Signal s = Signal(ownerId: id, destinationId: carId, duration: signalDuration, x: position.x, y: position.y, type: SignalType.data);
      s.setData( SignalData.free );
      signals.add(s);
    }

    for (final pair in conflictPairs) {
      final i = pair[0];
      final j = pair[1];

      if (stoppedCars.contains(updated[i].id)) {
        Signal s = Signal(ownerId: id, destinationId: updated[j].id, duration: signalDuration, x: position.x, y: position.y, type: SignalType.data);
        s.setData( SignalData.stop );
        signals.add(s);
        stoppedCars.add(updated[j].id);
      } else if (stoppedCars.contains(updated[j].id)) {
        Signal s = Signal(ownerId: id, destinationId: updated[i].id, duration: signalDuration, x: position.x, y: position.y, type: SignalType.data);
        s.setData( SignalData.stop );
        signals.add(s);
        stoppedCars.add(updated[i].id);
      } else {
        if (_rng.nextBool()) { 
          Signal s = Signal(ownerId: id, destinationId: updated[j].id, duration: signalDuration, x: position.x, y: position.y, type: SignalType.data);
          s.setData( SignalData.stop );
          signals.add(s);
        } else {
          Signal s = Signal(ownerId: id, destinationId: updated[i].id, duration: signalDuration, x: position.x, y: position.y, type: SignalType.data);
          s.setData( SignalData.stop );
          signals.add(s);
        }
      }
    }

    return signals;
  }
}