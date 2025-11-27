import 'package:daemon/domain/entities/position.dart';
import 'package:daemon/domain/entities/entity.dart';
import 'package:daemon/domain/network/signal.dart';
import 'package:daemon/utils/config.dart';

class Car extends Entity {
  final List<List<int>> manhattanGrid;
  final int model;

  int enqueuedStopSender = -1;
  int enqueuedCtsSender = -1;

  bool stop = false;
  bool free = false;

  Car({required int id, required this.model, required Position position, required this.manhattanGrid, required int range, required int sensingRange, int timer = 0}) : super(id, position, range, sensingRange, timer) {
    emoji = "🚗";
  }

  Signal? step(int tick, Signal? signalToRead) {

    // ---- RESET / TIMEOUT ----
    final bool timeoutExpired = consumeTimeoutIfExpired();
    if (timeoutExpired) {
      if (consecutiveCollisions >= MAX_BACKOFF_EXPONENT) {
        connectionState = ConnectionState.idle;
        print('$tick-$id)	$emoji	☠️\t: new state: $connectionState');
        consecutiveCollisions = 0;
        enqueuedStopSender = -1;
        enqueuedCtsSender = -1;
        communication = false;
        waiting = false;
      } else {
        connectionState = previousState();
        print('$tick-$id)	$emoji	⏰\t: new state: $connectionState');
        consecutiveCollisions++;
      }
    }

    // ---- SENSING / SIGNAL PROCESSING ----
    Signal? signal;
    final bool forMe = sense(signalToRead, tick);

    if (nav == 0) {
      timer++;

      if (forMe && signalToRead != null) {
        _handleOccupiedMedium(signalToRead);
      } else if (signalToRead == null && backoffSlots == 0) {
        signal = _handleFreeMedium();
      } else {
        backoffHelper();
      }
    }

    // ---- MOVEMENT LOGIC ----
    if (tick % BROADCASTINTERVAL == 0) {
      _movementStep();
      stop = false;
      free = false;
    }

    return signal;
  }

  void _handleOccupiedMedium(Signal signalToRead) {
    if (!attemptedNewCommunicationWhileBusy) {
      consecutiveCollisions = 0;

      //    receive cts
      if (signalToRead.type == SignalType.cts && connectionState == ConnectionState.rtsSent) {
        enqueuedCtsSender = signalToRead.ownerId;
        timeout = RESETTIME;
        waiting = false;
        connectionState = nextState();
      }
      
      //    receive response
      else if ((signalToRead.data == SignalData.stop || signalToRead.data == SignalData.free) && connectionState == ConnectionState.querySent) {
        stop = signalToRead.data == SignalData.stop;
        free = signalToRead.data == SignalData.free;
        enqueuedCtsSender = -1;
        enqueuedStopSender = signalToRead.ownerId;
        timeout = RESETTIME;
        waiting = false;
        connectionState = nextState();
      }
    }
  }

  Signal? _handleFreeMedium() {

    print("$id)\t$emoji\t📡\t: MEDIUM FREE, SENDING SIGNAL");

    // send ack for stop/free
    if (enqueuedStopSender != -1 && connectionState == ConnectionState.responseReceived) {
      final s = Signal(
        type: SignalType.ack,
        x: position.x,
        y: position.y,
        ownerId: id,
        destinationId: enqueuedStopSender,
      );

      enqueuedStopSender = -1;
      waiting = false;
      communication = false;
      backoffSlots = -1;
      timeout = RESETTIME;
      timer = 0;
      connectionState = nextState();
      return s;
    }

    // send position (query)
    else if (enqueuedCtsSender != -1 && connectionState == ConnectionState.ctsReceived) {
      final s = Signal(
        type: SignalType.query,
        x: position.x,
        y: position.y,
        ownerId: id,
        car: this,
        destinationId: enqueuedCtsSender,
      );

      waiting = true;
      backoffSlots = -1;
      timeout = RESETTIME;
      connectionState = nextState();
      return s;
    }

    // send rts (start communication)
    else if (!communication && connectionState == ConnectionState.idle) {
      final s = Signal(
        type: SignalType.rts,
        x: position.x,
        y: position.y,
        ownerId: id,
        car: this,
        destinationId: -1, // broadcast
      );

      communication = true;
      waiting = true;
      backoffSlots = -1;
      timeout = RESETTIME;
      connectionState = nextState();
      return s;
    }

    return null;
  }

  void _movementStep() {
    if (!stop) {
      if (manhattanGrid[position.y][position.x] == 5) {
        position.direction = position.newDirection();
      }

      Position newPosition = moveForward();
      int maxRetries = 10;
      while (manhattanGrid[newPosition.y][newPosition.x] == 0 ||
          (manhattanGrid[newPosition.y][newPosition.x] != position.direction.index + 1 && manhattanGrid[newPosition.y][newPosition.x] != 5)) {
        if (maxRetries-- <= 0) break;
        position.direction = position.newDirection();
        newPosition = moveForward();
      }

      position = Position(x: newPosition.x, y: newPosition.y, direction: position.direction);
    }
  }

  Position moveForward() {
    switch (position.direction) {
      case Direction.up:
        return position.movedBy(0, -1);
      case Direction.down:
        return position.movedBy(0, 1);
      case Direction.left:
        return position.movedBy(-1, 0);
      case Direction.right:
        return position.movedBy(1, 0);
    }
  }
}