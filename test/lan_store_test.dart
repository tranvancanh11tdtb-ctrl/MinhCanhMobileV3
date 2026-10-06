import 'dart:convert';
import 'dart:io';
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
    dir = await Directory.systemTemp.createTemp('mcm-lan-');
    await databaseFactory.setDatabasesPath(dir.path);
  });
  tearDownAll(() async {
    await (await store.database).close();
    await dir.delete(recursive: true);
  });
  Future<int> revision() async => (await store.executeRemote({'operation':'dashboard'}))['revision'] as int;
  test('retry returns same result and cannot change payload', () async {
    final request = <String,Object?>{'operation':'addProductBrand','arguments':{'rawName':'Retry brand'},'requestId':'request-retry-0001','revision':await revision()};
    final first = await store.executeRemote(request);
    expect(await store.executeRemote(request),first);
    expect((await store.productBrands()).where((r)=>r['name']=='Retry brand'),hasLength(1));
    expect(store.executeRemote({...request,'arguments':{'rawName':'Other'}}),throwsStateError);
  });
  test('stale revision rejects a write before it changes data', () async {
    final old = await revision();
    await store.addProductBrand('Local change');
    expect(store.executeRemote({'operation':'addProductBrand','arguments':{'rawName':'Stale'},'requestId':'request-stale-001','revision':old}),throwsStateError);
  });
  test('remote cannot read or change PIN and backup excludes PIN', () async {
    await store.setSetting('pin','1234');
    expect(store.executeRemote({'operation':'getSetting','arguments':{'key':'pin'}}),throwsStateError);
    final response = await store.executeRemote({'operation':'exportBackup'});
    final backup = jsonDecode(response['value'] as String) as Map;
    expect((backup['app_settings'] as List).where((r)=>r['setting_key']=='pin'),isEmpty);
    expect(await store.getSetting('pin'),'1234');
  });
  test('desktop can read payment settings', () async {
    await store.setSetting('payment_bank_bin','970422');
    final result = await store.executeRemote({'operation':'getSetting','arguments':{'key':'payment_bank_bin'}});
    expect(result['value'],'970422');
  });
  test('remote restore preserves device PIN and is replay safe', () async {
    final backup=jsonDecode(await store.exportBackup()) as Map<String,dynamic>;
    backup['app_settings']=[{'setting_key':'pin','setting_value':'9999'}];
    final request=<String,Object?>{'operation':'restoreBackup','arguments':{'source':jsonEncode(backup)},'requestId':'restore-request-0001','revision':await revision()};
    await store.executeRemote(request);
    expect(await store.getSetting('pin'),'1234');
    await store.executeRemote(request);
    expect(await store.getSetting('pin'),'1234');
  });
  test('debt reduction validates actual balance instead of caller balance', () async {
    final customer=await store.addCustomerDirectory(name:'Debt test',phone:'0900000001',note:'');
    final id=customer['id'] as int;
    await store.addDebtAdjustment(partyType:'customer',partyId:id,amount:100,increase:true,currentDebt:0,note:'');
    await expectLater(store.addDebtAdjustment(partyType:'customer',partyId:id,amount:101,increase:false,currentDebt:999,note:''),throwsException);
  });
  test('unknown operations rejected', () async {
    expect(store.executeRemote({'operation':'rawQuery','arguments':{'sql':'SELECT * FROM app_settings'}}),throwsArgumentError);
  });
}
