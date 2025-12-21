import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:daemon/utils/analyzer.dart';
import 'package:archive/archive.dart';

void main() {
  test('Analyzer JSON exports par:reward_slope per step', () async {
    final analyzer = Analyzer();
    analyzer.enableMDPTracking();

    // populate 200 episodes: first 100 constant 10.0 then 100 constant 3.0
    final rewards = <double>[];
    for (int i = 0; i < 100; i++) rewards.add(10.0);
    for (int i = 0; i < 100; i++) rewards.add(3.0);

    for (final r in rewards) {
      analyzer.recordMDPProgress(0, 'Car', r, {}, {'epsilon': 0.05});
    }

    final path = await analyzer.closeAndWrite(true);
    expect(path, isNotNull);
    final fileBytes = File(path!).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(fileBytes);
    ArchiveFile? jsonFile;
    for (final f in archive) {
      if (f.name.endsWith('.json')) {
        jsonFile = f;
        break;
      }
    }
    expect(jsonFile, isNotNull);
    final content = utf8.decode(jsonFile!.content as List<int>);
    final data = json.decode(content) as Map<String, dynamic>;
    final steps = data['mdp']['steps'] as List<dynamic>;
    // check at least one step has NODE0_par.reward_slope set
    bool found = false;
    for (final step in steps) {
      final row = step as Map<String, dynamic>;
      final par = row['NODE0_par'] as Map<String, dynamic>?;
      if (par != null && par['reward_slope'] != null) {
        found = true;
        break;
      }
    }
    expect(found, true);
    // verify epsilon decays over time if no further negative trends
    final before = analyzer.getRegisteredMdpAgent(0)?.getEpsilon() ?? 0.0;
    // feed some episodes with neutral rewards to allow decay
    for (int i = 0; i < 50; i++) analyzer.recordMDPProgress(0, 'Car', 10.0, {}, {'epsilon': 0.05});
    final after = analyzer.getRegisteredMdpAgent(0)?.getEpsilon() ?? 0.0;
    expect(after <= before, true);
  });
}
