import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Encodes a receipt image as a TSPL BITMAP print job for an Ethernet label
/// printer. The KiotViet-branded K80 printer was verified with TSPL commands
/// (DIRECTION 0) over TCP 9100, not with raw ESC/POS text commands.
class TsplPrinter {
  TsplPrinter._();

  static const int _printWidth = 576; // 72 mm at approximately 8 dots/mm.
  static const int _bytesPerRow = _printWidth ~/ 8;

  static Uint8List encodeRaster(Uint8List png) {
    final source = img.decodeImage(png);
    if (source == null) {
      throw FormatException('Không đọc được ảnh phiếu để in TSPL');
    }

    final image = img.copyResize(
      source,
      width: _printWidth,
      interpolation: img.Interpolation.average,
    );
    final height = image.height;
    if (height <= 0) {
      throw FormatException('Phiếu in không có nội dung');
    }

    final bitmap = Uint8List(_bytesPerRow * height);
    for (var y = 0; y < height; y++) {
      final rowStart = y * _bytesPerRow;
      for (var x = 0; x < _printWidth; x++) {
        final pixel = image.getPixel(x, y);
        // The receipt has a white background. Ignore fully transparent pixels
        // and pack dark pixels in most-significant-bit-first TSPL bitmap order.
        final brightness =
            pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114;
        if (pixel.a >= 128 && brightness < 180) {
          bitmap[rowStart + (x ~/ 8)] |= 0x80 >> (x % 8);
        }
      }
    }

    // A few blank lines prevent the last printed row being clipped.
    final heightMm = (height + 32 + 7) ~/ 8;
    final output = BytesBuilder(copy: false);
    output.add(ascii.encode(
      'SIZE 72 mm,$heightMm mm\r\n'
      'GAP 0 mm,0 mm\r\n'
      'DIRECTION 0\r\n'
      'CLS\r\n'
      'BITMAP 0,0,$_bytesPerRow,$height,0,',
    ));
    output.add(bitmap);
    output.add(ascii.encode('\r\nPRINT 1,1\r\n'));
    return output.takeBytes();
  }

  /// Build one physical 72 mm row containing two 35 x 22 mm labels,
  /// separated by a 1 mm gap. The two PNGs are sized to 280 x 176 dots.
  /// The vertical gap is between successive physical rows on the roll.
  static Uint8List encodeDoubleLabelRow(
    Uint8List leftPng,
    Uint8List? rightPng, {
    int horizontalOffsetDots = 0,
    int verticalOffsetDots = 0,
    int rowGapMm = 2,
  }) {
    const rowHeight = 176;
    const labelWidth = 280;
    const rightStart = 288; // 35 mm + 1 mm between two columns.
    final bitmap = Uint8List(_bytesPerRow * rowHeight);

    void pasteLabel(Uint8List png, int originX) {
      final decoded = img.decodeImage(png);
      if (decoded == null) {
        throw FormatException('Không đọc được ảnh tem đôi');
      }
      final resized = img.copyResize(
        decoded,
        width: labelWidth,
        height: rowHeight,
        interpolation: img.Interpolation.average,
      );
      for (var y = 0; y < rowHeight; y++) {
        final yy = y + verticalOffsetDots;
        if (yy < 0 || yy >= rowHeight) continue;
        for (var x = 0; x < labelWidth; x++) {
          final xx = originX + x + horizontalOffsetDots;
          if (xx < 0 || xx >= _printWidth) continue;
          final px = resized.getPixel(x, y);
          final brightness = px.r * 0.299 + px.g * 0.587 + px.b * 0.114;
          if (px.a >= 128 && brightness < 180) {
            bitmap[yy * _bytesPerRow + (xx ~/ 8)] |=
                0x80 >> (xx % 8);
          }
        }
      }
    }

    pasteLabel(leftPng, 0);
    if (rightPng != null) pasteLabel(rightPng, rightStart);
    final gap = rowGapMm.clamp(0, 6);
    final output = BytesBuilder(copy: false);
    output.add(ascii.encode(
      'SIZE 72 mm,22 mm\r\n'
      'GAP $gap mm,0 mm\r\n'
      'DIRECTION 0\r\n'
      'CLS\r\n'
      'BITMAP 0,0,$_bytesPerRow,$rowHeight,0,',
    ));
    output.add(bitmap);
    output.add(ascii.encode('\r\nPRINT 1,1\r\n'));
    return output.takeBytes();
  }
}
