import 'package:daemon/domain/entities/classic_car.dart';
import 'package:daemon/domain/entities/entity.dart';
import 'package:daemon/domain/entities/classic_rsu.dart';
import 'package:daemon/domain/network/medium.dart';
import 'package:daemon/domain/network/signal.dart';
import 'package:flutter/material.dart';

class ScenePainter extends CustomPainter {
  final List<Entity> entities;
  final Medium medium;
  final double tileSize;

  ScenePainter(this.entities, this.medium, this.tileSize);

  @override
  void paint(Canvas canvas, Size size) {
    final paintCar = Paint()..color = Colors.blue;
    final paintStoppedCar = Paint()..color = Colors.yellow;
    final paintFreeCar = Paint()..color = Colors.green;
    final paintCollision = Paint()..color = Colors.black;
    final paintRSU = Paint()..color = Colors.red;
    final paintRSUrange = Paint()
      ..color = Colors.red.withOpacity(0.2)
      ..style = PaintingStyle.fill;

    Set<(int, int)> drawnPositions = {};
    for (final ent in entities) {
      if (ent is RSU) {
        canvas.drawRect(
            Rect.fromLTWH(ent.position.x * tileSize, ent.position.y * tileSize, tileSize, tileSize),
            paintRSU);
        canvas.drawCircle(Offset(ent.position.x * tileSize + tileSize / 2, ent.position.y * tileSize + tileSize / 2), ent.range * ent.range as double, paintRSUrange);
      } else if (ent is Car) {

        bool collision = false;
        if (drawnPositions.contains((ent.position.x, ent.position.y))) {
          collision = true;
        } else {
          drawnPositions.add((ent.position.x, ent.position.y));
        }

        if (ent.stop == true) {
          canvas.drawCircle(
            Offset(ent.position.x * tileSize + tileSize / 2, ent.position.y * tileSize + tileSize / 2),
            tileSize / 2,
            paintStoppedCar);
        } else if (ent.free == true) {
          canvas.drawCircle(
            Offset(ent.position.x * tileSize + tileSize / 2, ent.position.y * tileSize + tileSize / 2),
            tileSize / 2,
            paintFreeCar);
        } else if (collision) {
          canvas.drawCircle(
            Offset(ent.position.x * tileSize + tileSize / 2, ent.position.y * tileSize + tileSize / 2),
            tileSize / 2,
            paintCollision);
        } else {
          canvas.drawCircle(
            Offset(ent.position.x * tileSize + tileSize / 2, ent.position.y * tileSize + tileSize / 2),
            tileSize / 2,
            paintCar);
        }
        canvas.drawCircle(Offset(ent.position.x * tileSize + tileSize / 2, ent.position.y * tileSize + tileSize / 2), ent.range * ent.range as double, paintRSUrange);
      }
    }
    List<Signal> signals = medium.signals;
    for (final signal in signals) {
      final paintSignal = Paint()
        ..color = signal.type == SignalType.rts ? Colors.green : (signal.type == SignalType.ack ? Colors.orange : Colors.purple)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(
          Offset(signal.x * tileSize + tileSize / 2, signal.y * tileSize + tileSize / 2),
          signal.duration * signal.duration as double,
          paintSignal);
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