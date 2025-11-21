import 'dart:async';
import 'dart:math';

import 'package:daemon/data/in_mem_repo_base.dart';
import 'package:daemon/data/repo_view.dart';
import 'package:daemon/domain/network/network_bitmap.dart';
import 'package:daemon/domain/repositories/base_repo.dart';
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
  late final NetworkBitmap _networkBitmap;
  late final BaseRepo<Car> _carRepo;
  late final BaseRepo<RSU> _rsuRepo;
  late final InMemRepoBase<Entity<dynamic>> _entRepo;
  late Loop _loop;

  // GAME PARAMETERS
  final int fps = 60;
  final double tileSize = 20;
  final int range = 5;
  final int carFrameUpdateInterval = 30;
  final int rsuFrameUpdateInterval = 30;
  final int carSensingRange = 3;
  final int rsuSensingRange = 3;
  int gridWidth = 0;
  int gridHeight = 0;
  List<List<int>> grid = [];

  @override
  void initState() {
    super.initState();
    _entRepo = InMemRepoBase<Entity<dynamic>>();
    _carRepo = RepoView<Car>(_entRepo, (e) => e is Car);
    _rsuRepo = RepoView<RSU>(_entRepo, (e) => e is RSU);

    Completer <void> completer = Completer<void>();

    completer.complete(_loadGrid());
    _networkBitmap = NetworkBitmap(gridWidth, gridHeight);
    print("Loading grid...");
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


      // --- INSTANTIATE RSUS ---
      int numRSUs = 0;
      for (int y = 0; y < image.height; y++) {
        for (int x = 0; x < image.width; x++) {

          final pixel = image.getPixel(x, y);
          final r = pixel.r, g = pixel.g, b = pixel.b, a = pixel.a;
          if (r + g + b == 0 && a == 255) {
            // Black pixel - crossroad
            grid[y][x] = 5;
          } else if (r + g + b == 765) {
            // White pixel - up road
            grid[y][x] = 1;
          } else if (r == 255 && g == 0 && b == 0) {
            // Red pixel - right road
            grid[y][x] = 2;
          } else if (r == 0 && g == 255 && b == 0) {
            // Green pixel - down road
            grid[y][x] = 3;
          } else if (r == 0 && g == 0 && b == 255) {
            // Blue pixel - left road
            grid[y][x] = 4;
          } else if (r == 100 && g == 0 && b == 0) {
            RSU rsu = RSU(
            id: numRSUs++,
            position: Position(
              x: x,
              y: y,
              direction: Direction.up,
            ),
            range: range,
            updateInterval: rsuFrameUpdateInterval,
            sensingRange: rsuSensingRange,
            );

            _rsuRepo.addItem(rsu);
            _entRepo.addItem(rsu);
          }

          if (grid[y][x] != 0) {
            if (rndm.nextDouble() > 0.95 && carPositions.length < 2) {
              if (!carPositions.contains((x, y))) {
                carPositions.add((x, y));
              }
            }
          }
        }
      }

      // --- INSTANTIATE CARS ---
      for (final pos in carPositions) {
        final (carX, carY) = pos;
        final direction = Direction.values[rndm.nextInt(Direction.values.length)];

        Car car = Car(
          id: _entRepo.items.length + 1,
          model: rndm.nextInt(5),
          position: Position(x: carX, y: carY, direction: direction),
          manhattanGrid: grid,
          range: range,
          updateInterval: carFrameUpdateInterval,
          sensingRange: carSensingRange,
        );

        _carRepo.addItem(car);
        _entRepo.addItem(car);
      }
      print('Grid loaded: $gridWidth x $gridHeight');
    } catch (e) {
      print('Error loading grid: $e');
    }
  }

  void _start() async {
    
    if (!_started) {
      print("STARTED");
      setState(() { _started = true; });

      _loop = Loop(carRepo: _carRepo, rsuRepo: _rsuRepo, entRepo: _entRepo, fps: fps, networkBitmap: _networkBitmap);
      _loop.start();
    } else {
      print('STOPPED');
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