import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:minh_canh_mobile_v3/tspl_printer.dart';

void main() {
  test('TSPL raster job uses the verified orientation and complete data', () {
    final source = img.Image(width: 576, height: 16);
    img.fill(source, color: img.ColorRgb8(255, 255, 255));
    source.setPixelRgb(0, 0, 0, 0, 0); // black mark on white paper
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
    final rasterStart = bitmapStart + bitmapCommand.length;
    // TSPL 0 means print black; 1 means leave paper unprinted white.
    expect(bytes[rasterStart], 0x7f);
    expect(bytes[rasterStart + 1], 0xff);
    expect(bytes[rasterStart + 72], 0xff);
  });

  test('paired 35x22 mm TSPL rows contain both label bitmaps', () {
    final left = img.Image(width: 280, height: 176);
    final right = img.Image(width: 280, height: 176);
    img.fill(left, color: img.ColorRgb8(255, 255, 255));
    img.fill(right, color: img.ColorRgb8(255, 255, 255));
    left.setPixelRgb(4, 4, 0, 0, 0);
    right.setPixelRgb(4, 4, 0, 0, 0);
    final raw = TsplPrinter.encodeDoubleLabelRow(
      Uint8List.fromList(img.encodePng(left)),
      Uint8List.fromList(img.encodePng(right)),
    );
    final asText = latin1.decode(raw);
    const marker = 'BITMAP 0,0,72,176,0,';
    final start = asText.indexOf(marker);
    const ending = '\r\nPRINT 1,1\r\n';
    expect(start, greaterThanOrEqualTo(0));
    expect(asText, contains('SIZE 72 mm,22 mm\r\n'));
    expect(asText, contains('GAP 2 mm,0 mm\r\n'));
    expect(asText, contains('DIRECTION 0\r\n'));
    expect(raw.length - (start + marker.length) - ending.length,
        72 * 176);
    final rasterStart = start + marker.length;
    expect(raw[rasterStart + 4 * 72], 0xf7); // left mark x=4 => clear bit3
    expect(raw[rasterStart + 4 * 72 + 36], 0xf7); // right mark x=292
    expect(raw[rasterStart + 4 * 72 + 35], 0xff); // 1 mm white gap
    expect(raw[rasterStart], 0xff); // unprinted background
  });
}
