import 'package:daemon/domain/entities/car.dart';
import 'package:daemon/utils/config.dart';

enum SignalType {
  rts,
  cts,
  query,
  response,
  ack,
}

enum SignalData {
  stop,
  free,
}

class Signal {
  final int ownerId;
  final int destinationId;
  final int x;
  final int y;
  final Car? car;
  final SignalType type;
  late int duration;
  
  SignalData ?data;
  int startTick = 0;

  Signal({required this.ownerId, required this.destinationId, required this.x, required this.y, required this.type, this.data, this.car}){
    switch (type){
      case SignalType.rts:
        duration = RTSDURATION;
        break;
      case SignalType.cts:
        duration = CTSDURATION;
        break;
      case SignalType.query:
        duration = QUERYDURATION;
        break;
      case SignalType.response:
        duration = RESPONSEDURATION;
        break;
      case SignalType.ack:
        duration = ACKDURATION;
        break;
    }
  }

  void setData(SignalData data) {
    this.data = data;
  }

  void setStartTick(int tick) {
    startTick = tick;
  }

}