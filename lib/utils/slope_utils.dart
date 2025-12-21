// Pure slope/tuning utilities used by Analyzer, Resumer and config.
// This file intentionally avoids importing `config.dart` to prevent
// circular dependencies (Analyzer imports config, so config must not import Analyzer).

/// Compute linear regression slope (y per x unit) for a vector y with x = 0..n-1.
double computeSlope(List<double> ys) {
  final n = ys.length;
  if (n < 2) return 0.0;
  double sumX = 0.0;
  double sumY = 0.0;
  double sumXY = 0.0;
  double sumXX = 0.0;
  for (int i = 0; i < n; i++) {
    final x = i.toDouble();
    final y = ys[i];
    sumX += x;
    sumY += y;
    sumXY += x * y;
    sumXX += x * x;
  }
  final denom = (n * sumXX - sumX * sumX);
  if (denom == 0) return 0.0;
  final slope = (n * sumXY - sumX * sumY) / denom;
  return slope;
}

/// Compute slope across a window of `window` recent rewards (if available).
double computeSlopeForWindow(List<double> rewards, {required int window}) {
  if (window < 2) return 0.0;
  if (rewards.length < window) return 0.0;
  final int total = rewards.length;
  final windowList = rewards.sublist(total - window, total);
  return computeSlope(windowList);
}

/// Recommend a threshold that would detect a linear drop from `start` to `end`
/// rewards across `window` episodes. `sensitivity` scales the threshold, and
/// `margin` can be used to make the recommendation slightly less negative.
double recommendThresholdForDrop(double start, double end, {required int window, required double sensitivity, double margin = 0.9}) {
  if (window < 2 || sensitivity <= 0.0) return 0.0;
  final double slope = (end - start) / (window - 1);
  return (slope / sensitivity) * margin;
}
