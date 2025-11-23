import 'package:daemon/domain/entities/car.dart';
import 'package:daemon/domain/entities/entity.dart';
import 'package:daemon/domain/entities/rsu.dart';
import 'package:flutter/material.dart';

class ScenePainter extends CustomPainter {
  final List<Entity> entities;
  final Map<(int, int), (double, int)> bitmapResidualIntensity;
  final double tileSize;

  ScenePainter(this.entities, this.bitmapResidualIntensity, this.tileSize);

  @override
  void paint(Canvas canvas, Size size) {
    final paintCar = Paint()..color = Colors.blue;
    final paintRSU = Paint()..color = Colors.red;
    final paintRSUrange = Paint()
      ..color = Colors.red.withOpacity(0.2)
      ..style = PaintingStyle.fill;

    for (final ent in entities) {
      if (ent is RSU) {
        canvas.drawRect(
            Rect.fromLTWH(ent.position.x * tileSize, ent.position.y * tileSize, tileSize, tileSize),
            paintRSU);
        canvas.drawCircle(Offset(ent.position.x * tileSize + tileSize / 2, ent.position.y * tileSize + tileSize / 2), ent.range * tileSize, paintRSUrange);
      } else if (ent is Car) {
        canvas.drawCircle(
            Offset(ent.position.x * tileSize + tileSize / 2, ent.position.y * tileSize + tileSize / 2),
            tileSize / 2,
            paintCar);
      }
    }
    for (final entry in bitmapResidualIntensity.entries) {
      final (x, y) = entry.key;
      final (ratio, ownerId) = entry.value;
      if (ratio > 0) {
        final paintSignal = Paint()
          ..color = const Color.fromARGB(255, 33, 243, 65).withOpacity(ratio)
          ..style = PaintingStyle.fill;
        canvas.drawRect(
            Rect.fromLTWH(x * tileSize, y * tileSize, tileSize, tileSize),
            paintSignal);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {

    return true;

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