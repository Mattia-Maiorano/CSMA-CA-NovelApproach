// dart:math no longer required
import 'package:daemon/data/in_mem_repo_base.dart';

import '../domain/entities/car.dart';
import '../domain/entities/rsu.dart';
import '../domain/repositories/rsu_repo.dart';

class InMemRsuRepo extends InMemRepoBase<RSU> implements RSURepo {

  @override
  List<Car> manageCars(List<Car> cars) {
    List<Car> updatedCars = cars.toList();
    // Track which individual cars were already stopped to avoid re-processing
    Set<int> stoppedIndices = {};

    for (final rsu in items) {
      final int n = updatedCars.length;
      for (int i = 0; i < n; i++) {
        for (int j = i + 1; j < n; j++) {
          if (stoppedIndices.contains(i) && stoppedIndices.contains(j)) continue;

          final car1 = updatedCars[i];
          final car2 = updatedCars[j];

          // check imminent collision using current (possibly-updated) positions
          if (rsu.step(car1.position, car2.position)) {
            // stop both cars involved to guarantee collision is avoided
            updatedCars[i] = car1.stop();
            updatedCars[j] = car2.stop();
            stoppedIndices.add(i);
            stoppedIndices.add(j);
          }
        }
      }
    }

    return updatedCars;
  }
}