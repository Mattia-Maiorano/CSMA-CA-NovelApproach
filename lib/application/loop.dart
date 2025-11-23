import 'dart:async';
// image storage logic removed

import 'package:daemon/domain/entities/car.dart';
import 'package:daemon/domain/entities/entity.dart';
import 'package:daemon/domain/entities/rsu.dart';
import 'package:daemon/domain/network/network_bitmap.dart';
import 'package:daemon/domain/network/signal.dart';
import 'package:daemon/domain/repositories/base_repo.dart';

class Loop {
  final Duration frameDuration;
  final BaseRepo<Car> _carRepo;
  final BaseRepo<RSU> _rsuRepo;
  final NetworkBitmap _networkBitmap;
  StreamSubscription<List<Car>>? carsSub;
  StreamSubscription<List<RSU>>? rsusSub;
  List<Car> cars = [];
  List<RSU> rsus = [];

  bool _running = false;
  Future<void>? _loopFuture;
  Completer<void>? _completer;

  Loop({required NetworkBitmap networkBitmap, required BaseRepo<Car> carRepo, required BaseRepo<RSU> rsuRepo, required BaseRepo<Entity> entRepo, required int fps})
      : _networkBitmap = networkBitmap,
        _carRepo = carRepo,
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
      while (_running) {
        final frameStart = DateTime.now();

        try {
          await tick();
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

  Future<void> tick() async {

    print("------- Tick ${_networkBitmap.tick} --------");


    // Work on a mutable snapshot to avoid modifying an unmodifiable list
    final snapshot = List<Car>.from(cars);
    List<Car> updatedCars = [];

    try {
      for (int i = 0; i < snapshot.length; i++) {
        Signal? signalToRead = _networkBitmap.receiveSignalsAt(snapshot[i].position.x, snapshot[i].position.y, snapshot[i].sensingRange, snapshot[i].id);
        if (signalToRead != null) {
          print('${_networkBitmap.tick}-${snapshot[i].id}) 🚗 CAR reading signal: ${signalToRead.data}');
        }
        final (updatedCar, signal) = snapshot[i].step(_networkBitmap.tick, signalToRead);
        updatedCars.add(updatedCar);
        if (signal != null) {
          print('${_networkBitmap.tick}-${snapshot[i].id}) 🚗   ENQUEUING CAR: ${signal.type}/${signal.data} to ${signal.destinationId}');
          _networkBitmap.enqueueSignal(signal);
        }
      }
    } catch (_) {
      rethrow;
    }

    try {
      for (final rsu in rsus) {
        print('${_networkBitmap.tick}-${rsu.id}) 🚦 RSU stepping');
        Signal? signalToRead = _networkBitmap.receiveSignalsAt(rsu.position.x, rsu.position.y, rsu.sensingRange, rsu.id);
        if (signalToRead != null) {
          print('${_networkBitmap.tick}-${rsu.id}) 🚦 RSU ${rsu.id} reading signal: ${signalToRead?.data}');
          List<Signal> newSignals = rsu.step(updatedCars, _networkBitmap.tick, signalToRead);
          for (final signal in newSignals) {
            print('${_networkBitmap.tick}-${rsu.id}) 🚦   ENQUEUING RSU: ${signal.type}/${signal.data} to ${signal.destinationId}');
            _networkBitmap.enqueueSignal(signal);
          }
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

    _networkBitmap.step();
  }
}