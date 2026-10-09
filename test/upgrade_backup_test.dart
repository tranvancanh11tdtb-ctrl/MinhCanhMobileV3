import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:minh_canh_mobile_v3/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = StoreDb.instance;
  late Directory dir;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dir = await Directory.systemTemp.createTemp('mcm-backup-upgrade-');
    await databaseFactory.setDatabasesPath(dir.path);
  });
  tearDownAll(() async {
    await (await store.database).close();
    await dir.delete(recursive: true);
  });
  test('legacy format 6 restores old cash entries as unclassified', () async {
    await store.addCashEntry(
      type: 'expense',
      category: 'Khoản cũ',
      amount: 1000,
      note: '',
    );
    final backup =
        jsonDecode(await store.exportBackup()) as Map<String, dynamic>;
    backup['backup_version'] = 6;
    for (final key in [
      'purchase_drafts',
      'purchase_completions',
      'recurring_expenses',
      'recurring_payments',
      'payment_events',
    ]) {
      backup.remove(key);
    }
    for (final row in backup['cash_entries'] as List) {
      (row as Map)
        ..remove('scope')
        ..remove('occurred_at')
        ..remove('payment_method');
    }
    await store.restoreBackup(jsonEncode(backup));
    final ledger = await store.financeLedger(DateTime(2000), DateTime(2100));
    expect(ledger.single['scope'], 'unclassified');
    expect(ledger.single['amount'], 1000);
  });
  test('legacy repair collections retain unknown timing', () async {
    await store.addRepair(
      customer: 'Legacy',
      phone: '',
      device: 'Phone',
      imei: '',
      issue: 'Fix',
      amount: 5000,
      partsCost: 0,
      paid: 4000,
      note: '',
    );
    final backup =
        jsonDecode(await store.exportBackup()) as Map<String, dynamic>;
    backup['backup_version'] = 6;
    for (final row in backup['repairs'] as List) {
      (row as Map)
        ..remove('initial_paid')
        ..remove('initial_payment_known');
      row['received_at'] = '2026-09-01T10:00:00';
    }
    await store.restoreBackup(jsonEncode(backup));
    final summary = await store.financeSummary(
      DateTime(2026, 9),
      DateTime(2026, 10),
    );
    expect(summary['income'], 0);
    expect(summary['unknown_repair_payments'], 4000);
  });
  test(
    'inventory period reconciles opening incoming outgoing and closing',
    () async {
      final id = await store.addProduct({
        'code': 'REPORT-PK',
        'name': 'Inventory period',
        'category': 'Phụ kiện',
        'track_imei': 0,
        'created_at': financeNow(),
      });
      final line = PurchaseLineDraft(
        product: await store.product(id),
        initialQuantity: 2,
      );
      line.cost.text = '1000';
      await store.completeMultiPurchase(
        items: [line],
        supplier: 'NCC',
        paid: 0,
        paymentMethod: 'cash',
      );
      line.dispose();
      await store.completeMultiSale(
        invoiceCode: 'PERIOD-SALE',
        items: [
          SaleLineDraft(
            product: await store.product(id),
            quantity: 1,
            unitPrice: 2000,
            discountPerItem: 0,
          ),
        ],
        customer: 'Khách lẻ',
        phone: '',
        cash: 2000,
        transfer: 0,
        warrantyMonths: 0,
      );
      final row = (await store.productReport(
        DateTime(2000),
        DateTime(2100),
      )).singleWhere((r) => r['id'] == id);
      expect(row['revenue'], 2000);
      expect(row['profit'], 1000);
      expect(row['opening_stock'], 0);
      expect(row['incoming'], 2);
      expect(row['outgoing'], 1);
      expect(row['closing_stock'], 1);
    },
  );
  test('format 7 preserves draft and recurring payment identity',()async{
    final id=await store.savePurchaseDraft(payload:{'supplier':'Roundtrip','items':[]});
    final template=await store.saveRecurringExpense(payload:{'title':'Rent backup','amount':1000,'scope':'business','day':31,'start_month':'2026-10','active':true});
    final cash=await store.payRecurringExpense(template,2026,10,'cash','2026-10-09T10:00:00');
    final source=await store.exportBackup();await store.deletePurchaseDraft(id);await store.restoreBackup(source);
    expect(((await store.purchaseDraft(id))['payload'] as Map)['supplier'],'Roundtrip');
    expect(await store.payRecurringExpense(template,2026,10,'cash','2026-10-09T10:00:00'),cash);
  });

}
