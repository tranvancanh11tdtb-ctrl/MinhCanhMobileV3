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
    await tester.runAsync(()async{await tester.pumpWidget(const MaterialApp(home:CashBookPage()));await store.financeSummary(DateTime(2000),DateTime(2100));await store.financeLedger(DateTime(2000),DateTime(2100));await store.recurringExpenses(DateTime.now().year,DateTime.now().month);await Future<void>.delayed(const Duration(milliseconds:100));});
    await tester.pumpAndSettle();
    expect(find.text('Tổng quan'),findsOneWidget);
    expect(find.text('Lịch sử'),findsOneWidget);
    expect(find.text('Chi phí cố định'),findsOneWidget);
  });
}
