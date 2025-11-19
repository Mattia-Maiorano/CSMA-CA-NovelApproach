import '../entities/car.dart';
import '../entities/rsu.dart';
import 'base_repo.dart';

abstract class RSURepo extends BaseRepo<RSU> {

  List<Car> manageCars(List<Car> cars);
}