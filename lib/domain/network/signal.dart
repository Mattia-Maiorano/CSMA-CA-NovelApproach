import 'package:daemon/domain/entities/classic_car.dart';
import 'package:daemon/utils/config.dart';

enum SignalType {
  broken,
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
  final bool communicationOngoing;
  final int txRange; // Transmission range in tiles
  late int duration;
  
  SignalData ?data;

  Signal({required this.ownerId, required this.destinationId, required this.x, required this.y, required this.type, this.communicationOngoing = false, this.data, this.car, this.txRange = 0}){
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
      case SignalType.broken:
        duration = DIFS;
    }
  }

  void setData(SignalData data) {
    this.data = data;
  }

  int navTime() {
    switch (type){
      case SignalType.rts:
        return NAVTIMECTS;
      case SignalType.cts:
        return NAVTIMEQUERY;
      case SignalType.query:
        return NAVTIMERESPONSE;
      case SignalType.response:
        return NAVTIMEACK;
      case SignalType.ack:
        return 0;
      case SignalType.broken:
        return DIFS;
    }
  }

}