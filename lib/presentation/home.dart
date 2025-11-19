import 'dart:async';
import 'dart:math';

import 'package:daemon/data/in_mem_car_repo.dart';
import 'package:daemon/data/in_mem_repo_base.dart';
import 'package:daemon/data/in_mem_rsu_repo.dart';
import 'package:daemon/application/loop.dart';
import 'package:daemon/domain/entities/car.dart';
import 'package:daemon/domain/entities/entity.dart';
import 'package:daemon/domain/entities/rsu.dart';
import 'package:daemon/domain/entities/position.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:image/image.dart' as img;

import 'painter.dart';


class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  bool _started = false;
  late final InMemCarRepo _carRepo;
  late final InMemRsuRepo _rsuRepo;
  late final InMemRepoBase<Entity<dynamic>> _entRepo;
  late Loop _loop;

  // GAME PARAMETERS
  final int fps = 2;
  final double tileSize = 20;
  int gridWidth = 0;
  int gridHeight = 0;
  List<List<int>> grid = [];

  @override
  void initState() {
    super.initState();
    _carRepo = InMemCarRepo();
    _rsuRepo = InMemRsuRepo();
    _entRepo = InMemRepoBase<Entity<dynamic>>();

    Completer <void> completer = Completer<void>();

    completer.complete(_loadGrid());
    print("LOAD GRID CALLED");
  }

  Future<void> _loadGrid() async {
    try{
      final file = (await rootBundle.load('assets/grid.png')).buffer.asUint8List();
      final bytes = file;
      final image = img.decodeImage(bytes.buffer.asUint8List());

      if (image == null) {
        return;
      }

      print('Image loaded: ${image.width}x${image.height}');
      setState(() {
        gridWidth = image.width;
        gridHeight = image.height;
        grid = List.generate(image.height, (_) => List<int>.filled(image.width, 0));
      });

      final Random rndm = Random();
      List<(int, int)> carPositions = [];

      // Read RGB values of each pixel
      for (int y = 0; y < image.height; y++) {
        for (int x = 0; x < image.width; x++) {

          final pixel = image.getPixel(x, y);
          final r = pixel.r, g = pixel.g, b = pixel.b, a = pixel.a;
          if (r + g + b == 0 && a == 255) {

            _rsuRepo.addItem(RSU(
              position: Position(x: x, y: y, direction: Direction.up),
              id: _entRepo.items.length + 1,
              range: 3,
            ));
            _entRepo.addItem(RSU(
              position: Position(x: x, y: y, direction: Direction.up),
              id: _entRepo.items.length + 1,
              range: 3,
            ));
          } else if (r + g + b == 765) {
            // White pixel - road
            grid[y][x] = 1;
            if (rndm.nextDouble() > 0.98 && carPositions.length < 2) {
              if (!carPositions.contains((x, y))) {
                carPositions.add((x, y));
              }
            }
          }
        }

        for (final pos in carPositions) {
          final (carX, carY) = pos;
          final direction = Direction.values[rndm.nextInt(Direction.values.length)];

          _carRepo.addItem(Car(
            id: _entRepo.items.length + 1,
            model: rndm.nextInt(5),
            position: Position(x: carX, y: carY, direction: direction),
            manhattanGrid: grid,
          ));
          _entRepo.addItem(Car(
            id: _entRepo.items.length + 1,
            model: rndm.nextInt(5),
            position: Position(x: carX, y: carY, direction: direction),
            manhattanGrid: grid,
          ));
        }
      }
    } catch (e) {
      print("Error in _loadGrid: $e");
    }
  }

  void _start() async {
    
    if (!_started) {
      setState(() { _started = true; });

      _loop = Loop(carRepo: _carRepo, rsuRepo: _rsuRepo, entRepo: _entRepo, fps: fps);
      _loop.start();
    } else {
      _loop.stop();
      await _loop.waitForStop();

      setState(() { _started = false; });
    }
  }

  @override
  Widget build(BuildContext context) {

    if (gridWidth == 0 || gridHeight == 0) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          titleTextStyle: const TextStyle(
            color: Color.fromARGB(255, 0, 0, 0),
            fontSize: 20,
          ),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        titleTextStyle: const TextStyle(
          color: Color.fromARGB(255, 0, 0, 0),
          fontSize: 20,
        ),
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(40.0),
              child: Align(
                alignment: Alignment.topLeft,
                child: GestureDetector(
                  onTap: _start,
                  child: Container(
                    width: 100,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _started ? Colors.red : Colors.green,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        _started ? 'STOP' : 'START',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                )
              ),
            )
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(100.0),
              child: Stack(
                children: [
                  SizedBox(
                    width: gridWidth * tileSize,
                    height: gridHeight * tileSize,
                    child: CustomPaint(
                      painter: StaticScenePainter(grid, tileSize),
                    ),
                  ),
                  SizedBox(
                    width: gridWidth * tileSize,
                    height: gridHeight * tileSize,
                    child: StreamBuilder(
                      stream: _entRepo.watchItems(),
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          final entities = snapshot.data!;
                          return CustomPaint(
                            painter: ScenePainter(entities.cast<Entity<dynamic>>(), tileSize),
                            child: SizedBox(
                              width: gridWidth * tileSize,
                              height: gridHeight * tileSize,
                            ),
                          );
                        } else {
                          return SizedBox(
                            width: gridWidth * tileSize,
                            height: gridHeight * tileSize,
                          );
                        }
                      },
                    )
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}