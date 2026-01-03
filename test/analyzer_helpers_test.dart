import 'package:flutter_test/flutter_test.dart';
import 'package:daemon/utils/config.dart';

void main() {
  test('EPSILON_WINDOW configuration is valid', () {
    expect(EPSILON_WINDOW, greaterThan(0));
  });

  test('Window average comparison works correctly', () {
    final rewards = <double>[];
    // First window: high values
    for (int i = 0; i < EPSILON_WINDOW; i++) rewards.add(10.0);
    // Second window: low values
    for (int i = 0; i < EPSILON_WINDOW; i++) rewards.add(5.0);

    final total = rewards.length;
    final recentWindow = rewards.sublist(total - EPSILON_WINDOW, total);
    final prevWindow = rewards.sublist(total - EPSILON_WINDOW * 2, total - EPSILON_WINDOW);
    final recentAvg = recentWindow.reduce((a, b) => a + b) / EPSILON_WINDOW;
    final prevAvg = prevWindow.reduce((a, b) => a + b) / EPSILON_WINDOW;

    expect(recentAvg, 5.0);
    expect(prevAvg, 10.0);
    expect(recentAvg < prevAvg, true); // would trigger epsilon increase
  });
}
