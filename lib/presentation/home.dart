/// ============================================================================
/// Home Page - Main UI for V2X Simulation
/// ============================================================================
/// Provides:
/// - Configuration panel to set simulation parameters (cars, RSUs, FPS, MDP mode)
/// - Visual grid display of the road network and entities
/// - Controls to start/stop simulation
/// - Access to the Resumer page for analyzing MDP learning progress
/// ============================================================================

import 'dart:async';
import 'dart:math';

import 'package:daemon/data/in_mem_repo_base.dart';
import 'package:daemon/data/repo_view.dart';
import 'package:daemon/domain/network/medium.dart';
import 'package:daemon/domain/repositories/base_repo.dart';
import 'package:daemon/application/loop.dart';
import 'package:daemon/domain/entities/classic_car.dart';
import 'package:daemon/domain/entities/mdp_car.dart';
import 'package:daemon/domain/ai/q_agent.dart';
import 'package:daemon/domain/entities/entity.dart';
import 'package:daemon/domain/entities/classic_rsu.dart';
import 'package:daemon/domain/entities/mdp_rsu.dart';
import 'package:daemon/domain/entities/position.dart';
import 'package:daemon/utils/config.dart';
import 'package:daemon/utils/analyzer.dart';
import 'package:daemon/utils/resumer.dart';

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
  // ─────────────────────────────────────────────────────────────────────────
  // State Variables
  // ─────────────────────────────────────────────────────────────────────────
  bool _started = false;
  bool _gridLoaded = false;
  bool _showConfig = true;

  // ─────────────────────────────────────────────────────────────────────────
  // Simulation Components
  // ─────────────────────────────────────────────────────────────────────────
  late final Medium medium = Medium();
  late final BaseRepo<Car> _carRepo;
  late final BaseRepo<RSU> _rsuRepo;
  late final InMemRepoBase<Entity<dynamic>> _entRepo;
  late final Analyzer _analyzer = Analyzer();
  late Loop _loop;

  // ─────────────────────────────────────────────────────────────────────────
  // Configuration Parameters (adjustable via UI)
  // ─────────────────────────────────────────────────────────────────────────
  int _carNum = CARNUM;
  int _rsuNum = RSUNUM;
  int _fps = FPS;
  // Toggle for MDP agents vs classic CSMA/CA
  bool _useMDP = USE_MDP;

  // ─────────────────────────────────────────────────────────────────────────
  // Grid/Display Parameters
  // ─────────────────────────────────────────────────────────────────────────
  final double tileSize = 20;
  final int range = RANGE;
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

    _loadGridOnly();
  }

  Future<void> _loadGridOnly() async {
    try {
      final file = (await rootBundle.load(
        'assets/simple_grid.png',
      )).buffer.asUint8List();
      final bytes = file;
      final image = img.decodeImage(bytes.buffer.asUint8List());

      if (image == null) {
        return;
      }

      setState(() {
        gridWidth = image.width;
        gridHeight = image.height;
        grid = List.generate(
          image.height,
          (_) => List<int>.filled(image.width, 0),
        );
      });

      // Parse grid
      for (int y = 0; y < image.height; y++) {
        for (int x = 0; x < image.width; x++) {
          final pixel = image.getPixel(x, y);
          final r = pixel.r, g = pixel.g, b = pixel.b, a = pixel.a;
          if (r + g + b == 0 && a == 255) {
            grid[y][x] = 5; // Black - crossroad
          } else if (r + g + b == 765) {
            grid[y][x] = 1; // White - up road
          } else if (r == 255 && g == 0 && b == 0) {
            grid[y][x] = 2; // Red - right road
          } else if (r == 0 && g == 255 && b == 0) {
            grid[y][x] = 3; // Green - down road
          } else if (r == 0 && g == 0 && b == 255) {
            grid[y][x] = 4; // Blue - left road
          } else if (r == 100 && g == 0 && b == 0) {
            grid[y][x] = 100; // Dark red - RSU location
          }
        }
      }

      setState(() {
        _gridLoaded = true;
      });

      print('Grid loaded: $gridWidth x $gridHeight');
    } catch (e) {
      print('Error loading grid: $e');
    }
  }

  Future<void> _loadGrid() async {
    // Clear existing entities
    final entitiesToRemove = _entRepo.items.toList();
    for (final entity in entitiesToRemove) {
      await _entRepo.removeItem(entity);
    }

    final Random rndm = Random();
    List<(int, int)> carPositions = [];
    // --- INSTANTIATE RSUS ---
    int numRSUs = 0;
    final List<(int, int)> availableTiles = [];
    for (int y = 0; y < gridHeight; y++) {
      for (int x = 0; x < gridWidth; x++) {
        // RSU placement
        if (grid[y][x] == 100 && numRSUs < _rsuNum) {
          RSU rsu;
          if (_useMDP) {
            final agent = QAgent(_entRepo.items.length, [
              'ready',
              'defer',
            ], epsilon: DEFAULT_EPSILON);
            rsu = MDPRSU(
              id: numRSUs++,
              position: Position(x: x, y: y, direction: Direction.up),
              range: range,
              sensingRange: rsuSensingRange,
              analyzer: _analyzer,
              agent: agent,
            );
          } else {
            rsu = RSU(
              id: numRSUs++,
              position: Position(x: x, y: y, direction: Direction.up),
              range: range,
              sensingRange: rsuSensingRange,
              analyzer: _analyzer,
            );
          }

          _entRepo.addItem(rsu);
        }

        // Collect road tiles (exclude RSU and empty)
        if (grid[y][x] != 0 && grid[y][x] != 100) {
          availableTiles.add((x, y));
        }
      }
    }

    // --- DISTRIBUTE CARS EQUALLY --- (farthest-first / k-center selection)
    carPositions = [];

    if (availableTiles.isNotEmpty) {
      final int carsToPlace = min(_carNum, availableTiles.length);

      // helper to compute Euclidean distance on records
      double _dist((int, int) a, (int, int) b) {
        final (ax, ay) = a;
        final (bx, by) = b;
        return sqrt((ax - bx) * (ax - bx) + (ay - by) * (ay - by));
      }

      // pick first at random
      final (int, int) first =
          availableTiles[rndm.nextInt(availableTiles.length)];
      carPositions.add(first);

      // greedily pick the farthest point from the set for each new car
      while (carPositions.length < carsToPlace) {
        double bestMinDist = -1;
        (int, int) bestCandidate = availableTiles.first;

        for (final candidate in availableTiles) {
          if (carPositions.contains(candidate)) continue;

          double minD = double.infinity;
          for (final chosen in carPositions) {
            final d = _dist(candidate, chosen);
            if (d < minD) minD = d;
          }

          if (minD > bestMinDist) {
            bestMinDist = minD;
            bestCandidate = candidate;
          }
        }

        carPositions.add(bestCandidate);
      }
    }

    // --- INSTANTIATE CARS ---
    for (final pos in carPositions) {
      final (carX, carY) = pos;
      final direction = Direction.values[rndm.nextInt(Direction.values.length)];

      Car car;
      if (_useMDP) {
        final agent = QAgent(_entRepo.items.length, [
          'startComm',
          'defer',
        ], epsilon: DEFAULT_EPSILON);
        car = MDPCar(
          id: _entRepo.items.length,
          model: rndm.nextInt(5),
          position: Position(x: carX, y: carY, direction: direction),
          manhattanGrid: grid,
          range: range,
          sensingRange: carSensingRange,
          timer: rndm.nextInt(10),
          analyzer: _analyzer,
          agent: agent,
        );
      } else {
        car = Car(
          id: _entRepo.items.length,
          model: rndm.nextInt(5),
          position: Position(x: carX, y: carY, direction: direction),
          manhattanGrid: grid,
          range: range,
          sensingRange: carSensingRange,
          timer: rndm.nextInt(10),
          analyzer: _analyzer,
        );
      }

      _entRepo.addItem(car);
    }

    print(
      'Loaded ${_entRepo.items.whereType<RSU>().length} RSUs and ${_entRepo.items.whereType<Car>().length} Cars',
    );
  }

  void _applyConfigAndStart() async {
    setState(() {
      _showConfig = false;
    });

    print("Applying configuration: Cars=$_carNum, RSUs=$_rsuNum, FPS=$_fps");

    await _loadGrid();
    _start();
  }

  void _start() async {
    if (!_started) {
      print("------------ STARTED ------------");
      setState(() {
        _started = true;
      });

      _loop = Loop(
        carRepo: _carRepo,
        rsuRepo: _rsuRepo,
        entRepo: _entRepo,
        fps: _fps,
        medium: medium,
        analyzer: _analyzer,
      );
      _loop.start(_useMDP);
    } else {
      print("------------ STOPPED ------------");

      _loop.stop();
      await _loop.waitForStop();
      // Ensure the Analyzer writes the ZIP and allow immediate download if available
      try {
        final savedPath = await _analyzer.closeAndWrite(_useMDP);
        final messenger = ScaffoldMessenger.of(context);
        if (savedPath != null) {
          messenger.showSnackBar(
            SnackBar(content: Text('Analyzer export saved: $savedPath')),
          );
        } else {
          // Fallback: maybe closeAndWrite didn't save to a file (web or other); try to trigger download with bytes
          final fallback = await _analyzer.downloadLastZip();
          if (fallback != null) {
            messenger.showSnackBar(
              SnackBar(content: Text('Analyzer export saved: $fallback')),
            );
          } else {
            messenger.showSnackBar(
              const SnackBar(
                content: Text(
                  'Analyzer export created; no file saved automatically - open Resumer to download or check console for logs',
                ),
              ),
            );
          }
        }
      } catch (e) {
        print('Analyzer export failed: $e');
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
          SnackBar(content: Text('Analyzer export failed: $e')),
        );
      }

      setState(() {
        _started = false;
        _showConfig = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_gridLoaded) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          titleTextStyle: const TextStyle(
            color: Color.fromARGB(255, 0, 0, 0),
            fontSize: 20,
          ),
          actions: [
            IconButton(
              tooltip: 'Download last analyzer ZIP',
              icon: const Icon(Icons.download),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  if (_analyzer.lastZipBytes == null ||
                      _analyzer.lastZipFilename == null) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('No analyzer ZIP available yet.'),
                      ),
                    );
                    return;
                  }
                  final saved = await _analyzer.downloadLastZip();
                  if (saved != null)
                    messenger.showSnackBar(
                      SnackBar(content: Text('Analyzer export saved: $saved')),
                    );
                  else
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Analyzer ZIP download started'),
                      ),
                    );
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Failed to download analyzer ZIP: $e'),
                    ),
                  );
                }
              },
            ),
            IconButton(
              tooltip: 'Export analyzer now',
              icon: const Icon(Icons.save),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  final savedPath = await _analyzer.closeAndWrite(_useMDP);
                  if (savedPath != null) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('Analyzer export saved: $savedPath'),
                      ),
                    );
                  } else {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Analyzer export created; check Resumer to download',
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(content: Text('Failed to export analyzer: $e')),
                  );
                }
              },
            ),
          ],
        ),
        body: const Center(child: CircularProgressIndicator()),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => ResumerPage(analyzer: _analyzer),
              ),
            );
          },
          tooltip: 'Open MDP Analyzer',
          child: const Icon(Icons.bar_chart),
        ),
      );
    }

    if (_showConfig) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          titleTextStyle: const TextStyle(
            color: Color.fromARGB(255, 0, 0, 0),
            fontSize: 20,
          ),
          actions: [
            IconButton(
              tooltip: 'Download last analyzer ZIP',
              icon: const Icon(Icons.download),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  if (_analyzer.lastZipBytes == null ||
                      _analyzer.lastZipFilename == null) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('No analyzer ZIP available yet.'),
                      ),
                    );
                    return;
                  }
                  final saved = await _analyzer.downloadLastZip();
                  if (saved != null)
                    messenger.showSnackBar(
                      SnackBar(content: Text('Analyzer export saved: $saved')),
                    );
                  else
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Analyzer ZIP download started'),
                      ),
                    );
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Failed to download analyzer ZIP: $e'),
                    ),
                  );
                }
              },
            ),
            IconButton(
              tooltip: 'Export analyzer now',
              icon: const Icon(Icons.save),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  final savedPath = await _analyzer.closeAndWrite(_useMDP);
                  if (savedPath != null) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('Analyzer export saved: $savedPath'),
                      ),
                    );
                  } else {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Analyzer export created; check Resumer to download',
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(content: Text('Failed to export analyzer: $e')),
                  );
                }
              },
            ),
          ],
        ),
        body: Center(
          child: Card(
            elevation: 8,
            margin: const EdgeInsets.all(40),
            child: Padding(
              padding: const EdgeInsets.all(40.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Simulation Configuration',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 30),

                  // Use MDP toggle
                  Row(
                    children: [
                      const Text(
                        'Use MDP Agents',
                        style: TextStyle(fontSize: 16),
                      ),
                      const SizedBox(width: 8),
                      Switch(
                        value: _useMDP,
                        onChanged: (v) => setState(() => _useMDP = v),
                      ),
                    ],
                  ),

                  // Car Number Slider
                  Text(
                    'Number of Cars: $_carNum',
                    style: const TextStyle(fontSize: 16),
                  ),

                  const SizedBox(height: 20),
                  Slider(
                    value: _carNum.toDouble(),
                    min: 1,
                    max: 20,
                    divisions: 19,
                    label: _carNum.toString(),
                    onChanged: (value) {
                      setState(() {
                        _carNum = value.toInt();
                      });
                    },
                  ),
                  const SizedBox(height: 20),

                  // RSU Number Slider
                  Text(
                    'Number of RSUs: $_rsuNum',
                    style: const TextStyle(fontSize: 16),
                  ),
                  Slider(
                    value: _rsuNum.toDouble(),
                    min: 1,
                    max: 4,
                    divisions: 3,
                    label: _rsuNum.toString(),
                    onChanged: (value) {
                      setState(() {
                        _rsuNum = value.toInt();
                      });
                    },
                  ),
                  const SizedBox(height: 20),

                  // FPS Slider
                  Text('FPS: $_fps', style: const TextStyle(fontSize: 16)),
                  Slider(
                    value: _fps.toDouble(),
                    min: 1,
                    max: 10,
                    divisions: 9,
                    label: _fps.toString(),
                    onChanged: (value) {
                      setState(() {
                        _fps = value.toInt();
                      });
                    },
                  ),
                  const SizedBox(height: 40), // Start Button
                  Center(
                    child: ElevatedButton(
                      onPressed: _applyConfigAndStart,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 50,
                          vertical: 20,
                        ),
                        textStyle: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      child: const Text('START SIMULATION'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => ResumerPage(analyzer: _analyzer),
              ),
            );
          },
          tooltip: 'Open MDP Analyzer',
          child: const Icon(Icons.bar_chart),
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
        actions: [
          IconButton(
            tooltip: 'Download last analyzer ZIP',
            icon: const Icon(Icons.download),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                if (_analyzer.lastZipBytes == null ||
                    _analyzer.lastZipFilename == null) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('No analyzer ZIP available yet.'),
                    ),
                  );
                  return;
                }
                await _analyzer.downloadLastZip();
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Analyzer ZIP download started'),
                  ),
                );
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Failed to download analyzer ZIP: $e'),
                  ),
                );
              }
            },
          ),
          IconButton(
            tooltip: 'Export analyzer now',
            icon: const Icon(Icons.save),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                final savedPath = await _analyzer.closeAndWrite(_useMDP);
                if (savedPath != null) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Analyzer export saved: $savedPath'),
                    ),
                  );
                } else {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Analyzer export created; check Resumer to download',
                      ),
                    ),
                  );
                }
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Failed to export analyzer: $e')),
                );
              }
            },
          ),
        ],
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
                ),
              ),
            ),
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
                            painter: ScenePainter(
                              entities.cast<Entity<dynamic>>(),
                              medium,
                              tileSize,
                            ),
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
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ResumerPage(analyzer: _analyzer),
            ),
          );
        },
        tooltip: 'Open MDP Analyzer',
        child: const Icon(Icons.bar_chart),
      ),
    );
  }
}
