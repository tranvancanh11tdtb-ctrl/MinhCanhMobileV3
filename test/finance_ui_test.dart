import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:minh_canh_mobile_v3/main.dart';
void main(){
  TestWidgetsFlutterBinding.ensureInitialized();final store=StoreDb.instance;late Directory dir;
  setUpAll(()async{sqfliteFfiInit();databaseFactory=databaseFactoryFfi;dir=await Directory.systemTemp.createTemp('mcm-fin-ui-');await databaseFactory.setDatabasesPath(dir.path);});
  tearDownAll(()async{await(await store.database).close();await dir.delete(recursive:true);});
  testWidgets('finance book separates overview history and fixed costs',(tester)async{
    await tester.runAsync(()async{await tester.pumpWidget(const MaterialApp(home:CashBookPage()));await store.cashEntries();});
    await tester.pumpAndSettle();
    expect(find.text('Tổng quan'),findsOneWidget);
    expect(find.text('Lịch sử'),findsOneWidget);
    expect(find.text('Chi phí cố định'),findsOneWidget);
  });
}
