import 'package:daemon/domain/entities/entity.dart';
import 'package:daemon/domain/entities/position.dart';

class RSU extends Entity{
  final int range;

  RSU({required Position position, required int id, required this.range}) : super(id, position);

  bool step(Position p1, Position p2) {
    // quick distance check (squared) to filter out far-away entities
    final distance = (p1.x - p2.x) * (p1.x - p2.x) + (p1.y - p2.y) * (p1.y - p2.y);
    if (distance > range * range) return false;

    // compute next positions assuming one-step movement based on direction
    final next1x = p1.x + p1.xVerse;
    final next1y = p1.y + p1.yVerse;
    final next2x = p2.x + p2.xVerse;
    final next2y = p2.y + p2.yVerse;

    // 1) They will move into the same cell next step -> collision
    if (next1x == next2x && next1y == next2y) return true;

    // 2) They will swap places (crossing paths) -> collision
    if (next1x == p2.x && next1y == p2.y && next2x == p1.x && next2y == p1.y) return true;

    // 3) Head-on on same axis (opposite directions) and aligned on that axis
    //    e.g., same x and one up, one down; or same y and one left, one right
    if (p1.conflictingDirection(p2.direction)) {
      if (p1.x == p2.x) return true; // vertical head-on
      if (p1.y == p2.y) return true; // horizontal head-on
    }

    // Otherwise, no immediate collision detected
    return false;
  }
}