import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:minh_canh_mobile_v3/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = StoreDb.instance;
  late Directory temp;
  late Map<String, Object?> product;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    temp = await Directory.systemTemp.createTemp('mcm-drafts-');
    await databaseFactory.setDatabasesPath(temp.path);
    final id = await store.addProduct({'code':'DRAFT-PHONE','name':'Điện thoại thử',
      'category':'Điện thoại','track_imei':1,'created_at':DateTime.now().toIso8601String()});
    product = await store.product(id);
  });
  tearDownAll(() async {
    await (await store.database).close();
    await temp.delete(recursive:true);
  });
  test('individual IMEI costs determine purchase total and saved serial costs', () async {
    final line = PurchaseLineDraft(product:product,initialQuantity:2);
    line.cost.text='5000000';
    line.serials[0]..imei='490154203237518'..color='Đen'..cost=5000000;
    line.serials[1]..imei='490154203237526'..color='Trắng'..cost=5100000;
    expect(line.total,10100000);
    await store.completeMultiPurchase(items:[line],supplier:'NCC thử',paid:0,paymentMethod:'cash');
    final rows = await store.serials(product['id'] as int);
    expect(rows.map((r)=>r['cost']).toSet(),{5000000,5100000});
    expect(rows.map((r)=>r['color']).toSet(),{'Đen','Trắng'});
    line.dispose();
  });
  test('saved draft survives reload without changing stock', () async {
    final before = await store.serials(product['id'] as int);
    final payload = <String,Object?>{'supplier':'NCC tạm','paid':'0','payment':'cash','items':[
      {'product':product,'quantity':1,'cost':'5200000','discount':'0','serials':[
        {'imei':'490154203237534','color':'Hồng','conditionText':'Mới','cost':5300000}
      ]}
    ]};
    final id = await store.savePurchaseDraft(payload:payload);
    expect((await store.purchaseDraft(id))['payload'],payload);
    expect(await store.serials(product['id'] as int),before);
    expect((await store.purchaseDrafts()).any((r)=>r['id']==id),true);
    await store.deletePurchaseDraft(id);
    expect((await store.purchaseDrafts()).any((r)=>r['id']==id),false);
  });
  test('completion key records stock once and removes draft atomically', () async {
    final line=PurchaseLineDraft(product:product);
    line.cost.text='5000000';line.serials.single.imei='490154203237542';
    final draftId=await store.savePurchaseDraft(payload:{'items':[]});
    final first=await store.completeMultiPurchase(items:[line],supplier:'NCC',paid:0,
      paymentMethod:'cash',draftId:draftId,completionKey:'draft-completion-001');
    final second=await store.completeMultiPurchase(items:[line],supplier:'NCC',paid:0,
      paymentMethod:'cash',draftId:draftId,completionKey:'draft-completion-001');
    expect(second,first);
    expect((await store.serials(product['id'] as int)).where((r)=>r['imei']=='490154203237542'),hasLength(1));
    expect((await store.purchaseDrafts()).any((r)=>r['id']==draftId),false);
    line.dispose();
  });
  test('invalid second purchase line rolls back draft and first line',()async{
    final good=PurchaseLineDraft(product:product);good.cost.text='1000';good.serials.single.imei='490154203237550';
    final bad=PurchaseLineDraft(product:product);bad.cost.text='1000';bad.serials.single.imei='490154203237550';
    final draftId=await store.savePurchaseDraft(payload:{'items':[]});
    final before=await store.serials(product['id'] as int);
    await expectLater(store.completeMultiPurchase(items:[good,bad],supplier:'NCC',paid:0,paymentMethod:'cash',draftId:draftId,completionKey:'rollback-review-001'),throwsException);
    expect(await store.serials(product['id'] as int),before);expect((await store.purchaseDraft(draftId))['id'],draftId);
    good.dispose();bad.dispose();
  });

}
