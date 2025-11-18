import 'dart:async';
import 'dart:ffi';
import 'dart:math';
import '../domain/entities/car.dart';
import '../domain/entities/rsu.dart';
import '../domain/repositories/rsu_repo.dart';

class InMemRsuRepo implements RSURepo {
  final List<RSU> _rsus = [];
  final _controller = StreamController<List<RSU>>.broadcast();

  InMemRsuRepo() {
    _controller.add(List.unmodifiable(_rsus));
  }

  @override
  Stream<List<RSU>> watchRSUs() => _controller.stream;

  @override
  Future<void> addRSU(RSU rsu) async {
    _rsus.add(rsu);
    _controller.add(List.unmodifiable(_rsus));
  }

  @override
  Future<void> removeRSU(RSU rsu) async {
    _rsus.remove(rsu);
    _controller.add(List.unmodifiable(_rsus));
  }

  @override
  Future<void> renewRSUs(List<RSU> rsus) async {
    _rsus
      ..clear()
      ..addAll(rsus);
    _controller.add(List.unmodifiable(_rsus));
  }

  @override
  List<Car> manageCars(List<Car> cars) {
    List<Car> updatedCars = cars;

    int index = 0;
    for (final rsu in _rsus) {
      for (final car1 in cars) {
        for (final car2 in cars) {
          if (car1.id != car2.id) {
            if (rsu.step(car1.position, car2.position)) {
              if (Random().nextBool()) {
                updatedCars[index] = car1.stop();
              } else {
                updatedCars[index] = car2.stop();
              }
            }
          }
        }
      }
    }

    return updatedCars;
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
  
}