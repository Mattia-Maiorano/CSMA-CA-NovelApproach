import 'dart:async';
// image storage logic removed

import 'package:daemon/domain/entities/car.dart';
import 'package:daemon/domain/entities/entity.dart';
import 'package:daemon/domain/entities/rsu.dart';
import 'package:daemon/domain/network/medium.dart';
import 'package:daemon/domain/network/signal.dart';
import 'package:daemon/domain/repositories/base_repo.dart';
import 'package:daemon/utils/config.dart';

class Loop {
  final Duration frameDuration;
  final BaseRepo<Car> _carRepo;
  final BaseRepo<RSU> _rsuRepo;
  final Medium medium;
  StreamSubscription<List<Car>>? carsSub;
  StreamSubscription<List<RSU>>? rsusSub;
  List<Car> cars = [];
  List<RSU> rsus = [];

  bool _running = false;
  Future<void>? _loopFuture;
  Completer<void>? _completer;

  Loop({required this.medium, required BaseRepo<Car> carRepo, required BaseRepo<RSU> rsuRepo, required BaseRepo<Entity> entRepo, required int fps})
      : _carRepo = carRepo,
        _rsuRepo = rsuRepo,
        frameDuration = Duration(milliseconds: (1000 / fps).round());
  Future<void> start() {

    print("Starting loop...");

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

    final currentCars = _carRepo.items;
    if (currentCars.isNotEmpty) {
      cars = currentCars;
      if (!carsReady.isCompleted) carsReady.complete();
    }

    final currentRsus = _rsuRepo.items;
    if (currentRsus.isNotEmpty) {
      rsus = currentRsus;
      if (!rsusReady.isCompleted) rsusReady.complete();
    }

    await carsReady.future;
    await rsusReady.future;

    try {
      int run = 0;
      while (_running) {
        final frameStart = DateTime.now();

        try {
          print("------- Tick ${run++} --------");
          for (int i = 0; i < SUBFRAMES; i++) {
            await tick(i);
          }
        } catch (e) {
          print('Error during loop tick: $e');
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

  Future<void> tick(int tick) async {

    // Work on a mutable snapshot to avoid modifying an unmodifiable list
    final snapshot = List<Car>.from(cars);
    List<Car> updatedCars = [];

    ///////////////
    /// CAR LOGIC
    ///////////////
    try {
      for (int i = 0; i < snapshot.length; i++) {
        Car forCar = snapshot[i];
        Signal? signalToRead = medium.sense(
            forCar.position.x,
            forCar.position.y,
            forCar.sensingRange,
            forCar.id);
        if (signalToRead != null) {
          if (signalToRead.destinationId == forCar.id) {
            print('$tick-${forCar.id})\t🚗\t👁️\t\t:\t${signalToRead.type}/${signalToRead.data}');
          } else {
          }
        }

        final (updatedCar, signal) = snapshot[i].step(tick, signalToRead);
        updatedCars.add(updatedCar);
        
        if (signal != null) {
          print('$tick-${forCar.id})\t🚗\t\t✍🏼\t:\t${signal.type}/${signal.data} to ${signal.destinationId}');
          medium.transmit(signal);
        }
      }
    } catch (_) {
      rethrow;
    }

    ///////////////
    /// RSU LOGIC
    ///////////////
    try {
      for (final rsu in rsus) {
        Signal? signalToRead = medium.sense(
            rsu.position.x,
            rsu.position.y,
            rsu.sensingRange,
            rsu.id);
        if (signalToRead != null) {
          if (signalToRead.destinationId == rsu.id || signalToRead.destinationId == -1) {
            print('$tick-${rsu.id})\t🚦\t👁️\t\t:\t${signalToRead.type}/${signalToRead.data}');
          } else {

          }
        }

        final signal = rsu.step(tick, signalToRead);

        if (signal != null) {
          print('$tick-${rsu.id})\t🚦\t\t✍🏼\t:\t${signal.type}/${signal.data} to ${signal.destinationId}');
          medium.transmit(signal);
        }
      }
    } catch (_) {
      rethrow;
    }

    try {
      await _carRepo.renewItems(updatedCars);
    } catch (_) {
      rethrow;
    }

    ///////////////
    /// MEDIUM LOGIC
    ///////////////
    medium.step();

  }
}