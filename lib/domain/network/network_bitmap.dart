import 'dart:collection';

import 'signal.dart';

class NetworkBitmap {
  final Queue<Signal> _enqueuedSignals = Queue<Signal>();
  final Set<Signal> _signals = {};
  int tick = 0;

  NetworkBitmap(int width, int height);

  void reserve(int x, int y, Signal signal) {
    final key = (x, y);
    if (_signals.add(signal)) {
      signal.setStartTick(tick);
    }
  }

  void enqueueSignal(Signal signal) {
    _enqueuedSignals.addLast(signal);
  }

  void step() {

    // --- CLEAN UP EXPIRED SIGNALS ---
    _signals.removeWhere((signal) => signal.endTick <= tick);
    List<(int, int)> keysToRemove = [];
    bitmap.forEach((key, signals) {
      signals.removeWhere((signal) => signal.endTick <= tick);
      if (signals.isEmpty) keysToRemove.add(key);
    });
    for (final k in keysToRemove) {
      bitmap.remove(k);
      bitmapResidualIntensity.remove(k);
    }

    // --- RESERVE ENQUEUED SIGNALS ---
    while (_enqueuedSignals.isNotEmpty) {
      final signal = _enqueuedSignals.removeFirst();
      print("${tick}-${signal.ownerId}) 🛜 enqueuing signal with data ${signal.data} for ${signal.destinationId}");
      if (canReserve(signal.x, signal.y).isEmpty || true) {
        print("${tick}-${signal.ownerId}) 🛜 reserving signal with data ${signal.data} for ${signal.destinationId} at (${signal.x}, ${signal.y})");
        reserve(signal.x, signal.y, signal);
      }
    }

    // --- PROPAGATE SIGNALS ---
    for (Signal signal in _signals) {
      int travelDistance = signal.duration - (signal.endTick - tick);
      if (travelDistance <= 0) {
        continue;
      }
      expandSignal(travelDistance, signal);
    }

    // --- RECOMPUTE RESIDUAL INTENSITIES ---
    bitmap.forEach((key, signals) {
      if (signals.isEmpty) {
        bitmapResidualIntensity.remove(key);
      } else {
        int maxIntensity = 0;
        int noise = 0;
        Signal? maxSignal;
        for (final existingSignal in signals) {
          int intensity = existingSignal.endTick - tick;
          if (intensity > maxIntensity) {
            maxIntensity = intensity;
            maxSignal = existingSignal;
          }
          noise += intensity;
        }
        double ratio = noise > 0 ? (maxIntensity / noise) : 0.0;
        int ownerId = maxSignal != null ? maxSignal.ownerId : -1;
        bitmapResidualIntensity[key] = (ratio, ownerId);
      }
    });

    tick++;
  }

  Signal? receiveSignalsAt(int x, int y, int sensingRange, int readerId) {
    if (bitmapResidualIntensity.containsKey((x, y))) {
      final (intensity, ownerId) = bitmapResidualIntensity[(x, y)]!;
      if (intensity > 0.5) {
        final signals = bitmap[(x, y)];
        if (signals == null) return null;
        for (final signal in signals) {
          // First we check that the signal is from the strongest owner.
          // Then we check that the signal is either broadcast (destinationId == -1) or specifically addressed to the reader.
          if (signal.ownerId == ownerId && (signal.destinationId == readerId || signal.destinationId == -1)) return signal;
        }
        return null;
      }
    }
    return null;
  }

}