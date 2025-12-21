import 'dart:convert';
import 'dart:io' as io;
import 'package:archive/archive.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:file_picker/file_picker.dart';
import 'package:daemon/utils/analyzer.dart';
// Resumer only reads JSON/ZIP files and does not produce them directly.

/// Resumer widget: load analyzer JSON and plot per-node rewards, parameters and state trends.
class ResumerPage extends StatefulWidget {
  final Analyzer? analyzer;
  const ResumerPage({Key? key, this.analyzer}) : super(key: key);

  @override
  State<ResumerPage> createState() => _ResumerPageState();
}

class _ResumerPageState extends State<ResumerPage> {
  Map<String, dynamic>? _json;
  List<int> _nodeIds = [];
  int? _selectedNode;
  List<String> _availableFields = [];
  final Set<String> _selectedFields = {};
  // Plot overlays absolute removed — overlays are mapped to reward range by default
  int _rewardAverageWindow = 5;
  // Debugging UI
  final List<String> _debugLines = [];
  bool _showDebugPanel = false;
  // overlays: select via chips

  Future<void> _loadJsonFile() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (kIsWeb) {
        // Use FilePicker for web too.
        final result = await FilePicker.platform.pickFiles(type: FileType.any);
        if (result == null) return;
        final bytes = result.files.single.bytes;
        if (bytes == null) return;
        // Detect ZIP archive (PK signature) and extract analyzer JSON if present
        String content;
        if (bytes.length >= 4 &&
            bytes[0] == 0x50 &&
            bytes[1] == 0x4B &&
            bytes[2] == 0x03 &&
            bytes[3] == 0x04) {
          final archive = ZipDecoder().decodeBytes(bytes);
          // find first JSON file or file ending with .json
          ArchiveFile? jsonFile;
          for (final f in archive) {
            if (f.name.endsWith('.json')) {
              jsonFile = f;
              break;
            }
          }
          if (jsonFile == null) throw 'No JSON file found in ZIP';
          final contentBytes = jsonFile.content as List<int>;
          content = utf8.decode(contentBytes);
        } else {
          content = utf8.decode(bytes);
        }
        if (!mounted) return;
        setState(() {
          _json = json.decode(content) as Map<String, dynamic>;
          _postLoad();
        });
      } else {
        final result = await FilePicker.platform.pickFiles(type: FileType.any);
        if (result == null) return;
        final path = result.files.single.path;
        if (path == null) return;
        final readBytes = await io.File(path).readAsBytes();
        String content;
        if (readBytes.length >= 4 &&
            readBytes[0] == 0x50 &&
            readBytes[1] == 0x4B &&
            readBytes[2] == 0x03 &&
            readBytes[3] == 0x04) {
          final archive = ZipDecoder().decodeBytes(readBytes);
          ArchiveFile? jsonFile;
          for (final f in archive) {
            if (f.name.endsWith('.json')) {
              jsonFile = f;
              break;
            }
          }
          if (jsonFile == null) throw 'No JSON file found in ZIP';
          final contentBytes = jsonFile.content as List<int>;
          content = utf8.decode(contentBytes);
        } else {
          content = utf8.decode(readBytes);
        }
        if (!mounted) return;
        setState(() {
          _json = json.decode(content) as Map<String, dynamic>;
          _postLoad();
        });
      }
    } catch (e) {
      print('Failed to load JSON file: $e');
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to load JSON: $e')),
      );
    }
  }

  void _postLoad() {
    _nodeIds.clear();
    final root = _mdpRoot();
    final steps = root?['steps'] as List<dynamic>?;
    _appendDebug('_postLoad - steps count: ${steps?.length ?? 0}');
    final first = (steps != null && steps.isNotEmpty)
        ? Map<String, dynamic>.from(steps.first as Map)
        : {};
    _appendDebug('First step keys: ${first.keys.toList()}');
    // discover node ids using keys pattern NODE<id>_rew
    for (final key in first.keys) {
      final m = RegExp(r'^NODE(\d+)_rew$').firstMatch(key);
      if (m != null) {
        final id = int.parse(m.group(1)!);
        _nodeIds.add(id);
        _appendDebug('Found node ID: $id from key: $key');
      }
    }
    // If we didn't find node ids via steps, try feature_matrices keys
    if (_nodeIds.isEmpty) {
      final fmRaw = root?['feature_matrices'];
      final fm = fmRaw == null ? null : Map<String, dynamic>.from(fmRaw as Map);
      if (fm != null) {
        for (final k in fm.keys) {
          final m = RegExp(r'^NODE(\d+)$').firstMatch(k);
          if (m != null) _nodeIds.add(int.parse(m.group(1)!));
        }
      }
    }
    _nodeIds.sort();
    _selectedNode = _nodeIds.isNotEmpty ? _nodeIds.first : null;
    _appendDebug('Total nodes found: ${_nodeIds.length}, IDs: $_nodeIds');
    _appendDebug('Selected node: $_selectedNode');
    // refresh param keys for the selected node
    _availableFields = _discoverFields();
    _appendDebug('Available fields: $_availableFields');
    // no feature matrix selected initially
  }

  Map<String, dynamic>? _mdpRoot() {
    if (_json == null) return null;
    final maybeMdp = _json?['mdp'];
    if (maybeMdp is Map) return Map<String, dynamic>.from(maybeMdp);
    return _json;
  }

  // param discovery retained via steps parsing

  // Toggle selection state for a field key
  void _toggleFieldSelection(String key) {
    setState(() {
      if (_selectedFields.contains(key))
        _selectedFields.remove(key);
      else
        _selectedFields.add(key);
    });
  }

  List<String> _discoverFields() {
    final root = _mdpRoot();
    final steps = root?['steps'] as List<dynamic>?;
    if (steps == null || _selectedNode == null) return [];
    final keys = <String>{};
    for (var rowRaw in steps) {
      final row = Map<String, dynamic>.from(rowRaw as Map<String, dynamic>);
      final par = row['NODE${_selectedNode}_par'] == null
          ? null
          : Map<String, dynamic>.from(row['NODE${_selectedNode}_par'] as Map);
      final st = row['NODE${_selectedNode}_state'] == null
          ? null
          : Map<String, dynamic>.from(row['NODE${_selectedNode}_state'] as Map);
      if (par != null) keys.addAll(par.keys.map((k) => 'par:$k'));
      if (st != null) keys.addAll(st.keys.map((k) => 'st:$k'));
      if (row.containsKey('env_throughput')) keys.add('env:throughput');
      if (row.containsKey('env_acks')) keys.add('env:acks');
      if (row.containsKey('env_rts')) keys.add('env:rts');
      // detect environment-level throughput field if present
      if (row.containsKey('env_throughput')) keys.add('env:throughput');
    }
    // Filter fields we display to: parameters (par:), states (st:) and environment (env:)
    final filtered =
      keys
        .where((k) => k.startsWith('par:') || k.startsWith('st:') || k.startsWith('env:'))
        .toList()
          ..sort();
    return filtered;
  }

  double? _getLastParamValue(int nodeId, String key) {
    final root = _mdpRoot();
    final steps = root?['steps'] as List<dynamic>?;
    if (steps == null) return null;
    for (int i = steps.length - 1; i >= 0; i--) {
      final row = Map<String, dynamic>.from(steps[i] as Map<String, dynamic>);
      final par = row['NODE${nodeId}_par'] == null
          ? null
          : Map<String, dynamic>.from(row['NODE${nodeId}_par'] as Map);
      if (par != null && par.containsKey(key) && par[key] != null) {
        final v = par[key];
        if (v is num) return v.toDouble();
      }
    }
    return null;
  }

  void _appendDebug(String s) {
    // Keep a short in-memory debug history for the UI and also print to the console
    final msg = 'DEBUG: $s';
    print(msg);
    _debugLines.insert(0, msg);
    if (_debugLines.length > 20)
      _debugLines.removeRange(20, _debugLines.length);
    if (mounted) setState(() {});
  }

  Future<void> _copyDebugToClipboard() async {
    final text = _debugLines.join('\n');
    if (text.isEmpty) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        const SnackBar(content: Text('No debug logs to copy')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Copied ${_debugLines.length} debug lines to clipboard'),
      ),
    );
  }

  // _getFeatureSpots provides unified state/param series

  /// Generic getter for a named feature (st:xxx, par:xxx)
  List<FlSpot> _getFeatureSpots(int nodeId, String key) {
    final steps = _mdpRoot()?['steps'] as List<dynamic>?;
    if (steps == null) return [];
    final spots = <FlSpot>[];
    for (var i = 0; i < steps.length; i++) {
      final row = Map<String, dynamic>.from(steps[i] as Map<String, dynamic>);
      if (key.startsWith('par:')) {
        final pr = row['NODE${nodeId}_par'] == null
            ? null
            : Map<String, dynamic>.from(row['NODE${nodeId}_par'] as Map);
        if (pr != null &&
            pr.containsKey(key.substring(4)) &&
            pr[key.substring(4)] != null) {
          final v = (pr[key.substring(4)] as num).toDouble();
          spots.add(FlSpot(i.toDouble(), v));
        }
      } else if (key.startsWith('st:')) {
        final st = row['NODE${nodeId}_state'] == null
            ? null
            : Map<String, dynamic>.from(row['NODE${nodeId}_state'] as Map);
        if (st != null &&
            st.containsKey(key.substring(3)) &&
            st[key.substring(3)] != null) {
          final v = st[key.substring(3)];
          final num? maybeNum = v as num?;
          if (maybeNum != null)
            spots.add(FlSpot(i.toDouble(), maybeNum.toDouble()));
          else if (v is bool) {
            final boolVal = v as bool;
            spots.add(FlSpot(i.toDouble(), boolVal ? 1.0 : 0.0));
          }
          } else if (key.startsWith('env:')) {
            // e.g. env:throughput -> row['env_throughput'] per step
            if (row.containsKey('env_throughput') && row['env_throughput'] != null) {
              final v = row['env_throughput'];
              final num? maybeNum = v as num?;
              if (maybeNum != null) spots.add(FlSpot(i.toDouble(), maybeNum.toDouble()));
            }
        }
      } else if (key.startsWith('env:')) {
        // Environment-level features like env:throughput, env:acks, env:rts
        final t = row['env_throughput'];
        final a = row['env_acks'];
        final r = row['env_rts'];
        if (key == 'env:throughput') {
          if (t != null) {
            final num? maybeNum = t as num?;
            if (maybeNum != null) spots.add(FlSpot(i.toDouble(), maybeNum.toDouble()));
          }
        } else if (key == 'env:acks') {
          if (a != null) {
            final num? maybeNum = a as num?;
            if (maybeNum != null) spots.add(FlSpot(i.toDouble(), maybeNum.toDouble()));
          }
        } else if (key == 'env:rts') {
          if (r != null) {
            final num? maybeNum = r as num?;
            if (maybeNum != null) spots.add(FlSpot(i.toDouble(), maybeNum.toDouble()));
          }
        }
      }
    }
    return spots;
  }

  // 'different cars processed' is not plotted in simplified UI

  List<FlSpot> _getRewardSpots(int nodeId) {
    final steps = _mdpRoot()?['steps'] as List<dynamic>?;
    if (steps == null) {
      _appendDebug('_getRewardSpots - steps is null for node $nodeId');
      return [];
    }
    final spots = <FlSpot>[];
    int foundCount = 0;
    for (var i = 0; i < steps.length; i++) {
      final row = Map<String, dynamic>.from(steps[i] as Map<String, dynamic>);
      final rew = row['NODE${nodeId}_rew'];
      if (rew != null) {
        final v = (rew as num).toDouble();
        spots.add(FlSpot(i.toDouble(), v));
        foundCount++;
      }
    }
    _appendDebug(
      '_getRewardSpots for NODE$nodeId - found $foundCount reward values out of ${steps.length} steps',
    );
    if (spots.isNotEmpty) {
      final minRew = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
      final maxRew = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
      final avgRew =
          spots.map((s) => s.y).reduce((a, b) => a + b) / spots.length;
      _appendDebug(
        'Reward range for NODE$nodeId - min: $minRew, max: $maxRew, avg: $avgRew',
      );
    }
    if (foundCount == 0 && steps.isNotEmpty) {
      final firstStep = Map<String, dynamic>.from(
        steps[0] as Map<String, dynamic>,
      );
      _appendDebug(
        'Sample keys from first step: ${firstStep.keys.take(10).toList()}',
      );
    }
    return spots;
  }

  List<FlSpot> _getEpsilonChangeSpots(int nodeId) {
    final steps = _mdpRoot()?['steps'] as List<dynamic>?;
    if (steps == null) return [];
    final spots = <FlSpot>[];
    for (var i = 0; i < steps.length; i++) {
      final row = Map<String, dynamic>.from(steps[i] as Map<String, dynamic>);
      final change = row['NODE${nodeId}_epsilon_change'];
      if (change != null) {
        final rew = row['NODE${nodeId}_rew'];
        if (rew != null) {
          final v = (rew as num).toDouble();
          spots.add(FlSpot(i.toDouble(), v));
        } else {
          // fallback
          spots.add(FlSpot(i.toDouble(), 0.0));
        }
      }
    }
    return spots;
  }

  List<FlSpot> _getRewardAverageSpots(int nodeId, int window) {
    final raw = _getRewardSpots(nodeId);
    if (raw.isEmpty) return [];
    if (window <= 1) return raw;
    final avg = <FlSpot>[];
    final half = window ~/ 2;
    for (var i = 0; i < raw.length; i++) {
      final start = math.max(0, i - half);
      final end = math.min(raw.length - 1, i + half);
      double sum = 0.0;
      int count = 0;
      for (var j = start; j <= end; j++) {
        sum += raw[j].y;
        count++;
      }
      avg.add(FlSpot(raw[i].x, sum / count));
    }
    _appendDebug(
      'Computed reward average (window=$window) for NODE$nodeId - first/last: ${avg.first.y}/${avg.last.y}',
    );
    return avg;
  }

  // _getActionSpots removed in favor of grouped-by-parameter action visualization.

  /// Parse the action string recorded by analyzer (e.g. "ParameterAction.increaseTimeoutSmall")
  /// and return the parameter name and signed magnitude.
  /// Returns a tuple-like Map {'param': 'timeout'|'broadcast'|'jitter'|'none', 'mag': double}
  Map<String, dynamic> _parseActionString(String actionStr) {
    final lower = actionStr.toLowerCase();
    var param = 'none';
    if (lower.contains('timeout'))
      param = 'timeout';
    else if (lower.contains('broadcast'))
      param = 'broadcast';
    else if (lower.contains('jitter'))
      param = 'jitter';
    // Determine sign and magnitude
    double mag = 0.0;
    if (lower.contains('increase'))
      mag = 1.0;
    else if (lower.contains('decrease'))
      mag = -1.0;
    // Scale small/large
    if (lower.contains('small'))
      mag *= 0.5;
    else if (lower.contains('large'))
      mag *= 1.0;
    return {'param': param, 'mag': mag};
  }

  // no parameter chart; reward + overlays only

  // no parameter chart; reward + overlays only

  // Map a series into the Y-range of a target series (e.g. reward)
  List<FlSpot> _mapSeriesToTargetRange(
    List<FlSpot> target,
    List<FlSpot> series,
  ) {
    if (target.isEmpty || series.isEmpty) return [];
    double tMin = target.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    double tMax = target.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final sMin = series.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final sMax = series.map((s) => s.y).reduce((a, b) => a > b ? a : b);

    // Compute ranges and handle degenerate cases
    double rangeS = (sMax - sMin).abs();
    double rangeT = (tMax - tMin).abs();

    // If target has effectively zero range, provide a minimal display range
    if (rangeT < 1e-6) {
      final center = (tMax + tMin) / 2.0;
      // Pick a reasonable default axis spread: 1.0 (so 0 -> [-0.5, +0.5] or center +/- 0.5)
      final defaultRange = 1.0;
      tMin = center - defaultRange / 2.0;
      tMax = center + defaultRange / 2.0;
      rangeT = defaultRange;
      // Debugging note
      _appendDebug(
        '_mapSeriesToTargetRange - target range tiny, using default range $defaultRange around $center',
      );
    }

    // If series has zero range, place it at center of the target range
    if (rangeS < 1e-9) {
      final centerT = tMin + rangeT / 2.0;
      return series.map((s) => FlSpot(s.x, centerT)).toList();
    }

    // Normal mapping
    final mapped = series.map((s) {
      final norm = (s.y - sMin) / rangeS;
      final y = tMin + norm * rangeT;
      return FlSpot(s.x, y);
    }).toList();

    // Debugging: report mapped range
    final mappedMin = mapped.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final mappedMax = mapped.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    _appendDebug(
      '_mapSeriesToTargetRange mapping: source sMin=$sMin sMax=$sMax -> target tMin=$tMin tMax=$tMax => mapped range [$mappedMin, $mappedMax]',
    );
    return mapped;
  }

  Widget _buildRewardChart() {
    if (_selectedNode == null) return const Text('No node selected');
    _appendDebug('Building reward chart for node $_selectedNode');
    final spots = _getRewardSpots(_selectedNode!);
    if (spots.isEmpty) {
      final nodeType = _detectNodeTypeFromSteps(_selectedNode!);
      _appendDebug('No spots found for node $_selectedNode (type: $nodeType)');
      return Text(
        'No reward data for selected node (NODE$_selectedNode, Type: $nodeType)',
      );
    }
    _appendDebug(
      'Successfully loaded ${spots.length} reward spots for node $_selectedNode',
    );

    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);

    // If all rewards are the same (e.g., all zeros), add a minimum range for visibility
    final range = (maxY - minY).abs();
    final displayMinY = range < 0.01 ? minY - 1.0 : minY - range * 0.1;
    final displayMaxY = range < 0.01 ? maxY + 1.0 : maxY + range * 0.1;

    // The chart focuses on reward; overlays are selected fields only
    final barSeries = <LineChartBarData>[];
    List<FlSpot> avgSpots = [];
    barSeries.add(
      LineChartBarData(
        spots: spots,
        isCurved: false,
        dotData: FlDotData(show: false),
        color: Colors.green,
      ),
    );
    // Reward moving average: compute and plot centered moving average (RewAvg)
    if (spots.isNotEmpty) {
      avgSpots = _getRewardAverageSpots(_selectedNode!, _rewardAverageWindow);
      if (avgSpots.isNotEmpty) {
        barSeries.add(
          LineChartBarData(
            spots: avgSpots,
            isCurved: false,
            color: Colors.black,
            barWidth: 2,
            dotData: FlDotData(show: false),
          ),
        );
      }
    }
      // Add epsilon change markers as purple dots
      final epsilonChangeSpots = _getEpsilonChangeSpots(_selectedNode!);
      if (epsilonChangeSpots.isNotEmpty) {
        barSeries.add(
          LineChartBarData(
            spots: epsilonChangeSpots,
            isCurved: false,
            color: Colors.purple,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                radius: 4.0,
                color: Colors.purple,
                strokeWidth: 0,
              ),
            ),
            barWidth: 0,
          ),
        );
      }
    // Overlay each selected field (state or param)
    final colorPool = [
      Colors.red,
      Colors.yellow,
      Colors.blueAccent,
      Colors.teal,
      Colors.orange,
      Colors.pink,
    ];
    int colorIndex = 0;
    final overlayCorrs = <Widget>[];
    // No absolute overlay plotting: overlay values are mapped to reward range
    for (final key in _selectedFields) {
      final featureSpots = _getFeatureSpots(_selectedNode!, key);
      if (featureSpots.isNotEmpty) {
        final fsMin = featureSpots
            .map((s) => s.y)
            .reduce((a, b) => a < b ? a : b);
        final fsMax = featureSpots
            .map((s) => s.y)
            .reduce((a, b) => a > b ? a : b);
        final fsAvg =
            featureSpots.map((s) => s.y).reduce((a, b) => a + b) /
            featureSpots.length;
        _appendDebug(
          'Feature $key raw range: min=$fsMin, max=$fsMax, avg=$fsAvg',
        );
        List<FlSpot> mapped;
        mapped = _mapSeriesToTargetRange(spots, featureSpots);
        final color = colorPool[colorIndex % colorPool.length];
        colorIndex++;
        barSeries.add(
          LineChartBarData(
            spots: mapped,
            isCurved: false,
            color: color,
            dotData: FlDotData(show: false),
          ),
        );
        final corr = _computeCorrelationBetweenSpots(spots, featureSpots);
        if (corr != null)
          overlayCorrs.add(
            Text(
              'Corr(rew,${_humanFeatureName(key)}): ${corr.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 12),
            ),
          );
      }
    }

    final List<Widget> corrWidgets = [];
    // Add overlay correlation widgets
    corrWidgets.addAll(overlayCorrs);

    Widget corrRow = const SizedBox.shrink();
    // Reward average legend (show if average computed)
    if (avgSpots.isNotEmpty) {
      corrWidgets.add(
        Padding(
          padding: const EdgeInsets.only(right: 12.0),
          child: Row(
            children: [
              Container(width: 10, height: 10, color: Colors.black),
              const SizedBox(width: 4),
              Text(
                'RewAvg(${_rewardAverageWindow})',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    if (corrWidgets.isNotEmpty) {
      corrRow = Padding(
        padding: const EdgeInsets.only(top: 4.0),
        child: Row(
          children: corrWidgets,
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
        ),
      );
    }

    // If epsilon change events exist, add a small legend entry
    if (epsilonChangeSpots.isNotEmpty) {
      corrRow = Padding(
        padding: const EdgeInsets.only(top: 4.0),
        child: Row(
          children: [
            Container(width: 10, height: 10, color: Colors.purple),
            const SizedBox(width: 6),
            const Text('Epsilon change', style: TextStyle(fontSize: 12)),
            const SizedBox(width: 12),
            corrRow,
          ],
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
        ),
      );
    }

    // final display min/max respects reward range and small padding
    double finalDisplayMinY = displayMinY;
    double finalDisplayMaxY = displayMaxY;

    final chartWidget = SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: spots.last.x,
          minY: finalDisplayMinY,
          maxY: finalDisplayMaxY,
          titlesData: FlTitlesData(show: true),
          lineBarsData: barSeries,
          extraLinesData: ExtraLinesData(horizontalLines: [], verticalLines: [], extraLinesOnTop: true),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        chartWidget,
        corrRow,
        // param stats row
        _buildParamStatsRow(),
        const SizedBox.shrink(),
        // action legend is simplified; no per-action list
      ],
    );
  }

  Widget _buildParamStatsRow() {
    if (_selectedNode == null) return const SizedBox.shrink();
    final nodeType = _detectNodeTypeFromSteps(_selectedNode!);
    List<Widget> cells = [];
    void addParamStats(String label, String? key) {
      if (key == null) return;
      final featureKey = (key.startsWith('st:') || key.startsWith('par:'))
          ? key
          : 'par:$key';
      final spots = _getFeatureSpots(_selectedNode!, featureKey);
      if (spots.isEmpty) return;
      final last = spots.last.y;
      final minv = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
      final maxv = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
      final mean = spots.map((s) => s.y).reduce((a, b) => a + b) / spots.length;
      cells.add(
        Padding(
          padding: const EdgeInsets.all(6.0),
          child: Text(
            '$label: last=${last.toStringAsFixed(2)}, min=${minv.toStringAsFixed(2)}, max=${maxv.toStringAsFixed(2)}, mean=${mean.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      );
    }

    // Display parameters based on node type
    if (nodeType == 'RSU') {
      addParamStats('timeout', 'timeout');
      addParamStats('jitter', 'jitter');
    } else {
      addParamStats('broadcastInterval', 'broadcastInterval');
      addParamStats('jitter', 'jitter');
    }
    // also display selected overlays
    for (final key in _selectedFields) {
      if (key.startsWith('par:'))
        addParamStats(key.substring(4), key.substring(4));
      else if (key.startsWith('st:'))
        addParamStats(key.substring(3), key);
    }
    if (cells.isEmpty) return const SizedBox.shrink();
    // Append last action summary if available
    final List<Widget> summary = [Wrap(children: cells)];
    if (_selectedNode != null) {
      final lastAction = _getLastAction(_selectedNode!);
      final lastParam = _getLastActionParam(_selectedNode!);
      summary.add(
        Padding(
          padding: const EdgeInsets.only(left: 12.0),
          child: Text(
            'Last action: ${lastAction ?? '-'}',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      );
      summary.add(
        Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: Text(
            'Param: ${lastParam[0].toUpperCase() + lastParam.substring(1)}',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6.0),
      child: Wrap(children: summary),
    );
  }

  String? _getLastAction(int nodeId) {
    final steps = _mdpRoot()?['steps'] as List<dynamic>?;
    if (steps == null || steps.isEmpty) return null;
    for (int i = steps.length - 1; i >= 0; i--) {
      final row = Map<String, dynamic>.from(steps[i] as Map<String, dynamic>);
      final act = row['NODE${nodeId}_act'] as String?;
      if (act != null && act.isNotEmpty) return act;
    }
    return null;
  }

  String _getLastActionParam(int nodeId) {
    final act = _getLastAction(nodeId);
    if (act == null) return '-';
    final parsed = _parseActionString(act);
    return parsed['param'] as String? ?? '-';
  }

  // simplified UI: no in-range or feature matrix views

  // Try to detect node type (Car/RSU) by inspecting param/state keys in steps
  String _detectNodeTypeFromSteps(int nodeId) {
    final steps = _mdpRoot()?['steps'] as List<dynamic>?;
    if (steps == null || steps.isEmpty) return 'Car';
    for (final s in steps) {
      final row = Map<String, dynamic>.from(s as Map<String, dynamic>);
      final par = row['NODE${nodeId}_par'] == null
          ? null
          : Map<String, dynamic>.from(row['NODE${nodeId}_par'] as Map);
      final st = row['NODE${nodeId}_state'] == null
          ? null
          : Map<String, dynamic>.from(row['NODE${nodeId}_state'] as Map);
      if (par != null) {
        if (par.containsKey('broadcastInterval')) return 'Car';
      }
      if (st != null) {
        if (st.containsKey('processedRate')) return 'RSU';
      }
    }
    return 'Car';
  }

  // no advanced matrix filtering

  double? _pearson(List<double> xs, List<double> ys) {
    if (xs.length != ys.length || xs.isEmpty) return null;
    final n = xs.length;
    final meanX = xs.reduce((a, b) => a + b) / n;
    final meanY = ys.reduce((a, b) => a + b) / n;
    double num = 0.0, denX = 0.0, denY = 0.0;
    for (int i = 0; i < n; i++) {
      final dx = xs[i] - meanX;
      final dy = ys[i] - meanY;
      num += dx * dy;
      denX += dx * dx;
      denY += dy * dy;
    }
    final denom = math.sqrt(denX * denY);
    if (denom == 0.0) return null;
    return num / denom;
  }

  double? _computeCorrelationBetweenSpots(List<FlSpot> a, List<FlSpot> b) {
    if (a.isEmpty || b.isEmpty) return null;
    final Map<double, double> amap = {for (final s in a) s.x: s.y};
    final Map<double, double> bmap = {for (final s in b) s.x: s.y};
    final xs = <double>[];
    final ys = <double>[];
    for (final k in amap.keys) {
      if (bmap.containsKey(k)) {
        xs.add(amap[k]!);
        ys.add(bmap[k]!);
      }
    }
    if (xs.length < 2) return null;
    return _pearson(xs, ys);
  }

  /// If feature_matrices isn't present in JSON, the simplified UI will not compute a full feature matrix.

  String _humanFeatureName(String f) {
    if (f == 'rew' || f == 'reward' || f == 'Reward') return 'Reward';
    if (f == 'env:throughput') return 'Env Throughput';
    if (f == 'env:acks') return 'Env ACKs';
    if (f == 'env:rts') return 'Env RTS';
    if (f.startsWith('par:')) return f.substring(4);
    if (f.startsWith('st:')) return f.substring(3);
    return f;
  }

  // matrix helpers are not present in this simplified view

  // State chart and reward-state overlay are intentionally omitted to keep the UI focused on reward and in-range trends.

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Resumer - MDP Summary'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Download last analyzer ZIP',
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              if (widget.analyzer == null) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('No analyzer instance provided'),
                  ),
                );
                return;
              }
              if (widget.analyzer!.lastZipBytes == null ||
                  widget.analyzer!.lastZipFilename == null) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('No analyzer ZIP available yet.'),
                  ),
                );
                return;
              }
              try {
                final saved = await widget.analyzer!.downloadLastZip();
                if (saved != null)
                  messenger.showSnackBar(
                    SnackBar(content: Text('Analyzer export saved: $saved')),
                  );
                else
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Analyzer export started')),
                  );
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Failed to download analyzer ZIP: $e'),
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ElevatedButton(
                  onPressed: _loadJsonFile,
                  child: const Text('Load Analyzer JSON'),
                ),
                const SizedBox(width: 8),
                // Legacy export removed: analyzer writes ZIP file directly (JSON + TXT logs)
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Toggle debug panel',
                  icon: Icon(
                    _showDebugPanel ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () {
                    setState(() {
                      _showDebugPanel = !_showDebugPanel;
                    });
                  },
                ),
                IconButton(
                  tooltip: 'Copy debug logs to clipboard',
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    _copyDebugToClipboard();
                  },
                ),
                if (_json != null)
                  Text('Loaded: ${_mdpRoot()?['config']?['use_mdp'] ?? ''}'),
              ],
            ),
            const SizedBox(height: 12),
            if (_showDebugPanel)
              Container(
                height: 120,
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: SingleChildScrollView(
                  reverse: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _debugLines
                        .map(
                          (d) => Text(d, style: const TextStyle(fontSize: 12)),
                        )
                        .toList(),
                  ),
                ),
              ),
            if (_json != null) ...[
              Row(
                children: [
                  const Text('Nodes:'),
                  const SizedBox(width: 8),
                  DropdownButton<int?>(
                    value: _selectedNode,
                    items: [null, ..._nodeIds]
                        .map(
                          (e) => DropdownMenuItem<int?>(
                            value: e,
                            child: Text(e == null ? 'none' : 'NODE$e'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() {
                      _selectedNode = v;
                      // update cached fields for new selection
                      _availableFields = _discoverFields();
                      // reset and choose sensible defaults based on node type
                      _selectedFields.clear();
                      if (_selectedNode != null) {
                        final nodeType = _detectNodeTypeFromSteps(
                          _selectedNode!,
                        );
                        if (nodeType == 'RSU') {
                          if (_availableFields.contains('st:processedRate'))
                            _selectedFields.add('st:processedRate');
                          if (_availableFields.contains('st:processedCount'))
                            _selectedFields.add('st:processedCount');
                          if (_availableFields.contains('st:timeoutBucket'))
                            _selectedFields.add('st:timeoutBucket');
                        } else {
                          if (_availableFields.contains(
                            'par:broadcastInterval',
                          ))
                            _selectedFields.add('par:broadcastInterval');
                        }
                        _appendDebug(
                          'Auto-selected overlays for NODE${_selectedNode}: $_selectedFields',
                        );
                      }
                    }),
                  ),
                  const SizedBox(width: 24),
                  // Display key param quick view based on node type
                  if (_selectedNode != null) ...[
                    () {
                      final nodeType = _detectNodeTypeFromSteps(_selectedNode!);
                      if (nodeType == 'RSU') {
                        return Row(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: Text(
                                'timeout: ${_getLastParamValue(_selectedNode!, 'timeout')?.toStringAsFixed(2) ?? '-'}',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: Text(
                                'jitter: ${_getLastParamValue(_selectedNode!, 'jitter')?.toStringAsFixed(2) ?? '-'}',
                              ),
                            ),
                          ],
                        );
                      } else {
                        // Car parameters
                        return Row(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: Text(
                                'broadcast: ${_getLastParamValue(_selectedNode!, 'broadcastInterval')?.toStringAsFixed(2) ?? '-'}',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: Text(
                                'jitter: ${_getLastParamValue(_selectedNode!, 'jitter')?.toStringAsFixed(2) ?? '-'}',
                              ),
                            ),
                          ],
                        );
                      }
                    }(),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              // Controls for plotting behavior: reward average window (analysis only)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // plotting options simplified: overlays mapped to reward range by default
                  // Avg window is configurable in code for analyses (no visual overlay)
                  const Text('Avg window'),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 140,
                    child: Slider(
                      min: 1,
                      max: 1000,
                      divisions: 25,
                      inactiveColor: Colors.grey,
                      activeColor: Colors.black,
                      label: _rewardAverageWindow.toString(),
                      value: _rewardAverageWindow.toDouble(),
                      onChanged: (v) =>
                          setState(() => _rewardAverageWindow = v.toInt()),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  if (_availableFields.isNotEmpty) ...[
                    const Text('Overlay fields:'),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 540,
                      child: Wrap(
                        children: _availableFields
                            .map(
                              (f) => Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: FilterChip(
                                  label: Text(_humanFeatureName(f)),
                                  selected: _selectedFields.contains(f),
                                  onSelected: (_) => _toggleFieldSelection(f),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              // simplified view - reward trend and overlays only
              // Node selection already present above
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // The analyzer exports a single ZIP file containing JSON and log; Resumer UI focuses on reward and field overlays.
                      const Text(
                        'Reward Trend (rew: green; overlays: selected fields)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      _buildRewardChart(),
                      const SizedBox(height: 16),
                      // Discovery functions for parameters and state keys are elsewhere; Resumer focuses on reward and overlays.
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
