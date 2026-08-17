import 'package:flutter_test/flutter_test.dart';
import 'package:minh_canh_mobile_v3/main.dart';
import 'package:minh_canh_mobile_v3/scanner_page.dart';
import 'package:minh_canh_mobile_v3/vietqr.dart';

void main() {
  test('formats Vietnamese currency', () {
    expect(vnd(1000000), contains('1.000.000'));
  });

  test('validates and extracts a standard IMEI', () {
    expect(extractImei('IMEI: 490154203237518'), '490154203237518');
    expect(isValidImei('490154203237518'), isTrue);
    expect(isValidImei('490154203237519'), isFalse);
  });

  test('builds a dynamic VietQR payload with amount and valid CRC', () {
    final payload = buildVietQrPayload(
      bankBin: '970422',
      accountNumber: '123456789',
      amount: 18300000,
      description: 'MCM HD202608180001',
    );
    expect(payload, contains('0006' '970422'));
    expect(payload, contains('5408' '18300000'));
    final body = payload.substring(0, payload.length - 4);
    expect(payload.substring(payload.length - 4), crc16Ccitt(body));
  });
}
