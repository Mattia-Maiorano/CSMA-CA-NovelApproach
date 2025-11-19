import 'package:daemon/domain/entities/car.dart';
import 'package:daemon/domain/entities/entity.dart';
import 'package:daemon/domain/entities/rsu.dart';
import 'package:flutter/material.dart';

class ScenePainter extends CustomPainter {
  final List<Entity> entities;
  final double tileSize;

  ScenePainter(this.entities, this.tileSize);

  @override
  void paint(Canvas canvas, Size size) {
    final paintCar = Paint()..color = Colors.blue;
    final paintRSU = Paint()..color = Colors.red;

    for (final ent in entities) {
      if (ent is RSU) {
        canvas.drawRect(
            Rect.fromLTWH(ent.position.x * tileSize, ent.position.y * tileSize, tileSize, tileSize),
            paintRSU);
      } else if (ent is Car) {
        canvas.drawCircle(
            Offset(ent.position.x * tileSize + tileSize / 2, ent.position.y * tileSize + tileSize / 2),
            tileSize / 2,
            paintCar);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {

    for (int i = 0; i < entities.length; i++) {
      if (entities[i].position != (oldDelegate as ScenePainter).entities[i].position) {
        return true;
      }
    }

    return false;
  }
}

class StaticScenePainter extends CustomPainter {
  List<List<int>> grid = [];
  final double tileSize;

  StaticScenePainter(this.grid, this.tileSize);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.grey.shade300;
    // draw the static background once (example: grid)
    for (int y = 0; y < grid.length; y++) {
      for (int x = 0; x < grid[y].length; x++) {
        if (grid[y][x] == 0) continue;
        canvas.drawRect(
          Rect.fromLTWH(x * tileSize, y * tileSize, tileSize, tileSize),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}