import 'dart:io';

import 'package:flutter/material.dart';
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
    dir = await Directory.systemTemp.createTemp('mcm-purchase-ui-');
    await databaseFactory.setDatabasesPath(dir.path);
  });
  tearDownAll(() async {
    await (await store.database).close();
    await dir.delete(recursive: true);
  });
  testWidgets('typed quantity is saved without keyboard submit', (
    tester,
  ) async {
    late Map<String, Object?> product;
    await tester.runAsync(() async {
      final id = await store.addProduct({
        'code': 'UI-QUANTITY',
        'name': 'Cable',
        'category': 'Phụ kiện',
        'track_imei': 0,
        'created_at': financeNow(),
      });
      product = await store.product(id);
      await tester.pumpWidget(
        MaterialApp(home: PurchaseForm(initialProduct: product)),
      );
      await store.products();
      await store.supplierDirectory();
    });
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '20');
    await tester.runAsync(() async {
      await tester.tap(find.text('Lưu tạm'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final draft = (await store.purchaseDrafts()).first;
      final items = (draft['payload'] as Map)['items'] as List;
      expect(items.single['quantity'], 20);
    });
  });
  for (final width in [390.0, 1440.0]) {
    testWidgets('purchase footer stays accessible at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        await tester.pumpWidget(const MaterialApp(home: PurchaseForm()));
        await store.products();
        await store.supplierDirectory();
      });
      await tester.pumpAndSettle();
      expect(find.text('Lưu tạm').hitTestable(), findsOneWidget);
      expect(find.text('Hoàn thành').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
