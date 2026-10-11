import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:minh_canh_mobile_v3/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = StoreDb.instance;
  late Directory folder;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    folder = await Directory.systemTemp.createTemp('mcm-fund-checkpoint-');
    await databaseFactory.setDatabasesPath(folder.path);
  });
  tearDownAll(() async {
    await (await store.database).close();
    await folder.delete(recursive: true);
  });

  test('dashboard stops mixing historical paid stock with post-opening cash flow', () async {
    // These occurred before any software cash opening balance was entered.
    await store.saveCashEntry(
      type: 'expense', scope: 'unclassified', category: 'Nhập hàng đã trả',
      amount: 10000000, note: 'Lịch sử trước chốt',
      paymentMethod: 'cash', occurredAt: '2025-10-01T10:00:00',
    );
    final now = DateTime.now().toUtc().add(const Duration(hours: 7));
    final checkpoint = DateTime(now.year, now.month, now.day).subtract(
      const Duration(days: 1),
    );
    await store.setSetting(
      'capital_guard_started_at', checkpoint.toIso8601String(),
    );
    final afterCheckpoint = checkpoint.add(const Duration(hours: 2));
    await store.saveCashEntry(
      type: 'income', scope: 'business', category: 'Tiền thu sau chốt',
      amount: 500000, note: 'Tiền thu sau khi xác nhận số dư',
      paymentMethod: 'transfer', occurredAt: afterCheckpoint.toIso8601String(),
    );

    final overview = await store.dashboard();
    expect(overview['fund_since_opening'], 1);
    expect(overview['fund'], 500000);
    final historical = await store.financeSummary(DateTime(2000), DateTime(2100));
    expect(historical['cash_flow'], -9500000);
  });
}
