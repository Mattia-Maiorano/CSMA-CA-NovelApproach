import 'dart:async';
// image storage logic removed

import 'package:daemon/domain/entities/classic_car.dart';
import 'package:daemon/domain/entities/entity.dart';
import 'package:daemon/domain/entities/classic_rsu.dart';
import 'package:daemon/domain/network/medium.dart';
import 'package:daemon/domain/network/signal.dart';
import 'package:daemon/domain/repositories/base_repo.dart';
import 'package:daemon/utils/analyzer.dart';
import 'package:daemon/utils/config.dart';
import 'package:daemon/utils/measurement.dart';

class Loop {
  final Duration frameDuration;
  final BaseRepo<Car> _carRepo;
  final BaseRepo<RSU> _rsuRepo;
  final Medium medium;
  StreamSubscription<List<Car>>? carsSub;
  StreamSubscription<List<RSU>>? rsusSub;
  List<Car> cars = [];
  List<RSU> rsus = [];

  Set<int> processedCars = {};
  Set<int> freeToMoveCars = {};
  Analyzer? analyzer;

  bool _running = false;
  Future<void>? _loopFuture;
  Completer<void>? _completer;

  Loop({required this.medium, required this.analyzer, required BaseRepo<Car> carRepo, required BaseRepo<RSU> rsuRepo, required BaseRepo<Entity> entRepo, required int fps})
      : _carRepo = carRepo,
        _rsuRepo = rsuRepo,
        frameDuration = Duration(milliseconds: (1000 / fps).round());
  Future<void> start(bool MDP) {

    print("Starting loop...");

    if (_running) {
      return _loopFuture!;
    }
    _running = true;
    
    // Enable MDP progress tracking if in MDP mode
    if (MDP) {
      analyzer?.enableMDPTracking();
    }
    
    _completer = Completer<void>();
    _loopFuture = loop(MDP).whenComplete(() {
      _running = false;
      _completer?.complete();
      _completer = null;
    });

    return _loopFuture!;
  }

  Future<void> loop(bool MDP) async {
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
            await tick(i, run);
          }

          final union = Set<int>.from(processedCars);
          union.addAll(freeToMoveCars);
          analyzer?.recordDifferentCarsProcessed(union.length);
          processedCars.clear();
          analyzer?.setFreeCars(freeToMoveCars.length);
          freeToMoveCars.clear();
          
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

      await analyzer?.closeAndWrite(MDP);
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

  Future<void> tick(int tick, int frame) async {

    // Work on a mutable snapshot to avoid modifying an unmodifiable list
    final snapshot = List<Car>.from(cars);
    List<Car> updatedCars = [];

    ///////////////
    /// CAR LOGIC
    ///////////////
    try {
      for (int i = 0; i < snapshot.length; i++) {
        analyzer?.incrementTotalPerNode();

        Car forCar = snapshot[i];
        // Compute how many cars and RSUs are in sensing range of this car
        int carsInRange = 0;
        int rsusInRange = 0;
        final rangeSqCar = forCar.sensingRange * forCar.sensingRange;
        for (final other in cars) {
          if (other.id == forCar.id) continue;
          final dx = other.position.x - forCar.position.x;
          final dy = other.position.y - forCar.position.y;
          if (dx * dx + dy * dy <= rangeSqCar) carsInRange++;
        }
        for (final other in rsus) {
          final dx = other.position.x - forCar.position.x;
          final dy = other.position.y - forCar.position.y;
          if (dx * dx + dy * dy <= rangeSqCar) rsusInRange++;
        }
        forCar.seenCarsCount = carsInRange;
        forCar.seenRsusCount = rsusInRange;
        Signal? signalToRead = medium.sense(
            forCar.position.x,
            forCar.position.y,
            forCar.sensingRange,
            forCar.id);
        if (signalToRead != null) {
          analyzer?.incrementBusyMedium();

          if (signalToRead.destinationId == forCar.id) {
            // print('$tick-${forCar.id}-${forCar.state})\t🚗\t👁️\t\t:\t${signalToRead.type}/${signalToRead.data}\t(${forCar.nav}/${forCar.timer}/${forCar.backoffSlots} || ${forCar.timeout}/${forCar.consecutiveCollisions})');
          } else {
          }
        }

        final stepProd = snapshot[i].step(tick, frame, signalToRead);
        final Signal? signal = stepProd.$1;
        final Measurement measurement = stepProd.$2;

        if (measurement.answered && !processedCars.contains(forCar.id)) processedCars.add(forCar.id);
        if (measurement.free && !freeToMoveCars.contains(forCar.id)) freeToMoveCars.add(forCar.id);
        analyzer?.update(measurement);
        updatedCars.add(snapshot[i]);
        
        if (signal != null) {
          print('$tick-${forCar.id}-${forCar.state})\t🚗\t\t✍🏼\t:\t${signal.type}/${signal.data} to ${signal.destinationId}');
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
        // Compute how many cars and RSUs are in sensing range of this rsu
        int carsInRange = 0;
        int rsusInRange = 0;
        final rangeSqRsu = rsu.sensingRange * rsu.sensingRange;
        for (final car in cars) {
          final dx = car.position.x - rsu.position.x;
          final dy = car.position.y - rsu.position.y;
          if (dx * dx + dy * dy <= rangeSqRsu) carsInRange++;
        }
        for (final other in rsus) {
          if (other.id == rsu.id) continue;
          final dx = other.position.x - rsu.position.x;
          final dy = other.position.y - rsu.position.y;
          if (dx * dx + dy * dy <= rangeSqRsu) rsusInRange++;
        }
        rsu.seenCarsCount = carsInRange;
        rsu.seenRsusCount = rsusInRange;
        analyzer?.incrementTotalPerNode();

        Signal? signalToRead = medium.sense(
            rsu.position.x,
            rsu.position.y,
            rsu.sensingRange,
            rsu.id);
        if (signalToRead != null) {
          analyzer?.incrementBusyMedium();

          if (signalToRead.destinationId == rsu.id || signalToRead.destinationId == -1) {
            print('$tick-${rsu.id}-${rsu.state})\t🚦\t👁️\t\t:\t${signalToRead.type}/${signalToRead.data}\t(${rsu.nav}/${rsu.ifsTimer}/${rsu.backoffSlots} || ${rsu.timeout}/${rsu.consecutiveCollisions})');
          } else {

          }
        }

        final stepProd = rsu.step(tick, frame, signalToRead);
        final Signal? signal = stepProd.$1;
        final Measurement measurement = stepProd.$2;
        analyzer?.update(measurement);

        if (signal != null) {
          print('$tick-${rsu.id}-${rsu.state})\t🚦\t\t✍🏼\t:\t${signal.type}/${signal.data} to ${signal.destinationId}');
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

    analyzer?.incrementTotal();

    if (tick % 100 == 0) {
      medium.getSignalsInfo();
    }

  }
}