import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:minh_canh_mobile_v3/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = StoreDb.instance;
  late Directory dir;
  late int phoneId, cableId;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dir = await Directory.systemTemp.createTemp('mcm-opening-stock-');
    await databaseFactory.setDatabasesPath(dir.path);
    final now = DateTime.now().toIso8601String();
    phoneId = await store.addProduct({
      'code': 'OPEN-PHONE',
      'name': 'Máy tồn từ trước',
      'category': 'Điện thoại',
      'track_imei': 1,
      'created_at': now,
    });
    cableId = await store.addProduct({
      'code': 'OPEN-CABLE',
      'name': 'Cáp tồn từ trước',
      'category': 'Phụ kiện',
      'track_imei': 0,
      'created_at': now,
    });
  });

  tearDownAll(() async {
    await (await store.database).close();
    await dir.delete(recursive: true);
  });

  test('paid opening stock raises inventory without any new cash payment/debt/profit', () async {
    final phone = PurchaseLineDraft(product: await store.product(phoneId), initialQuantity: 2);
    phone.cost.text = '3000000';
    phone.serials[0]
      ..imei = '490154203237518'
      ..color = 'Đen'
      ..cost = 3000000;
    phone.serials[1]
      ..imei = '490154203237526'
      ..color = 'Trắng'
      ..cost = 3100000;
    final cable = PurchaseLineDraft(product: await store.product(cableId), initialQuantity: 3);
    cable.cost.text = '50000';

    final before = await store.financeSummary(DateTime(2000), DateTime(2100));
    final id = await store.completeMultiPurchase(
      items: [phone, cable],
      supplier: '',
      paid: 0,
      paymentMethod: 'cash',
      openingStock: true,
      completionKey: 'opening-stock-test-001',
    );
    final saved = (await (await store.database).query('purchases',
      where: 'id=?', whereArgs: [id])).single;
    expect(saved['status'], 'opening_stock');
    expect(saved['total'], 6250000);
    expect(saved['paid'], 6250000);
    expect(saved['payment_method'], 'Tồn đầu kỳ');

    expect((await store.serials(phoneId)).map((r) => r['color']).toSet(),
        {'Đen', 'Trắng'});
    expect((await store.serials(phoneId)).map((r) => r['cost']).toSet(),
        {3000000, 3100000});
    expect((await store.product(cableId))['quantity'], 3);
    expect((await store.product(cableId))['avg_cost'], 50000);
    final ledger = await store.financeLedger(DateTime(2000), DateTime(2100));
    expect(ledger, isEmpty);
    final after = await store.financeSummary(DateTime(2000), DateTime(2100));
    expect(after['cash_flow'], before['cash_flow']);
    expect(after['business_profit'], before['business_profit']);
    expect((await store.suppliers()).where((r) => r['debt'] != 0), isEmpty);
    final movements = await (await store.database).query('inventory_movements',
        where: "reference_type='purchase' AND reference_id=?", whereArgs: [id]);
    expect(movements, hasLength(3));
    expect(movements.every((m) => m['kind'] == 'opening_stock'), true);

    // Retry/duplicate submission must never double inventory.
    expect(await store.completeMultiPurchase(
      items: [phone, cable], supplier: '', paid: 0, paymentMethod: 'cash',
      openingStock: true, completionKey: 'opening-stock-test-001',
    ), id);
    expect((await store.serials(phoneId)), hasLength(2));
    expect((await store.product(cableId))['quantity'], 3);

    final backup = jsonDecode(await store.exportBackup()) as Map;
    expect((backup['purchases'] as List).single['status'], 'opening_stock');
    await store.restoreBackup(jsonEncode(backup));
    expect((await store.serials(phoneId)), hasLength(2));
    expect((await store.product(cableId))['quantity'], 3);

    phone.dispose();
    cable.dispose();
  });

  test('selling an opening-stock IMEI recognizes original cost only at sale', () async {
    final phone = await store.product(phoneId);
    final serial = (await store.serials(phoneId)).firstWhere(
      (r) => r['imei'] == '490154203237518',
    );
    final id = await store.completeMultiSale(
      invoiceCode: 'OPEN-SALE-001',
      items: [SaleLineDraft(
        product: phone, quantity: 1, unitPrice: 4000000,
        discountPerItem: 0, serialId: serial['id'] as int,
        imei: serial['imei'] as String,
      )],
      customer: 'Khách thử', phone: '', cash: 4000000, transfer: 0,
      warrantyMonths: 12,
    );
    final invoice = (await store.saleDetail(id))['sale'] as Map;
    expect(invoice['cost_total'], 3000000);
    final summary = await store.financeSummary(DateTime(2000), DateTime(2100));
    expect(summary['business_profit'], 1000000);
    expect(summary['cash_flow'], 4000000);
  });
}
