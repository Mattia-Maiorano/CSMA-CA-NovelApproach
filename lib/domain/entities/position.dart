enum Direction { up, down, left, right }

class Position {
  final int x;
  final int y;
  final int xVerse;
  final int yVerse;

  const Position(this.x, this.y, Direction direction)
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

  Position movedBy(int dx, int dy) => Position(x + dx, y + dy, Direction.right);

  bool conflictingDirection(int otherXVerse, int otherYVerse) {
    if (xVerse != 0) {
      return (otherXVerse + xVerse == 0);
    } else if (yVerse != 0) {
      return (otherYVerse + yVerse == 0);
    }
    return false;
  }
}