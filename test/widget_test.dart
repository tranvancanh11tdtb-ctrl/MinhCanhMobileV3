import 'package:flutter_test/flutter_test.dart';
import 'package:minh_canh_mobile_v3/main.dart';

void main() {
  test('formats Vietnamese currency', () {
    expect(vnd(1000000), contains('1.000.000'));
  });
}
