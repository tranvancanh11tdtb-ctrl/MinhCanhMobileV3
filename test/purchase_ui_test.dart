import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:minh_canh_mobile_v3/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store=StoreDb.instance;late Directory dir;
  setUpAll(() async {sqfliteFfiInit();databaseFactory=databaseFactoryFfi;dir=await Directory.systemTemp.createTemp('mcm-purchase-ui-');await databaseFactory.setDatabasesPath(dir.path);});
  tearDownAll(() async {await (await store.database).close();await dir.delete(recursive:true);});
  for(final width in [390.0,1440.0]) {
    testWidgets('purchase footer stays accessible at width $width', (tester) async {
      tester.view.physicalSize=Size(width,850);tester.view.devicePixelRatio=1;
      addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        await tester.pumpWidget(const MaterialApp(home:PurchaseForm()));
        await store.products();await store.supplierDirectory();
      });
      await tester.pumpAndSettle();
      expect(find.text('Lưu tạm').hitTestable(),findsOneWidget);
      expect(find.text('Hoàn thành').hitTestable(),findsOneWidget);
      expect(tester.takeException(),isNull);
    });
  }
}
