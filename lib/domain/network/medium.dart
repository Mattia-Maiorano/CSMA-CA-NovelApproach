import 'signal.dart';

class Medium {
  List<Signal> signals = [];

  Signal? sense(int x, int y, int range, int receiverId) {
    for (var signal in signals) {
      final dx = signal.x - x;
      final dy = signal.y - y;
      final distanceSquared = dx * dx + dy * dy;
      if (distanceSquared <= range * range) {
        return signal;
      }
    }

    return null;
  }

  void transmit(Signal signal) {
    signals.add(signal);
  }

}