import 'package:draft_survey/core/util.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('toFixed matches JS', () {
    expect(toFixed(1.005, 2), '1.00');
    expect(toFixed(2.5, 0), '3');
    expect(toFixed(-0.0, 3), '0.000');
    expect(toFixed(12.3456, 3), '12.346');
  });

  test('toNum', () {
    expect(toNum('3.5'), 3.5);
    expect(toNum(''), 0);
    expect(toNum('abc'), 0);
  });

  test('lerp', () {
    expect(lerp(0, 0, 10, 100, 5), 50);
  });
}
