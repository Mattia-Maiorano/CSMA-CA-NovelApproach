import 'package:daemon/domain/entities/car.dart';

enum SignalType {
  ack,
  rts,
  cts,
  data,
}

enum SignalData {
  stop,
  free,
  query,
  position,
  ack,
}

class Signal {
  final int ownerId;
  final int destinationId;
  final int x;
  final int y;
  final Car? car;
  int duration;
  
  SignalData ?data;
  SignalType type;
  int startTick = 0;

  Signal({required this.ownerId, required this.destinationId, required this.duration, required this.x, required this.y, required this.type, this.data, this.car});

  void setData(SignalData data) {
    this.data = data;
  }

  void setStartTick(int tick) {
    startTick = tick;
  }

}