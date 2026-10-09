import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:minh_canh_mobile_v3/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store=StoreDb.instance;
  late Directory dir;
  setUpAll(() async {
    sqfliteFfiInit();databaseFactory=databaseFactoryFfi;
    dir=await Directory.systemTemp.createTemp('mcm-finance-');
    await databaseFactory.setDatabasesPath(dir.path);
  });
  tearDownAll(() async {await (await store.database).close();await dir.delete(recursive:true);});
  test('business profit excludes personal principal and borrowed money',() async {
    final id=await store.addProduct({'code':'FIN-PK','name':'Finance cable','category':'Phụ kiện','track_imei':0,'created_at':'2026-10-09T09:00:00'});
    final line=PurchaseLineDraft(product:await store.product(id));line.cost.text='5000000';
    await store.completeMultiPurchase(items:[line],supplier:'Finance supplier',paid:5000000,paymentMethod:'cash');
    line.dispose();
    await store.completeMultiSale(invoiceCode:'FIN-SALE',items:[SaleLineDraft(product:await store.product(id),quantity:1,unitPrice:6000000,discountPerItem:0)],customer:'Finance buyer',phone:'',cash:6000000,transfer:0,warrantyMonths:0);
    for(final entry in [
      ['expense','personal',200000],['expense','business',100000],
      ['expense','loan_principal',300000],['expense','business_interest',50000],
      ['income','loan_received',2000000],
    ]) {
      await store.saveCashEntry(type:entry[0] as String,scope:entry[1] as String,category:'Test',amount:entry[2] as int,note:'',paymentMethod:'cash',occurredAt:'2026-10-09T10:00:00');
    }
    final totals=await store.financeSummary(DateTime(2000),DateTime(2100));
    expect(totals['business_profit'],850000);
    expect(totals['personal_expenses'],200000);
    expect(totals['principal_paid'],300000);
    expect(totals['cash_flow'],2350000);
    final ledger=await store.financeLedger(DateTime(2000),DateTime(2100));
    expect(ledger.where((r)=>r['source_type']=='purchase'),hasLength(1));
    expect(ledger.where((r)=>r['source_type']=='sale'),hasLength(1));
  });
  test('recurring February due date clamps and payment is idempotent',() async {
    final id=await store.saveRecurringExpense(payload:{'title':'Tiền nhà','amount':4000000,'day':31,'scope':'business','category':'Tiền thuê mặt bằng','start_month':'2026-01'});
    final rows=await store.recurringExpenses(2026,2);
    expect(rows.single['due_date'],'2026-02-28');
    final first=await store.payRecurringExpense(id,2026,2,'cash','2026-02-28T09:00:00');
    final second=await store.payRecurringExpense(id,2026,2,'cash','2026-02-28T09:00:00');
    expect(second,first);
    expect((await store.recurringExpenses(2026,2)).single['paid'],true);
  });
  test('Vietnam day filter respects UTC midnight boundary',() async {
    await store.saveCashEntry(type:'expense',scope:'personal',category:'Boundary',amount:123,note:'',paymentMethod:'transfer',occurredAt:'2026-10-08T17:01:00Z');
    final rows=await store.financeLedger(DateTime(2026,10,9),DateTime(2026,10,10));
    expect(rows.where((r)=>r['category']=='Boundary'),hasLength(1));
  });
  test('edit delete and backup preserve finance classification',() async {
    final id=await store.saveCashEntry(type:'expense',scope:'personal',category:'Edit me',amount:500,note:'',paymentMethod:'cash',occurredAt:'2026-10-09T11:00:00');
    await store.saveCashEntry(id:id,type:'expense',scope:'business',category:'Edited',amount:600,note:'',paymentMethod:'transfer',occurredAt:'2026-10-09T11:00:00');
    final backup=await store.exportBackup();await store.restoreBackup(backup);
    final rows=await store.financeLedger(DateTime(2000),DateTime(2100));
    expect(rows.singleWhere((r)=>r['source_type']=='manual'&&r['source_id']==id)['scope'],'business');
    await store.deleteCashEntry(id);
    expect((await store.financeLedger(DateTime(2000),DateTime(2100))).any((r)=>r['source_type']=='manual'&&r['source_id']==id),false);
  });
}
