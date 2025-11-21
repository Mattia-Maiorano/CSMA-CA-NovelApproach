import 'dart:async';

import 'package:daemon/domain/entities/car.dart';
import 'package:daemon/domain/entities/entity.dart';
import 'package:daemon/domain/entities/rsu.dart';
import 'package:daemon/domain/repositories/base_repo.dart';

class Loop {
  late final Duration frameDuration;
  late final BaseRepo<Entity> _entRepo;
  late final BaseRepo<Car> _carRepo;
  late final BaseRepo<RSU> _rsuRepo;
  StreamSubscription<List<Car>>? carsSub;
  StreamSubscription<List<RSU>>? rsusSub;
  List<Car> cars = [];
  List<RSU> rsus = [];

  bool _running = false;
  Future<void>? _loopFuture;
  Completer<void>? _completer;

  Loop({required BaseRepo<Car> carRepo, required BaseRepo<RSU> rsuRepo, required BaseRepo<Entity> entRepo, required int fps})
      : _carRepo = carRepo,
        _rsuRepo = rsuRepo,
        _entRepo = entRepo,
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
    final carsReady = Completer<void>();
    final rsusReady = Completer<void>();

    carsSub = _carRepo.watchItems().listen((carsList) {
      cars = carsList;
      if (!carsReady.isCompleted) carsReady.complete();
    }, onError: (e) {
      // swallow errors from the repo stream to avoid unhandled exceptions
    });

    rsusSub = _rsuRepo.watchItems().listen((rsusList) {
      rsus = rsusList;
      if (!rsusReady.isCompleted) rsusReady.complete();
    }, onError: (e) {
      // swallow errors from the repo stream to avoid unhandled exceptions
    });

    await carsReady.future;
    await rsusReady.future;

    try {
      while (_running) {
        final frameStart = DateTime.now();

        try {
          tick();
        } catch (e) {
          // swallow errors from tick to keep the loop running
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

    // Work on a mutable snapshot to avoid modifying an unmodifiable list
    final snapshot = List<Car>.from(cars);
    final List<Car> updatedCars = [];

    for (int i = 0; i < snapshot.length; i++) {
      updatedCars.add(snapshot[i].step());
    }

    // Allow each RSU to manage cars (CSMA/CA slot arbitration)
    var newCars = updatedCars;
    for (final rsu in rsus) {
      newCars = rsu.manageCars(newCars);
    }

    _carRepo.renewItems(newCars);

    _entRepo.renewItems([...newCars, ...rsus]);
  }
}