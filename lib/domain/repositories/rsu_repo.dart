import 'dart:ffi';

import '../entities/rsu.dart';
import '../entities/car.dart';

abstract class RSURepo {
  Stream<List<RSU>> watchRSUs();

  Future<void> addRSU(RSU rsu);
  Future<void> removeRSU(RSU rsu);
  Future<void> renewRSUs(List<RSU> rsus);
  List<Car> manageCars(List<Car> cars);

  Future<void> dispose();
}