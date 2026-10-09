import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:minh_canh_mobile_v3/main.dart';
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();final store=StoreDb.instance;late Directory dir;
 setUpAll(()async{sqfliteFfiInit();databaseFactory=databaseFactoryFfi;dir=await Directory.systemTemp.createTemp('review-finance-');await databaseFactory.setDatabasesPath(dir.path);});
 tearDownAll(()async{await(await store.database).close();await dir.delete(recursive:true);});
 Future<int> sell(String code)async{
  final id=await store.addProduct({'code':code,'name':code,'category':'Phụ kiện','track_imei':0,'created_at':financeNow()});
  final line=PurchaseLineDraft(product:await store.product(id));line.cost.text='1000';await store.completeMultiPurchase(items:[line],supplier:'NCC',paid:0,paymentMethod:'cash');line.dispose();
  return store.completeMultiSale(invoiceCode:code,items:[SaleLineDraft(product:await store.product(id),quantity:1,unitPrice:2000,discountPerItem:0)],customer:'Khách lẻ',phone:'',cash:2000,transfer:0,warrantyMonths:0);
 }
 test('cancel preserves collection date and records one refund today',()async{
  final id=await sell('CANCEL');final db=await store.database;
  await db.update('sales',{'created_at':'2026-09-01T10:00:00'},where:'id=?',whereArgs:[id]);
  await store.cancelSale(id);await store.cancelSale(id);
  final historical=await store.financeSummary(DateTime(2026,9),DateTime(2026,10));expect(historical['income'],2000);
  final current=await store.financeLedger(DateTime(2026,10),DateTime(2026,11));
  expect(current.where((r)=>r['source_type']=='sale_refund_payment').single['amount'],2000);
  expect(historical['revenue'],0);
 });
 test('Vietnam midnight agrees in summary invoice detail and trend',()async{
  final id=await sell('UTC');final db=await store.database;
  final wall=vietnamWallDate(financeNow());final from=DateTime(wall.year,wall.month,wall.day),to=from.add(const Duration(days:1));
  final utc=DateTime.utc(wall.year,wall.month,wall.day).subtract(const Duration(hours:7)).add(const Duration(minutes:1));
  await db.update('sales',{'created_at':utc.toIso8601String()},where:'id=?',whereArgs:[id]);
  final summary=await store.reportSummary(from,to);expect(summary['sales_revenue'],2000);expect(summary['invoices'],1);
  expect((await store.invoiceReport(from,to)).single['id'],id);
  expect((await store.salesTrend('day')).last['revenue'],2000);
 });
}
