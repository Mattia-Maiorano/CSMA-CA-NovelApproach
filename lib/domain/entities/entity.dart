import 'package:daemon/domain/entities/position.dart';
import 'package:daemon/domain/network/signal.dart';
import 'package:daemon/utils/config.dart';
import 'package:image/image.dart';

enum NodeState {
  idle,
  sleeping,
  waiting,
  querying,
  collision,
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
  bool requestedQueueReceive = false;
  bool queuedReceive = false;
  bool queuedSleep = false;
  bool queuedWake = false;
  bool requestedExit = false;
  bool backoffExpired = false;

  int ifsTimer = 0;
  int nav = 0;
  int pal = -1;
  int consecutiveCollisions = STARTING_EXPONENT;
  int backoffSlots = -1;
  int timeout = 0;

  Signal? lastSeenSignal;
  TalkingStage? lastReachedStage;
  NodeState? lastReachedState;

  Entity(this.id, this.position, this.range, this.sensingRange, this.ifsTimer);

  Signal? step(int tick, Signal? signalToRead) {

    if (id == 4) print("");

    Signal? signal;

    // STATE MACHINE
    handleState(tick);

    // TIMING HANDLING
    handleTimers();

    // SIGNAL HANDLING
    handleSignal(tick, signalToRead);
    if (state == NodeState.querying || state == NodeState.collision) signal = handleResponse();

    handleStage(tick);
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

  void enterCollisionHandling() {
    lastReachedStage = stage;
    lastReachedState = state;
    previousStage();
    state = NodeState.collision;
    consecutiveCollisions++;
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

  void restoreState() {
    if (lastReachedState != null) {
      state = lastReachedState!;
      if (state == NodeState.waiting) confirmedSend = false;
    }
  }

  Signal? send() {
    return null;
  }

  void reset({bool resetNav = true}) {
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
    pal = -1;
    consecutiveCollisions = STARTING_EXPONENT;
    backoffSlots = -1;
    timeout = 0;
    lastSeenSignal = null;
    requestedQueueReceive = false;
    if (resetNav) nav = 0;
  }

  void softReset();

  void previousStage() {
    if (stage == TalkingStage.rts) {
      stage = TalkingStage.idle;
    } else if (stage == TalkingStage.cts) {
      stage = TalkingStage.rts;
    } else if (stage == TalkingStage.query) {
      stage = TalkingStage.cts;
    } else if (stage == TalkingStage.response) {
      stage = TalkingStage.query;
    }
  }

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