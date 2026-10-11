import 'package:draft_survey/core/util.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final table = <Row>[
    {'d': 1.0, 'v': 10.0},
    {'d': 2.0, 'v': 20.0},
    {'d': 4.0, 'v': 60.0},
  ];
  test('interpolates inside the table', () {
    expect(interpTable(table, 'd', 'v', 3.0), 40.0);
  });
  test('extrapolates outside', () {
    expect(interpTable(table, 'd', 'v', 0.0), 0.0);
    expect(interpTable(table, 'd', 'v', 5.0), 80.0);
  });
  test('empty table -> null', () {
    expect(interpTable(<Row>[], 'd', 'v', 1.0), isNull);
  });
}
