import 'package:daemon/data/in_mem_repo_base.dart';

import '../domain/entities/car.dart';

class InMemCarRepo extends InMemRepoBase<Car>{
  final List<Car> _cars = [];

  List<Car> get cars => List.unmodifiable(_cars);
}