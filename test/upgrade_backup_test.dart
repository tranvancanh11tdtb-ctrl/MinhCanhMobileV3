import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:minh_canh_mobile_v3/main.dart';
void main(){
  TestWidgetsFlutterBinding.ensureInitialized();final store=StoreDb.instance;late Directory dir;
  setUpAll(()async{sqfliteFfiInit();databaseFactory=databaseFactoryFfi;dir=await Directory.systemTemp.createTemp('mcm-backup-upgrade-');await databaseFactory.setDatabasesPath(dir.path);});
  tearDownAll(()async{await(await store.database).close();await dir.delete(recursive:true);});
  test('legacy format 6 restores old cash entries as unclassified',()async{
    await store.addCashEntry(type:'expense',category:'Khoản cũ',amount:1000,note:'');
    final backup=jsonDecode(await store.exportBackup()) as Map<String,dynamic>;
    backup['backup_version']=6;
    for(final key in ['purchase_drafts','purchase_completions','recurring_expenses','recurring_payments','payment_events']){backup.remove(key);}
    for(final row in backup['cash_entries'] as List){(row as Map)..remove('scope')..remove('occurred_at')..remove('payment_method');}
    await store.restoreBackup(jsonEncode(backup));
    final ledger=await store.financeLedger(DateTime(2000),DateTime(2100));
    expect(ledger.single['scope'],'unclassified');expect(ledger.single['amount'],1000);
  });
  test('inventory period reconciles opening incoming outgoing and closing',()async{
    final id=await store.addProduct({'code':'REPORT-PK','name':'Inventory period','category':'Phụ kiện','track_imei':0,'created_at':financeNow()});
    final line=PurchaseLineDraft(product:await store.product(id),initialQuantity:2);line.cost.text='1000';
    await store.completeMultiPurchase(items:[line],supplier:'NCC',paid:0,paymentMethod:'cash');line.dispose();
    await store.completeMultiSale(invoiceCode:'PERIOD-SALE',items:[SaleLineDraft(product:await store.product(id),quantity:1,unitPrice:2000,discountPerItem:0)],customer:'Khách lẻ',phone:'',cash:2000,transfer:0,warrantyMonths:0);
    final row=(await store.productReport(DateTime(2000),DateTime(2100))).singleWhere((r)=>r['id']==id);
    expect(row['opening_stock'],0);expect(row['incoming'],2);expect(row['outgoing'],1);expect(row['closing_stock'],1);
  });
}
