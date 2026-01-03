/// ============================================================================
/// Position and Direction for Grid-Based Movement
/// ============================================================================
/// Represents an entity's position on the 2D grid with movement direction.
/// Used by cars to navigate the road network.
/// ============================================================================

import 'dart:math';

enum Direction { up, right, down, left }

class Position {
  final int x;
  final int y;
  final int xVerse;
  final int yVerse;
  final Random rndm = Random();
  Direction direction;

  Position({required this.x, required this.y, required this.direction})
    : xVerse = (direction == Direction.right)
          ? 1
          : (direction == Direction.left)
          ? -1
          : 0,
      yVerse = (direction == Direction.down)
          ? 1
          : (direction == Direction.up)
          ? -1
          : 0;

  Position movedBy(int dx, int dy) =>
      Position(x: x + dx, y: y + dy, direction: direction);

  bool conflictingDirection(Direction otherDirection) {
    if ((direction == Direction.up && otherDirection == Direction.down) ||
        (direction == Direction.down && otherDirection == Direction.up) ||
        (direction == Direction.left && otherDirection == Direction.right) ||
        (direction == Direction.right && otherDirection == Direction.left)) {
      return true;
    }
    return false;
  }

  Direction newDirection() {
    direction = Direction.values[rndm.nextInt(4)];
    return direction;
  }
}
