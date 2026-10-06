import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:minh_canh_mobile_v3/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = StoreDb.instance;
  late Directory temp;
  late int phoneId, accessoryId, saleId;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    temp = await Directory.systemTemp.createTemp('mcm-test-');
    await databaseFactory.setDatabasesPath(temp.path);
    final now = DateTime.now().toIso8601String();
    phoneId = await store.addProduct({'code':'PHONE', 'name':'Máy thử',
      'category':'Điện thoại', 'track_imei':1, 'created_at':now});
    accessoryId = await store.addProduct({'code':'PK', 'name':'Cáp thử',
      'category':'Phụ kiện', 'track_imei':0, 'created_at':now});
    final phone = PurchaseLineDraft(product: await store.product(phoneId));
    phone.cost.text = '5000000';
    phone.serials.single.imei = '490154203237518';
    final cable = PurchaseLineDraft(product: await store.product(accessoryId), initialQuantity:2);
    cable.cost.text = '50000';
    await store.completeMultiPurchase(items:[phone,cable], supplier:'Nhà cung cấp A',
      paid:5100000, paymentMethod:'cash');
    phone.dispose(); cable.dispose();
    final serial = (await store.serials(phoneId)).single;
    saleId = await store.completeMultiSale(invoiceCode:'HD-TEST', items:[
      SaleLineDraft(product:await store.product(phoneId), quantity:1, unitPrice:6000000,
        discountPerItem:0, serialId:serial['id'] as int, imei:'490154203237518'),
      SaleLineDraft(product:await store.product(accessoryId), quantity:1, unitPrice:100000,
        discountPerItem:0),
    ], customer:'Khách thử', phone:'0900000000', cash:6000000, transfer:0, warrantyMonths:12);
  });
  tearDownAll(() async {
    await (await store.database).close();
    await temp.delete(recursive:true);
  });
  test('multi-line purchase and sale preserve cost and stock', () async {
    final detail = await store.saleDetail(saleId);
    final sale = detail['sale'] as Map;
    expect(sale['total'],6100000);
    expect(sale['cost_total'],5050000);
    expect((await store.product(accessoryId))['quantity'],1);
    expect((await store.customers()).single['debt'],100000);
  });
  test('warranties exclude accessories in a mixed invoice', () async {
    final rows = await store.warranties();
    expect(rows.length,1);
    expect(rows.single['imei'],'490154203237518');
  });
  test('inventory report keeps inactive products with remaining stock', () async {
    await store.setProductActive(accessoryId,false);
    final rows = await store.productReport(DateTime(2020),DateTime(2100));
    final cable = rows.where((r)=>r['id']==accessoryId);
    expect(cable,hasLength(1));
    expect(cable.single['stock_value'],50000);
  });
  test('restore preserves mixed invoice, IMEI, debt and warranty history', () async {
    final warranty=(await store.warranties()).single;
    // The sale item identity is the warranty record ID.
    final db=await store.database;
    final saleItem=(await db.query('sale_items',where:'sale_id=? AND serial_id IS NOT NULL',whereArgs:[saleId])).single;
    await store.addWarrantyClaim(saleItemId:saleItem['id'] as int,issue:'Kiểm tra',note:'Lịch sử cần giữ');
    final source=await store.exportBackup();
    await store.restoreBackup(source);
    final detail=await store.saleDetail(saleId);
    expect((detail['sale'] as Map)['total'],6100000);
    expect((await store.customers()).single['debt'],100000);
    expect((await store.product(accessoryId))['quantity'],1);
    expect((await store.warranties()).single['imei'],warranty['imei']);
    expect(await store.warrantyClaims(saleItem['id'] as int),hasLength(1));
    final backup=jsonDecode(await store.exportBackup()) as Map;
    expect(backup['sale_items'],hasLength(2));
  });
  test('two simultaneous sales of the same IMEI commit only once', () async {
    final id=await store.addProduct({'code':'RACE','name':'Máy đồng thời','category':'Điện thoại','track_imei':1,'created_at':DateTime.now().toIso8601String()});
    final purchase=PurchaseLineDraft(product:await store.product(id));
    purchase.cost.text='5000000';purchase.serials.single.imei='490154203237526';
    await store.completeMultiPurchase(items:[purchase],supplier:'NCC',paid:5000000,paymentMethod:'cash');
    purchase.dispose();
    final product=await store.product(id);
    final serial=(await store.serials(id)).single;
    Future<bool> sell(String code) async {
      try {
        await store.completeMultiSale(invoiceCode:code,items:[SaleLineDraft(product:product,quantity:1,unitPrice:6000000,discountPerItem:0,serialId:serial['id'] as int,imei:serial['imei'] as String)],customer:'Khách lẻ',phone:'',cash:6000000,transfer:0,warrantyMonths:12);
        return true;
      }catch(_){return false;}
    }
    final results=await Future.wait([sell('RACE-A'),sell('RACE-B')]);
    expect(results.where((ok)=>ok),hasLength(1));
    expect((await store.sales()).where((r)=>r['code']=='RACE-A'||r['code']=='RACE-B'),hasLength(1));
  });
}
