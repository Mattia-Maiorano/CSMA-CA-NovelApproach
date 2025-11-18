import 'package:daemon/domain/entities/position.dart';

class RSU{
  final Position position;
  final int id;
  final int range;

  RSU({required this.position, required this.id, required this.range});

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