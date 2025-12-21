import 'package:daemon/domain/entities/classic_car.dart';
import 'package:daemon/domain/entities/entity.dart';
import 'package:daemon/domain/entities/classic_rsu.dart';
// MDP entities no longer required for painting directly; rely on base classes
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
        // Base range (static)
        canvas.drawCircle(Offset(ent.position.x * tileSize + tileSize / 2, ent.position.y * tileSize + tileSize / 2), ent.range * tileSize, paintRSUrange);
        // Epsilon change visual marker
        if (ent.epsilonChanged) {
          final paintEps = Paint()
            ..color = Colors.purple
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.0;
          canvas.drawCircle(Offset(ent.position.x * tileSize + tileSize / 2, ent.position.y * tileSize + tileSize / 2), tileSize / 2 + 4.0, paintEps);
        }
        // (Removed visualization for MDP txPower since txPower is no longer an MDP parameter)
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
        } else if (collision) {
          canvas.drawCircle(
            Offset(ent.position.x * tileSize + tileSize / 2, ent.position.y * tileSize + tileSize / 2),
            tileSize / 2,
            paintCollision);
        } else if (ent.free == true) {
          canvas.drawCircle(
            Offset(ent.position.x * tileSize + tileSize / 2, ent.position.y * tileSize + tileSize / 2),
            tileSize / 2,
            paintFreeCar);
        } else {
          canvas.drawCircle(
            Offset(ent.position.x * tileSize + tileSize / 2, ent.position.y * tileSize + tileSize / 2),
            tileSize / 2,
            paintCar);
        }
        // Epsilon change visual marker for cars
        if (ent.epsilonChanged) {
          final paintEps = Paint()
            ..color = Colors.purple
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.0;
          canvas.drawCircle(Offset(ent.position.x * tileSize + tileSize / 2, ent.position.y * tileSize + tileSize / 2), tileSize / 2 + 4.0, paintEps);
        }
        // (Removed visualization for MDP txPower since txPower is no longer an MDP parameter)
      }
    }
    List<Signal> signals = medium.signals;
    for (final signal in signals) {
      final paintSignal = Paint()
        ..color = signal.type == SignalType.rts ? Colors.green : (signal.type == SignalType.ack ? Colors.orange : Colors.purple)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
        final double r = (signal.txRange > 0) ? signal.txRange.toDouble() : (signal.duration.toDouble());
        canvas.drawCircle(
          Offset(signal.x * tileSize + tileSize / 2, signal.y * tileSize + tileSize / 2),
          r * tileSize,
          paintSignal);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
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