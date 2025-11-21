import 'signal.dart';

class NetworkBitmap {
  final Map<(int, int), List<Signal>> bitmap = {};
  final Map<(int, int), (double, int)> bitmapResidualIntensity = {};
  List<Signal> _enqueuedSignals = [];
  List<Signal> _signals = [];
  int tick = 0;

  NetworkBitmap(int width, int height);

  List<Signal> canReserve(int x, int y) {
    return bitmap[(x, y)] ?? [];
  }

  void reserve(int x, int y, Signal signal) {
    final key = (x, y);
    if (!bitmap.containsKey(key)) {
      bitmap[key] = [];
    }
    _signals.add(signal);
    bitmap[key]!.add(signal);

    int maxIntensity = 0;
    int noise = 0;
    Signal ?maxSignal;
    for (final existingSignal in bitmap[key]!) {
      int intensity = existingSignal.endTick - tick;

      if (intensity > maxIntensity) {
        maxIntensity = intensity;
        maxSignal = existingSignal;
      }
      noise += intensity;
    }

    bitmapResidualIntensity[key] = (maxIntensity / noise, maxSignal!.ownerId);
  }

  void expandSignal(int travelDistance, Signal signal) {

    print('  Expanding signal from owner ${signal.ownerId} to distance $travelDistance');

    for (int partialDistance = 0; partialDistance < travelDistance; partialDistance++) {

      reserve(signal.x - travelDistance, signal.y - partialDistance, signal);
      reserve(signal.x - travelDistance, signal.y + partialDistance, signal);
      reserve(signal.x + travelDistance, signal.y - partialDistance, signal);
      reserve(signal.x + travelDistance, signal.y + partialDistance, signal);
      reserve(signal.x - partialDistance, signal.y - travelDistance, signal);
      reserve(signal.x + partialDistance, signal.y - travelDistance, signal);
      reserve(signal.x - partialDistance, signal.y + travelDistance, signal);
      reserve(signal.x + partialDistance, signal.y + travelDistance, signal);

    }
    reserve(signal.x - travelDistance, signal.y - travelDistance, signal);
    reserve(signal.x - travelDistance, signal.y + travelDistance, signal);
    reserve(signal.x + travelDistance, signal.y - travelDistance, signal);
    reserve(signal.x + travelDistance, signal.y + travelDistance, signal);

    print('  Removing signal from owner ${signal.ownerId} at distance ${travelDistance - 1}');

    int removeDistance = travelDistance - 1;
    for (int partialDistance = 0; partialDistance < removeDistance; partialDistance++) {
      bitmap[(signal.x - removeDistance, signal.y - partialDistance)]?.remove(signal);
      bitmap[(signal.x - removeDistance, signal.y + partialDistance)]?.remove(signal);
      bitmap[(signal.x + removeDistance, signal.y - partialDistance)]?.remove(signal);
      bitmap[(signal.x + removeDistance, signal.y + partialDistance)]?.remove(signal);
      bitmap[(signal.x - partialDistance, signal.y - removeDistance)]?.remove(signal);
      bitmap[(signal.x + partialDistance, signal.y + removeDistance)]?.remove(signal);
      bitmap[(signal.x - partialDistance, signal.y + removeDistance)]?.remove(signal);
      bitmap[(signal.x + partialDistance, signal.y - removeDistance)]?.remove(signal);
    }
    bitmap[(signal.x - removeDistance, signal.y - removeDistance)]?.remove(signal);
    bitmap[(signal.x - removeDistance, signal.y + removeDistance)]?.remove(signal);
    bitmap[(signal.x + removeDistance, signal.y - removeDistance)]?.remove(signal);
    bitmap[(signal.x + removeDistance, signal.y + removeDistance)]?.remove(signal);

    print('  Expansion and removal complete for signal from owner ${signal.ownerId}');
  }

  void enqueueSignal(Signal signal) {
    _enqueuedSignals.add(signal);
  }

  void step() {

    print('NetworkBitmap Step Tick $tick');

    // --- CLEAN UP EXPIRED SIGNALS ---
    _signals.removeWhere((signal) => signal.endTick <= tick);
    bitmap.forEach((key, signals) {
      signals.removeWhere((signal) => signal.endTick <= tick);
    });

    print('  Active signals count: ${_signals.length}');

    // --- RESERVE ENQUEUED SIGNALS ---
    for (final signal in _enqueuedSignals) {
      if (canReserve(signal.x, signal.y).isEmpty) {
        reserve(signal.x, signal.y, signal);
      }
    }

    print('  Signals after enqueue count: ${_signals.length}');

    // --- PROPAGATE SIGNALS ---
    List<Signal> signalsCopy = List.from(_signals);
    for (Signal signal in signalsCopy) {
      int travelDistance = signal.duration - (signal.endTick - tick);
      if (travelDistance <= 0) {
        continue;
      }
      expandSignal(travelDistance, signal);
    }

    print('  Signals after propagation count: ${_signals.length}');

    tick++;
  }

  Signal? receiveSignalsAt(int x, int y, int sensingRange, int readerId) {
    if (bitmapResidualIntensity.containsKey((x, y))) {
      final (intensity, ownerId) = bitmapResidualIntensity[(x, y)]!;
      if (intensity > 0.5) {
        return bitmap[(x, y)]!.firstWhere((signal) => signal.destinationId == readerId);
      }
    }
    return null;
  }

}