import 'dart:math';
import 'package:daemon/data/in_mem_repo_base.dart';

import '../domain/entities/car.dart';
import '../domain/entities/rsu.dart';
import '../domain/repositories/rsu_repo.dart';

class InMemRsuRepo extends InMemRepoBase<RSU> implements RSURepo {

  @override
  List<Car> manageCars(List<Car> cars) {
    List<Car> updatedCars = cars.toList();
    Set<(int, int)> stoppedPairs = {};

    Random random = Random();

    for (final rsu in items) {
      int index1 = 0;
      for (Car car1 in cars) {
        int index2 = 0;
        for (Car car2 in cars) {
          if (car1.id != car2.id && !stoppedPairs.contains((index1, index2)) && !stoppedPairs.contains((index2, index1))) {
            if (rsu.step(car1.position, car2.position)) {
              stoppedPairs.add((index1, index2));
              if (random.nextBool()) {
                updatedCars[index1] = car1.stop();
              } else {
                updatedCars[index2] = car2.stop();
              }
            }
          }
          index2++;
        }
        index1++;
      }
    }

    return updatedCars;
  }
}