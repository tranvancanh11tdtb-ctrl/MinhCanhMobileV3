import 'package:flutter_test/flutter_test.dart';
import 'package:minh_canh_mobile_v3/main.dart';
void main() {
  test('leap February includes final day, excludes March', () {
    final p=PeriodFilter.month(DateTime(2024,2,10));
    expect(p.start,DateTime(2024,2));
    expect(p.end,DateTime(2024,3));
    expect(p.includes(DateTime(2024,2,29,23,59)),isTrue);
    expect(p.includes(DateTime(2024,3)),isFalse);
  });
  test('year rollover uses half open range', () {
    final p=PeriodFilter('day',DateTime(2026,12,31));
    expect(p.end,DateTime(2027));
    expect(p.includes(DateTime(2027)),isFalse);
    expect(PeriodFilter('all',DateTime(2026)).includes(DateTime(2000)),isTrue);
  });
}
