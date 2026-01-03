import 'package:flutter_test/flutter_test.dart';
import 'package:daemon/utils/config.dart';

void main() {
  test('config EPSILON_WINDOW is reasonable', () {
    expect(EPSILON_WINDOW, greaterThanOrEqualTo(5));
    expect(EPSILON_WINDOW, lessThanOrEqualTo(100));
  });

  test('EPSILON_COOLDOWN_EPISODES prevents rapid changes', () {
    expect(EPSILON_COOLDOWN_EPISODES, greaterThanOrEqualTo(EPSILON_WINDOW));
  });
}
