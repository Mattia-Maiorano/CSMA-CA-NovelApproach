import 'signal.dart';

class Medium {
  List<Signal> signals = [];
  List<Signal> queuedSignals = [];

  Signal? sense(int x, int y, int range, int receiverId) {
    Signal? toReturn;

    for (var signal in signals) {
      final dx = signal.x - x;
      final dy = signal.y - y;
      final distanceSquared = dx * dx + dy * dy;
      if (distanceSquared <= range * range) {
        if (toReturn == null) {
          toReturn = signal;
        } else {
          return null;
        }
      }
    }

    return toReturn;
  }

  void transmit(Signal signal) {
    queuedSignals.add(signal);
  }

  void step() {
    signals.removeWhere((signal) {
      signal.duration -= 1;
      return signal.duration <= 0;
    });

    signals.addAll(queuedSignals);
    queuedSignals.clear();
  }
}