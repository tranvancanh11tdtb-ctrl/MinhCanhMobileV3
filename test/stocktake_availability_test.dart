import 'package:flutter_test/flutter_test.dart';
import 'package:minh_canh_mobile_v3/main.dart';

void main() {
  test('Stocktake quantity filters include out of stock IMEI and accessories', () {
    const none = <String, Object?>{'stock': 0, 'track_imei': 1};
    const nearlyGone = <String, Object?>{'stock': 2, 'track_imei': 0};
    const plentiful = <String, Object?>{'stock': 8, 'track_imei': 1};
    expect(stocktakeMatchesAvailability(none, 'out', 3), true);
    expect(stocktakeMatchesAvailability(nearlyGone, 'out', 3), false);
    expect(stocktakeMatchesAvailability(none, 'low', 3), false);
    expect(stocktakeMatchesAvailability(nearlyGone, 'low', 3), true);
    expect(stocktakeMatchesAvailability(plentiful, 'low', 3), false);
    expect(stocktakeMatchesAvailability(nearlyGone, 'available', 3), true);
    expect(stocktakeMatchesAvailability(none, 'available', 3), false);
    expect(stocktakeMatchesAvailability(plentiful, 'enough', 3), true);
    expect(stocktakeMatchesAvailability(nearlyGone, 'enough', 3), false);
    expect(stocktakeMatchesAvailability(nearlyGone, 'low', 1), false);
    expect(stocktakeMatchesAvailability(nearlyGone, 'low', 2), true);
    expect(stocktakeMatchesAvailability(none, 'all', 3), true);
    expect(stocktakeMatchesAvailability(plentiful, 'all', 3), true);
  });
}
