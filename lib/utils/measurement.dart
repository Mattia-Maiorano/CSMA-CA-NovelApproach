import 'package:daemon/domain/entities/entity.dart';

class Measurement {

  final NodeState state;
  final TalkingStage stage;
  final bool free;
  final bool answered;
  final bool softReset;
  final bool hardReset;

  Measurement({required this.state, required this.stage, required this.free, required this.answered, required this.softReset, required this.hardReset});

}