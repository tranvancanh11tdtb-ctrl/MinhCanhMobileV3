import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:minh_canh_mobile_v3/main.dart';
import 'package:minh_canh_mobile_v3/lan/remote_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = StoreDb.instance;
  late Directory dir;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dir = await Directory.systemTemp.createTemp('mcm-release-');
    await databaseFactory.setDatabasesPath(dir.path);
    await store.setSetting('pin', '1234');
    await store.setSetting('biometric_enabled', '1');
  });
  tearDownAll(() async {
    await (await store.database).close();
    await dir.delete(recursive:true);
  });
  test('authoritative rejection releases an uncertain write', () async {
    await http.runWithClient(() async {
      final bridge=RemoteBridge();
      bridge.pending={'protocol':2,'operation':'addProductBrand','arguments':{'rawName':'A'},'requestId':'uncertain-request-001','revision':0};
      await bridge.resolvePending();
      expect(bridge.pending,isNull);
      bridge.disconnect();
    },()=>MockClient((_) async => http.Response(jsonEncode({'error':'Dữ liệu đã thay đổi','code':'not_committed'}),400,headers:{'content-type':'application/json; charset=utf-8'})));
  });
  test('expired authentication does not discard uncertain write', () async {
    await http.runWithClient(() async {
      final bridge=RemoteBridge();
      bridge.pending={'protocol':2,'operation':'addProductBrand','arguments':{},'requestId':'uncertain-request-002','revision':0};
      await bridge.resolvePending();
      expect(bridge.pending,isNotNull);
      expect(bridge.connected,isFalse);
      bridge.disconnect();
    },()=>MockClient((_) async => http.Response(jsonEncode({'error':'Phiên hết hạn'}),401,headers:{'content-type':'application/json; charset=utf-8'})));
  });
  test('incomplete restore is rejected without erasing store', () async {
    final before=await store.exportBackup();
    await expectLater(store.restoreBackup('{"app":"MinhCanhMobileV3"}'),throwsException);
    final after=jsonDecode(await store.exportBackup()) as Map;
    expect(after['app_settings'],(jsonDecode(before) as Map)['app_settings']);
  });
  test('native restore retains recovery snapshot and business balances',() async {
    final customer=await store.addCustomerDirectory(name:'Khách khôi phục',phone:'0911111111',note:'');
    await store.addDebtAdjustment(partyType:'customer',partyId:customer['id'] as int,amount:80000,increase:true,currentDebt:0,note:'');
    final backup=await store.exportBackup();
    await store.restoreBackup(backup);
    expect((await store.customers()).where((r)=>r['id']==customer['id']).single['debt'],80000);
    final safety=jsonDecode((await (await store.database).query('restore_safety')).single['source'] as String) as Map;
    final expected=jsonDecode(backup) as Map;
    safety.remove('created_at');expected.remove('created_at');
    expect(safety,expected);
  });
  test('remote change rejects stale native edits until acknowledged',() async {
    final revision=(await store.executeRemote({'protocol':2,'operation':'dashboard'}))['revision'];
    await store.executeRemote({'protocol':2,'operation':'addProductBrand','arguments':{'rawName':'Máy tính'},'requestId':'revision-guard-0001','revision':revision});
    await expectLater(store.addProductBrand('Điện thoại cũ'),throwsStateError);
    expect((await store.productBrands()).any((r)=>r['name']=='Điện thoại cũ'),false);
    store.acknowledgeRemoteChanges();
    await store.addProductBrand('Điện thoại mới');
    expect((await store.productBrands()).any((r)=>r['name']=='Điện thoại mới'),true);
  });
  testWidgets('enabled biometric unlock has an explicit action and PIN fallback', (tester) async {
    // SQLite uses a real isolate; launch and drain its reads in the real zone.
    await tester.runAsync(() async {
      await tester.pumpWidget(const MaterialApp(home:PinGate()));
      await store.getSetting('biometric_enabled');
      await store.getSetting('pin');
    });
    await tester.pumpAndSettle();
    expect(find.text('Mở khóa bằng sinh trắc học'),findsOneWidget);
    expect(find.widgetWithText(TextField,'Mã PIN'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
