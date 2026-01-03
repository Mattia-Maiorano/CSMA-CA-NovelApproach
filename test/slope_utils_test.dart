import 'package:flutter_test/flutter_test.dart';
import 'package:daemon/utils/config.dart';

void main() {
  test('EPSILON_WINDOW is configurable and positive', () {
    expect(EPSILON_WINDOW, greaterThan(0));
  });

  test('EPSILON_COOLDOWN_EPISODES is based on EPSILON_WINDOW', () {
    expect(EPSILON_COOLDOWN_EPISODES, equals(EPSILON_WINDOW * 2));
  });
}
