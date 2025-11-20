// dart:math no longer required
import 'dart:math';

import 'package:daemon/data/in_mem_repo_base.dart';

import '../domain/entities/car.dart';
import '../domain/entities/rsu.dart';
import '../domain/repositories/rsu_repo.dart';

class InMemRsuRepo extends InMemRepoBase<RSU> implements RSURepo {
  Random random = Random();

  @override
  List<Car> manageCars(List<Car> cars) {
    // Track which individual cars were already stopped to avoid re-processing
    List<Car> updatedCars = cars.toList();
    Set<int> stoppedIndices = {};

    for (final rsu in items) {
      final int n = updatedCars.length;
      for (int i = 0; i < n; i++) {
        for (int j = i + 1; j < n; j++) {
          if (stoppedIndices.contains(i) && stoppedIndices.contains(j)) continue;

          final car1 = updatedCars[i];
          final car2 = updatedCars[j];

          if (rsu.step(car1.position, car2.position)) {
            if (random.nextBool()) {
              updatedCars[i] = car1.stop();
              updatedCars[j] = car2;
            } else {
              updatedCars[i] = car1;
              updatedCars[j] = car2.stop();
            }
            stoppedIndices.add(i);
            stoppedIndices.add(j);
          }
        }
      }
    }

    return updatedCars;
  }
}