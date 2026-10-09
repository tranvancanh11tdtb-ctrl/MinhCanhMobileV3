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
  for(final width in [390.0,1440.0]) {
    testWidgets('twenty purchase lines and IMEI reduction at $width', (tester) async {
      tester.view.physicalSize=Size(width,850);tester.view.devicePixelRatio=1;
      addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
      late int draftId;
      await tester.runAsync(()async {
        final items=<Map<String,Object?>>[];
        for(var i=0;i<20;i++) {
          final id=await store.addProduct({'code':'DENSE-$width-$i','name':'Line $i','category':i==0?'Điện thoại':'Phụ kiện','track_imei':i==0?1:0,'created_at':financeNow()});
          items.add({'product':await store.product(id),'quantity':i==0?2:1,'cost':'1000','discount':'0','serials':i==0?[{'imei':'490154203237518','color':'Đen','cost':1000},{'imei':'490154203237526','color':'Trắng','cost':1200}]:[]});
        }
        draftId=await store.savePurchaseDraft(payload:{'supplier':'Twenty $width','items':items});
        await tester.pumpWidget(const MaterialApp(home:PurchaseForm()));await store.products();await store.supplierDirectory();
      });
      await tester.pumpAndSettle();
      await tester.runAsync(()async{await tester.tap(find.byTooltip('Phiếu lưu tạm'));await store.purchaseDrafts();await Future<void>.delayed(const Duration(milliseconds:100));});
      await tester.pumpAndSettle();
      await tester.tap(find.text('Phiếu $draftId • Twenty $width'));
      await tester.pumpAndSettle();
      expect(find.text('Lưu tạm').hitTestable(),findsOneWidget);expect(find.text('Hoàn thành').hitTestable(),findsOneWidget);
      if(width<500) {
        final firstCard=find.ancestor(of:find.text('Line 0'),matching:find.byType(Card)).first;
        expect(tester.getSize(firstCard).height,lessThanOrEqualTo(160));
      }
      final quantity=find.byType(TextFormField).first;
      await tester.enterText(quantity,'1');await tester.tap(find.text('Lưu tạm'));await tester.pumpAndSettle();
      expect(find.text('Giảm số máy'),findsOneWidget);await tester.tap(find.text('Không'));await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(quantity).controller!.text,'2');
      await tester.runAsync(()async{final items=((await store.purchaseDraft(draftId))['payload'] as Map)['items'] as List;expect(items,hasLength(20));expect(items.first['serials'],hasLength(2));expect(items.first['serials'][1]['color'],'Trắng');expect(items.first['serials'][1]['cost'],1200);});
      expect(tester.takeException(),isNull);
    });
  }
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
