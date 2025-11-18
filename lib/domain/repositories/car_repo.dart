import '../entities/car.dart';

abstract class CarRepo {
  Stream<List<Car>> watchCars();

  Future<void> addCar(Car car);
  Future<void> removeCar(Car car);
  Future<void> renewCars(List<Car> cars);

  Future<void> dispose();
}