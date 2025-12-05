import 'package:daemon/utils/config.dart';
import 'package:daemon/domain/entities/entity.dart';
import 'package:daemon/utils/measurement.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
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

  // MDP progress tracking
  final Map<int, MDPNodeProgress> _mdpProgress = {};
  bool _mdpEnabled = false;
  // Keep last generated zip bytes & filename so the UI can re-download it on demand
  Uint8List? lastZipBytes;
  String? lastZipFilename;

  // Reusable mapping for what state features an agent family uses
  static const Map<String, List<String>> agentUsedFields = {
    'Car': [
      'st:carsInRange',
      'st:consecutiveCollisions',
      'st:carsInRangeRollingMean',
      'st:broadcastBucket',
      'st:timeoutBucket',
      'st:jitterBucket',
    ],
    'RSU': [
      'st:processedRate',
      'st:processedCount',
      'st:consecutiveCollisions',
      'st:timeoutBucket',
      'st:jitterBucket',
      'st:carsInRange',
    ],
  };

  void enableMDPTracking() {
    _mdpEnabled = true;
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

  double _pearsonCorrelation(List<double> xs, List<double> ys) {
    if (xs.length != ys.length || xs.isEmpty) return double.nan;
    final n = xs.length;
    final meanX = xs.reduce((a, b) => a + b) / n;
    final meanY = ys.reduce((a, b) => a + b) / n;
    double num = 0.0;
    double denX = 0.0;
    double denY = 0.0;
    for (int i = 0; i < n; i++) {
      final dx = xs[i] - meanX;
      final dy = ys[i] - meanY;
      num += dx * dy;
      denX += dx * dx;
      denY += dy * dy;
    }
    final denom = math.sqrt(denX * denY);
    if (denom == 0.0) return double.nan;
    return num / denom;
  }

  /// Compute per-node feature matrices and correlations from _mdpProgress.
  /// Returns a map with keys 'correlations' and 'matrices'.
  Map<String, dynamic> _computeFeatureData() {
    final featureCorrelations = <String, Map<String, double>>{};
    final featureMatrices = <String, dynamic>{};
    if (_mdpProgress.isEmpty)
      return {'correlations': featureCorrelations, 'matrices': featureMatrices};

    for (final progress in _mdpProgress.values) {
      if (progress.rewards.length < 2) {
        // Not enough data to compute correlations
        continue;
      }

      // Build state-side feature matrix and correlations
      final stateResult = _buildFeatureVectorsAndMatrix(progress, 'state');
      if (stateResult.isNotEmpty) {
        final fList = stateResult['features'] as List<String>;
        final matrix = stateResult['matrix'] as List<List<double?>>;
        final corrMap = stateResult['corrMap'] as Map<String, double>;
        featureMatrices['NODE${progress.nodeId}'] ??= {};
        featureMatrices['NODE${progress.nodeId}']['state'] = {
          'features': fList,
          'matrix': matrix,
        };
        featureCorrelations['NODE${progress.nodeId}'] =
            Map<String, double>.from(corrMap);
      }

      // Build params-side matrix and merge correlations
      final paramsResult = _buildFeatureVectorsAndMatrix(progress, 'params');
      if (paramsResult.isNotEmpty) {
        final fList = paramsResult['features'] as List<String>;
        final matrix = paramsResult['matrix'] as List<List<double?>>;
        final corrMap = paramsResult['corrMap'] as Map<String, double>;
        featureMatrices['NODE${progress.nodeId}'] ??= {};
        featureMatrices['NODE${progress.nodeId}']['params'] = {
          'features': fList,
          'matrix': matrix,
        };
        // merge into single map
        final existing = featureCorrelations['NODE${progress.nodeId}'] ?? {};
        existing.addAll(corrMap);
        featureCorrelations['NODE${progress.nodeId}'] = existing;
      }
    }

    return {'correlations': featureCorrelations, 'matrices': featureMatrices};
  }

  /// Build feature vectors, pairwise correlation matrix and single feature correlations for a single progress entry.
  /// Returns a map: { 'features': fList, 'matrix': matrix, 'corrMap': corrMap }
  Map<String, dynamic> _buildFeatureVectorsAndMatrix(
    MDPNodeProgress progress,
    String type,
  ) {
    final Set<String> stateFeatureKeys = {};
    final Set<String> paramKeys = {};
    final List<double> rew = [];
    final List<Map<String, dynamic>> stateRows = [];
    final List<Map<String, dynamic>> paramRows = [];

    for (final stepState in progress.states) {
      stateRows.add(stepState);
      stateFeatureKeys.addAll(stepState.keys.map((k) => 'st:$k'));
    }
    for (final par in progress.parameters) {
      paramRows.add(par);
      paramKeys.addAll(par.keys.map((k) => 'par:$k'));
    }
    for (final r in progress.rewards) rew.add(r);

    // Filter out state features not used by the agent type
    final nodeType = progress.nodeType;
    final allowed = Analyzer.agentUsedFields[nodeType] ?? [];
    stateFeatureKeys.removeWhere((k) => !allowed.contains(k));

    // Build feature vectors
    final featureVectors = <String, List<double?>>{};
    if (type == 'state') {
      if (stateFeatureKeys.isEmpty) return {};
      for (final f in stateFeatureKeys)
        featureVectors[f] = List<double?>.filled(stateRows.length, null);
      featureVectors['rew'] = List<double?>.filled(stateRows.length, null);
      for (int i = 0; i < stateRows.length; i++) {
        featureVectors['rew']![i] = rew.length > i ? rew[i] : null;
        final st = stateRows[i];
        for (final f in stateFeatureKeys) {
          final key = f.substring(3);
          if (st.containsKey(key)) {
            final v = st[key];
            final num? maybeNum = v as num?;
            if (maybeNum != null)
              featureVectors[f]![i] = maybeNum.toDouble();
            else if (v is bool)
              featureVectors[f]![i] = (v as bool) ? 1.0 : 0.0;
          }
        }
      }
    } else {
      if (paramKeys.isEmpty) return {};
      for (final f in paramKeys)
        featureVectors[f] = List<double?>.filled(paramRows.length, null);
      featureVectors['rew'] = List<double?>.filled(paramRows.length, null);
      for (int i = 0; i < paramRows.length; i++) {
        featureVectors['rew']![i] = rew.length > i ? rew[i] : null;
        final pr = paramRows[i];
        for (final f in paramKeys) {
          final key = f.substring(4);
          if (pr.containsKey(key)) {
            final v = pr[key];
            final num? maybeNum = v as num?;
            if (maybeNum != null) featureVectors[f]![i] = maybeNum.toDouble();
          }
        }
      }
    }

    if (featureVectors.isEmpty) return {};
    final fList = featureVectors.keys.toList()
      ..sort((a, b) {
        if (a == 'rew' && b != 'rew') return -1;
        if (b == 'rew' && a != 'rew') return 1;
        return a.compareTo(b);
      });
    final int fN = fList.length;
    final matrix = List.generate(fN, (_) => List<double?>.filled(fN, null));
    for (int i = 0; i < fN; i++) {
      for (int j = 0; j < fN; j++) {
        final a = fList[i];
        final b = fList[j];
        final la = featureVectors[a]!;
        final lb = featureVectors[b]!;
        final int len = la.length < lb.length ? la.length : lb.length;
        final List<double> xs = [];
        final List<double> ys = [];
        for (int k = 0; k < len; k++) {
          final av = la[k];
          final bv = lb[k];
          if (av != null && bv != null) {
            xs.add(av);
            ys.add(bv);
          }
        }
        if (xs.length >= 2) {
          final corr = _pearsonCorrelation(xs, ys);
          if (corr.isFinite) matrix[i][j] = corr;
        }
      }
    }

    final Map<String, double> corrMap = {};
    for (final f in featureVectors.keys) {
      final la = featureVectors[f]!;
      final List<double> xs = [];
      final List<double> ys = [];
      for (int k = 0; k < la.length; k++) {
        final av = la[k];
        final rv = featureVectors['rew']![k];
        if (av != null && rv != null) {
          xs.add(av);
          ys.add(rv);
        }
      }
      if (xs.length >= 2) {
        final c = _pearsonCorrelation(xs, ys);
        if (c.isFinite) corrMap[f] = c;
      }
    }

    return {'features': fList, 'matrix': matrix, 'corrMap': corrMap};
  }

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
    buffer.writeln('---------------------');

    // Compute and collect MDP feature matrices and correlations if needed
    final featureCorrelations = <String, Map<String, double>>{};
    final featureMatrices = <String, dynamic>{};
    final matricesAndCorrelations = useMDP ? _computeFeatureData() : null;
    if (matricesAndCorrelations != null) {
      // Safely cast nested maps from dynamic to correct types to avoid runtime type errors
      final rawCorr = matricesAndCorrelations['correlations'];
      if (rawCorr is Map) {
        final typedCorr = <String, Map<String, double>>{};
        for (final e in rawCorr.entries) {
          final key = e.key.toString();
          final val = e.value as Map?;
          if (val != null)
            typedCorr[key] = Map<String, double>.from(
              val.map((k, v) => MapEntry(k.toString(), (v as num).toDouble())),
            );
        }
        featureCorrelations.addAll(typedCorr);
      }
      final rawMats = matricesAndCorrelations['matrices'];
      if (rawMats is Map) {
        final typedMats = <String, dynamic>{};
        for (final e in rawMats.entries) {
          typedMats[e.key.toString()] = e.value;
        }
        featureMatrices.addAll(typedMats);
      }
      buffer.writeln('\n\n=== MDP LEARNING PROGRESS ===\n');
      // Short readable per-node summary
      for (final progress in _mdpProgress.values) {
        buffer.writeln('--- ${progress.nodeType} ${progress.nodeId} ---');
        buffer.writeln('Training Episodes: ${progress.rewards.length}');
        if (progress.rewards.isNotEmpty) {
          double avgReward =
              progress.rewards.reduce((a, b) => a + b) /
              progress.rewards.length;
          buffer.writeln('Average Reward: ${avgReward.toStringAsFixed(2)}');
        }
      }
      buffer.writeln('=============================');
      // Append brief correlations snapshot
      for (final entry in featureCorrelations.entries) {
        buffer.writeln('\n-- Feature correlations for ${entry.key} --');
        final sorted = entry.value.entries.toList()
          ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
        for (int i = 0; i < math.min(sorted.length, 8); i++) {
          final kv = sorted[i];
          buffer.writeln('  ${kv.key}: ${kv.value.toStringAsFixed(3)}');
        }
      }
      // Append pairwise matrix brief summary if present
      for (final entry in featureMatrices.entries) {
        buffer.writeln('\n-- Feature matrix for ${entry.key} --');
        final mat = Map<String, dynamic>.from(entry.value as Map);
        final flist = mat['features'] as List<dynamic>? ?? [];
        buffer.writeln('Features: ${flist.length}');
      }
    }

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
          row['${nodeKey}_state'] = i < p.states.length ? p.states[i] : null;
          row['${nodeKey}_act'] = i < p.actions.length ? p.actions[i] : null;
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
        'feature_correlations': featureCorrelations,
        'feature_matrices': featureMatrices,
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

  // NOTE: `buildCombinedJson` helper removed — Analyzer now writes JSON + TXT into a ZIP and stores its bytes for UI re-download.
  // (states_report and related functions removed)
}
