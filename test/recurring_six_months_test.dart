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
    folder = await Directory.systemTemp.createTemp('mcm-six-month-rent-');
    await databaseFactory.setDatabasesPath(folder.path);
  });
  tearDownAll(() async {
    await (await store.database).close();
    await folder.delete(recursive: true);
  });

  test('six-month rent only appears in actual due months', () async {
    final id = await store.saveRecurringExpense(payload: {
      'title': 'Tiền thuê nhà 6 tháng', 'category': 'Thuê mặt bằng',
      'amount': 24000000, 'day': 15, 'scope': 'business',
      'start_month': '2026-11', 'interval_months': 6,
    });
    expect(await store.recurringExpenses(2026, 10), isEmpty);
    final due = await store.recurringExpenses(2026, 11);
    expect(due.single['id'], id);
    expect(due.single['amount'], 24000000);
    expect(due.single['paid'], false);
    expect(await store.recurringExpenses(2026, 12), isEmpty);
    expect(await store.recurringExpenses(2027, 4), isEmpty);
    expect((await store.recurringExpenses(2027, 5)).single['id'], id);
    expect((await store.recurringExpenses(2027, 11)).single['id'], id);
  });

  test('already paid marks without new cash flow and can undo safely', () async {
    final id = await store.saveRecurringExpense(payload: {
      'title': 'Tiền điện nước', 'category': 'Điện nước',
      'amount': 1500000, 'day': 10, 'scope': 'business',
      'start_month': '2026-10', 'interval_months': 1,
    });
    final before = await store.financeSummary(DateTime(2000), DateTime(2100));
    await store.markRecurringPaidNoEntry(id, 2026, 10);
    final rows = await store.recurringExpenses(2026, 10);
    final paid = rows.singleWhere((r) => r['id'] == id);
    expect(paid['paid'], true);
    expect(paid['paid_without_entry'], true);
    expect(paid['cash_entry_id'], null);
    final after = await store.financeSummary(DateTime(2000), DateTime(2100));
    expect(after['cash_flow'], before['cash_flow']);
    expect(after['business_profit'], before['business_profit']);
    await expectLater(
      store.payRecurringExpense(id, 2026, 10, 'cash', '2026-10-11T08:00:00'),
      throwsStateError,
    );
    final backup = await store.exportBackup();
    await store.restoreBackup(backup);
    final afterRestore = await store.recurringExpenses(2026, 10);
    expect(afterRestore.singleWhere((r) => r['id'] == id)['paid'], true);
    await store.unmarkRecurringPaidNoEntry(id, 2026, 10);
    expect((await store.recurringExpenses(2026, 10))
        .singleWhere((r) => r['id'] == id)['paid'], false);
    await expectLater(store.unmarkRecurringPaidNoEntry(id, 2026, 10), throwsStateError);
    final entryId = await store.payRecurringExpense(
      id, 2026, 10, 'transfer', '2026-10-11T08:00:00');
    expect(entryId, greaterThan(0));
    expect((await store.financeSummary(DateTime(2000), DateTime(2100)))['cash_flow'], -1500000);
    expect(await store.payRecurringExpense(
      id, 2026, 10, 'transfer', '2026-10-11T08:00:00'), entryId);
    await expectLater(store.markRecurringPaidNoEntry(id, 2026, 10), throwsStateError);
  });

  test('old recurring templates still default to monthly', () async {
    final id = await store.saveRecurringExpense(payload: {
      'title': 'Khoản cũ', 'amount': 1000, 'day': 30,
      'scope': 'business', 'start_month': '2026-09',
    });
    final sep = await store.recurringExpenses(2026, 9);
    final oct = await store.recurringExpenses(2026, 10);
    expect(sep.singleWhere((r) => r['id'] == id)['interval_months'], 1);
    expect(oct.singleWhere((r) => r['id'] == id)['due_date'], '2026-10-30');
  });
}
