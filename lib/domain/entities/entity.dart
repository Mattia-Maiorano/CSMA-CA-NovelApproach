import 'package:daemon/domain/entities/position.dart';
import 'package:daemon/domain/network/signal.dart';
import 'package:daemon/utils/config.dart';

enum NodeState {
  idle,
  sleeping,
  waiting,
  querying,
}

enum TalkingStage {
  idle,
  rts,
  cts,
  query,
  response,
  ack,
}

abstract class Entity<T> {
  final int id;
  final int range;
  final int sensingRange;
  Position position;

  NodeState state = NodeState.idle;
  TalkingStage stage = TalkingStage.idle;

  String emoji = "❓";

  bool requestedSend = false;
  bool confirmedSend = false;
  bool queuedReceive = false;
  bool queuedSleep = false;
  bool queuedWake = false;
  bool requestedExit = false;
  bool backoffExpired = false;

  int ifsTimer = 0;
  int nav = 0;
  int pal = -1;
  int consecutiveCollisions = 0;
  int backoffSlots = -1;
  int timeout = 0;

  Entity(this.id, this.position, this.range, this.sensingRange, this.ifsTimer);

  Signal? step(int tick, Signal? signalToRead) {

    Signal? signal;

    // STATE MACHINE
    handleState(tick);
    handleStage(tick);

    // TIMING HANDLING
    handleTimers();

    // SIGNAL HANDLING
    handleSignal(tick, signalToRead);
    signal = handleResponse();

    specificStep(tick);

    return signal;
  }

  void specificStep(int tick);

  void handleState(int tick);

  void handleStage(int tick);

  void handleSignal(int tick, Signal? signalToRead);

  Signal? handleResponse();

  void handleTimers();

  void nextState(NodeState newState) {
    state = newState;
  }

  void switchState() {
    if (state == NodeState.querying) {
      state = NodeState.waiting;
    } else if (state == NodeState.waiting) {
      state = NodeState.querying;
    }
  }

  void nextStage(TalkingStage newStage) {
    stage = newStage;
  }

  Signal? send() {
    return null;
  }

  void reset() {
    ifsTimer = 0;
    state = NodeState.idle;
    stage = TalkingStage.idle;
    requestedSend = false;
    confirmedSend = false;
    queuedReceive = false;
    queuedSleep = false;
    queuedWake = false;
    requestedExit = false;
    backoffExpired = false;
    nav = 0;
    pal = -1;
    consecutiveCollisions = 0;
    backoffSlots = -1;
    timeout = 0;
  }

  void softReset();

  int getNav(SignalType type) {
    switch (type) {
      case SignalType.rts:
        return NAVTIME;
      case SignalType.cts:
        return NAVTIMECTS;
      case SignalType.query:
        return NAVTIMEQUERY;
      case SignalType.response:
        return NAVTIMERESPONSE;
      case SignalType.ack:
        return NAVTIMEACK;
      default:
        return 0;
    }
  }
}