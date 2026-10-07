import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:minh_canh_mobile_v3/main.dart';
import 'package:minh_canh_mobile_v3/lan/lan_host.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final store = StoreDb.instance;
  late Directory dir;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dir = await Directory.systemTemp.createTemp('mcm-final-');
    await databaseFactory.setDatabasesPath(dir.path);
  });
  tearDownAll(() async {
    await (await store.database).close();
    await dir.delete(recursive:true);
  });
  test('restore invalidates success receipts for writes removed by restore', () async {
    final backup=await store.exportBackup();
    final revision=(await store.executeRemote({'operation':'dashboard'}))['revision'];
    final request=<String,Object?>{'operation':'addProductBrand','arguments':{'rawName':'Removed by restore'},'requestId':'restore-stale-replay-001','revision':revision};
    await store.executeRemote(request);
    store.acknowledgeRemoteChanges();
    await store.restoreBackup(backup);
    expect((await store.productBrands()).any((r)=>r['name']=='Removed by restore'),false);
    await expectLater(store.executeRemote(request),throwsStateError);
  });
  test('LAN restart preserves browser origin for pending recovery', () async {
    final messenger=binding.defaultBinaryMessenger;
    messenger.setMockMessageHandler('flutter/assets', (_) async => ByteData.view(Uint8List.fromList('<html></html>'.codeUnits).buffer));
    messenger.setMockMethodCallHandler(LanHost.channel, (_) async => null);
    final host=LanHost();
    try {
      await host.start((_) async => {'value':null,'revision':0});
      final before=List<String>.from(host.addresses);
      await host.stop();
      await host.start((_) async => {'value':null,'revision':0});
      expect(host.addresses,before);
    } finally {
      await host.stop();
      messenger.setMockMessageHandler('flutter/assets',null);
      messenger.setMockMethodCallHandler(LanHost.channel,null);
    }
  });
  testWidgets('report row opens complete product details', (tester) async {
    await tester.runAsync(() async {
      await store.addProduct({'code':'REPORT-DETAIL','name':'Report detail product','category':'Phụ kiện','track_imei':0,'sale_price':123000,'created_at':DateTime.now().toIso8601String()});
      await tester.pumpWidget(const MaterialApp(home:ProductReportPage()));
      await store.productReport(DateTime(2000),DateTime(2100));
    });
    await tester.pumpAndSettle();
    final row=find.text('Report detail product').first;
    await tester.ensureVisible(row);
    await tester.runAsync(() async {
      await tester.tap(row);
      await store.products();
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(),isNull);
    expect(find.byType(ProductDetail),findsOneWidget);
    expect(find.text('Giá bán: ${vnd(123000)}'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('long receipt includes content below the screen height', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home:Builder(builder:(c){context=c;return const SizedBox();})));
    final receipt=ReceiptDocument(title:'HÓA ĐƠN DÀI',code:'LONG',date:'07/10/2026',details:const [],items:[
      for(var i=0;i<25;i++) ReceiptItem(name:'Sản phẩm tiếng Việt số $i',detail:'Tên dài cần giữ đủ nội dung khi in',quantity:1,unitPrice:123000),
    ],totals:const [MapEntry('TỔNG TIỀN CUỐI PHIẾU','3.075.000 đ')]);
    final png=await tester.runAsync(()=>ReceiptPrinter.render(context,receipt));
    expect(tester.takeException(),isNull);
    final decoded=img.decodeImage(png!);
    expect(decoded,isNotNull);
    expect(decoded!.height,greaterThan(2000));
    await tester.runAsync(() async {
      await Directory('build/test-output').create(recursive:true);
      await File('build/test-output/long-receipt.png').writeAsBytes(png);
    });
    await tester.pumpWidget(const SizedBox());
  });
}
