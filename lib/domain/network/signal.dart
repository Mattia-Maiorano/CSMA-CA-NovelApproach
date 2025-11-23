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
}

class Signal {
  final int ownerId;
  final int destinationId;
  final int duration;
  final int x;
  final int y;
  
  SignalData ?data;
  SignalType type;
  int startTick = 0;
  int get endTick => startTick + duration;

  Signal({required this.ownerId, required this.destinationId, required this.duration, required this.x, required this.y, required this.type, this.data});

  void setData(SignalData data) {
    this.data = data;
  }

  void setStartTick(int tick) {
    startTick = tick;
  }

}