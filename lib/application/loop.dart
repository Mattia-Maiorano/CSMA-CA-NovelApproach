import 'dart:async';

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

    print("Tick ${_networkBitmap.tick}");


    // Work on a mutable snapshot to avoid modifying an unmodifiable list
    final snapshot = List<Car>.from(cars);
    List<Car> updatedCars = [];

    print('Processing ${snapshot.length} cars and ${rsus.length} RSUs');

    try {
      for (int i = 0; i < snapshot.length; i++) {
        Signal? signalToRead = _networkBitmap.receiveSignalsAt(snapshot[i].position.x, snapshot[i].position.y, snapshot[i].sensingRange, snapshot[i].id);
        final (updatedCar, signal) = snapshot[i].step(_networkBitmap.tick, signalToRead);
        updatedCars.add(updatedCar);
        if (signal != null) {
          _networkBitmap.enqueueSignal(signal);
        }
      }
    } catch (_) {
      rethrow;
    }

    print('Processing RSUs...');

    try {
      for (final rsu in rsus) {
        Signal? signalToRead = _networkBitmap.receiveSignalsAt(rsu.position.x, rsu.position.y, rsu.sensingRange, rsu.id);
        if (signalToRead != null) {
          List<Signal> newSignals = rsu.step(updatedCars, _networkBitmap.tick, signalToRead);
          for (final signal in newSignals) {
            _networkBitmap.enqueueSignal(signal);
          }
        }
      }
    } catch (_) {
      rethrow;
    }

    print('Renewing car items...');

    try {
      await _carRepo.renewItems(updatedCars);
    } catch (_) {
      rethrow;
    }

    print('Stepping network bitmap...');

    _networkBitmap.step();

    print('Printing residual intensity matrix...');

    /////////////////////////////////
    /// DEBUG: Print residual intensity matrix
    /////////////////////////////////

    // Build and print a formatted matrix composed by the value bitmapResidualIntensity[0] at location matrix[x][y]
    final keys = _networkBitmap.bitmapResidualIntensity.keys.toList();
    if (keys.isEmpty) {
      // ignore: avoid_print
      print('Residual intensity matrix (index 0): <empty>');
    } else {
      // determine bounds
      int maxX = 0;
      int maxY = 0;
      for (final (int x, int y) in keys) {
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }

      // create matrix[x][y] as List of columns (x) each containing rows (y)
      List<List<double>> matrix = List.generate(maxX + 1, (_) => List.filled(maxY + 1, 0.0));

      for (final (int x, int y) in keys) {
        final dynamic cell = _networkBitmap.bitmapResidualIntensity[(x, y)];
        if (cell == null) continue;
        double value = 0.0;
        bool assigned = false;

        if (cell is List && (cell as List).isNotEmpty) {
          final first = (cell as List).first;
          if (first is num) {
            value = (first as num).toDouble();
            assigned = true;
          }
        }

        if (!assigned && cell is Map && (cell as Map).containsKey(0)) {
          final v = (cell as Map)[0];
          if (v is num) {
            value = (v as num).toDouble();
            assigned = true;
          }
        }

        if (!assigned && cell is num) {
          value = (cell as num).toDouble();
          assigned = true;
        }

        if (!assigned) {
          // attempt to read a Dart record (e.g. (num, ...)) using .$1; protect with try/catch
          try {
            final dyn = cell as dynamic;
            final first = dyn.$1;
            if (first is num) {
              value = (first as num).toDouble();
            }
          } catch (_) {
            // leave value as 0.0 if it isn't accessible
          }
        }

        matrix[x][y] = value;
      }

      // print header and rows (iterate rows by y so output looks like a matrix)
      // ignore: avoid_print
      print('Residual intensity matrix (index 0):');
      for (int y = 0; y <= maxY; y++) {
        final rowBuffer = StringBuffer();
        for (int x = 0; x <= maxX; x++) {
          final v = matrix[x][y];
          rowBuffer.write(v.toStringAsFixed(2).padLeft(8));
        }
        // ignore: avoid_print
        print(rowBuffer.toString());
      }
    }
  }
}