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

  int navTime() {
    int partial = 0;
    switch (type){
      case SignalType.rts:
        partial = NAVTIMECTS;
        break;
      case SignalType.cts:
        partial = NAVTIMEQUERY;
        break;
      case SignalType.query:
        partial = NAVTIMERESPONSE;
        break;
      case SignalType.response:
        partial = NAVTIMEACK;
        break;
      case SignalType.ack:
        partial = 0;
        break;
    }
    return partial + duration;
  }

}