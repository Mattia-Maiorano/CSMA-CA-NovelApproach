/// ============================================================================
/// Medium - Shared Wireless Channel Simulation
/// ============================================================================
/// Simulates the shared wireless medium for V2X communication.
///
/// Features:
/// - Transmit: Queue signals for broadcast
/// - Sense: Check for signals within range (returns collision if multiple)
/// - Step: Advance signal durations and add queued signals
///
/// Collision Detection:
/// - If a receiver senses multiple overlapping signals, returns a "broken" signal
/// ============================================================================

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
      // The transmitter's txRange may limit reception as well; if not specified, default to receiver range
      final txRange = signal.txRange > 0 ? signal.txRange : range;
      if (distanceSquared <= txRange * txRange && distanceSquared <= range * range) {
        if (toReturn == null) {
          toReturn = signal;
        } else {
          return Signal(
            ownerId: -1,
            destinationId: -2,
            x: -1,
            y: -1,
            type: SignalType.broken,
          );
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

  void getSignalsInfo() {
    print("");
    print("-------- Signals in Medium -------");
    for (var signal in signals) {
      print('Signal from ${signal.ownerId} to ${signal.destinationId} at (${signal.x}, ${signal.y}) of type ${signal.type} with duration ${signal.duration}');
    }
    print("-------- End of Signals -------");
    print("");
  }
}
