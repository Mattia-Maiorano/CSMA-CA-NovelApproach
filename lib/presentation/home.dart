import 'package:daemon/data/in_mem_car_repo.dart';
import 'package:daemon/data/in_mem_rsu_repo.dart';
import 'package:daemon/application/loop.dart';
import 'package:daemon/domain/entities/car.dart';
import 'package:daemon/domain/entities/rsu.dart';
import 'package:daemon/domain/entities/position.dart';
import 'package:flutter/material.dart';

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
  final int fps = 60;
  late Loop _loop;
  late Future<void> _loopFuture;

  @override
  void initState() {
    super.initState();
    _carRepo = InMemCarRepo();
    _rsuRepo = InMemRsuRepo();

    _carRepo.addCar(Car(
      id: '1', model: 1, position: Position(x: 0, y: 0, direction: Direction.right)));
    _carRepo.addCar(Car(
      id: '2', model: 2, position: Position(x: 5, y: 0, direction: Direction.left)));

    _rsuRepo.addRSU(RSU(position: Position(x: 2, y: 0, direction: Direction.up), id: 1, range: 3));
  }

  void _start() async {
    print('Entered');
    
    if (!_started) {
      setState(() { _started = true; });

      _loop = Loop(carRepo: _carRepo, rsuRepo: _rsuRepo, fps: fps);
      _loopFuture = _loop.start();
    } else {
      _loop.stop();
      _loop.waitForStop();
      print("Waiting for loop to stop");
      await _loopFuture;
      print("Loop stopped");

      _carRepo.dispose();
      _rsuRepo.dispose();
      setState(() { _started = false; });
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        titleTextStyle: const TextStyle(
          color: Color.fromARGB(255, 0, 0, 0),
          fontSize: 20,
        ),
      ),
      body: Center(
        child: Stack(
          children: [
            StreamBuilder(
              stream: _carRepo.watchCars(),
              builder:  (context, snapshot) {
                final cars = snapshot.data ?? [];
                return ListView.builder(
                  itemCount: cars.length,
                  itemBuilder: (_, i) {
                    final c = cars[i];
                    return ListTile(
                      title: Text('Car ${c.id}'),
                      subtitle: Text('pos: (${c.position.x}, ${c.position.y})'),
                    );
                  },
                );
              },
            ),
            AnimatedAlign(
              alignment: _started ? Alignment.center : Alignment.topLeft,
              duration: Duration(milliseconds: 500),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _start,
                child: Icon(_started ? Icons.stop : Icons.play_arrow, size: 40)),
            ),
          ],
        ),
      ),
    );
  }
}