import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:minh_canh_mobile_v3/tspl_printer.dart';

void main() {
  test('TSPL raster job uses the verified orientation and complete data', () {
    final source = img.Image(width: 576, height: 16);
    final png = Uint8List.fromList(img.encodePng(source));
    final bytes = TsplPrinter.encodeRaster(png);
    final text = latin1.decode(bytes);
    const bitmapCommand = 'BITMAP 0,0,72,16,0,';
    const ending = '\r\nPRINT 1,1\r\n';

    expect(text, contains('SIZE 72 mm,6 mm\r\n'));
    expect(text, contains('GAP 0 mm,0 mm\r\n'));
    expect(text, contains('DIRECTION 0\r\n'));
    final bitmapStart = text.indexOf(bitmapCommand);
    expect(bitmapStart, greaterThanOrEqualTo(0));
    expect(text.endsWith(ending), isTrue);
    expect(bytes.length - bitmapStart - bitmapCommand.length - ending.length,
        72 * 16);
  });
}
