import 'dart:async';

import 'package:daemon/domain/entities/car.dart';
import 'package:daemon/domain/entities/rsu.dart';
import 'package:daemon/domain/repositories/car_repo.dart';
import 'package:daemon/domain/repositories/rsu_repo.dart';

class Loop {
  late final Duration frameDuration;
  late final CarRepo _carRepo;
  late final RSURepo _rsuRepo;
  StreamSubscription<List<Car>>? carsSub;
  StreamSubscription<List<RSU>>? rsusSub;
  List<Car> cars = [];
  List<RSU> rsus = [];

  bool _running = false;
  Future<void>? _loopFuture;
  Completer<void>? _completer;

  Loop({required CarRepo carRepo, required RSURepo rsuRepo, required int fps})
      : _carRepo = carRepo,
        _rsuRepo = rsuRepo,
        frameDuration = Duration(milliseconds: (1000 / fps).round());

  Future<void> start() {

    if (_running) {
      return _loopFuture!;
    }
    _running = true;
    _completer = Completer<void>();
    _loopFuture = loop().whenComplete(() {
      _running = false;
      _completer?.complete();
      _completer = null;
    });

    return _loopFuture!;
  }

  Future<void> loop() async {
    carsSub = _carRepo.watchCars().listen((carsList) {
      cars = carsList;
    }, onError: (e) {
      // swallow errors from the repo stream to avoid unhandled exceptions
    });

    rsusSub = _rsuRepo.watchRSUs().listen((rsusList) {
      rsus = rsusList;
    }, onError: (e) {
      // swallow errors from the repo stream to avoid unhandled exceptions
    });

    try {
      while (_running) {
        final frameStart = DateTime.now();

        try {
          tick();
        } catch (e) {
          // protect the loop from exceptions in tick so the loop keeps running
        }

        final frameEnd = DateTime.now();

        final elapsed = frameEnd.difference(frameStart);
        final sleepDuration = frameDuration - elapsed;
        if (sleepDuration.isNegative) {
          await Future.delayed(Duration.zero);
        } else {
          await Future.delayed(sleepDuration);
        }
      }
    } finally {
      await carsSub?.cancel();
      await rsusSub?.cancel();
    }
  }

  void stop() {
    _running = false;
  }

  Future<void> waitForStop() async {
    if (_running) {
      await _completer!.future;
      _completer = null;
      _running = false;
    }
  }

  void tick() {
    List<Car> newCars = cars.map((car) => car.step()).toList();
    newCars = _rsuRepo.manageCars(newCars);

    _carRepo.renewCars(newCars);
  }
}