import 'dart:math';
import 'package:daemon/domain/entities/entity.dart';
import 'package:daemon/domain/entities/position.dart';
import 'package:daemon/domain/entities/car.dart';

class RSU extends Entity{
  final int range;
  final int slots;
  final int _maxBackoff = 5;

  // Persistent per-car backoff state maintained by the RSU
  final Map<int, int> _backoffs = {};
  final Random _rng = Random();

  RSU({required Position position, required int id, required this.range, this.slots = 3}) : super(id, position);

  bool step(Position p1, Position p2) {

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

  // CSMA/CA-style slot competition: RSU assigns slots; cars in conflict compete.
  // Cars that successfully transmit in a slot cause the RSU to instruct their conflicting
  // partners to stop. Backoff counters are updated per-car to reduce repeated collisions.
  List<Car> manageCars(List<Car> cars) {
    final updated = cars.toList();
    final int n = updated.length;

    // Collect conflict pairs and contenders
    final List<List<int>> conflictPairs = [];
    final Set<int> contenders = {};

    for (int i = 0; i < n; i++) {
      for (int j = i + 1; j < n; j++) {
        if (step(updated[i].position, updated[j].position)) {
          conflictPairs.add([i, j]);
          contenders.add(i);
          contenders.add(j);
        }
      }
    }

    if (contenders.isEmpty) return updated;

    // Each contender picks a slot based on its backoff
    final Map<int, int> chosenSlot = {};
    final Map<int, List<int>> slotMap = {};

    for (final idx in contenders) {
      final carId = updated[idx].id;
      final backoff = _backoffs[carId] ?? 0;
      final multiplier = 1 << min(backoff, _maxBackoff);
      final slotRange = max(1, slots * multiplier);
      final slot = _rng.nextInt(slotRange);
      chosenSlot[idx] = slot;
      slotMap.putIfAbsent(slot, () => []).add(idx);
    }

    // Determine which contenders successfully transmitted (unique in their slot)
    final Set<int> transmitted = {};

    slotMap.forEach((slot, list) {
      if (list.length == 1) {
        final idx = list.first;
        transmitted.add(idx);
        _backoffs[updated[idx].id] = 0; // reset backoff on success
      } else {
        // collision in slot: increment backoff for all involved
        for (final idx in list) {
          final id = updated[idx].id;
          _backoffs[id] = min(_maxBackoff, (_backoffs[id] ?? 0) + 1);
        }
      }
    });

    // For each conflicting pair, if one side transmitted and the other didn't, stop the non-transmitter
    for (final pair in conflictPairs) {
      final i = pair[0];
      final j = pair[1];

      final iTrans = transmitted.contains(i);
      final jTrans = transmitted.contains(j);

      if (iTrans && !jTrans) {
        updated[j] = updated[j].stop();
      } else if (jTrans && !iTrans) {
        updated[i] = updated[i].stop();
      }
      // if both transmitted (different slots) or both failed, leave as-is
    }

    return updated;
  }
}