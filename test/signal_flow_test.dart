import 'package:flutter_test/flutter_test.dart';
import 'package:daemon/domain/network/medium.dart';
import 'package:daemon/domain/entities/classic_car.dart';
import 'package:daemon/domain/entities/position.dart';
import 'package:daemon/domain/entities/entity.dart';
import 'package:daemon/domain/network/signal.dart';
// config import not needed for test

void main() {
  test('Signal creation and sensing between two adjacent cars', () {
    final grid = List.generate(10, (_) => List<int>.filled(10, 1));
    final medium = Medium();

    final carA = Car(id: 0, model: 0, position: Position(x: 2, y: 2, direction: Direction.up), manhattanGrid: grid, range: 7, sensingRange: 3);
    final carB = Car(id: 1, model: 0, position: Position(x: 3, y: 2, direction: Direction.up), manhattanGrid: grid, range: 7, sensingRange: 3);

    // Force Car A to send a signal immediately by setting flags
    carA.state = NodeState.querying;
    carA.stage = TalkingStage.idle;
    carA.requestedSend = true;
    carA.backoffExpired = true;

    final stepA = carA.step(0, 0, null);
    final signalA = stepA.$1;

    expect(signalA, isNotNull, reason: 'Car A should create an RTS signal when requestedSend and backoffExpired are true');
    expect(signalA!.type, SignalType.rts);

    medium.transmit(signalA);
    medium.step();

    final sensed = medium.sense(carB.position.x, carB.position.y, carB.sensingRange, carB.id);
    expect(sensed, isNotNull, reason: 'Car B should sense Car A\'s signal');
    expect(sensed!.type, SignalType.rts);
  });
}
