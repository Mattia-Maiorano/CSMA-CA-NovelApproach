import 'dart:async';
import '../domain/entities/car.dart';
import '../domain/repositories/car_repo.dart';

class InMemCarRepo implements CarRepo {
  final List<Car> _cars = [];
  final _controller = StreamController<List<Car>>.broadcast();

  InMemCarRepo() {
    _controller.add(List.unmodifiable(_cars));
  }

  @override
  Stream<List<Car>> watchCars() => _controller.stream;

  @override
  Future<void> addCar(Car car) async {
    _cars.add(car);
    _controller.add(List.unmodifiable(_cars));
  }

  @override
  Future<void> removeCar(Car car) async {
    _cars.remove(car);
    _controller.add(List.unmodifiable(_cars));
  }

  @override
  Future<void> renewCars(List<Car> cars) async {
    _cars
      ..clear()
      ..addAll(cars);
    _controller.add(List.unmodifiable(_cars));
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
  
}