/// ============================================================================
/// Analyzer - Simulation Metrics and MDP Progress Tracker
/// ============================================================================
/// Collects and exports simulation performance metrics:
/// - Protocol statistics: idle time, collisions, resets, throughput
/// - MDP learning progress: rewards, states, parameters per agent
/// - Epsilon adaptation: automatic exploration rate adjustment
///
/// Exports results as ZIP containing JSON data and text log.
/// ============================================================================

import 'package:daemon/utils/config.dart';
import 'package:daemon/domain/entities/entity.dart';
import 'package:daemon/utils/measurement.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'analyzer_writer_io.dart'
    if (dart.library.html) 'analyzer_writer_web.dart';

/// Data structure to track MDP learning progress per node
class MDPNodeProgress {
  final int nodeId;
  final String nodeType; // 'Car' or 'RSU'
  final List<double> rewards = [];
  final List<Map<String, dynamic>> states = [];
  final List<Map<String, double>> parameters = [];
  final List<String> actions = [];

  MDPNodeProgress(this.nodeId, this.nodeType);

  void recordProgress(
    double reward,
    Map<String, dynamic> state,
    Map<String, double> params,
  ) {
    rewards.add(reward);
    states.add(Map.from(state));
    parameters.add(Map.from(params));
  }

  void recordAction(String action) {
    actions.add(action);
  }
}

class Analyzer {
  int totalSlots = 0;
  int totalSlotsPerNode = 0;
  int idleSlots = 0;

  int softResets = 0;
  int hardResets = 0;

  int avgBusyMedium = 0;
  int avgFreeCars = 0;
  int totalDifferentProcessed = 0;
  int totalDifferentProcessedFrames = 0;
  final List<int> _differentCarsProcessed = [];
  int totalRts = 0;
  int totalAcks = 0;
  final List<int> _rtsPerFrame = [];
  final List<int> _acksPerFrame = [];
  int _currentFrameRts = 0;
  int _currentFrameAcks = 0;

  // MDP progress tracking
  final Map<int, MDPNodeProgress> _mdpProgress = {};
  bool _mdpEnabled = false;
  // optional map of registered live agent instances so Analyzer can trigger epsilon changes
  final Map<int, dynamic> _mdpAgents = {};
  // optional map of registered live entity instances so Analyzer can toggle visual markers
  final Map<int, Entity> _mdpEntities = {};
  // track last episode index when epsilon was changed per-node to enforce cooldown
  final Map<int, int> _lastEpsilonChangeEpisode = {};
  // track epsilon change events per node: nodeId -> episodeIndex -> { 'old': x, 'new': y }
  final Map<int, Map<int, Map<String, double>>> _epsilonChangeEvents = {};
  // Keep last generated zip bytes & filename so the UI can re-download it on demand
  Uint8List? lastZipBytes;
  String? lastZipFilename;

  // Reusable mapping for what state features an agent family uses
  // NOTE: agentUsedFields removed; Resumer will dynamically discover fields from exporter JSON.

  void enableMDPTracking() {
    _mdpEnabled = true;
    // Reset per-run collections when enabling tracking to avoid mixing across runs
    _differentCarsProcessed.clear();
    _rtsPerFrame.clear();
    _acksPerFrame.clear();
    _currentFrameRts = 0;
    _currentFrameAcks = 0;
    totalRts = 0;
    totalAcks = 0;
  }

  /// Register a live Agent instance by its nodeId so Analyzer can request epsilon changes.
  void registerMdpAgent(int nodeId, dynamic agent) {
    _mdpAgents[nodeId] = agent;
  }

  /// Register a live Entity instance by its nodeId so Analyzer can toggle visual markers
  void registerMdpEntity(int nodeId, Entity ent) {
    _mdpEntities[nodeId] = ent;
  }

  /// Return the registered agent for the given nodeId (useful for testing/monitoring)
  dynamic getRegisteredMdpAgent(int nodeId) {
    return _mdpAgents[nodeId];
  }

  void recordMDPProgress(
    int nodeId,
    String nodeType,
    double reward,
    Map<String, dynamic> state,
    Map<String, double> params,
  ) {
    if (!_mdpEnabled) return;

    if (!_mdpProgress.containsKey(nodeId)) {
      _mdpProgress[nodeId] = MDPNodeProgress(nodeId, nodeType);
    }

    _mdpProgress[nodeId]!.recordProgress(reward, state, params);
    // Apply passive epsilon decay if enabled (separate flag)
    final agent = _mdpAgents[nodeId];
    if (ENABLE_EPSILON_DECAY && agent != null) {
      try {
        final oldEps = agent.getEpsilon();
        final double newEps = oldEps > EPSILON_BASELINE ? (oldEps * EPSILON_DECAY_FACTOR).clamp(EPSILON_BASELINE, EPSILON_MAX) : oldEps;
        if (newEps != oldEps) agent.setEpsilon(newEps);
      } catch (e) {
        // ignore if agent doesn't support get/set
      }
    }

    // Perform adaptive epsilon increases based on reward gradient only when
    // enabled through ENABLE_EPSILON_ADAPT. This allows experiments where
    // passive decay is disabled but gradient-triggered re-exploration is used,
    // or vice-versa.
    if (ENABLE_EPSILON_ADAPT) {
      try {
        _evaluateRewardGradient(nodeId);
      } catch (e) {
        print('Gradient evaluation failed for node $nodeId: $e');
      }
    }
  }

  void _evaluateRewardGradient(int nodeId) {
    final prog = _mdpProgress[nodeId];
    final int w = EPSILON_WINDOW;
    // Need 2*w frames to compare two consecutive windows
    if (prog == null || prog.rewards.length < w * 2) return;
    final int total = prog.rewards.length;
    // Compute average of last w frames and the w frames before that
    final recentWindow = prog.rewards.sublist(total - w, total);
    final prevWindow = prog.rewards.sublist(total - w * 2, total - w);
    final double recentAvg = recentWindow.reduce((a, b) => a + b) / w;
    final double prevAvg = prevWindow.reduce((a, b) => a + b) / w;
    // Trigger if recent average is lower than previous average
    final bool triggered = recentAvg < prevAvg;
    if (triggered) {
      final agent = _mdpAgents[nodeId];
      if (agent == null) return;
      // Enforce cooldown
      final int lastChange = _lastEpsilonChangeEpisode[nodeId] ?? -9999999;
      if (total - lastChange < EPSILON_COOLDOWN_EPISODES) return;
      print('Analyzer: node $nodeId avg reward $recentAvg < prev $prevAvg. Adjust epsilon.');
      try {
        final oldEps = agent.getEpsilon();
        final newEps = (oldEps + EPSILON_INC).clamp(EPSILON_MIN, EPSILON_MAX);
        agent.setEpsilon(newEps);
        _lastEpsilonChangeEpisode[nodeId] = total;
        _epsilonChangeEvents[nodeId] ??= {};
        _epsilonChangeEvents[nodeId]![total] = {'old': oldEps, 'new': newEps};
        final ent = _mdpEntities[nodeId];
        if (ent != null) {
          ent.epsilonChanged = true;
          ent.lastEpsilonChangeEpisode = total;
        }
        print('Analyzer: node $nodeId epsilon changed from $oldEps to $newEps');
      } catch (e) {
        // ignore if agent doesn't implement get/set
      }
    }
  }

  void recordMDPAction(int nodeId, String action) {
    if (!_mdpEnabled) return;
    if (!_mdpProgress.containsKey(nodeId)) return;
    _mdpProgress[nodeId]!.recordAction(action);
  }

  void update(Measurement measurement) {
    if (measurement.state == NodeState.idle) idleSlots++;

    if (measurement.softReset) softResets++;
    if (measurement.hardReset) hardResets++;
  }

  void setFreeCars(int freeCars) {
    avgFreeCars += freeCars;
  }

  void recordDifferentCarsProcessed(int differentCars) {
    totalDifferentProcessed += differentCars;
    totalDifferentProcessedFrames++;
    _differentCarsProcessed.add(differentCars);
  }

  void incrementRts() {
    totalRts++;
    _currentFrameRts++;
  }

  void incrementAcks() {
    totalAcks++;
    _currentFrameAcks++;
  }

  /// Called at the end of a frame to record per-frame ack/rts observations
  void completeThroughputFrame() {
    _rtsPerFrame.add(_currentFrameRts);
    _acksPerFrame.add(_currentFrameAcks);
    _currentFrameRts = 0;
    _currentFrameAcks = 0;
  }

  void incrementBusyMedium() {
    avgBusyMedium++;
  }

  void incrementTotal() {
    totalSlots++;
  }

  void incrementTotalPerNode() {
    totalSlotsPerNode++;
  }

  void setTotal(int slots) {
    totalSlots = slots;
  }

  // NOTE: Pearson correlation and feature matrix generation removed for simplicity and readability.

  /// Compute per-node feature matrices and correlations from _mdpProgress.
  /// Returns a map with keys 'correlations' and 'matrices'.
  // Feature matrix computation removed - not currently used by Resumer.

  /// Build feature vectors, pairwise correlation matrix and single feature correlations for a single progress entry.
  /// Returns a map: { 'features': fList, 'matrix': matrix, 'corrMap': corrMap }
  // Feature matrix helpers removed

  Future<String?> closeAndWrite(bool useMDP) async {
    // closeAndWrite called
    final buffer = StringBuffer();
    buffer.writeln('--- ANALYZER LOG ---');
    buffer.writeln('Simulation Configuration:');
    buffer.writeln('Cars: $CARNUM');
    buffer.writeln('RSUs: $RSUNUM');
    buffer.writeln('FPS: $FPS');
    buffer.writeln('MDP Enabled: $useMDP');
    buffer.writeln('---------------------\n');
    buffer.writeln(
      'Soft resets every ${softResets > 0 ? (totalSlotsPerNode / softResets).toStringAsFixed(2) : 'N/A'} slots',
    );
    buffer.writeln(
      'Hard resets every ${hardResets > 0 ? (totalSlotsPerNode / hardResets).toStringAsFixed(2) : 'N/A'} slots',
    );
    buffer.writeln(
      '\nAverage Idle: ${totalSlotsPerNode > 0 ? (idleSlots / totalSlotsPerNode * 100).toStringAsFixed(2) : 0}%',
    );
    buffer.writeln(
      'Average free cars: ${totalSlots / SUBFRAMES > 0 ? (avgFreeCars / (totalSlots / SUBFRAMES)).toStringAsFixed(2) : 0}',
    );
    // 'responses' metric removed; processed cars metric is available via MDP progress per-node if needed
    buffer.writeln(
      'Average Busy Medium: ${totalSlotsPerNode > 0 ? (avgBusyMedium / totalSlotsPerNode * 100).toStringAsFixed(2) : 0}%',
    );
    final avgDifferentProcessed = totalDifferentProcessedFrames > 0
        ? (totalDifferentProcessed / totalDifferentProcessedFrames)
        : 0.0;
    buffer.writeln(
      'Average different cars processed (free OR answered): ${avgDifferentProcessed.toStringAsFixed(2)}',
    );
    // Throughput: acks per rts across frames
    final double avgThroughput = totalRts > 0 ? totalAcks / totalRts : 0.0;
    buffer.writeln('Average throughput (acks/rts): ${avgThroughput.toStringAsFixed(3)}');
    if (_acksPerFrame.isNotEmpty && _rtsPerFrame.isNotEmpty) {
      final int frames = math.min(_acksPerFrame.length, _rtsPerFrame.length);
      final int recentCount = (frames * 0.1).ceil().clamp(1, frames);
      final startIndex = frames - recentCount;
      final recentAcks = _acksPerFrame.sublist(startIndex, frames).reduce((a, b) => a + b);
      final recentRts = _rtsPerFrame.sublist(startIndex, frames).reduce((a, b) => a + b);
      final double recentThroughput = recentRts > 0 ? recentAcks / recentRts : 0.0;
      buffer.writeln('Recent Average throughput (last ${recentCount} frames): ${recentThroughput.toStringAsFixed(3)}');
    }
    if (_differentCarsProcessed.isNotEmpty) {
      final int frames = _differentCarsProcessed.length;
      final int recentCount = (frames * 0.1).ceil().clamp(1, frames);
      final startIndex = frames - recentCount;
      final recentList = _differentCarsProcessed.sublist(startIndex, frames);
      final double recentAvg = recentList.reduce((a, b) => a + b) / recentList.length;
      buffer.writeln('Recent Average different cars processed (last ${recentList.length} frames): ${recentAvg.toStringAsFixed(2)}');
    }
    buffer.writeln('---------------------');

    // Compute feature matrices and correlations removed for simplicity.
    buffer.writeln('\n\n=== MDP LEARNING PROGRESS ===\n');
    // Short readable per-node summary
    for (final progress in _mdpProgress.values) {
      buffer.writeln('--- ${progress.nodeType} ${progress.nodeId} ---');
      buffer.writeln('Training Episodes: ${progress.rewards.length}');
      if (progress.rewards.isNotEmpty) {
        double avgReward =
            progress.rewards.reduce((a, b) => a + b) / progress.rewards.length;
        buffer.writeln('Average Reward: ${avgReward.toStringAsFixed(2)}');

          // Compute recent average over the last 10% of episodes to highlight progress
          final int total = progress.rewards.length;
          final int recentCount = (total * 0.1).ceil().clamp(1, total);
          final startIndex = total - recentCount;
          final recentList = progress.rewards.sublist(startIndex, total);
          final double recentAvg = recentList.reduce((a, b) => a + b) / recentList.length;
          buffer.writeln('Recent Average (last ${recentList.length} episodes): ${recentAvg.toStringAsFixed(2)}');
          // include window averages for epsilon adaptation
          if (total >= EPSILON_WINDOW * 2) {
            final recentW = progress.rewards.sublist(total - EPSILON_WINDOW, total);
            final prevW = progress.rewards.sublist(total - EPSILON_WINDOW * 2, total - EPSILON_WINDOW);
            final recentWAvg = recentW.reduce((a, b) => a + b) / EPSILON_WINDOW;
            final prevWAvg = prevW.reduce((a, b) => a + b) / EPSILON_WINDOW;
            buffer.writeln('Window avg (last $EPSILON_WINDOW): ${recentWAvg.toStringAsFixed(3)}, prev: ${prevWAvg.toStringAsFixed(3)}');
          }
        }
        // Print final parameters if available (e.g., epsilon for QAgent)
        if (progress.parameters.isNotEmpty) {
          final lastPar = progress.parameters.last;
          buffer.writeln('Final Parameters:');
          for (final entry in lastPar.entries) {
            final key = entry.key;
            final val = entry.value;
            buffer.writeln('  $key: ${val.toStringAsFixed(3)}');
          }
        }
      }
      buffer.writeln('=============================');

    // For non-web: write the text log
    if (!kIsWeb) {
      await AnalyzerWriter().write(buffer.toString());
    }

    // Create per-step JSON export for rewards and parameters
    try {
      // sort nodes by id for deterministic column order
      final nodeList = _mdpProgress.values.toList()
        ..sort((a, b) => a.nodeId.compareTo(b.nodeId));
      int maxLen = 0;
      for (final p in nodeList) {
        maxLen = math.max(maxLen, p.rewards.length);
        maxLen = math.max(maxLen, p.parameters.length);
      }

      final List<Map<String, dynamic>> rows = [];
      for (int i = 0; i < maxLen; i++) {
        final Map<String, dynamic> row = {'step': i};
        for (final p in nodeList) {
          final nodeKey = 'NODE${p.nodeId}';
          row['${nodeKey}_rew'] = i < p.rewards.length ? p.rewards[i] : null;
          row['${nodeKey}_par'] = i < p.parameters.length
              ? p.parameters[i]
              : null;
          // export epsilon as flat top-level field for convenience
          if (i < p.parameters.length && p.parameters[i].containsKey('epsilon')) {
            row['${nodeKey}_epsilon'] = p.parameters[i]['epsilon'];
          } else {
            row['${nodeKey}_epsilon'] = null;
          }
          // Export epsilon change event if it occurred at this step
          if (_epsilonChangeEvents.containsKey(p.nodeId) && _epsilonChangeEvents[p.nodeId]!.containsKey(i)) {
            row['${nodeKey}_epsilon_change'] = _epsilonChangeEvents[p.nodeId]![i];
          } else {
            row['${nodeKey}_epsilon_change'] = null;
          }
          row['${nodeKey}_state'] = i < p.states.length ? p.states[i] : null;
          row['${nodeKey}_act'] = i < p.actions.length ? p.actions[i] : null;
        }
        // Optionally include environment-level throughput metrics aligned by frame index
        final int framesAcks = _acksPerFrame.length;
        final int framesRts = _rtsPerFrame.length;
        row['env_acks'] = i < framesAcks ? _acksPerFrame[i] : null;
        row['env_rts'] = i < framesRts ? _rtsPerFrame[i] : null;
        if (i < framesAcks && i < framesRts && _rtsPerFrame[i] > 0) {
          row['env_throughput'] = _acksPerFrame[i] / _rtsPerFrame[i];
        } else {
          row['env_throughput'] = null;
        }
        rows.add(row);
      }

      final Map<String, dynamic> jsonOut = {
        'config': {
          'cars': CARNUM,
          'rsus': RSUNUM,
          'fps': FPS,
          'use_mdp': useMDP,
          'subframes': SUBFRAMES,
          'range': RANGE,
        },
        'steps': rows,
        // feature_correlations/feature_matrices removed for readability and performance
      };

      final wrappedOut = {'mdp': jsonOut};
      final jsonString = const JsonEncoder.withIndent('  ').convert(wrappedOut);
      try {
        final logString = buffer.toString();
        final jsonFilename =
            'analyzer_mdp_${DateTime.now().toIso8601String().replaceAll(':', '-')}.json';
        final logFilename =
            'analyzer_log_${DateTime.now().toIso8601String().replaceAll(':', '-')}.txt';
        final zipFilename =
            'analyzer_${DateTime.now().toIso8601String().replaceAll(':', '-')}.zip';
        try {
          final bytes = await AnalyzerWriter().writeZip(
            zipFilename,
            jsonFilename,
            jsonString,
            logFilename,
            logString,
          );
          if (bytes != null) {
            lastZipBytes = bytes;
            lastZipFilename = zipFilename;
            // Built ZIP bytes for $zipFilename: ${bytes.length} bytes
            if (kIsWeb) {
              // For web, don't auto-trigger downloads because they may be blocked.
              // Running on web: defer download to UI gesture
              return lastZipFilename;
            } else {
              final savedPath = await AnalyzerWriter().writeBytes(
                zipFilename,
                bytes,
              );
              // writeBytes returned: $savedPath
              return savedPath;
            }
          }
        } catch (e) {
          buffer.writeln('Error while writing MDP JSON or ZIP: $e');
        }
      } catch (e) {
        buffer.writeln('Error while writing MDP JSON or ZIP: $e');
      }
    } catch (e) {
      // be conservative: don't fail the close if JSON writing fails
      buffer.writeln('Error while writing MDP JSON: $e');
      // In non-web case, try to write the log anyway
      if (!kIsWeb) await AnalyzerWriter().write(buffer.toString());
    }
    return null;
  }

  /// Triggers a download of the last generated zip using the platform writer
  /// Returns the file path or filename where the zip was written, or null on failure
  Future<String?> downloadLastZip() async {
    // downloadLastZip called
    if (lastZipBytes == null || lastZipFilename == null) {
      // No lastZipBytes available for download
      return null;
    }
    final path = await AnalyzerWriter().writeBytes(
      lastZipFilename!,
      lastZipBytes!,
    );
    // downloadLastZip wrote file: $path
    return path;
  }

  /// Compute the slope for a sliding window of `window` episodes from the end
  /// of the provided reward list. If there are fewer than `window` rewards,
  /// the function will return `0.0`.

  /// Recommend a `REWARD_GRAD_THRESHOLD` value that would detect a linear
  /// drop from `start` to `end` rewards over `window` episodes, given a
  /// `sensitivity` and an optional `margin` multiplier (default 0.9) to make
  /// the suggested threshold slightly less negative (easier to trigger).
  ///
  /// Formula:
  ///   slope ≈ (end - start) / (window - 1)
  ///   recommendedThreshold = (slope / sensitivity) * margin

  // NOTE: `buildCombinedJson` helper removed — Analyzer now writes JSON + TXT into a ZIP and stores its bytes for UI re-download.
  // (states_report and related functions removed)
}
