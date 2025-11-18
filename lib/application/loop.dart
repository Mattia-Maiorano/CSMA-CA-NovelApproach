import 'dart:async';

import 'package:daemon/domain/entities/car.dart';
import 'package:daemon/domain/entities/rsu.dart';
import 'package:daemon/domain/repositories/car_repo.dart';
import 'package:daemon/domain/repositories/rsu_repo.dart';

class Loop {
  late final Duration frameDuration;
  late final CarRepo _carRepo;
  late final RSURepo _rsuRepo;
  late final StreamSubscription<List<Car>> carsSub;
  late final StreamSubscription<List<RSU>> rsusSub;
  List<Car> cars = [];
  List<RSU> rsus = [];
  bool _running = true;

  Loop({required CarRepo carRepo, required RSURepo rsuRepo, required int fps})
      : _carRepo = carRepo,
        _rsuRepo = rsuRepo,
        frameDuration = Duration(milliseconds: (1000 / fps).round());

  Future<void> start() async {

    carsSub = _carRepo.watchCars().listen((carsList) {
      cars = carsList;
    });
    rsusSub = _rsuRepo.watchRSUs().listen((rsusList) {
      rsus = rsusList;
    });

    while (_running) {

      final frameStart = DateTime.now();

      tick();

      final frameEnd = DateTime.now();

      final elapsed = frameEnd.difference(frameStart);
      final sleepDuration = frameDuration - elapsed;
      if (sleepDuration.isNegative) {
        await Future.delayed(Duration.zero);
      } else {
        await Future.delayed(sleepDuration);
      }

    }

    await dispose();
  }

  void tick() {
    List<Car> newCars = cars.map((car) => car.step()).toList();
    newCars = _rsuRepo.manageCars(newCars);

    _carRepo.renewCars(newCars);
  }

  void stop() {
    _running = false;
  }

  Future<void> dispose() async {
    await carsSub.cancel();
    await _carRepo.dispose();
    await _rsuRepo.dispose();
  }
}