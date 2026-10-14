import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:minh_canh_mobile_v3/main.dart';

void main() {
  test('file import handles long V7 backups without clipboard truncation', () {
    final source = <String, Object?>{
      'app': 'MinhCanhMobileV3',
      'backup_version': 7,
      'created_at': '2026-10-13T14:47:53.570393',
      for (final key in [
        'products', 'purchases', 'serial_units', 'purchase_items', 'sales',
        'sale_items', 'inventory_movements', 'repairs', 'warranty_claims',
        'cash_entries', 'stocktakes', 'customer_directory',
        'supplier_directory', 'debt_adjustments', 'product_categories',
        'product_brands', 'app_settings',
      ]) key: <Object>[],
    };
    (source['customer_directory'] as List).add({
      'id': 1,
      'name': 'Khách thử',
      'note': List.filled(55000, 'x').join(),
    });
    final json = jsonEncode(source);
    expect(json.length, greaterThan(39291));
    expect(parseMinhCanhBackupFile(Uint8List.fromList(utf8.encode(json))), json);
    expect(
      () => parseMinhCanhBackupFile(Uint8List.fromList(utf8.encode(json.substring(0, 39291)))),
      throwsFormatException,
    );
  });

  test('wrong app name is rejected before modifying the database', () {
    expect(
      () => parseMinhCanhBackupFile(Uint8List.fromList(utf8.encode('{"app":"other","backup_version":7}'))),
      throwsFormatException,
    );
  });
}
