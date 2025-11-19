import 'package:daemon/domain/entities/entity.dart';
import 'package:daemon/domain/entities/position.dart';

class RSU extends Entity{
  final int range;

  RSU({required Position position, required int id, required this.range}) : super(id, position);

  bool step(Position p1, Position p2) {

    final distance = (p1.x - p2.x) * (p1.x - p2.x) + (p1.y - p2.y) * (p1.y - p2.y);
    if (distance <= range * range) {
      if (p1.conflictingDirection(p2.direction)) {
        return true;
      }
    }

    return false;
  }
}